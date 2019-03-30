# Global method definition needs to be at top level in .7

# Is this redefinition of Base.convert still needed? Looks like this is
# implemented correctly in 1.0, and with correct throw of InexactError (here, I
# get `ERROR: UndefVarError: Inexacterror not defined`), JJS 1/31/19

# Convert bool to int
Base.convert(::Type{Bool}, x::Int) = x==0 ? false : x==1 ? true : throw(Inexacterror())
#############################################

"""
Takes a PowerSystems dictionary and return an array of PowerSystems struct for
Bus, Generator, Branch and load
"""
function ps_dict2ps_struct(data::Dict{String,Any})
    generators = Array{G where {G<:Generator},1}()
    storages = Array{S where {S<:Storage},1}()
    buses = Array{Bus,1}()
    branches = Array{B where {B<:Branch},1}()
    loads = Array{E where {E<:ElectricLoad},1}()
    shunts = Array{FixedAdmittance,1}()
    loadZones = Array{D where {D<:PowerSystemDevice},1}()
    services = Array{S where {S<:Service},1}()

    # TODO: should we raise an exception in the following?

    if haskey(data, "bus")
        buses = PowerSystems.bus_dict_parse(data["bus"])
    else
        @warn "key 'bus' not found in PowerSystems dictionary, this will result in an empty Bus array"
    end
    if haskey(data, "gen")
        (generators, storage) = PowerSystems.gen_dict_parser(data["gen"])
    else
        @warn "key 'gen' not found in PowerSystems dictionary, this will result in an empty Generators and Storage array"
    end
    if haskey(data, "branch")
        branches = PowerSystems.branch_dict_parser(data["branch"], branches)
    else
        @warn "key 'branch' not found in PowerSystems dictionary, this will result in an empty Branches array"
    end
    if haskey(data, "load")
        loads = PowerSystems.load_dict_parser(data["load"])
    else
        @warn "key 'load' not found in PowerSystems dictionary, this will result in an empty Loads array"
    end
    if haskey(data, "loadzone")
        loadZones = PowerSystems.loadzone_dict_parser(data["loadzone"])
    else
        @warn "key 'loadzone' not found in PowerSystems dictionary, this will result in an empty LoadZones array"
    end
    if haskey(data, "shunt")
        shunts = PowerSystems.shunt_dict_parser(data["shunt"])
    else
        @warn "key 'shunt' not found in PowerSystems dictionary, this will result in an empty Shunts array"
    end
    if haskey(data, "dcline")
        branches = PowerSystems.dclines_dict_parser(data["dcline"], branches)
    else
        @warn "key 'dcline' not found in PowerSystems dictionary, this will result in an empty DCLines array"
    end
    if haskey(data, "services")
        services = PowerSystems.services_dict_parser(data["services"],generators)
    else
        @warn "key 'services' not found in PowerSystems dictionary, this will result in an empty services array"
    end
    if haskey(data,"forecasts")
        devices = collect(vcat(buses,generators,storage,branches,loads,loadZones,shunts,branches,services))
        forecasts = PowerSystems.forecasts_dict_parser(data["forecasts"],devices)

    end

    return sort!(buses, by = x -> x.number), generators, storage,  sort!(branches, by = x -> x.connectionpoints.from.number), loads, loadZones, shunts, services

end

#Union{String,DataType,Union}
function _retrieve(dict::T, key_of_interest::Union{DataType,Union,String,Symbol}, output::Dict, path::Array) where T<:AbstractDict
    iter_result = Base.iterate(dict)
    last_element = length(path)
    while iter_result !== nothing
        ((key,value), state) = iter_result
        if isa(key_of_interest,Union{DataType,Union})
            if typeof(value) <: key_of_interest
                output[key] = !haskey(output,key) ? path[1:end] : push!(output[key],path[1:end])
            end
        elseif key == key_of_interest
            output[value] = !haskey(output,value) ? path[1:end] : push!(output[value],path[1:end])
        end
        if value isa AbstractDict
            push!(path,key)
            _retrieve(value, key_of_interest, output, path)
            path = path[1:last_element]
        end
        iter_result = Base.iterate(dict, state)
    end
    return output
end



function _access(nesteddict::T,keylist) where T<:AbstractDict
    if !haskey(nesteddict,keylist[1])
        @error "$(keylist[1]) not found in dict"        
    end
    if length(keylist) > 1
        nesteddict = _access(nesteddict[keylist[1]],keylist[2:end])
    else
        nesteddict = nesteddict[keylist[1]]
    end
