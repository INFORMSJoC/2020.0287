function iterate!(ph::AbstractProgressiveHedging, ::AbstractProgressiveHedgingExecution)
    # Resolve all subproblems at the current optimal solution
    Q = resolve_subproblems!(ph)
    if !(Q.status ∈ AcceptableTermination)
        # Early termination log
        log!(ph; status = Q.status)
        return Q.status
    end
    ph.data.Q = Q.value
    # Update iterate
    update_iterate!(ph)
    # Update subproblems
    update_subproblems!(ph)
    # Get dual gap
    update_dual_gap!(ph)
    # Update penalty (if applicable)
    update_penalty!(ph)
    # Check optimality
    if check_optimality(ph)
        # Final log
        log!(ph; optimal = true)
        # Optimal
        return MOI.OPTIMAL
    end
    # Log progress
    log!(ph)
    # Dont return a status as procedure should continue
    return nothing
end

function finish_initilization!(execution::AbstractProgressiveHedgingExecution, penalty::AbstractFloat)
    @sync begin
        for w in workers()
            @async remotecall_fetch(
                w,
                execution.subworkers[w-1],
                penalty) do sw, penalty
                    for subproblem in fetch(sw)
                        initialize!(subproblem, penalty)
                    end
                end
        end
    end
    return nothing
end

function start_workers!(::AbstractProgressiveHedging, ::AbstractProgressiveHedgingExecution)
    return nothing
end

function close_workers!(::AbstractProgressiveHedging, ::AbstractProgressiveHedgingExecution)
    return nothing
end
