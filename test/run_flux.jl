@testset "test simple flux (build by Symbolics.jl)" begin
    @variables a b c
    @parameters p1 p2
    simple_flux_1 = HydroModels.SimpleFlux([a, b] => [c], [p1, p2], exprs=[a * p1 + b * p2])
    @test HydroModels.get_input_names(simple_flux_1) == [:a, :b]
    @test HydroModels.get_param_names(simple_flux_1) == [:p1, :p2]
    @test HydroModels.get_output_names(simple_flux_1) == [:c,]
    @test simple_flux_1([2.0, 3.0], ComponentVector(params=(p1=3.0, p2=4.0))) == [2.0 * 3.0 + 3.0 * 4.0]
    @test simple_flux_1([2.0 3.0 1.0; 3.0 2.0 2.0], ComponentVector(params=(p1=3.0, p2=4.0))) == [2.0 * 3.0 + 3.0 * 4.0 3.0 * 3.0 + 2.0 * 4.0 1.0 * 3.0 + 2.0 * 4.0]
end

@testset "test simple flux (build by symbol)" begin
    simple_flux_1 = HydroModels.SimpleFlux([:a, :b] => [:c, :d], [:p1, :p2],
        flux_funcs=[(i, p) -> i[1] * p[1] + i[2] * p[2], (i, p) -> i[1] / p[1] + i[2] / p[2]])
    @test HydroModels.get_input_names(simple_flux_1) == [:a, :b]
    @test HydroModels.get_param_names(simple_flux_1) == [:p1, :p2]
    @test HydroModels.get_output_names(simple_flux_1) == [:c, :d]
    @test simple_flux_1([2.0, 3.0], [3.0, 4.0]) == [2.0 * 3.0 + 3.0 * 4.0, 2.0 / 3.0 + 3.0 / 4.0]
    @test simple_flux_1([2.0 3.0 1.0; 3.0 2.0 2.0], ComponentVector(params=(p1=3.0, p2=4.0))) == [
        2.0*3.0+3.0*4.0 3.0*3.0+2.0*4.0 1.0*3.0+2.0*4.0;
        2.0/3.0+3.0/4.0 3.0/3.0+2.0/4.0 1.0/3.0+2.0/4.0
    ]
end

@testset "test state flux (build by Symbolics.jl)" begin
    @variables a b c d e
    @parameters p1 p2
    simple_flux_1 = HydroModels.SimpleFlux([a, b] => [c], [p1, p2], exprs=[a * p1 + b * p2])
    simple_flux = HydroModels.SimpleFlux([a, b] => [d], [p1, p2], exprs=[a / p1 + b / p2])
    state_flux_1 = HydroModels.StateFlux([a, b] => [c, d], e)
    @test HydroModels.get_input_names(state_flux_1) == [:a, :b, :c, :d]
    @test HydroModels.get_param_names(state_flux_1) == Symbol[]
    @test HydroModels.get_output_names(state_flux_1) == Symbol[]
    @test HydroModels.get_state_names(state_flux_1) == [:e]

    state_flux = HydroModels.StateFlux([a, b, c, d], e, [p1, p2], expr=a * p1 + b * p2 - c - d)
    @test HydroModels.get_input_names(state_flux) == [:a, :b, :c, :d]
    @test HydroModels.get_param_names(state_flux) == [:p1, :p2]
    @test HydroModels.get_output_names(state_flux) == Symbol[]
    @test HydroModels.get_state_names(state_flux) == [:e]

    state_flux_3 = HydroModels.StateFlux(d => e)
    @test HydroModels.get_input_names(state_flux_3) == [:e,]
    @test HydroModels.get_param_names(state_flux_3) == Symbol[]
    @test HydroModels.get_output_names(state_flux_3) == Symbol[]
    @test HydroModels.get_state_names(state_flux_3) == [:d,]
end