end

function _get_device(name::Union{String,Symbol}, collection, devices = [])
    if isa(collection,Union{Array,Dict}) 
        if !isempty(collection)
            fn = fieldnames(typeof(collection[1]))
            if :name in fn
                [push!(devices,d) for d in collection if d.name == name]
            end
        end
    else
        fn = fieldnames(typeof(collection))
        for f in fn
            _get_device(name,getfield(collection,f),devices)
        end
    end
    return devices
end

#=
function _getfieldpath(device,field::Symbol)
    # function to map struct fields into a dict
    function _getsubfields(device)
        fn = fieldnames(typeof(device))
        fielddict = Dict()
        for f in fn
            fielddict[f] = _getsubfields(getfield(device,f))
        end
        return fielddict
    end

    fielddict = _getsubfields(device)

    tmp = PowerSystems._retrieve(fielddict,field,Dict(),[])
    if isempty(tmp)
        @error "Device $(device.name) has no field $field"
    else
        fieldpath = collect(Iterators.flatten(values(tmp)))
        push!(fieldpath,field)
    end

    return fieldpath
end


function _getfield(device,fieldpath::Array{Symbol,1})
    f = getfield(device,fieldpath[1])
    length(fieldpath)>1 ? _getfield(f,fieldpath[2:end]) : return f
end
=#

"""
Arg:
    Dataframes which includes a timerseries columns of either:
        Year, Month, Day, Period
      or
        DateTime
      or
        nothing (creates a today referenced DateTime Column)
Returns:
    Dataframe with a DateTime columns
"""
function read_datetime(df; kwargs...)
    if [c for c in [:Year,:Month,:Day] if c in names(df)] == [:Year,:Month,:Day]
        if !(:Period in names(df))
            df = DataFrames.rename!(DataFrames.stack(df,[c for c in names(df) if !(c in [:Year,:Month,:Day])]),:variable=>:Period)
            df.Period = parse.(Int,string.(df.Period))
            if :valuecolname in keys(kwargs)
                DataFrames.rename!(df,:value=>kwargs[:valuecolname])
            end
        end
        if Dates.Hour(DataFrames.maximum(df[:Period])) <= Dates.Hour(25)
            df[:DateTime] = collect(Dates.DateTime(df[1,:Year],df[1,:Month],df[1,:Day],(df[1,:Period]-1)) :Dates.Hour(1) : Dates.DateTime(df[end,:Year],df[end,:Month],df[end,:Day],(df[end,:Period]-1)))
        elseif (Dates.Minute(5) * DataFrames.maximum(df[:Period]) >= Dates.Minute(1440))& (Dates.Minute(5) * DataFrames.maximum(df[:Period]) <= Dates.Minute(1500))
            df[:DateTime] = collect(Dates.DateTime(df[1,:Year],df[1,:Month],df[1,:Day],floor(df[1,:Period]/12),Int(df[1,:Period])-1) :Dates.Minute(5) :
                            Dates.DateTime(df[end,:Year],df[end,:Month],df[end,:Day],floor(df[end,:Period]/12)-1,5*(Int(df[end,:Period])-(floor(df[end,:Period]/12)-1)*12) -5))
        else
            @error "I don't know what the period length is, reformat timeseries"
        end
        DataFrames.deletecols!(df, [:Year,:Month,:Day,:Period])

    elseif :DateTime in names(df)
        df[:DateTime] = Dates.DateTime(df[:DateTime])
    else
        if :startdatetime in keys(kwargs)
            startdatetime = kwargs[:startdatetime]
        else
            @warn "No reference date given, assuming today"
            startdatetime = Dates.today()
        end
        df[:DateTime] = collect(Dates.DateTime(startdatetime):Dates.Hour(1):Dates.DateTime(startdatetime)+Dates.Hour(size(df)[1]-1))
    end
    return df
end

#=
"""
Arg:
    Device dictionary - Generators
    Dataframe contains device Realtime/Forecast TimeSeries
Returns:
    Device dictionary with timeseries added
"""
function add_time_series(Device_dict::Dict{String,Any}, df::DataFrames.DataFrame)
    for (device_key,device) in Device_dict
        if device_key in map(string, names(df))
            ts_raw = df[Symbol(device_key)]
            if maximum(ts_raw) <= 1.0
                @info "assumed time series is a scaling factor for $device_key"
                Device_dict[device_key]["scalingfactor"] = TimeSeries.TimeArray(df[:DateTime],ts_raw)
            else
                @info "assumed time series is MW for $device_key"
                Device_dict[device_key]["scalingfactor"] = TimeSeries.TimeArray(df[:DateTime],ts_raw/device["tech"]["installedcapacity"])
            end
        end
    end
    return Device_dict
