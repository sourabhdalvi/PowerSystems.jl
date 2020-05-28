
const PARTITION_ZONE_TO_BUS_NUMBER = Dict{Int, Vector{Int}}

function read_partition_mapping(filename::AbstractString)
    data = open(filename) do io
        JSON.parse(io)
    end

    return PARTITION_ZONE_TO_BUS_NUMBER(parse(Int, k) => v for (k, v) in data)
end

"""
Record partition zones in system components per the mapping in filename.
"""
function partition_system!(sys::System, filename::AbstractString)
    partition_system!(sys, read_partition_mapping(filename))
    @info "Partitioned system with" filename
end

function partition_system!(sys::System, bus_mapping::PARTITION_ZONE_TO_BUS_NUMBER)
    bus_number_to_bus = Dict(get_number(x) => x for x in get_components(Bus, sys))

    for (partition_zone, bus_numbers) in bus_mapping
        for bus_number in bus_numbers
            bus = bus_number_to_bus[bus_number]
            set_partition_zone!(bus, partition_zone)
        end
    end

    for branch in get_components(Branch, sys)
        arc = get_arc(branch)
        from_bus = get_from(arc)
        from_partition_zone = get_partition_zone(from_bus)
        to_bus = get_to(arc)
        to_partition_zone = get_partition_zone(to_bus)
        if from_partition_zone != to_partition_zone
            _set_spanned_info!(from_bus, get_name(to_bus), get_name(branch))
            _set_spanned_info!(to_bus, get_name(from_bus), get_name(branch))
        end
    end
end

"""
Set the partition zone containing the bus.
"""
function set_partition_zone!(bus::Bus, partition_zone::Int)
    ext = get_ext(bus)
    ext["partition_zone"] = partition_zone
    @debug "Set bus partition zone" get_number(bus) partition_zone
end

function _set_spanned_info!(bus::Bus, connected_bus::AbstractString, branch::AbstractString)
    ext = get_ext(bus)
    ext["connected_spanned_bus"] = connected_bus
    ext["spanned_branch"] = branch
    @debug "Found spanned branch" get_name(bus) connected_bus branch
end

"""
Return the partition zone in which component resides.
"""
get_partition_zone(component::T) where {T <: Component} = error("not implemented for $T")
get_partition_zone(bus::Bus) = get_ext(bus)["partition_zone"]
get_partition_zone(device::StaticInjection) = get_partition_zone(get_bus(device))

get_connected_spanned_bus_name(bus::Bus) = _get_ext_field(bus, "connected_spanned_bus")
get_spanned_branch_name(bus::Bus) = _get_ext_field(bus, "spanned_branch")

"""
Return the connected bus if that bus is in a different partition zone.
Otherwise, return nothing.
"""
function get_connected_spanned_bus(sys::System, bus::Bus) 
    name = get_connected_spanned_bus_name(bus)
    isnothing(name) && return nothing
    return get_component(Bus, sys, name)
end

"""
Return a branch if the bus is connected a bus in a different partition zone.
Otherwise, return nothing.
"""
function get_spanned_branch(sys::System, bus::Bus) 
    name = get_spanned_branch_name(bus)
    isnothing(name) && return nothing
    return get_component(Branch, sys, name)
end

"""
Return partition zones for bus. If the bus is connected to a bus in a different partition
zone, that zone is included.
"""
function get_partition_zones(sys::System, bus::Bus)
    partition_zones = [get_partition_zone(bus)]
    spanned_bus = get_connected_spanned_bus(sys, bus)
    if !isnothing(spanned_bus)
        push!(partition_zones, get_partition_zone(spanned_bus))
    end

    return partition_zones
end

"""
Return partition zones of buses to which branch is connected.
"""
function get_partition_zones(branch::Branch)
    from_partition_zone, to_partition_zone = _from_to_partition_zones(branch)
    if from_partition_zone == to_partition_zone
        return [from_partition_zone]
    end

    return [from_partition_zone, to_partition_zone]
end

"""
Return StaticInjection devices with buses in partition.
"""
function get_components(::Type{T}, sys::System, partition::Int) where {T <: StaticInjection}
    return get_components(T, sys, x -> get_partition_zone(x) == partition)
end

"""
Return buses in partition. Include buses in a different partition that are connected to a
bus in partition.
"""
function get_components(::Type{Bus}, sys::System, partition::Int)
    return get_components(Bus, sys, x -> partition in Set(get_partition_zones(sys, x)))
end

function _get_ext_field(component::Component, field)
    ext = get_ext(component)
    return get(ext, field, nothing)
end

function _from_to_partition_zones(branch::Branch)
    arc = get_arc(branch)
    from_bus = get_from(arc)
    from_partition_zone = get_partition_zone(from_bus)
    to_bus = get_to(arc)
    to_partition_zone = get_partition_zone(to_bus)
    return from_partition_zone, to_partition_zone
end
