@kwdef struct Pet{T<:Number} <: AbstractFunc
    input_names::Vector{Symbol}
    output_name::Symbol = :Pet
    parameters::Dict{Symbol,T}
end

function Pet(input_names::Vector{Symbol}; parameters::Dict{Symbol,T}) where {T<:Number}
    Pet{T}(id=id, input_names=input_names, parameters=parameters)
end

function get_output(ele::Pet; input::ComponentVector{T}) where {T<:Number}
    args = [input[input_nm] for input_nm in ele.input_names]
    ComponentVector(; Dict(ele.output_name => pet.(args...; ele.parameters...))...)
end


function pet(Temp::T, Lday::T) where {T<:Number}
    29.8 * Lday * 0.611 * exp((17.3 * Temp) / (Temp + 237.3)) / (Temp + 273.2)
end