end

function add_time_series(Device_dict::Dict{String,Any}, ts_raw::TimeSeries.TimeArray)
    """
    Arg:
        Device dictionary - Generators
        Dict contains device Realtime/Forecast TimeSeries.TimeArray
    Returns:
        Device dictionary with timeseries added
    """

    if haskey(Device_dict,"name")
        name = Device_dict["name"]
    else
        @error "input dict in wrong format"
    end

    if maximum(values(ts_raw)) <= 1.0
        @info "assumed time series is a scaling factor for $name"
        Device_dict["scalingfactor"] = ts_raw
    else
        @info "assumed time series is MW for $name"
        Device_dict["scalingfactor"] = TimeSeries.TimeArray(TimeSeries.timestamp(ts_raw),values(ts_raw)/Device_dict["tech"]["installedcapacity"])
    end

    return Device_dict
end


"""
Arg:
    Load dictionary
    Dataframe contains device Realtime/Forecast TimeSeries
Returns:
    Forecast dictionary
"""
function add_time_series_load(sys::PowerSystem, df::DataFrames.DataFrame)

    ts_names = [string(n) for n in names(df) if n != :DateTime]

    load_dict = Dict()
    assigned_loads = []

    @info "assigning load scaling factors by bus"
    for l in sys.loads
        load_dict[l.name] = TimeSeries.TimeArray(df[:DateTime],df[Symbol(l.name)],[:maxactivepower])
        push!(assigned_loads,l.name)
    end

    for l in [l.name for l in sys.loads if !(l.name in assigned_loads)]
        @warn "No load scaling factor assigned for $l"
    end

    return load_dict
end

"""
Arg:
    PowerSystem
    Dataframe contains device Realtime/Forecast TimeSeries
    LoadZones dictionary
Returns:
    Forecast dictionary
"""
function add_time_series_load(sys::PowerSystem, df::DataFrames.DataFrame,lz_dict::Dict)

    ts_names = [string(n) for n in names(df) if n != :DateTime]

    z_names = [string(z["name"]) for (k,z) in lz_dict]
    if !(length([n for n in z_names if n in ts_names]) > 0)
        @error "loadzone names don't match names of dataframe"
    end

    load_dict = Dict()
    assigned_loads = []
    @info "assigning load scaling factors by load_zone"
    # TODO: make this faster/better
    for l in sys.loads
        for (lz_key,lz) in lz_dict
            if l.bus in lz["buses"]
                ts_raw = df[lz_key]/lz["maxactivepower"]
                load_dict[l.name] = TimeSeries.TimeArray(df[:DateTime],ts_raw,[:maxactivepower])
                push!(assigned_loads,l.name)
            end
        end
    end

    for l in [l.name for l in sys.loads if !(l.name in assigned_loads)]
        @warn "No load scaling factor assigned for $l"
    end

    return load_dict
end
=#

## - Parse Dict to Struct
function bus_dict_parse(dict::Dict{Int,Any})
    Buses = [Bus(b["number"],b["name"], b["bustype"],b["angle"],b["voltage"],b["voltagelimits"],b["basevoltage"]) for (k_b,b) in dict ]
    return Buses
end


