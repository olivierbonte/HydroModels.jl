"""
    HydroBucket(name::Symbol; funcs::Vector, dfuncs::Vector=StateFlux[])

Represents a hydrological bucket model component.

# Arguments
- `name::Symbol`: A symbol representing the name of the HydroBucket instance. If not provided, a name will be automatically generated from state variable names.
- `funcs::Vector`: A vector of flux functions that describe the hydrological processes.
- `dfuncs::Vector`: A vector of state derivative functions (default is an empty vector of StateFlux).

# Fields
- `funcs::Vector{<:AbstractFlux}`: Vector of flux functions describing hydrological processes.
- `dfuncs::Vector{<:AbstractStateFlux}`: Vector of state derivative functions for ODE calculations.
- `flux_func::Function`: Combined function for calculating all hydrological fluxes.
- `ode_func::Union{Nothing,Function}`: Function for ordinary differential equations (ODE) calculations, or nothing if no ODE calculations are needed.
- `meta::HydroMeta`: Contains metadata about the bucket, including input, output, state, parameter, and neural network names.

# Description
HydroBucket is a structure that encapsulates the behavior of a hydrological bucket model. 
It combines multiple flux functions and state derivative functions to model water movement 
and storage within a hydrological unit.

The structure automatically extracts relevant information from the provided functions to 
populate the metadata, which includes names of:
- Inputs: Variables that drive the model
- Outputs: Variables produced by the model
- States: Internal model states that evolve over time
- Parameters: Model parameters that control behavior
- Neural Networks: Any neural network components (if applicable)

The `flux_func` and `ode_func` are constructed based on the provided `funcs` and `dfuncs`, 
enabling efficient calculation of fluxes and state changes over time.

This structure is particularly useful for building complex hydrological models by combining 
multiple HydroBucket instances to represent different components of a water system.

"""
struct HydroBucket{F<:AbstractFlux,D<:AbstractStateFlux,FF<:Function,OF<:Union{Nothing,Function},M<:HydroMeta} <: AbstractBucket
    """
    Vector of flux functions describing hydrological processes.
    """
    funcs::Vector{F}
    """
    Vector of state derivative functions for ODE calculations.
    """
    dfuncs::Vector{D}
    """
    Generated function for calculating all hydrological fluxes.
    """
    flux_func::FF
    """
    Generated function for ordinary differential equations (ODE) calculations, or nothing if no ODE calculations are needed.
    """
    ode_func::OF
    """
    Metadata about the bucket, including input, output, state, parameter, and neural network names.
    """
    meta::M

    function HydroBucket(;
        funcs::Vector{F},
        dfuncs::Vector{D}=StateFlux[],
        name::Union{Symbol,Nothing}=nothing,
        sort_funcs::Bool=false
    ) where {F<:AbstractFlux,D<:AbstractStateFlux}
        funcs = sort_funcs ? sort_funcs(funcs) : funcs
        #* Extract all variable names of funcs and dfuncs
        input_names, output_names, state_names = get_var_names(funcs, dfuncs)
        #* Extract all parameters names of funcs and dfuncs
        param_names = get_param_names(vcat(funcs, dfuncs))
        #* Extract all neuralnetwork names of the funcs
        nn_names = get_nn_names(funcs)
        #* Setup the name information of the hydrobucket
        bucket_name = name === nothing ? Symbol(Symbol(reduce((x, y) -> Symbol(x, y), state_names)), :_bucket) : name
        meta = HydroMeta(bucket_name, input_names, output_names, param_names, state_names, nn_names)
        #* Construct a function for ordinary differential calculation based on dfunc and funcs
        flux_func, ode_func = build_ele_func(funcs, dfuncs, meta)

        return new{F,D,typeof(flux_func),typeof(ode_func),typeof(meta)}(
            funcs,
            dfuncs,
            flux_func,
            ode_func,
            meta,
        )
    end
end

function _get_parameter_extractors(ele::HydroBucket, pas::ComponentVector)
    #* extract params and nn params
    #* Check if all required parameter names are present in pas[:params]
    check_parameters(ele, pas)
    #* Check if all required neural network names are present in pas[:nn] (if any)
    if !isempty(get_nn_names(ele))
        check_nns(ele, pas)
        nn_params_idx = [getaxes(pas[:nn])[1][nm].idx for nm in get_nn_names(ele)]
        nn_param_func = (p) -> [p[:nn][idx] for idx in nn_params_idx]
    else
        nn_param_func = (_) -> nothing
    end
    ele_params_idx = [getaxes(pas[:params])[1][nm].idx for nm in get_param_names(ele)]
    param_func = (p) -> [p[:params][idx] for idx in ele_params_idx]
    return param_func, nn_param_func
end

