@variables t
const D = Differential(t)

struct MTKElement <: AbstractElement
    name::Symbol

    # attribute
    input_names::Vector{Symbol}
    output_names::Vector{Symbol}
    param_names::Vector{Symbol}
    state_names::Vector{Symbol}

    # mtk.jl 相关的变量
    var_dict::Dict{Symbol,Num}
    param_dict::Dict{Symbol,Num}

    # functions
    funcs::Vector{AbstractFlux}
    dfuncs::Vector{AbstractFlux}

    func_sys::ODESystem
    dfunc_sys::ODESystem
end

function MTKElement(
    ; name::Symbol,
    funcs::Vector{F},
    dfuncs::Vector{F}
) where {F<:AbstractFlux}

    # combine the info of func and d_func
    input_names1, output_names, param_names1 = get_func_infos(funcs)
    input_names2, state_names, param_names2 = get_dfunc_infos(dfuncs)
    # 避免一些中间变量混淆为输入要素
    setdiff!(input_names2, output_names)
    # 合并两种func的输入要素
    input_names = union(input_names1, input_names2)
    # 删除输入要素的状态要素
    setdiff!(input_names, state_names)
    param_names = union(param_names1, param_names2)

    # prepare mtk building
    # 构建参数和变量
    var_dict = Dict(nm => first(eval(Meta.parse("@variables $nm(t)"))) for nm in vcat(input_names, output_names, state_names))
    param_dict = Dict(nm => first(eval(Meta.parse("@parameters $nm"))) for nm in param_names)
    # 构建函数系统
    func_sys = build_func_system(funcs, var_dict, param_dict, name=Symbol(name, :_funcs))
    dfunc_sys = build_dfunc_system(dfuncs, var_dict, param_dict, name=Symbol(name, :_dfuncs))

    return MTKElement(
        name,
        input_names,
        output_names,
        param_names,
        state_names,
        var_dict,
        param_dict,
        funcs,
        dfuncs,
        func_sys,
        dfunc_sys
    )
end

function data_itp(t, time::AbstractVector, value::AbstractVector)
    itp = LinearInterpolation(value, time, extrapolate=true)
    itp(t)
end

function build_interpolation_system(
    input::ComponentVector{T},
    time::Vector{T};
    name::Symbol=:interpolator
) where {T<:Number}
    eqs = []
    for nm in keys(input)
        func_nm = Symbol(nm, "_itp")
        tmp_itp = data_itp(t, time, input[nm])
        eval(:($(func_nm)(t) = $tmp_itp))
        # eval(:(@register_symbolic $(func_nm)(t)))
        push!(eqs, eval(:($nm ~ $(func_nm)(t))))
    end
    ODESystem(eqs, t; name=name)
end

function build_func_system(funcs, var_dict, param_dict; name::Symbol)
    eqs = []
    for func in funcs
        tmp_input = namedtuple(get_input_names(func), [var_dict[nm] for nm in get_input_names(func)])
        tmp_param = namedtuple(func.param_names, [param_dict[nm] for nm in func.param_names])
        push!(eqs, var_dict[first(get_output_names(func))] ~ func.func(tmp_input, tmp_param, func.step_func))
    end
    ODESystem(eqs, t; name=name)
end

function build_dfunc_system(dfuncs, var_dict, param_dict; name::Symbol)
    eqs = []
    for dfunc in dfuncs
        tmp_input = namedtuple(get_input_names(dfunc), [var_dict[nm] for nm in get_input_names(dfunc)])
        tmp_param = namedtuple(dfunc.param_names, [param_dict[nm] for nm in dfunc.param_names])
        push!(eqs, D(var_dict[first(get_output_names(dfunc))]) ~ dfunc.func(tmp_input, tmp_param, dfunc.step_func))
    end
    ODESystem(eqs, t; name=name)
end

function combine_systems(ele::MTKElement, itp_sys::ODESystem)
    eqs = []
    # 先将插值系统的数据与方程的输入变量绑定
    # intersect(get_func_infos(ele.funcs)[1], ele.input_names)是指funcs的外界输入变量
    for nm in intersect(get_func_infos(ele.funcs)[1], ele.input_names)
        push!(eqs, eval(Expr(:call, :~, getproperty(ele.func_sys, nm), getproperty(itp_sys, nm))))
    end
    # intersect(get_func_infos(ele.dfuncs)[1], ele.input_names)是指funcs的外界输入变量
    for nm in intersect(get_func_infos(ele.dfuncs)[1], ele.input_names)
        push!(eqs, eval(Expr(:call, :~, getproperty(ele.dfunc_sys, nm), getproperty(itp_sys, nm))))
    end
    # 然后将func和dfunc的变量结合到一块
    # setdiff(get_func_infos(ele.dfuncs)[1], ele.input_names)是指dfuncs需要从funcs里传过来的中间变量
    for nm in setdiff(get_func_infos(ele.dfuncs)[1], ele.input_names)
        push!(eqs, eval(Expr(:call, :~, getproperty(ele.dfunc_sys, nm), getproperty(ele.func_sys, nm))))
    end
    # intersect(get_func_infos(ele.funcs)[1], ele.state_names)是指funcs需要从states_names里的输入变量
    for nm in intersect(get_func_infos(ele.funcs)[1], ele.state_names)
        push!(eqs, eval(Expr(:call, :~, getproperty(ele.func_sys, nm), getproperty(ele.dfunc_sys, nm))))
    end
    structural_simplify(compose(ODESystem(eqs, t; name=ele.name), itp_sys, ele.func_sys, ele.dfunc_sys))
end


function solve_prob(
    ele::MTKElement;
    input::ComponentVector{T},
    params::ComponentVector{T},
    init_states::ComponentVector{T},
    # solver::AbstractSolver,
) where {T<:Number}
    itp_sys = build_interpolation_system(input[ele.input_names], input[:time], name=Symbol(ele.name, :_itp))
    # combine system
    ele_sys = combine_systems(ele, itp_sys)
    # setup init states
    x0 = [eval(Expr(:call, :(=>), getproperty(getproperty(ele_sys, ele.dfunc_sys.name), nm), init_states[nm])) for nm in ele.state_names]
    # setup
    func_p = [eval(Expr(:call, :(=>), getproperty(getproperty(ele_sys, ele.func_sys.name), Symbol(nm)), params[Symbol(nm)])) for nm in ModelingToolkit.parameters(ele.func_sys)]
    dfunc_p = [eval(Expr(:call, :(=>), getproperty(getproperty(ele_sys, ele.dfunc_sys.name), Symbol(nm)), params[Symbol(nm)])) for nm in ModelingToolkit.parameters(ele.dfunc_sys)]

    prob = ODEProblem{true,SciMLBase.FullSpecialize}(ele_sys, x0, (1, length(input[:time])), vcat(func_p, dfunc_p))
    sol = solve(prob,Tsit5())
    sol
end