## - Parse Dict to Array
function gen_dict_parser(dict::Dict{String,Any})
    Generators = Array{G where {G<:Generator},1}()
    Storage_gen = Array{S where {S<:Storage},1}()
    for (gen_type_key,gen_type_dict) in dict
        if gen_type_key =="Thermal"
            for (thermal_key,thermal_dict) in gen_type_dict
                push!(Generators,ThermalDispatch(string(thermal_dict["name"]),
                                                            Bool(thermal_dict["available"]),
                                                            thermal_dict["bus"],
                                                            TechThermal(thermal_dict["tech"]["activepower"],
                                                                        thermal_dict["tech"]["activepowerlimits"],
                                                                        thermal_dict["tech"]["reactivepower"],
                                                                        thermal_dict["tech"]["reactivepowerlimits"],
                                                                        thermal_dict["tech"]["ramplimits"],
                                                                        thermal_dict["tech"]["timelimits"]),
                                                            EconThermal(thermal_dict["econ"]["capacity"],
                                                                        thermal_dict["econ"]["variablecost"],
                                                                        thermal_dict["econ"]["fixedcost"],
                                                                        thermal_dict["econ"]["startupcost"],
                                                                        thermal_dict["econ"]["shutdncost"],
                                                                        thermal_dict["econ"]["annualcapacityfactor"])
                            ))
            end
        elseif gen_type_key =="Hydro"
            for (hydro_key,hydro_dict) in gen_type_dict
                push!(Generators,HydroCurtailment(string(hydro_dict["name"]),
                                                            hydro_dict["available"],
                                                            hydro_dict["bus"],
                                                            TechHydro(  hydro_dict["tech"]["installedcapacity"],
                                                                        hydro_dict["tech"]["activepower"],
                                                                        hydro_dict["tech"]["activepowerlimits"],
                                                                        hydro_dict["tech"]["reactivepower"],
                                                                        hydro_dict["tech"]["reactivepowerlimits"],
                                                                        hydro_dict["tech"]["ramplimits"],
                                                                        hydro_dict["tech"]["timelimits"]),
                                                            hydro_dict["econ"]["curtailcost"]
                            ))
            end
        elseif gen_type_key =="Renewable"
            for (ren_key,ren_dict) in  gen_type_dict
                if ren_key == "PV"
                    for (pv_key,pv_dict) in ren_dict
                        push!(Generators,RenewableCurtailment(string(pv_dict["name"]),
                                                                    Bool( pv_dict["available"]),
                                                                    pv_dict["bus"],
                                                                    pv_dict["tech"]["installedcapacity"],
                                                                    EconRenewable(pv_dict["econ"]["curtailcost"],
                                                                                pv_dict["econ"]["interruptioncost"])
                                    ))
                    end
                elseif ren_key == "RTPV"
                    for (rtpv_key,rtpv_dict) in ren_dict
                        push!(Generators,RenewableFix(string(rtpv_dict["name"]),
                                                                    Bool(rtpv_dict["available"]),
                                                                    rtpv_dict["bus"],
                                                                    rtpv_dict["tech"]["installedcapacity"]
                                    ))
                    end
                elseif ren_key == "WIND"
                    for (wind_key,wind_dict) in ren_dict
                        push!(Generators,RenewableCurtailment(string(wind_dict["name"]),
                                                                    Bool(wind_dict["available"]),
                                                                    wind_dict["bus"],
                                                                    wind_dict["tech"]["installedcapacity"],
                                                                    EconRenewable(wind_dict["econ"]["curtailcost"],
                                                                                wind_dict["econ"]["interruptioncost"])
                                    ))
                    end
                end
            end
        elseif gen_type_key =="Storage"
            for (storage_key,storage_dict) in  gen_type_dict
                push!(Storage_gen,GenericBattery(string(storage_dict["name"]),
                                                            Bool(storage_dict["available"]),
                                                            storage_dict["bus"],
                                                            storage_dict["energy"],
                                                            storage_dict["capacity"],
                                                            storage_dict["activepower"],
                                                            storage_dict["inputactivepowerlimits"],
                                                            storage_dict["outputactivepowerlimits"],
                                                            storage_dict["efficiency"],
                                                            storage_dict["reactivepower"],
                                                            storage_dict["reactivepowerlimits"]
                            ))
            end
        end
    end
    return (Generators, Storage_gen)
end

# - Parse Dict to Array

function branch_dict_parser(dict::Dict{String,Any},Branches::Array{B,1}) where {B<:Branch}
    for (branch_key,branch_dict) in dict
        if branch_key == "Transformers"
            for (trans_key,trans_dict) in branch_dict
                if trans_dict["tap"] ==1.0
                    push!(Branches,Transformer2W(string(trans_dict["name"]),
                                                Bool(trans_dict["available"]),
                                                trans_dict["connectionpoints"],
                                                trans_dict["r"],
                                                trans_dict["x"],
                                                trans_dict["primaryshunt"],
                                                trans_dict["rate"]
                                                ))
                elseif trans_dict["tap"] !=1.0
                    alpha = "α" in keys(trans_dict) ? trans_dict["α"] : 0.0
                    if alpha !=0.0 #TODO : 3W Transformer
                        push!(Branches,PhaseShiftingTransformer(string(trans_dict["name"]),
                                                    Bool(trans_dict["available"]),
                                                    trans_dict["connectionpoints"],
                                                    trans_dict["r"],
                                                    trans_dict["x"],
                                                    trans_dict["primaryshunt"],
                                                    trans_dict["tap"],
                                                    trans_dict["α"],
                                                    trans_dict["rate"]
                                                    ))
                    else
                        push!(Branches,TapTransformer(string(trans_dict["name"]),
                                                    Bool(trans_dict["available"]),
                                                    trans_dict["connectionpoints"],
                                                    trans_dict["r"],
                                                    trans_dict["x"],
                                                    trans_dict["primaryshunt"],
                                                    trans_dict["tap"],
                                                    trans_dict["rate"]
                                                    ))
                    end
                end
            end
        else branch_key == "Lines"
            for (line_key,line_dict) in branch_dict
                push!(Branches,Line(string(line_dict["name"]),
                                    Bool(line_dict["available"]),
                                    line_dict["connectionpoints"],
                                    line_dict["r"],
                                    line_dict["x"],
                                    line_dict["b"],
                                    float(line_dict["rate"]),
                                    line_dict["anglelimits"]
                                    ))
            end
        end
    end
    return Branches
