# MIT License
#
# Copyright (c) 2018 Martin Biel
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

@info "Running functionality tests..."
@testset "Distributed Stochastic Programs" begin
    for (model, _scenarios, res, name) in problems
        tol = 1e-2
        sp = instantiate(model,
                         _scenarios,
                         optimizer = LShaped.Optimizer)
        @test_throws UnloadableStructure optimize!(sp)
        set_silent(sp)
        set_optimizer_attribute(sp, MasterOptimizer(), GLPK.Optimizer)
        set_optimizer_attribute(sp, SubProblemOptimizer(), GLPK.Optimizer)
        if name == "Infeasible" || name == "Vectorized Infeasible"
            set_optimizer_attribute(sp, FeasibilityStrategy(), FeasibilityCuts())
        end
        @testset "Distributed SP Constructs: $name" begin
            optimize!(sp, cache = true)
            @test termination_status(sp) == MOI.OPTIMAL
            @test isapprox(optimal_decision(sp), res.x̄, rtol = tol)
            for i in 1:num_scenarios(sp)
                @test isapprox(optimal_recourse_decision(sp, i), res.ȳ[i], rtol = tol)
            end
            @test isapprox(objective_value(sp), res.VRP, rtol = tol)
            @test isapprox(EWS(sp), res.EWS, rtol = tol)
            @test isapprox(EVPI(sp), res.EVPI, rtol = tol)
            @test isapprox(VSS(sp), res.VSS, rtol = tol)
            @test isapprox(EV(sp), res.EV, rtol = tol)
            @test isapprox(EEV(sp), res.EEV, rtol = tol)
        end
        @testset "Distributed Sanity Check: $name" begin
            sp_nondist = copy(sp, instantiation = StageDecomposition())
            add_scenarios!(sp_nondist, scenarios(sp))
            set_optimizer(sp_nondist, LShaped.Optimizer)
            set_silent(sp_nondist)
            set_optimizer_attribute(sp_nondist, Execution(), Serial())
            set_optimizer_attribute(sp_nondist, MasterOptimizer(), GLPK.Optimizer)
            set_optimizer_attribute(sp_nondist, SubProblemOptimizer(), GLPK.Optimizer)
            if name == "Infeasible" || name == "Vectorized Infeasible"
                set_optimizer_attribute(sp_nondist, FeasibilityStrategy(), FeasibilityCuts())
            end
            optimize!(sp_nondist)
            @test termination_status(sp_nondist) == MOI.OPTIMAL
            @test scenario_type(sp) == scenario_type(sp_nondist)
            @test isapprox(stage_probability(sp), stage_probability(sp_nondist))
            @test num_scenarios(sp) == num_scenarios(sp_nondist)
            @test num_scenarios(sp) == length(scenarios(sp))
            @test num_subproblems(sp) == num_subproblems(sp_nondist)
            @test isapprox(optimal_decision(sp), optimal_decision(sp_nondist))
            for i in 1:num_scenarios(sp)
                @test isapprox(optimal_recourse_decision(sp, i), optimal_recourse_decision(sp_nondist, i), rtol = sqrt(tol))
            end
            @test isapprox(objective_value(sp), objective_value(sp_nondist))
        end
        @testset "Distributed Inequalities: $name" begin
            @test EWS(sp) <= VRP(sp)
            @test VRP(sp) <= EEV(sp)
            @test VSS(sp) >= 0
            @test EVPI(sp) >= 0
            @test VSS(sp) <= EEV(sp) - EV(sp)
            @test EVPI(sp) <= EEV(sp) - EV(sp)
        end
        @testset "Distributed Copying: $name" begin
            sp_copy = copy(sp, optimizer = LShaped.Optimizer)
            set_silent(sp_copy)
            add_scenarios!(sp_copy, scenarios(sp))
            @test num_scenarios(sp_copy) == num_scenarios(sp)
            generate!(sp_copy)
            @test num_subproblems(sp_copy) == num_subproblems(sp)
            set_optimizer_attribute(sp_copy, MasterOptimizer(), () -> GLPK.Optimizer())
            set_optimizer_attribute(sp_copy, SubProblemOptimizer(), () -> GLPK.Optimizer())
            if name == "Infeasible" || name == "Vectorized Infeasible"
                set_optimizer_attribute(sp_copy, FeasibilityStrategy(), FeasibilityCuts())
            end
            optimize!(sp)
            optimize!(sp_copy)
            @test termination_status(sp_copy) == MOI.OPTIMAL
            @test isapprox(optimal_decision(sp_copy), optimal_decision(sp), rtol = tol)
            for i in 1:num_scenarios(sp)
                @test isapprox(optimal_recourse_decision(sp_copy, i), optimal_recourse_decision(sp, i), rtol = sqrt(tol))
            end
            @test isapprox(objective_value(sp_copy), objective_value(sp), rtol = tol)
            @test isapprox(EWS(sp_copy), EWS(sp), rtol = tol)
            @test isapprox(EVPI(sp_copy), EVPI(sp), rtol = tol)
            @test isapprox(VSS(sp_copy), VSS(sp), rtol = tol)
            @test isapprox(EV(sp_copy), EV(sp), rtol = tol)
            @test isapprox(EEV(sp_copy), EEV(sp), rtol = tol)
        end
    end
end
