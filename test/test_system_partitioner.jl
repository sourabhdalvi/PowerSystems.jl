
function create_partitions(sys::System)
    areas = [get_name(x) for x in get_components(Area, sys)]
    partition_to_bus_numbers = PSY.PARTITION_ZONE_TO_BUS_NUMBER()
    for bus in get_components(Bus, sys)
        area = parse(Int, get_name(get_area(bus)))
        if !haskey(partition_to_bus_numbers, area)
            partition_to_bus_numbers[area] = Vector{Int}()
        end
        push!(partition_to_bus_numbers[area], get_number(bus))
    end

    @test sort!(collect(keys(partition_to_bus_numbers))) == [1, 2, 3]
    path, io = mktemp()
    try
        text = JSON.json(partition_to_bus_numbers)
        write(io, JSON.json(partition_to_bus_numbers))
    finally
        close(io)
    end

    return path
end

function test_bus_partition_zones(sys::System, filename::AbstractString)
    for (partition, bus_numbers) in read_partition_mapping(filename)
        total = Set([get_number(x) for x in get_components(Bus, sys, partition)])
        # total includes attached buses in other partitions.
        @test length(total) > length(bus_numbers)
        for bus_number in bus_numbers
            @test bus_number in total
        end
    end
end

function test_spanned_branches(sys::System)
    for bus in get_components(Bus, sys)
        spanned_bus = get_connected_spanned_bus(sys, bus)
        isnothing(spanned_bus) && continue
        branch = get_spanned_branch(sys, bus)
        from_partition_zone, to_partition_zone = _from_to_partition_zones(branch)
        println("Buses $(get_name(bus)) and $(get_name(spanned_bus)) span partitions " *
                "$from_partition_zone and $to_partition_zone via $(get_name(branch))")

        # Test get_partition_zones.
        partitions = sort!([from_partition_zone, to_partition_zone])
        partitions2 = sort!(PSY.get_partition_zones(sys, bus))
        @test partitions == partitions2
        partitions3 = sort!(PSY.get_partition_zones(branch))
        @test partitions == partitions3
    end
end

function test_devices_by_partition_zone(sys)
    partition_zone_to_device = Dict{Int, Vector{StaticInjection}}()
    for device in get_components(StaticInjection, sys)
        partition_zone = PSY.get_partition_zone(device)
        if !haskey(partition_zone_to_device, partition_zone)
            partition_zone_to_device[partition_zone] = Vector{StaticInjection}()
        end
        push!(partition_zone_to_device[partition_zone], device)
    end

    for partition_zone in sort!(collect(keys(partition_zone_to_device)))
        devices = partition_zone_to_device[partition_zone]

        # Test get_components.
        devices2 = collect(get_components(StaticInjection, sys, partition_zone))
        sort!(devices, by = x -> get_name(x))
        sort!(devices2, by = x -> get_name(x))
        @test devices == devices2

        println("partition zone $partition_zone: ($(length(devices)) devices)")
        for device in devices
            println("  $(summary(device))")
        end
    end
end

@testset "Test system partitioning" begin
    sys = create_rts_system()
    partition_file = create_partitions(sys)
    PSY.partition_system!(sys, partition_file)

    test_bus_partition_zones(sys, partition_file)
    test_spanned_branches(sys)
    test_devices_by_partition_zone(sys)
end