function _get_parameter_extractors(ele::HydroBucket, pas::ComponentVector, ptypes::AbstractVector{Symbol})
    #* extract params and nn params
    check_parameters(ele, pas, ptypes)
    #* Check if all required neural network names are present in pas[:nn] (if any)
    if !isempty(get_nn_names(ele))
        check_nns(ele, pas)
        nn_params_idx = [getaxes(pas[:nn])[1][nm].idx for nm in get_nn_names(ele)]
        nn_param_func = (p) -> Ref([p[:nn][idx] for idx in nn_params_idx])
    else
        nn_param_func = (_) -> nothing
    end
    ele_params_idx = [getaxes(pas[:params][ptypes[1]])[1][nm].idx for nm in get_param_names(ele)]
    param_func = (p) -> [p[:params][ptype][ele_params_idx] for ptype in ptypes]
    return param_func, nn_param_func
end

function _get_du_func(ele::HydroBucket, ode_input_func::Function, param_func::Function, nn_param_func::Function)
    (u, p, t) -> ele.ode_func(ode_input_func(t), u, param_func(p), nn_param_func(p), t)
end

function _get_dum_func(ele::HydroBucket, ode_input_func::Function, param_func::Function, nn_param_func::Function)
    (u, p, t) -> reduce(hcat, ele.ode_func.(ode_input_func(t), eachslice(u, dims=2), param_func(p), nn_param_func(p), t))
end

"""
    (ele::HydroBucket)(input::Matrix, pas::ComponentVector; config::NamedTuple=NamedTuple(), kwargs...)
    (ele::HydroBucket)(input::Array, pas::ComponentVector; config::NamedTuple=NamedTuple(), kwargs...)
    (ele::HydroBucket)(input::NamedTuple, pas::ComponentVector; config::NamedTuple=NamedTuple(), kwargs...)
    (ele::HydroBucket)(input::Vector{<:NamedTuple}, pas::ComponentVector; config::NamedTuple=NamedTuple(), kwargs...)

Run the HydroBucket model for given input and parameters.

# Arguments
- `input`: Input data. Can be a Matrix (dims: variables × time) or Array (dims: variables × nodes × time)
           or NamedTuple (variables => time series) or Vector{NamedTuple} (variables => time series, for multiple nodes)
- `pas`: ComponentVector containing parameters and initial states
- `config`: Configuration options including:
  - `solver`: AbstractHydroSolver to use for ODE solving (default: ODESolver())
  - `interp`: Interpolation method for input data (default: LinearInterpolation)
  - `timeidx`: Vector of time indices (default: 1:size(input, last_dim))
  - `ptypes`: (Array input only) Parameter types to use (default: all parameter types)
  - `stypes`: (Array input only) State types to use (default: all state types)
- `kwargs`: Additional keyword arguments
  - `convert_to_ntp`: Whether to convert output to NamedTuple (default: false)

# Returns
If convert_to_ntp=false (default):
- Matrix (dims: (states+outputs) × time) for Matrix input
- Array (dims: (states+outputs) × nodes × time) for Array input

If convert_to_ntp=true:
- NamedTuple of time series for Matrix input
- Vector of NamedTuples for Array input

# Details
- For Matrix input: Processes single node/location data
- For Array input: Processes multiple nodes/locations simultaneously
- If the bucket has an ODE function, solves states over time
- Calculates fluxes using the model's flux function
- Concatenates solved states (if any) with calculated fluxes for output
- Input dimensions must match number of input variables defined in model
- Required parameters and initial states must be present in pas
"""

function (ele::HydroBucket{F,D,FF,OF,M})(
    input::AbstractArray{T,2},
    pas::ComponentVector;
    config::NamedTuple=NamedTuple(),
    kwargs...
) where {F,D,FF,OF<:Function,M,T}
    #* get kwargs
    solver = get(config, :solver, ManualSolver{true}())
    interp = get(config, :interp, LinearInterpolation)
    timeidx = get(config, :timeidx, collect(1:size(input, 2)))
    #* check input data
    check_input(ele, input, timeidx)
    #* get initial states matrix
    check_initstates(ele, pas)
    initstates_mat = collect(pas[:initstates][get_state_names(ele)])
    #* extract params and nn params function
    param_func, nn_param_func = _get_parameter_extractors(ele, pas)
    itpfunc_list = map((var) -> interp(var, timeidx, extrapolate=true), eachrow(input))
    ode_input_func = (t) -> [itpfunc(t) for itpfunc in itpfunc_list]
    du_func = _get_du_func(ele, ode_input_func, param_func, nn_param_func)

    #* solve the problem by call the solver
    solved_states = solver(du_func, pas, initstates_mat, timeidx)
    #* Store the solved bucket state in fluxes
    fluxes = cat(input, solved_states, dims=1)

    #* calculate output, slice input on time dim, then calculate each output
    params_vec, nn_params_vec = param_func(pas), nn_param_func(pas)
    flux_output = ele.flux_func.(eachslice(fluxes, dims=2), Ref(params_vec), Ref(nn_params_vec), timeidx)
    #* convert vector{vector} to matrix
    flux_output_mat = reduce(hcat, flux_output)
    #* merge output and state, if solved_states is not nothing, then cat it at the first dim
    output_mat = cat(solved_states, flux_output_mat, dims=1)
    output_mat