@testset "test unit hydro flux" begin
    @variables q1
    @parameters x1
    router = HydroModels.UnitHydroRouteFlux(q1, x1, HydroModels.uh_1_half)
    @test HydroModels.get_input_names(router) == [:q1]
    @test HydroModels.get_param_names(router) == [:x1]
    @test HydroModels.get_output_names(router) == [:q1_routed]
    @test router(Float32[2 3 4 2 3 1], ComponentVector(x1=3.5)) ≈ [0.043634488475497855 0.334102918508042 1.2174967306061588 2.519953682639187 3.2301609643779736 2.7991762465729138]
end

@testset "test neural flux (single output)" begin
    @variables a b c d e
    nn_1 = Lux.Chain(
        layer_1=Lux.Dense(3, 16, Lux.leakyrelu),
        layer=Lux.Dense(16, 16, Lux.leakyrelu),
        layer_3=Lux.Dense(16, 1, Lux.leakyrelu),
        name=:testnn
    )
    nn_ps = ComponentVector(LuxCore.initialparameters(StableRNG(42), nn_1))
    nn_ps_vec = collect(ComponentVector(LuxCore.initialparameters(StableRNG(42), nn_1)))
    func_1 = (x, p) -> LuxCore.stateless_apply(nn_1, x, p)
    nn_flux_1 = HydroModels.NeuralFlux([a, b, c] => [d], nn_1)
    @test HydroModels.get_input_names(nn_flux_1) == [:a, :b, :c]
    @test HydroModels.get_param_names(nn_flux_1) == Symbol[]
    @test HydroModels.get_nn_names(nn_flux_1) == [:testnn]
    @test HydroModels.get_output_names(nn_flux_1) == [:d]
    test_input = [1 3 3; 2 2 2; 1 2 1; 3 1 2]
    @test nn_flux_1([1, 2, 3], ComponentVector(nn=(testnn=nn_ps_vec,))) ≈ func_1([1, 2, 3], nn_ps)
    @test nn_flux_1(test_input, ComponentVector(nn=(testnn=nn_ps_vec,))) ≈ func_1(test_input', nn_ps)
end

@testset "test neural flux (multiple output)" begin
    @variables a b c d e
    nn = Lux.Chain(
        layer_1=Lux.Dense(3, 16, Lux.leakyrelu),
        layer_2=Lux.Dense(16, 16, Lux.leakyrelu),
        layer_3=Lux.Dense(16, 2, Lux.leakyrelu),
        name=:testnn
    )
    nn_ps = LuxCore.initialparameters(StableRNG(42), nn)
    func = (x, p) -> LuxCore.stateless_apply(nn, x, p)
    nn_flux = HydroModels.NeuralFlux([a, b, c] => [d, e], nn)
    @test HydroModels.get_input_names(nn_flux) == [:a, :b, :c]
    @test HydroModels.get_param_names(nn_flux) == Symbol[]
    @test HydroModels.get_nn_names(nn_flux) == [:testnn]
    @test HydroModels.get_output_names(nn_flux) == [:d, :e]
    test_input = [1 3 3; 2 2 2; 1 2 1; 3 1 2]
    @test nn_flux([1, 2, 3], ComponentVector(nn=(testnn=nn_ps_vec,))) ≈ func([1, 2, 3], nn_ps)
    @test nn_flux(test_input, ComponentVector(nn=(testnn=nn_ps_vec,))) ≈ func(test_input', nn_ps)
end

@testset "test runtime flux function building" begin
    @variables a b c d e
    @parameters x1 x2
    inputs = [a, b, c]
    outputs = [d, e]
    params = [x1, x2]
    exprs = [x1 * a + x2 * b + c, x1 * c + x2]
    func = HydroModels.build_flux_func(inputs, outputs, params, exprs)
    @test func([1, 2, 1], [2, 1]) == [2 * 1 + 1 * 2 + 1, 2 * 1 + 1]
end