end


function load_dict_parser(dict::Dict{String,Any})
    Loads =Array{L where {L<:ElectricLoad},1}()
    for (load_key,load_dict) in dict
        push!(Loads,PowerLoad(string(load_dict["name"]),
                Bool(load_dict["available"]),
                load_dict["bus"],
                load_dict["maxactivepower"],
                load_dict["maxreactivepower"]
                ))
    end
    return Loads
end

function loadzone_dict_parser(dict::Dict{Int64,Any})
    LoadZs =Array{D where {D<:PowerSystemDevice},1}()
    for (lz_key,lz_dict) in dict
        push!(LoadZs,LoadZones(lz_dict["number"],
                                string(lz_dict["name"]),
                                lz_dict["buses"],
                                lz_dict["maxactivepower"],
                                lz_dict["maxreactivepower"]
                                ))
    end
    return LoadZs
end

function shunt_dict_parser(dict::Dict{String,Any})
    Shunts = Array{FixedAdmittance,1}()
    for (s_key,s_dict) in dict
        push!(Shunts,FixedAdmittance(string(s_dict["name"]),
                            Bool(s_dict["available"]),
                            s_dict["bus"],
                            s_dict["Y"]
                            )
            )
    end
    return Shunts
end


function dclines_dict_parser(dict::Dict{String,Any},Branches::Array{Branch,1})
    for (dct_key,dct_dict) in dict
        if dct_key == "HVDCLine"
            for (dcl_key,dcl_dict) in dct_dict
                push!(Branches,HVDCLine(string(dcl_dict["name"]),
                                    Bool(dcl_dict["available"]),
                                    dcl_dict["connectionpoints"],
                                    dcl_dict["activepowerlimits_from"],
                                    dcl_dict["activepowerlimits_to"],
                                    dcl_dict["reactivepowerlimits_from"],
                                    dcl_dict["reactivepowerlimits_to"],
                                    dcl_dict["loss"]
                                    ))
            end
        elseif dct_key == "VSCDCLine"
            for (dcl_key,dcl_dict) in dct_dict
                push!(Branches,VSCDCLine(string(dcl_dict["name"]),
                                    Bool(dcl_dict["available"]),
                                    dcl_dict["connectionpoints"],
                                    dcl_dict["rectifier_taplimits"],
                                    dcl_dict["rectifier_xrc"],
                                    dcl_dict["rectifier_firingangle"],
                                    dcl_dict["inverter_taplimits"],
                                    dcl_dict["inverter_xrc"],
                                    dcl_dict["inverter_firingangle"]
                                    ))
            end
        end
    end
    return Branches
end


function services_dict_parser(dict::Dict{String,Any},generators::Array{Generator,1})
    Services = Array{D where {D <: Service},1}()

    for (k,d) in dict
        contributingdevices = Array{D where {D<:PowerSystems.PowerSystemDevice},1}()
        [PowerSystems._get_device(dev,generators) for dev in d["contributingdevices"]] |> (x->[push!(contributingdevices,d[1]) for d in x if length(d)==1])
        push!(Services,ProportionalReserve(d["name"],
                            contributingdevices,
                            Float64(d["timeframe"]),
                            TimeSeries.TimeArray(Dates.today(),ones(1))  #TODO : fix requirement 
                            ))
    end
    return Services
end


function forecasts_dict_parser(dict::Dict, devices::Array{Any,1})
    
    forecasts = Dict{Symbol,Array{C,1} where C <: Forecast}()

    for (k,v) in dict
        forecasts[Symbol(k)] =  make_forecast_array(devices, v)
    end
    return forecasts
end