end

function (ele::HydroBucket{F,D,FF,OF,M})(
    input::AbstractArray{T,2},
    pas::ComponentVector;
    config::NamedTuple=NamedTuple(),
    kwargs...
) where {F,D,FF,OF<:Nothing,M,T}
    #* get kwargs
    timeidx = get(config, :timeidx, collect(1:size(input, 2)))
    #* check input and parameter
    check_input(ele, input, timeidx)
    #* extract params and nn params
    param_func, nn_param_func = _get_parameter_extractors(ele, pas)
    #* calculate output, slice input on time dim, then calculate each output
    params_vec, nn_params_vec = param_func(pas), nn_param_func(pas)
    flux_output = ele.flux_func.(eachslice(input, dims=2), Ref(params_vec), Ref(nn_params_vec), timeidx)
    #* convert vector{vector} to matrix
    flux_output_mat = reduce(hcat, flux_output)
    flux_output_mat
end

function (ele::HydroBucket{F,D,FF,OF,M})(
    input::AbstractArray{T,3},
    pas::ComponentVector;
    config::NamedTuple=NamedTuple(),
    kwargs...
) where {F,D,FF,OF<:Function,M,T}
    #* get kwargs
    solver = get(config, :solver, ManualSolver{true}())
    interp = get(config, :interp, LinearInterpolation)
    ptypes = get(config, :ptypes, collect(keys(pas[:params])))
    stypes = get(config, :stypes, collect(keys(pas[:initstates])))
    timeidx = get(config, :timeidx, collect(1:size(input, 3)))
    #* check input data
    check_input(ele, input, timeidx)
    #* check ptypes and stypes
    check_ptypes(ele, input, ptypes)
    check_stypes(ele, input, stypes)
    #* check initial states
    check_initstates(ele, pas, stypes)
    #* prepare initial states
    init_states_mat = reduce(hcat, [collect(pas[:initstates][stype][get_state_names(ele)]) for stype in stypes])
    #* extract params and nn params
    param_func, nn_param_func = _get_parameter_extractors(ele, pas, ptypes)
    #* prepare input function
    itpfunc_vecs = [interp.(eachslice(input[:, i, :], dims=1), Ref(timeidx), extrapolate=true) for i in 1:size(input)[2]]
    ode_input_func = (t) -> [[itpfunc(t) for itpfunc in itpfunc_vec] for itpfunc_vec in itpfunc_vecs]
    #* build differential equation function
    du_func = _get_dum_func(ele, ode_input_func, param_func, nn_param_func)
    #* Call the solve_prob method to solve the state of bucket at the specified timeidx
    solved_states = solver(du_func, pas, init_states_mat, timeidx; convert_to_array=true)
    #* Store the solved bucket state in fluxes
    fluxes = cat(input, solved_states, dims=1)
    #* array dims: (num of node, sequence length, variable dim)
    ele_output_vec = [ele.flux_func.(eachslice(fluxes[:, :, i], dims=2), param_func(pas), nn_param_func(pas), timeidx[i]) for i in axes(fluxes, 3)]
    ele_output_arr = reduce((m1, m2) -> cat(m1, m2, dims=3), [reduce(hcat, u) for u in ele_output_vec])
    #* merge state and output, if solved_states is not nothing, then cat it at the first dim
    output_arr = cat(solved_states, ele_output_arr, dims=1)
    output_arr
end

function (ele::HydroBucket{F,D,FF,OF,M})(
    input::AbstractArray{T,3},
    pas::ComponentVector;
    config::NamedTuple=NamedTuple(),
    kwargs...
) where {F,D,FF,OF<:Nothing,M,T}
    #* get kwargs
    ptypes = get(config, :ptypes, collect(keys(pas[:params])))
    timeidx = get(config, :timeidx, collect(1:size(input, 3)))
    #* check input data
    check_input(ele, input, timeidx)
    #* check ptypes and stypes
    check_ptypes(ele, input, ptypes)
    #* extract params and nn params
    param_func, nn_param_func = _get_parameter_extractors(ele, pas, ptypes)
    #* array dims: (num of node, sequence length, variable dim)
    ele_output_vec = [ele.flux_func.(eachslice(input[:, :, i], dims=2), param_func(pas), nn_param_func(pas), timeidx[i]) for i in 1:size(input)[3]]
    output_arr = reduce((m1, m2) -> cat(m1, m2, dims=3), [reduce(hcat, u) for u in ele_output_vec])
    output_arr
end