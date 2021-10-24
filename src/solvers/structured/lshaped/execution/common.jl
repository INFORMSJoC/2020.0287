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

function num_thetas(lshaped::AbstractLShaped, ::AbstractLShapedExecution)
    return num_thetas(num_subproblems(lshaped),
                      lshaped.aggregation,
                      scenarioproblems(lshaped.structure))
end

function timestamp(lshaped::AbstractLShaped, ::AbstractLShapedExecution)
    return lshaped.data.iterations
end

function current_decision(lshaped::AbstractLShaped, ::AbstractLShapedExecution)
    return lshaped.x
end

function incumbent_decision(::AbstractLShaped, ::Integer, regularization::AbstractRegularization, ::AbstractLShapedExecution)
    return map(regularization.ξ) do ξᵢ
        return ξᵢ.value
    end
end

function incumbent_objective(::AbstractLShaped, ::Integer, regularization::AbstractRegularization, ::AbstractLShapedExecution)
    return regularization.data.Q̃
end

function incumbent_trustregion(::AbstractLShaped, ::Integer, rd::RegularizedDecomposition, ::AbstractLShapedExecution)
    return rd.data.σ
end

function incumbent_trustregion(::AbstractLShaped, ::Integer, tr::TrustRegion, ::AbstractLShapedExecution)
    Δ = StochasticPrograms.decision(tr.decisions, tr.data.Δ)
    return Δ.value
end

function start_workers!(::AbstractLShaped, ::AbstractLShapedExecution)
    return nothing
end

function close_workers!(::AbstractLShaped, ::AbstractLShapedExecution)
    return nothing
end

function readd_cuts!(lshaped::AbstractLShaped, consolidation::Consolidation, ::AbstractLShapedExecution)
    for i in eachindex(consolidation.cuts)
        for cut in consolidation.cuts[i]
            add_cut!(lshaped, cut; consider_consolidation = false, check = false)
        end
        for cut in consolidation.feasibility_cuts[i]
            add_cut!(lshaped, cut; consider_consolidation = false, check = false)
        end
    end
    return nothing
end

function subobjectives(lshaped::AbstractLShaped, execution::AbstractLShapedExecution)
    return execution.subobjectives
end

function set_subobjectives(lshaped::AbstractLShaped, Qs::AbstractVector, execution::AbstractLShapedExecution)
    execution.subobjectives .= Qs
    return nothing
end

function model_objectives(lshaped::AbstractLShaped, execution::AbstractLShapedExecution)
    return execution.model_objectives
end

function set_model_objectives(lshaped::AbstractLShaped, θs::AbstractVector, execution::AbstractLShapedExecution)
    ids = active_model_objectives(lshaped)
    execution.model_objectives[ids] .= θs[ids]
    return nothing
end

function solve_master!(lshaped::AbstractLShaped, ::AbstractLShapedExecution)
    try
        MOI.optimize!(lshaped.master)
    catch err
        status = MOI.get(lshaped.master, MOI.TerminationStatus())
        # Master problem could not be solved for some reason.
        @unpack Q,θ = lshaped.data
        gap = abs(θ-Q)/(abs(Q)+1e-10)
        # Always print this warning
        @warn "Master problem could not be solved, solver returned status $status. The following relative tolerance was reached: $(@sprintf("%.1e",gap)). Aborting procedure."
        rethrow(err)
    end
    return MOI.get(lshaped.master, MOI.TerminationStatus())
end

function iterate!(lshaped::AbstractLShaped, ::AbstractLShapedExecution)
    # Resolve all subproblems at the current optimal solution
    Q, added = resolve_subproblems!(lshaped)
    if Q == Inf && !handle_feasibility(lshaped.feasibility)
        @warn "Stochastic program is not second-stage feasible at the current decision. Rerun procedure with feasibility_strategy = FeasibilityCuts to use feasibility cuts."
        # Early termination log
        log!(lshaped; status = MOI.INFEASIBLE)
        return MOI.INFEASIBLE
    end
    if Q == -Inf
        # Early termination log
        log!(lshaped; status = MOI.DUAL_INFEASIBLE)
        return MOI.DUAL_INFEASIBLE
    end
    lshaped.data.Q = Q
    # Update incumbent (if applicable)
    take_step!(lshaped)
    # Early gap optimality check if using level sets
    if lshaped.regularization isa LevelSet && check_optimality(lshaped, true)
        # Resolve subproblems with optimal vector
        lshaped.x .= decision(lshaped)
        resolve_subproblems!(lshaped)
        # Optimal, final log
        log!(lshaped; optimal = true)
        return MOI.OPTIMAL
    end
    # Solve master problem
    status = solve_master!(lshaped)
    if !(status ∈ AcceptableTermination)
        # Early termination log
        log!(lshaped; status = status)
        return status
    end
    # Update master solution
    update_solution!(lshaped)
    lshaped.data.θ = calculate_estimate(lshaped)
    # Handle integrality
    handle_integrality!(lshaped, lshaped.integer)
    # Log progress
    log!(lshaped)
    # Check optimality
    if check_optimality(lshaped, added)
        # Optimal, final log
        log!(lshaped; optimal = true)
        return MOI.OPTIMAL
    end
    # Calculate time spent so far and check perform time limit check
    time_spent = lshaped.progress.tlast - lshaped.progress.tinit
    if time_spent >= lshaped.parameters.time_limit
        log!(lshaped; status = MOI.TIME_LIMIT)
        return MOI.TIME_LIMIT
    end
    # Consolidate (if applicable)
    consolidate!(lshaped, lshaped.consolidation)
    # Dont return a status as procedure should continue
    return nothing
end
