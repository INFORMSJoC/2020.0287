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

struct SubProblem{T <: AbstractFloat, A <: AbstractVector, PT <: AbstractPenaltyTerm}
    id::Int
    probability::T
    optimizer::MOI.AbstractOptimizer
    objective::MOI.AbstractScalarFunction

    decisions::DecisionMap
    projection_targets::Vector{MOI.VariableIndex}
    ξ::Vector{Decision{T}}

    x::A
    ρ::A

    penaltyterm::PT

    function SubProblem(model::JuMP.Model,
                        id::Integer,
                        π::AbstractFloat,
                        penaltyterm::AbstractPenaltyTerm)
        T = typeof(π)
        # Get optimizer backend and initial objective
        optimizer = backend(model)
        F = MOI.get(optimizer, MOI.ObjectiveFunctionType())
        objective = MOI.get(optimizer, MOI.ObjectiveFunction{F}())
        # Ensure that we use AffineDecisionFunction
        if !(F <: AffineDecisionFunction)
            F = AffineDecisionFunction{Float64}
            MOI.set(optimizer, MOI.ObjectiveFunction{F}(), convert(F, objective))
        end
        # Get decisions
        decisions = get_decisions(model)::Decisions
        # Optimize wait-and-see model to generate
        # initial decision
        MOI.optimize!(optimizer)
        status = MOI.get(optimizer, MOI.TerminationStatus())
        x₀ = if status in AcceptableTermination
            x₀ = map(all_decisions(decisions, 1)) do vi
                T(MOI.get(optimizer, MOI.VariablePrimal(), vi))
            end
        else
            # Fallback in case crash was unsuccessful
            x₀ = rand(T, num_decisions(decisions, 1))
        end
        A = typeof(x₀)
        ξ = map(x₀) do val
            KnownDecision(val, T)
        end
        # Penalty term
        PT = typeof(penaltyterm)
        subproblem = new{T,A,PT}(id,
                                 π,
                                 optimizer,
                                 objective,
                                 decisions[1],
                                 Vector{MOI.VariableIndex}(undef, length(x₀)),
                                 ξ,
                                 x₀,
                                 zero(x₀),
                                 penaltyterm)
        return subproblem
    end
end

struct SubproblemSolution{T}
    status::MOI.TerminationStatusCode
    value::T
end
function Base.:+(lhs::SubproblemSolution{T}, rhs::SubproblemSolution{T}) where T
    val = lhs.value + rhs.value
    if lhs.status == rhs.status
        return SubproblemSolution(lhs.status, val)
    end
    # Ensure that non-optimal status is propagated
    if lhs.status in AcceptableTermination
        return SubproblemSolution(rhs.status, val)
    end
    if rhs.status in AcceptableTermination
        return SubproblemSolution(lhs.status, val)
    end
    # Let lhs dictate end status
    return SubproblemSolution(lhs.status, val)
end
Base.zero(::Type{SubproblemSolution{T}}) where T = SubproblemSolution(MOI.OPTIMAL, zero(T))

function initialize!(subproblem::SubProblem, penalty::AbstractFloat)
    # Add projection targets
    add_projection_targets!(subproblem)
    # Initialize penalty
    initialize_penaltyterm!(subproblem.penaltyterm,
                            subproblem.optimizer,
                            penalty / 2,
                            all_decisions(subproblem.decisions),
                            subproblem.projection_targets)
end

function add_projection_targets!(subproblem::SubProblem)
    ξ = subproblem.ξ
    model = subproblem.optimizer
    for i in eachindex(ξ)
        name = add_subscript(:ξ, i)
        set = SingleDecisionSet(2, ξ[i], NoSpecifiedConstraint(), false)
        var_index, _ = MOI.add_constrained_variable(model, set)
        set_decision!(subproblem.decisions, var_index, ξ[i])
        MOI.set(model, MOI.VariableName(), var_index, name)
        subproblem.projection_targets[i] = var_index
    end
    return nothing
end

function update_subproblem!(subproblem::SubProblem, ξ::AbstractVector, r::AbstractFloat)
    x = subproblem.x
    ρ = subproblem.ρ
    ρ .= ρ + r * (x - ξ)
    return nothing
end
update_subproblems!(subproblems::Vector{<:SubProblem}, ξ::AbstractVector, r::AbstractFloat) =
    map(prob -> update_subproblem!(prob, ξ, r), subproblems)

function reformulate_subproblem!(subproblem::SubProblem, ξ::AbstractVector, r::AbstractFloat)
    model = subproblem.optimizer
    f = subproblem.objective
    F = AffineDecisionFunction{Float64}
    # Update dual penalty
    for (i,vi) in enumerate(all_decisions(subproblem.decisions))
        j = if typeof(f) <: AffineDecisionFunction
            j = something(findfirst(t -> t.variable_index == vi,
                                    f.decision_part.terms), 0)
        else
            j = 0
        end
        coefficient = iszero(j) ? 0.0 : f.decision_part.terms[j].coefficient
        MOI.modify(model, MOI.ObjectiveFunction{F}(),
                   DecisionCoefficientChange(vi, coefficient + subproblem.ρ[i]))
    end
    # Update projection targets
    for i in eachindex(ξ)
        subproblem.ξ[i].value = ξ[i]
    end
    # Update penalty
    update_penaltyterm!(subproblem.penaltyterm,
                        model,
                        r / 2,
                        all_decisions(subproblem.decisions),
                        subproblem.projection_targets)
    return nothing
end

function restore_subproblem!(subproblem::SubProblem)
    model = subproblem.optimizer
    # Delete penalty-term
    remove_penalty!(subproblem.penaltyterm, model)
    # Delete projection targets
    for var in subproblem.projection_targets
        remove_decision!(subproblem.decisions, var)
        MOI.delete(model, var)
    end
    empty!(subproblem.projection_targets)
    # Restore objective
    f = subproblem.objective
    F = typeof(f)
    MOI.set(model, MOI.ObjectiveFunction{F}(), f)
    return nothing
end

function (subproblem::SubProblem{T})(ξ::AbstractVector) where T <: AbstractFloat
    MOI.optimize!(subproblem.optimizer)
    status = MOI.get(subproblem.optimizer, MOI.TerminationStatus())
    if status ∈ AcceptableTermination
        subproblem.x .= _get_iterate(subproblem)
        return SubproblemSolution(status, T(_objective_value(subproblem)))
    elseif status == MOI.INFEASIBLE
        val = MOI.get(subproblem.optimizer, MOI.ObjectiveSense()) == MOI.MAX_SENSE ? -Inf : Inf
        return SubproblemSolution(status, T(val))
    elseif status == MOI.DUAL_INFEASIBLE
        val = MOI.get(subproblem.optimizer, MOI.ObjectiveSense()) == MOI.MAX_SENSE ? Inf : -Inf
        return SubproblemSolution(status, T(val))
    else
        return SubproblemSolution(status, NaN)
    end
end

function _objective_value(subproblem::SubProblem)
    objective = subproblem.objective
    obj_val = MOIU.eval_variables(objective) do vi
        MOI.get(subproblem.optimizer, MOI.VariablePrimal(), vi)
    end
    return subproblem.probability * obj_val
end

function _get_iterate(subproblem::SubProblem)
    return map(all_decisions(subproblem.decisions)) do vi
        MOI.get(subproblem.optimizer, MOI.VariablePrimal(), vi)
    end
end
