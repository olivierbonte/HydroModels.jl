mutable struct ParamInfo{T<:Number}
    name::Symbol
    default::T
    lb::T
    ub::T
    value::T
end

function ParamInfo(name::Symbol, default::T; lb::T=nothing, ub::T=nothing) where {T<:Number}
    lb = isnothing(lb) ? default : lb
    ub = isnothing(ub) ? default : ub
    ParamInfo{T}(name, default, lb, ub, default)
end

function update_paraminfos!(paraminfos::Vector{ParamInfo{T}}, paramvalues::Vector{T}) where {T<:Number}
    for (idx, value) in enumerate(paramvalues)
        paraminfos[idx].value = value
    end
end