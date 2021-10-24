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

"""
    SynchronousExecution

Functor object for using synchronous execution in a progressive-hedging algorithm (assuming multiple Julia cores are available). Create by supplying a [`Synchronous`](@ref) object through `execution` in the `ProgressiveHedgingSolver` factory function and then pass to a `StochasticPrograms.jl` model.

"""
struct SynchronousExecution{T <: AbstractFloat,
                            A <: AbstractVector,
                            PT <: AbstractPenaltyTerm} <: AbstractProgressiveHedgingExecution
    subworkers::Vector{SubWorker{T,A,PT}}

    function SynchronousExecution(::Type{T}, ::Type{A}, ::Type{PT}) where {T <: AbstractFloat,
                                                                           A <: AbstractVector,
                                                                           PT <: AbstractPenaltyTerm}
        return new{T,A,PT}(Vector{SubWorker{T,A,PT}}(undef, nworkers()))
    end
end

function initialize_subproblems!(ph::AbstractProgressiveHedging,
                                 execution::SynchronousExecution,
                                 scenarioproblems::DistributedScenarioProblems,
                                 penaltyterm::AbstractPenaltyTerm)
    # Create subproblems on worker processes
    initialize_subproblems!(ph,
                            execution.subworkers,
                            scenarioproblems,
                            penaltyterm)
    # Initial reductions
    update_iterate!(ph)
    update_dual_gap!(ph)
    return nothing
end

function restore_subproblems!(::AbstractProgressiveHedging, execution::SynchronousExecution)
    restore_subproblems!(execution.subworkers)
    return nothing
end

function resolve_subproblems!(ph::AbstractProgressiveHedging, execution::SynchronousExecution{T}) where T <: AbstractFloat
    partial_solutions = Vector{SubproblemSolution{T}}(undef, nworkers())
    @sync begin
        for (i,w) in enumerate(workers())
            @async partial_solutions[i] = remotecall_fetch(resolve_subproblems!,
                                                           w,
                                                           execution.subworkers[w-1],
                                                           ph.ξ,
                                                           penalty(ph))
        end
    end
    return sum(partial_solutions)
end

function update_iterate!(ph::AbstractProgressiveHedging, execution::SynchronousExecution{T,A}) where {T <: AbstractFloat, A <: AbstractVector}
    partial_primals = Vector{A}(undef, nworkers())
    @sync begin
        for (i,w) in enumerate(workers())
            @async partial_primals[i] = remotecall_fetch(collect_primals,
                                                         w,
                                                         execution.subworkers[w-1],
                                                         length(ph.ξ))
        end
    end
    ξ_prev = copy(ph.ξ)
    ph.ξ .= sum(partial_primals)
    # Update δ₁
    ph.data.δ₁ = norm(ph.ξ - ξ_prev, 2) ^ 2
    return nothing
end

function update_subproblems!(ph::AbstractProgressiveHedging, execution::SynchronousExecution)
    # Update dual prices
    @sync begin
        for w in workers()
            @async remotecall_fetch(
                w,
                execution.subworkers[w-1],
                ph.ξ,
                penalty(ph)) do sw, ξ, r
                    subproblems = fetch(sw)
                    if length(subproblems) > 0
                        update_subproblems!(subproblems, ξ, r)
                    end
                end
        end
    end
    return nothing
end

function update_dual_gap!(ph::AbstractProgressiveHedging, execution::SynchronousExecution)
    return update_dual_gap!(ph, execution.subworkers)
end

function calculate_objective_value(ph::AbstractProgressiveHedging, execution::SynchronousExecution)
    return calculate_objective_value(execution.subworkers)
end

function scalar_subproblem_reduction(value::Function, execution::SynchronousExecution{T}) where T <: AbstractFloat
    partial_results = Vector{T}(undef, nworkers())
    @sync begin
        for (i,w) in enumerate(workers())
            @async partial_results[i] = remotecall_fetch(w, execution.subworkers[w-1], value) do sw, value
                subproblems = fetch(sw)
                return mapreduce(+, subproblems, init = zero(T)) do subproblem
                    π = subproblem.probability
                    return π * value(subproblem)
                end
            end
        end
    end
    return sum(partial_results)
end

function vector_subproblem_reduction(value::Function, execution::SynchronousExecution{T,A}, n::Integer) where {T <: AbstractFloat, A <: AbstractVector}
    partial_results = Vector{A}(undef, nworkers())
    @sync begin
        for (i,w) in enumerate(workers())
            @async partial_results[i] = remotecall_fetch(w, execution.subworkers[w-1], value, n) do sw, value, n
                subproblems = fetch(sw)
                return mapreduce(+, subproblems, init = zero(T, n)) do subproblem
                    π = subproblem.probability
                    return π * value(subproblem)
                end
            end
        end
    end
    return sum(partial_results)
end

# API
# ------------------------------------------------------------
function (execution::Synchronous)(::Type{T}, ::Type{A}, ::Type{PT}) where {T <: AbstractFloat,
                                                                           A <: AbstractVector,
                                                                           PT <: AbstractPenaltyTerm}
    return SynchronousExecution(T,A,PT)
end

function str(::Synchronous)
    return "Synchronous "
end
