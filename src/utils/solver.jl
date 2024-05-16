"""
$(TYPEDEF)
A custom ODEProblem solver
# Fields
$(FIELDS)
"""
@kwdef struct ODESolver <: AbstractSolver
    alg::OrdinaryDiffEqAlgorithm = Tsit5()
    sensealg = InterpolatingAdjoint()
    reltol = 1e-3
    abstol = 1e-3
    saveat = 1.0
end

function (solver::ODESolver)(
    ode_prob::ODEProblem,
    state_names::AbstractVector{Symbol},
)
    sol = solve(
        ode_prob,
        solver.alg,
        saveat=solver.saveat,
        reltol=solver.reltol,
        abstol=solver.abstol,
        sensealg=solver.sensealg
    )
    if SciMLBase.successful_retcode(sol)
        solved_u = hcat(sol.u...)
        namedtuple(state_names, [solved_u[idx, :] for idx in 1:length(state_names)])
    else
        @error "ode failed to solve"
        false
    end

end


