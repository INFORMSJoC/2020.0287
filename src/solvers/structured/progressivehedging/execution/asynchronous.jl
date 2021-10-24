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
    AsynchronousExecution

Functor object for using asynchronous execution in a progressive-hedging algorithm (assuming multiple Julia cores are available). Create by supplying an [`Asynchronous`](@ref) object through `execution` in the `ProgressiveHedgingSolver` factory function and then pass to a `StochasticPrograms.jl` model.

"""
struct AsynchronousExecution{T <: AbstractFloat,
                             A <: AbstractVector,
                             PT <: AbstractPenaltyTerm} <: AbstractProgressiveHedgingExecution
    subworkers::Vector{SubWorker{T,A,PT}}
    work::Vector{Work}
    finalize::Vector{Work}
    progressqueue::ProgressQueue{T}
    x̄::Vector{RemoteRunningAverage{A}}
    δ::Vector{RemoteRunningAverage{T}}
    iterates::RemoteIterates{A}
    r::IteratedValue{T}
    active_workers::Vector{Future}
    # Bookkeeping
    subobjectives::Vector{A}
    finished::Vector{Int}
    # Parameters
    κ::T

    function AsynchronousExecution(κ::T,
                                   ::Type{T}, ::Type{A}, ::Type{PT}) where {T <: AbstractFloat,
                                                                            A <: AbstractVector,
                                                                            PT <: AbstractPenaltyTerm}
        return new{T,A,PT}(Vector{SubWorker{T,A,PT}}(undef, nworkers()),
                           Vector{Work}(undef, nworkers()),
                           Vector{Work}(undef, nworkers()),
                           RemoteChannel(() -> Channel{Progress{T}}(4 * nworkers())),
                           Vector{RemoteRunningAverage{A}}(undef, nworkers()),
                           Vector{RemoteRunningAverage{T}}(undef, nworkers()),
                           RemoteChannel(() -> IterationChannel(Dict{Int,A}())),
                           RemoteChannel(() -> IterationChannel(Dict{Int,T}())),
                           Vector{Future}(undef, nworkers()),
                           Vector{A}(),
                           Vector{Int}(),
                           κ)
    end
end

function initialize_subproblems!(ph::AbstractProgressiveHedging,
                                 execution::AsynchronousExecution{T,A},
                                 scenarioproblems::DistributedScenarioProblems,
                                 penaltyterm::AbstractPenaltyTerm) where {T <: AbstractFloat, A <: AbstractVector}
    # Create subproblems on worker processes
    initialize_subproblems!(ph,
                            execution.subworkers,
                            scenarioproblems,
                            penaltyterm)
    # Continue preparation
    @sync begin
        for w in workers()
            execution.work[w-1] = RemoteChannel(() -> Channel{Int}(round(Int,10/execution.κ)), w)
            execution.finalize[w-1] = RemoteChannel(() -> Channel{Int}(1), w)
            execution.x̄[w-1] = RemoteChannel(() -> Channel{RunningAverage{A}}(1), w)
            execution.δ[w-1] = RemoteChannel(() -> Channel{RunningAverage{T}}(1), w)
            @async remotecall_fetch(
                w,
                execution.subworkers[w-1],
                execution.x̄[w-1],
                length(ph.ξ)) do sw, average, xdim
                    subproblems = fetch(sw)
                    x̄ = mapreduce(+, subproblems, init = zeros(T, xdim)) do subproblem
                        x = subproblem.x
                        π = subproblem.probability
                        return π * x
                    end
                    running_average = RunningAverage(x̄, [s.x for s in subproblems])
                    put!(average, running_average)
                    return x̄
                end
            @async remotecall_fetch(
                w,
                execution.subworkers[w-1],
                execution.δ[w-1],
                length(ph.ξ)) do sw, average, xdim
                    running_average =
                        RunningAverage(zero(T),
                                       fill(zero(T), length(fetch(sw))))
                    put!(average, running_average)
                end
            put!(execution.work[w-1], 1)
        end
        # Prepare memory
        push!(execution.subobjectives, zeros(num_subproblems(ph)))
        push!(execution.finished, 0)
        log_val = ph.parameters.log
        ph.parameters.log = false
        log!(ph)
        ph.parameters.log = log_val
    end
    # Initial reductions
    update_iterate!(ph)
    # Init δ₂
    @sync begin
        for w in workers()
            @async remotecall_fetch(
                w,
                execution.subworkers[w-1],
                ph.ξ,
                execution.δ[w-1]) do sw, ξ, δ
                    for (i, subproblem) in enumerate(fetch(sw))
                        subtract!(fetch(δ), i)
                        x = subproblem.x
                        π = subproblem.probability
                        add!(fetch(δ), i, norm(x - ξ, 2) ^ 2, π)
                    end
                end
        end
    end
    update_dual_gap!(ph)
    return nothing
end

function iterate!(ph::AbstractProgressiveHedging, execution::AsynchronousExecution{T}) where T <: AbstractFloat
    wait(execution.progressqueue)
    while isready(execution.progressqueue)
        # Add new cuts from subworkers
        t::Int, i::Int, Q::SubproblemSolution{T} = take!(execution.progressqueue)
        if !(Q.status ∈ AcceptableTermination)
            # Early termination log
            log!(ph; status = Q.status)
            return Q.status
        end
        execution.subobjectives[t][i] = Q.value
        execution.finished[t] += 1
        if execution.finished[t] == num_subproblems(ph)
            # Update objective
            ph.Q_history[t] = current_objective_value(ph, execution.subobjectives[t])
            ph.data.Q = ph.Q_history[t]
        end
    end
    # Project and generate new iterate
    t = ph.data.iterations
    if execution.finished[t] >= execution.κ * num_subproblems(ph)
        # Get dual gap
        update_dual_gap!(ph)
        # Update progress
        @unpack δ₁, δ₂ = ph.data
        ph.primal_gaps[t] = δ₁
        ph.dual_gaps[t] = δ₂
        # Check if optimal
        if check_optimality(ph)
            # Optimal, final log
            log!(ph, optimal = true)
            return MOI.OPTIMAL
        end
        # Calculate time spent so far and check perform time limit check
        time_spent = ph.progress.tlast - ph.progress.tinit
        if time_spent >= ph.parameters.time_limit
            log!(ph; status = MOI.TIME_LIMIT)
            return MOI.TIME_LIMIT
        end
        # Update penalty (if applicable)
        update_penalty!(ph)
        # Update iterate
        update_iterate!(ph)
        # Send new work to workers
        put!(execution.iterates, t + 1, ph.ξ)
        put!(execution.r, t + 1, penalty(ph))
        map((w, aw) -> !isready(aw) && put!(w, t + 1), execution.work, execution.active_workers)
        # Prepare memory for next iteration
        push!(execution.subobjectives, zeros(num_subproblems(ph)))
        push!(execution.finished, 0)
        # Log progress
        log!(ph)
    end
    # Dont return a status as procedure should continue
    return nothing
end

function start_workers!(ph::AbstractProgressiveHedging, execution::AsynchronousExecution)
    # Load initial decision
    put!(execution.iterates, 1, ph.ξ)
    put!(execution.r, 1, penalty(ph))
    for w in workers()
        execution.active_workers[w-1] = remotecall(work_on_subproblems!,
                                                   w,
                                                   execution.subworkers[w-1],
                                                   execution.work[w-1],
                                                   execution.finalize[w-1],
                                                   execution.progressqueue,
                                                   execution.x̄[w-1],
                                                   execution.δ[w-1],
                                                   execution.iterates,
                                                   execution.r)
    end
    return nothing
end

function close_workers!(ph::AbstractProgressiveHedging, execution::AsynchronousExecution)
    t = ph.data.iterations-1
    map((w, aw)->!isready(aw) && put!(w, t), execution.finalize, execution.active_workers)
    map((w, aw)->!isready(aw) && put!(w, -1), execution.work, execution.active_workers)
    map(wait, execution.active_workers)
end

function restore_subproblems!(::AbstractProgressiveHedging, execution::AsynchronousExecution)
    restore_subproblems!(execution.subworkers)
    return nothing
end

function resolve_subproblems!(ph::AbstractProgressiveHedging, execution::AsynchronousExecution)
    return nothing
end

function update_iterate!(ph::AbstractProgressiveHedging, execution::AsynchronousExecution)
    ξ_prev = copy(ph.ξ)
    ph.ξ .= sum(average.(fetch.(execution.x̄)))
    # Update δ₁
    ph.data.δ₁ = norm(ph.ξ - ξ_prev, 2) ^ 2
    return nothing
end

function update_subproblems!(ph::AbstractProgressiveHedging, execution::AsynchronousExecution)
    return nothing
end

function update_dual_gap!(ph::AbstractProgressiveHedging, execution::AsynchronousExecution)
    ph.data.δ₂ = sum(average.(fetch.(execution.δ)))
    return nothing
end

function calculate_objective_value(ph::AbstractProgressiveHedging, execution::AsynchronousExecution)
    return calculate_objective_value(execution.subworkers)
end

function scalar_subproblem_reduction(value::Function, execution::AsynchronousExecution{T}) where T <: AbstractFloat
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

function vector_subproblem_reduction(value::Function, execution::AsynchronousExecution{T,A}, n::Integer) where {T <: AbstractFloat, A <: AbstractVector}
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
function (execution::Asynchronous)(::Type{T}, ::Type{A}, ::Type{PT}) where {T <: AbstractFloat,
                                                                            A <: AbstractVector,
                                                                            PT <: AbstractPenaltyTerm}
    return AsynchronousExecution(execution.κ, T, A, PT)
end

function str(::Asynchronous)
    return "Asynchronous "
end
