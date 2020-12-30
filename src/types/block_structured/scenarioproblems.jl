struct ScenarioProblems{S <: AbstractScenario} <: AbstractScenarioProblems{S}
    scenarios::Vector{S}
    problems::Vector{JuMP.Model}

    function ScenarioProblems(scenarios::Vector{S}) where S <: AbstractScenario
        # ScenarioProblems are initialized without any subproblems.
        # These are added during generation.
        return new{S}(scenarios, Vector{JuMP.Model}())
    end
end
ScenarioProblemChannel{S} = RemoteChannel{Channel{ScenarioProblems{S}}}
DecisionChannel = RemoteChannel{Channel{Decisions}}
struct DistributedScenarioProblems{S <: AbstractScenario} <: AbstractScenarioProblems{S}
    scenario_distribution::Vector{Int}
    scenarioproblems::Vector{ScenarioProblemChannel{S}}
    decisions::Vector{DecisionChannel}

    function DistributedScenarioProblems(scenario_distribution::Vector{Int},
                                         scenarioproblems::Vector{ScenarioProblemChannel{S}},
                                         decisions::Vector{DecisionChannel}) where S <: AbstractScenario
        return new{S}(scenario_distribution, scenarioproblems, decisions)
    end
end

function DistributedScenarioProblems(_scenarios::Vector{S}) where S <: AbstractScenario
    scenarioproblems = Vector{ScenarioProblemChannel{S}}(undef, nworkers())
    decisions = Vector{DecisionChannel}(undef, nworkers())
    (nscen, extra) = divrem(length(_scenarios), nworkers())
    start = 1
    stop = nscen + (extra > 0)
    scenario_distribution = zeros(Int, nworkers())
    @sync begin
        for (i,w) in enumerate(workers())
            n = nscen + (extra > 0)
            scenarioproblems[i] = RemoteChannel(() -> Channel{ScenarioProblems{S}}(1), w)
            decisions[i] = RemoteChannel(() -> Channel{Decisions}(1), w)
            scenario_range = start:stop
            @async remotecall_fetch(
                w,
                scenarioproblems[i],
                _scenarios[scenario_range]) do sp, scenarios
                    put!(sp, ScenarioProblems(scenarios))
                end
            @async remotecall_fetch(
                w,
                decisions[i]) do channel
                    put!(channel, Decisions())
                end
            scenario_distribution[i] = n
            start = stop + 1
            stop += n
            stop = min(stop, length(_scenarios))
            extra -= 1
        end
    end
    return DistributedScenarioProblems(scenario_distribution, scenarioproblems, decisions)
end

ScenarioProblems(::Type{S}, instantiation) where S <: AbstractScenario = ScenarioProblems(Vector{S}(), instantiation)

function ScenarioProblems(scenarios::Vector{S}, ::Union{Vertical, Horizontal}) where S <: AbstractScenario
    ScenarioProblems(scenarios)
end

function ScenarioProblems(scenarios::Vector{S}, ::Union{DistributedVertical, DistributedHorizontal}) where S <: AbstractScenario
    DistributedScenarioProblems(scenarios)
end


# Base overloads #
# ========================== #
Base.getindex(sp::DistributedScenarioProblems, i::Integer) = sp.scenarioproblems[i]
# ========================== #

# MOI #
# ========================== #
function MOI.get(scenarioproblems::ScenarioProblems, attr::ScenarioDependentModelAttribute)
    MOI.get(backend(subproblem(scenarioproblems, attr.scenario_index)), attr.attr)
end
function MOI.get(scenarioproblems::DistributedScenarioProblems, attr::ScenarioDependentModelAttribute)
    isempty(scenarioproblems.scenarioproblems) && error("No remote scenario problems.")
    j = 0
    for w in workers()
        n = scenarioproblems.scenario_distribution[w-1]
        if attr.scenario_index <= n + j
            return remotecall_fetch(
                w, scenarioproblems[w-1], attr.scenario_index - j, attr.attr) do sp, i, attr
                    MOI.get(backend(fetch(sp).problems[i]), attr)
                end
        end
        j += n
    end
    throw(BoundsError(scenarioproblems, scenario_index))
end
function MOI.get(scenarioproblems::ScenarioProblems, attr::ScenarioDependentVariableAttribute, index::MOI.VariableIndex)
    MOI.get(backend(subproblem(scenarioproblems, attr.scenario_index)), attr.attr, index)
end
function MOI.get(scenarioproblems::DistributedScenarioProblems, attr::ScenarioDependentVariableAttribute, index::MOI.VariableIndex)
    isempty(scenarioproblems.scenarioproblems) && error("No remote scenario problems.")
    j = 0
    for w in workers()
        n = scenarioproblems.scenario_distribution[w-1]
        if attr.scenario_index <= n + j
            return remotecall_fetch(
                w, scenarioproblems[w-1], attr.scenario_index - j, attr.attr, index) do sp, i, attr, index
                    MOI.get(backend(fetch(sp).problems[i]), attr, index)
                end
        end
        j += n
    end
    throw(BoundsError(scenarioproblems, scenario_index))
end
function MOI.get(scenarioproblems::ScenarioProblems, attr::ScenarioDependentConstraintAttribute, ci::CI)
    MOI.get(backend(subproblem(scenarioproblems, attr.scenario_index)), attr.attr, ci)
end
function MOI.get(scenarioproblems::DistributedScenarioProblems, attr::ScenarioDependentConstraintAttribute, ci::CI)
    isempty(scenarioproblems.scenarioproblems) && error("No remote scenario problems.")
    j = 0
    for w in workers()
        n = scenarioproblems.scenario_distribution[w-1]
        if attr.scenario_index <= n + j
            return remotecall_fetch(
                w, scenarioproblems[w-1], attr.scenario_index - j, attr.attr, ci) do sp, i, attr, ci
                    MOI.get(backend(fetch(sp).problems[i]), attr, ci)
                end
        end
        j += n
    end
    throw(BoundsError(scenarioproblems, scenario_index))
end

function MOI.set(scenarioproblems::ScenarioProblems, attr::MOI.AbstractModelAttribute, value)
    for problem in subproblems(scenarioproblems)
        MOI.set(backend(problem), attr, value)
    end
    return nothing
end
function MOI.set(scenarioproblems::DistributedScenarioProblems, attr::MOI.AbstractModelAttribute, value)
    isempty(scenarioproblems.scenarioproblems) && error("No remote scenario problems.")
    @sync begin
        for (i,w) in enumerate(workers())
            @async remotecall_fetch(
                w, scenarioproblems[w-1], attr, value) do sp, attr, value
                    MOI.set(fetch(sp), attr, value)
                end
        end
    end
    return nothing
end
function MOI.set(scenarioproblems::ScenarioProblems, attr::ScenarioDependentModelAttribute, value)
    MOI.set(backend(subproblem(scenarioproblems, attr.scenario_index)), attr.attr, value)
    return nothing
end
function MOI.set(scenarioproblems::DistributedScenarioProblems, attr::ScenarioDependentModelAttribute, value)
    isempty(scenarioproblems.scenarioproblems) && error("No remote scenario problems.")
    j = 0
    for w in workers()
        n = scenarioproblems.scenario_distribution[w-1]
        if scenario_index <= n + j
            return remotecall_fetch(
                w, scenarioproblems[w-1], scenario_index - j, attr.attr, value) do sp, i, attr, value
                    MOI.set(backend(fetch(sp).problems[i]), attr, value)
                end
        end
        j += n
    end
    throw(BoundsError(scenarioproblems, scenario_index))
end
function MOI.set(scenarioproblems::ScenarioProblems, attr::MOI.AbstractOptimizerAttribute, value)
    for problem in subproblems(scenarioproblems)
        MOI.set(backend(problem), attr, value)
    end
    return nothing
end
function MOI.set(scenarioproblems::DistributedScenarioProblems, attr::MOI.AbstractOptimizerAttribute, value)
    isempty(scenarioproblems.scenarioproblems) && error("No remote scenario problems.")
    @sync begin
        for (i,w) in enumerate(workers())
            @async remotecall_fetch(
                w, scenarioproblems[w-1], attr, value) do sp, attr, value
                    MOI.set(fetch(sp), attr, value)
                end
        end
    end
    return nothing
end
function MOI.set(scenarioproblems::ScenarioProblems, attr::MOI.AbstractVariableAttribute,
                 index::MOI.VariableIndex, value)
    for problem in subproblems(scenarioproblems)
        MOI.set(backend(problem), attr, index, value)
    end
    return nothing
end
function MOI.set(scenarioproblems::DistributedScenarioProblems, attr::MOI.AbstractVariableAttribute,
                 index::MOI.VariableIndex, value)
    isempty(scenarioproblems.scenarioproblems) && error("No remote scenario problems.")
    @sync begin
        for (i,w) in enumerate(workers())
            @async remotecall_fetch(
                w, scenarioproblems[w-1], attr, index, value) do sp, attr, index, value
                    MOI.set(fetch(sp), attr, index, value)
                end
        end
    end
    return nothing
end
function MOI.set(scenarioproblems::ScenarioProblems, attr::ScenarioDependentVariableAttribute,
                 index::MOI.VariableIndex, value)
    MOI.set(backend(subproblem(scenarioproblems, attr.scenario_index)), attr.attr, index, value)
    return nothing
end
function MOI.set(scenarioproblems::DistributedScenarioProblems, attr::ScenarioDependentVariableAttribute,
                 index::MOI.VariableIndex, value)
    isempty(scenarioproblems.scenarioproblems) && error("No remote scenario problems.")
    j = 0
    for w in workers()
        n = scenarioproblems.scenario_distribution[w-1]
        if attr.scenario_index <= n + j
            return remotecall_fetch(
                w, scenarioproblems[w-1], attr.scenario_index - j, attr.attr, index, value) do sp, i, attr, index, value
                    MOI.set(backend(fetch(sp).problems[i]), attr, index, value)
                end
        end
        j += n
    end
    throw(BoundsError(scenarioproblems, scenario_index))
end
function MOI.set(scenarioproblems::ScenarioProblems, attr::MOI.AbstractConstraintAttribute, ci::MOI.ConstraintIndex, value)
    for problem in subproblems(scenarioproblems)
        MOI.set(backend(problem), attr, ci, value)
    end
    return nothing
end
function MOI.set(scenarioproblems::DistributedScenarioProblems, attr::MOI.AbstractConstraintAttribute,
                 ci::MOI.ConstraintIndex, value)
    isempty(scenarioproblems.scenarioproblems) && error("No remote scenario problems.")
    @sync begin
        for (i,w) in enumerate(workers())
            @async remotecall_fetch(
                w, scenarioproblems[w-1], attr, ci, value) do sp, attr, ci, value
                    MOI.set(fetch(sp), attr, ci, value)
                end
        end
    end
    return nothing
end
function MOI.set(scenarioproblems::ScenarioProblems, attr::ScenarioDependentConstraintAttribute,
                 ci::MOI.ConstraintIndex, value)
    MOI.set(backend(subproblem(scenarioproblems, attr.scenario_index)), attr.attr, ci, value)
    return nothing
end
function MOI.set(scenarioproblems::DistributedScenarioProblems, attr::ScenarioDependentConstraintAttribute,
                 ci::MOI.ConstraintIndex, value)
    isempty(scenarioproblems.scenarioproblems) && error("No remote scenario problems.")
    j = 0
    for w in workers()
        n = scenarioproblems.scenario_distribution[w-1]
        if attr.scenario_index <= n + j
            return remotecall_fetch(
                w, scenarioproblems[w-1], attr.scenario_index - j, attr.attr, ci, value) do sp, i, attr, ci, value
                    MOI.set(backend(fetch(sp).problems[i]), attr, ci, value)
                end
        end
        j += n
    end
    throw(BoundsError(scenarioproblems, scenario_index))
end

function MOI.is_valid(scenarioproblems::ScenarioProblems, index::MOI.VariableIndex, scenario_index::Integer)
    return MOI.is_valid(backend(subproblem(scenarioproblems, scenario_index)), index)
end
function MOI.is_valid(scenarioproblems::DistributedScenarioProblems, index::MOI.VariableIndex, scenario_index::Integer)
    isempty(scenarioproblems.scenarioproblems) && error("No remote scenario problems.")
    j = 0
    for w in workers()
        n = scenarioproblems.scenario_distribution[w-1]
        if scenario_index <= n + j
            return remotecall_fetch(
                w, scenarioproblems[w-1], scenario_index - j, index) do sp, i, index
                    MOI.is_valid(backend(fetch(sp).problems[i]), index)
                end
        end
        j += n
    end
    throw(BoundsError(scenarioproblems, scenario_index))
end

function MOI.is_valid(scenarioproblems::ScenarioProblems, ci::MOI.ConstraintIndex, scenario_index::Integer)
    return MOI.is_valid(backend(subproblem(scenarioproblems, scenario_index)), ci)
end
function MOI.is_valid(scenarioproblems::DistributedScenarioProblems, ci::MOI.ConstraintIndex, scenario_index::Integer)
    isempty(scenarioproblems.scenarioproblems) && error("No remote scenario problems.")
    j = 0
    for w in workers()
        n = scenarioproblems.scenario_distribution[w-1]
        if scenario_index <= n + j
            return remotecall_fetch(
                w, scenarioproblems[w-1], scenario_index - j, ci) do sp, i, ci
                    MOI.is_valid(backend(fetch(sp).problems[i]), ci)
                end
        end
        j += n
    end
    throw(BoundsError(scenarioproblems, scenario_index))
end

function MOI.add_constraint(scenarioproblems::ScenarioProblems, f::SingleDecision, s::MOI.AbstractSet, scenario_index::Integer)
    return MOI.add_constraint(backend(subproblem(scenarioproblems, scenario_index)), f, s)
end
function MOI.add_constraint(scenarioproblems::DistributedScenarioProblems, f::SingleDecision, s::MOI.AbstractSet, scenario_index::Integer)
    isempty(scenarioproblems.scenarioproblems) && error("No remote scenario problems.")
    j = 0
    for w in workers()
        n = scenarioproblems.scenario_distribution[w-1]
        if scenario_index <= n + j
            return remotecall_fetch(
                w, scenarioproblems[w-1], scenario_index - j, f, s) do sp, i, f, s
                    MOI.add_constraint(backend(fetch(sp).problems[i]), f, s)
                end
        end
        j += n
    end
    throw(BoundsError(scenarioproblems, scenario_index))
end

function MOI.delete(scenarioproblems::ScenarioProblems, index::MOI.VariableIndex, scenario_index::Integer)
    subprob = subproblem(scenarioproblems, scenario_index)
    JuMP.delete(subprob, DecisionRef(subprob, index))
    return nothing
end
function MOI.delete(scenarioproblems::DistributedScenarioProblems, index::MOI.VariableIndex, scenario_index::Integer)
    isempty(scenarioproblems.scenarioproblems) && error("No remote scenario problems.")
    j = 0
    for w in workers()
        n = scenarioproblems.scenario_distribution[w-1]
        if scenario_index <= n + j
            return remotecall_fetch(
                w, scenarioproblems[w-1], scenario_index - j, index) do sp, i, index
                    subprob = fetch(sp).problems[i]
                    JuMP.delete(subprob, DecisionRef(subprob, index))
                end
        end
        j += n
    end
    throw(BoundsError(scenarioproblems, scenario_index))
end
function MOI.delete(scenarioproblems::ScenarioProblems, indices::Vector{MOI.VariableIndex}, scenario_index::Integer)
    subprob = subproblem(scenarioproblems, scenario_index)
    JuMP.delete(subprob, DecisionRef.(subprob, indices))
    return nothing
end
function MOI.delete(scenarioproblems::DistributedScenarioProblems, indices::Vector{MOI.VariableIndex}, scenario_index::Integer)
    isempty(scenarioproblems.scenarioproblems) && error("No remote scenario problems.")
    j = 0
    for w in workers()
        n = scenarioproblems.scenario_distribution[w-1]
        if scenario_index <= n + j
            return remotecall_fetch(
                w, scenarioproblems[w-1], scenario_index - j, indices) do sp, i, indices
                    subprob = fetch(sp).problems[i]
                    JuMP.delete(subprob, DecisionRef.(subprob, indices))
                end
        end
        j += n
    end
    throw(BoundsError(scenarioproblems, scenario_index))
end
function MOI.delete(scenarioproblems::ScenarioProblems, ci::MOI.ConstraintIndex, scenario_index::Integer)
    MOI.delete(backend(subproblem(scenarioproblems, scenario_index)), ci)
    return nothing
end
function MOI.delete(scenarioproblems::DistributedScenarioProblems, ci::MOI.ConstraintIndex, scenario_index::Integer)
    isempty(scenarioproblems.scenarioproblems) && error("No remote scenario problems.")
    j = 0
    for w in workers()
        n = scenarioproblems.scenario_distribution[w-1]
        if scenario_index <= n + j
            return remotecall_fetch(
                w, scenarioproblems[w-1], scenario_index - j, ci) do sp, i, ci
                    MOI.delete(backend(fetch(sp).problems[i]), ci)
                end
        end
        j += n
    end
    throw(BoundsError(scenarioproblems, scenario_index))
end
function MOI.delete(scenarioproblems::ScenarioProblems, cis::Vector{<:MOI.ConstraintIndex}, scenario_index::Integer)
    MOI.delete(backend(subproblem(scenarioproblems, scenario_index)), cis)
    return nothing
end
function MOI.delete(scenarioproblems::DistributedScenarioProblems, cis::Vector{<:MOI.ConstraintIndex}, scenario_index::Integer)
    isempty(scenarioproblems.scenarioproblems) && error("No remote scenario problems.")
    j = 0
    for w in workers()
        n = scenarioproblems.scenario_distribution[w-1]
        if scenario_index <= n + j
            return remotecall_fetch(
                w, scenarioproblems[w-1], scenario_index - j, cis) do sp, i, cis
                    MOI.delete(backend(fetch(sp).problems[i]), cis)
                end
        end
        j += n
    end
    throw(BoundsError(scenarioproblems, scenario_index))
end

# JuMP #
# ========================== #
function JuMP.fix(scenarioproblems::ScenarioProblems, index::MOI.VariableIndex, scenario_index::Integer, val::Number)
    d = decision(scenarioproblems, index, scenario_index)
    if state(d) == NotTaken
        # Prepare modification
        change = DecisionStateChange(index, Taken, val)
        # Update state
        d.state = Taken
        # Update value
        d.value = val
    else
        # Prepare modification
        change = DecisionStateChange(index, Taken, val - d.value)
        # Just update value
        d.value = val
    end
    # Update objective and constraints
    update_decisions!(scenarioproblems, change)
    return nothing
end
function JuMP.fix(scenarioproblems::DistributedScenarioProblems, index::MOI.VariableIndex, scenario_index::Integer, val::Number)
    isempty(scenarioproblems.scenarioproblems) && error("No remote scenario problems.")
    j = 0
    for w in workers()
        n = scenarioproblems.scenario_distribution[w-1]
        if scenario_index <= n + j
            return remotecall_fetch(
                w, scenarioproblems[w-1], scenario_index - j, index) do sp, i, index
                    subprob = fetch(sp).problems[i]
                    d = decision(DecisionRef(subprob, index))
                    if state(d) == NotTaken
                        # Prepare modification
                        change = DecisionStateChange(index, Taken, val)
                        # Update state
                        d.state = Taken
                        # Update value
                        d.value = val
                    else
                        # Prepare modification
                        change = DecisionStateChange(index, Taken, val - d.value)
                        # Just update value
                        d.value = val
                    end
                    # Update objective and constraints
                    update_decisions!(subprob, change)
                    return nothing
                end
        end
        j += n
    end
    throw(BoundsError(scenarioproblems, scenario_index))
end
function JuMP.unfix(scenarioproblems::ScenarioProblems, index::MOI.VariableIndex, scenario_index::Integer)
    # Get decision
    d = decision(scenarioproblems, index, scenario_index)
    # Update state
    d.state = NotTaken
    # Prepare modification
    change = DecisionStateChange(index, NotTaken, -d.value)
    # Update objective and constraints
    update_decisions!(scenarioproblems, change)
    return nothing
end
function JuMP.unfix(scenarioproblems::DistributedScenarioProblems, index::MOI.VariableIndex, scenario_index::Integer)
    isempty(scenarioproblems.scenarioproblems) && error("No remote scenario problems.")
    j = 0
    for w in workers()
        n = scenarioproblems.scenario_distribution[w-1]
        if scenario_index <= n + j
            return remotecall_fetch(
                w, scenarioproblems[w-1], scenario_index - j, index) do sp, i, index
                    subprob = fetch(sp).problems[i]
                    d = decision(DecisionRef(subprob, index))
                    # Update state
                    d.state = NotTaken
                    # Prepare modification
                    change = DecisionStateChange(index, NotTaken, -d.value)
                    # Update objective and constraints
                    update_decisions!(subprob, change)
                    return nothing
                end
        end
        j += n
    end
    throw(BoundsError(scenarioproblems, scenario_index))
end

function JuMP.objective_function_type(scenarioproblems::ScenarioProblems, scenario_index::Integer)
    subprob = subproblem(scenarioproblems, scenario_index)
    return jump_function_type(subprob, MOI.get(backend(subprob), MOI.ObjectiveFunctionType()))
end
function JuMP.objective_function_type(scenarioproblems::DistributedScenarioProblems, scenario_index::Integer)
    isempty(scenarioproblems.scenarioproblems) && error("No remote scenario problems.")
    j = 0
    for w in workers()
        n = scenarioproblems.scenario_distribution[w-1]
        if scenario_index <= n + j
            return remotecall_fetch(
                w, scenarioproblems[w-1], scenario_index - j) do sp, i
                    s = fetch(sp).problems[i]
                    return jump_function_type(s, MOI.get(backend(s), MOI.ObjectiveFunctionType()))
                end
        end
        j += n
    end
    throw(BoundsError(scenarioproblems, scenario_index))
end

function JuMP.objective_function(scenarioproblems::ScenarioProblems,
                                 proxy::JuMP.Model,
                                 scenario_index::Integer,
                                 FunType::Type{<:AbstractJuMPScalar})
    MOIFunType = moi_function_type(FunType)
    subprob = subproblem(scenarioproblems, scenario_index)
    func = MOI.get(subprob, MOI.ObjectiveFunction{MOIFunType}())::MOIFunType
    return jump_function(proxy, func)
end
function JuMP.objective_function(scenarioproblems::DistributedScenarioProblems,
                                 proxy::JuMP.Model,
                                 scenario_index::Integer,
                                 FunType::Type{<:AbstractJuMPScalar})
    isempty(scenarioproblems.scenarioproblems) && error("No remote scenario problems.")
    j = 0
    for w in workers()
        n = scenarioproblems.scenario_distribution[w-1]
        if scenario_index <= n + j
            f = remotecall_fetch(
                w, scenarioproblems[w-1], scenario_index - j, FunType) do sp, i, FunType
                    MOIFunType = moi_function_type(FunType)
                    subprob = fetch(sp).problems[i]
                    func = MOI.get(subprob, MOI.ObjectiveFunction{MOIFunType}())::MOIFunType
                    return func
                end
            return jump_function(proxy, f)
        end
        j += n
    end
    throw(BoundsError(scenarioproblems, scenario_index))
end

function JuMP.set_objective_coefficient(scenarioproblems::ScenarioProblems, index::VI, scenario_index::Integer, coeff::Real)
    subprob = subproblem(scenarioproblems, scenario_index)
    dref = DecisionRef(subprob, index)
    set_objective_coefficient(subprob, dref, coeff)
    return nothing
end
function JuMP.set_objective_coefficient(scenarioproblems::DistributedScenarioProblems, index::VI, scenario_index::Integer, coeff::Real)
    isempty(scenarioproblems.scenarioproblems) && error("No remote scenario problems.")
    j = 0
    for w in workers()
        n = scenarioproblems.scenario_distribution[w-1]
        if scenario_index <= n + j
            return remotecall_fetch(
                w, scenarioproblems[w-1], scenario_index - j, index, coeff) do sp, i, index, coeff
                    subprob = fetch(sp).problems[i]
                    dref = DecisionRef(subprob, index)
                    set_objective_coefficient(subprob, dref, coeff)
                end
        end
        j += n
    end
    throw(BoundsError(scenarioproblems, scenario_index))
end
function set_known_objective_coefficient(scenarioproblems::ScenarioProblems, index::VI, coeff::Real)
    for subprob in subproblems(scenarioproblems)
        kref = KnownRef(subprob, index)
        set_objective_coefficient(subprob, kref, coeff)
    end
    return nothing
end
function set_known_objective_coefficient(scenarioproblems::DistributedScenarioProblems, index::VI, coeff::Real)
    isempty(scenarioproblems.scenarioproblems) && error("No remote scenario problems.")
    @sync begin
        for (i,w) in enumerate(workers())
            @async remotecall_fetch(
                w, scenarioproblems[w-1], index, coeff) do sp, index, coeff
                    for subprob in fetch(sp).problems
                        kref = KnownRef(subprob, index)
                        set_objective_coefficient(subprob, kref, coeff)
                    end
                end
        end
    end
    return nothing
end
function set_known_objective_coefficient(scenarioproblems::ScenarioProblems, index::VI, scenario_index::Integer, coeff::Real)
    subprob = subproblem(scenarioproblems, scenario_index)
    kref = KnownRef(subprob, index)
    set_objective_coefficient(subprob, kref, coeff)
    return nothing
end
function set_known_objective_coefficient(scenarioproblems::DistributedScenarioProblems, index::VI, scenario_index::Integer, coeff::Real)
    isempty(scenarioproblems.scenarioproblems) && error("No remote scenario problems.")
    j = 0
    for w in workers()
        n = scenarioproblems.scenario_distribution[w-1]
        if scenario_index <= n + j
            return remotecall_fetch(
                w, scenarioproblems[w-1], scenario_index - j, index, coeff) do sp, i, index, coeff
                    subprob = fetch(sp).problems[i]
                    kref = KnownRef(subprob, index)
                    set_objective_coefficient(subprob, kref, coeff)
                end
        end
        j += n
    end
    throw(BoundsError(scenarioproblems, scenario_index))
end

function JuMP.set_normalized_coefficient(scenarioproblems::ScenarioProblems,
                                         ci::CI{F,S},
                                         index::VI,
                                         scenario_index::Integer,
                                         value) where {T, F <: Union{AffineDecisionFunction{T}, QuadraticDecisionFunction{T}}, S}
    MOI.modify(backend(subproblem(scenarioproblems, scenario_index)), ci,
               DecisionCoefficientChange(index, convert(T, value)))
    return nothing
end
function JuMP.set_normalized_coefficient(scenarioproblems::DistributedScenarioProblems,
                                         ci::CI{F,S},
                                         index::VI,
                                         scenario_index::Integer,
                                         value) where {T, F <: Union{AffineDecisionFunction{T}, QuadraticDecisionFunction{T}}, S}
    isempty(scenarioproblems.scenarioproblems) && error("No remote scenario problems.")
    j = 0
    for w in workers()
        n = scenarioproblems.scenario_distribution[w-1]
        if scenario_index <= n + j
            return remotecall_fetch(
                w, scenarioproblems[w-1], scenario_index - j, ci, index, value) do sp, i, ci, index, value
                    MOI.modify(backend(fetch(sp).problems[i]), ci,
                               DecisionCoefficientChange(index, convert(T, value)))
                end
        end
        j += n
    end
    throw(BoundsError(scenarioproblems, scenario_index))
    return nothing
end

function JuMP.normalized_coefficient(scenarioproblems::ScenarioProblems,
                                     ci::CI{F,S},
                                     index::VI,
                                     scenario_index::Integer) where {T, F <: Union{AffineDecisionFunction{T}, QuadraticDecisionFunction{T}}, S}
    subprob = subproblem(scenarioproblems, scenario_index)
    f = MOI.get(backend(subprob), MOI.ConstraintFunction(), ci)::F
    dref = DecisionRef(subprob, index)
    return JuMP._affine_coefficient(jump_function(subprob, f), dref)
end
function JuMP.normalized_coefficient(scenarioproblems::DistributedScenarioProblems,
                                     ci::CI{F,S},
                                     index::VI,
                                     scenario_index::Integer) where {T, F <: Union{AffineDecisionFunction{T}, QuadraticDecisionFunction{T}}, S}
    isempty(scenarioproblems.scenarioproblems) && error("No remote scenario problems.")
    j = 0
    for w in workers()
        n = scenarioproblems.scenario_distribution[w-1]
        if scenario_index <= n + j
            return remotecall_fetch(
                w, scenarioproblems[w-1], scenario_index - j, ci, index) do sp, i, ci, index
                    subprob = fetch(sp).problems[i]
                    f = MOI.get(backend(subprob), MOI.ConstraintFunction(), ci)::F
                    dref = DecisionRef(subprob, index)
                    return JuMP._affine_coefficient(jump_function(subprob, f), dref)
                end
        end
        j += n
    end
    throw(BoundsError(scenarioproblems, scenario_index))
end

function JuMP.set_normalized_rhs(scenarioproblems::ScenarioProblems,
                                 ci::CI{F,S},
                                 scenario_index::Integer,
                                 value) where {T,
                                               F <: Union{AffineDecisionFunction{T}, QuadraticDecisionFunction{T}},
                                               S <: MOIU.ScalarLinearSet{T}}
    MOI.set(backend(subproblem(scenarioproblems, scenario_index)), MOI.ConstraintSet(), ci,
            S(convert(T, value)))
    return nothing
end
function JuMP.set_normalized_rhs(scenarioproblems::DistributedScenarioProblems,
                                 ci::CI{F,S},
                                 scenario_index::Integer,
                                 value) where {T,
                                               F <: Union{AffineDecisionFunction{T}, QuadraticDecisionFunction{T}},
                                               S <: MOIU.ScalarLinearSet{T}}
    isempty(scenarioproblems.scenarioproblems) && error("No remote scenario problems.")
    j = 0
    for w in workers()
        n = scenarioproblems.scenario_distribution[w-1]
        if scenario_index <= n + j
            return remotecall_fetch(
                w, scenarioproblems[w-1], scenario_index - j, ci, value) do sp, i, ci, value
                    MOI.set(backend(fetch(sp).problems[i]), MOI.ConstraintSet(), ci,
                            S(convert(T, value)))
                end
        end
        j += n
    end
    throw(BoundsError(scenarioproblems, scenario_index))
end

# Getters #
# ========================== #
function decision(scenarioproblems::ScenarioProblems, index::MOI.VariableIndex, scenario_index::Integer) where N
    subprob = subproblem(scenarioproblems, scenario_index)
    return decision(DecisionRef(subprob, index))
end
function decision(scenarioproblems::DistributedScenarioProblems, index::MOI.VariableIndex, scenario_index::Integer) where N
    isempty(scenarioproblems.scenarioproblems) && error("No remote scenario problems.")
    j = 0
    for w in workers()
        n = scenarioproblems.scenario_distribution[w-1]
        if scenario_index <= n + j
            return remotecall_fetch(
                w, scenarioproblems[w-1], scenario_index - j, index) do sp, i, index
                    subprob = fetch(sp).problems[i]
                    return decision(DecisionRef(subprob, index))
                end
        end
        j += n
    end
    throw(BoundsError(scenarioproblems, scenario_index))
end
function scenario(scenarioproblems::ScenarioProblems, scenario_index::Integer)
    return scenarioproblems.scenarios[scenario_index]
end
function scenario(scenarioproblems::DistributedScenarioProblems, scenario_index::Integer)
    isempty(scenarioproblems.scenarioproblems) && error("No remote scenario problems.")
    j = 0
    for w in workers()
        n = scenarioproblems.scenario_distribution[w-1]
        if scenario_index <= n + j
            return remotecall_fetch(
                w, scenarioproblems[w-1], scenario_index - j) do sp, i
                    fetch(sp).scenarios[i]
                end
        end
        j += n
    end
    throw(BoundsError(scenarioproblems, scenario_index))
end
function scenarios(scenarioproblems::ScenarioProblems)
    return scenarioproblems.scenarios
end
function scenarios(scenarioproblems::DistributedScenarioProblems{S}) where S <: AbstractScenario
    isempty(scenarioproblems.scenarioproblems) && error("No remote scenario problems.")
    partial_scenarios = Vector{Vector{S}}(undef, nworkers())
    @sync begin
        for (i,w) in enumerate(workers())
            @async partial_scenarios[i] = remotecall_fetch(
                w, scenarioproblems[w-1]) do sp
                    fetch(sp).scenarios
                end
        end
    end
    return reduce(vcat, partial_scenarios)
end
function expected(scenarioproblems::ScenarioProblems)
    return expected(scenarioproblems.scenarios)
end
function expected(scenarioproblems::DistributedScenarioProblems{S}) where S <: AbstractScenario
    isempty(scenarioproblems.scenarioproblems) && error("No remote scenario problems.")
    partial_expecations = Vector{S}(undef, nworkers())
    @sync begin
        for (i,w) in enumerate(workers())
            @async partial_expecations[i] = remotecall_fetch(
                w, scenarioproblems[w-1]) do sp
                    expected(fetch(sp)).scenario
                end
        end
    end
    return expected(partial_expecations)
end
function scenario_type(scenarioproblems::ScenarioProblems{S}) where S <: AbstractScenario
    return S
end
function scenario_type(scenarioproblems::DistributedScenarioProblems{S}) where S <: AbstractScenario
    return S
end
function subproblem(scenarioproblems::ScenarioProblems, scenario_index::Integer)
    return scenarioproblems.problems[scenario_index]
end
function subproblem(scenarioproblems::DistributedScenarioProblems, scenario_index::Integer)
    isempty(scenarioproblems.scenarioproblems) && error("No remote scenario problems.")
    j = 0
    for w in workers()
        n = scenarioproblems.scenario_distribution[w-1]
        if scenario_index <= n + j
            return remotecall_fetch(
                w, scenarioproblems[w-1], scenario_index - j) do sp, i
                    fetch(sp).problems[i]
                end
        end
        j += n
    end
    throw(BoundsError(scenarioproblems, scenario_index))
end
function subproblems(scenarioproblems::ScenarioProblems)
    return scenarioproblems.problems
end
function subproblems(scenarioproblems::DistributedScenarioProblems)
    isempty(scenarioproblems.scenarioproblems) && error("No remote scenario problems.")
    partial_subproblems = Vector{Vector{JuMP.Model}}(undef, nworkers())
    @sync begin
        for (i,w) in enumerate(workers())
            @async partial_subproblems[i] = remotecall_fetch(
                w,scenarioproblems[w-1]) do sp
                    fetch(sp).problems
                end
        end
    end
    return reduce(vcat, partial_subproblems)
end
function num_subproblems(scenarioproblems::ScenarioProblems)
    return length(scenarioproblems.problems)
end
function num_subproblems(scenarioproblems::DistributedScenarioProblems)
    isempty(scenarioproblems.scenarioproblems) && error("No remote scenario problems.")
    partial_lengths = Vector{Int}(undef, nworkers())
    @sync begin
        for (i,w) in enumerate(workers())
            @async partial_lengths[i] = remotecall_fetch(
                w,scenarioproblems[w-1]) do sp
                    num_subproblems(fetch(sp))
                end
        end
    end
    return sum(partial_lengths)
end
function decision_variables(scenarioproblems::ScenarioProblems)
    return scenarioproblems.decision_variables
end
function probability(scenarioproblems::ScenarioProblems, scenario_index::Integer)
    return probability(scenario(scenarioproblems, scenario_index))
end
function probability(scenarioproblems::DistributedScenarioProblems, scenario_index::Integer)
    isempty(scenarioproblems.scenarioproblems) && error("No remote scenario problems.")
    j = 0
    for w in workers()
        n = scenarioproblems.scenario_distribution[w-1]
        if scenario_index <= n + j
            return remotecall_fetch(
                w, scenarioproblems[w-1], scenario_index - j) do sp, i
                    probability(fetch(sp).scenarios[i])
                end
        end
        j += n
    end
    throw(BoundsError(scenarioproblems, scenario_index))
end
function probability(scenarioproblems::ScenarioProblems)
    return probability(scenarioproblems.scenarios)
end
function probability(scenarioproblems::DistributedScenarioProblems)
    isempty(scenarioproblems.scenarioproblems) && error("No remote scenario problems.")
    partial_probabilities = Vector{Float64}(undef, nworkers())
    @sync begin
        for (i,w) in enumerate(workers())
            @async partial_probabilities[i] = remotecall_fetch(
                w, scenarioproblems[w-1]) do sp
                    probability(fetch(sp))
                end
        end
    end
    return sum(partial_probabilities)
end
function num_scenarios(scenarioproblems::ScenarioProblems)
    return length(scenarioproblems.scenarios)
end
function num_scenarios(scenarioproblems::DistributedScenarioProblems)
    return sum(scenarioproblems.scenario_distribution)
end
distributed(scenarioproblems::ScenarioProblems) = false
distributed(scenarioproblems::DistributedScenarioProblems) = true
# ========================== #

# Setters
# ========================== #
function update_decisions!(scenarioproblems::ScenarioProblems, change::DecisionModification)
    map(subproblems(scenarioproblems)) do subprob
        update_decisions!(subprob, change)
    end
    return nothing
end
function update_decisions!(scenarioproblems::DistributedScenarioProblems, change::DecisionModification)
    isempty(scenarioproblems.scenarioproblems) && error("No remote scenario problems.")
    @sync begin
        for (i,w) in enumerate(workers())
            @async remotecall_fetch(
                w, scenarioproblems[w-1], change) do sp, change
                    update_decisions!(fetch(sp), change)
                end
        end
    end
    return nothing
end
function update_decisions!(scenarioproblems::ScenarioProblems, change::DecisionModification, scenario_index::Integer)
    update_decisions!(subproblem(scenarioproblems, scenario_index), change)
    return nothing
end
function update_decisions!(scenarioproblems::DistributedScenarioProblems, change::DecisionModification, scenario_index::Integer)
    isempty(scenarioproblems.scenarioproblems) && error("No remote scenario problems.")
    j = 0
    for w in workers()
        n = scenarioproblems.scenario_distribution[w-1]
        if scenario_index <= n + j
            return remotecall_fetch(
                w, scenarioproblems[w-1], scenario_index - j, change) do sp, i, change
                    update_decisions!(fetch(sp).problems[i], change)
                end
        end
        j += n
    end
    throw(BoundsError(scenarioproblems, scenario_index))
end

function set_optimizer!(scenarioproblems::ScenarioProblems, optimizer)
    map(subproblems(scenarioproblems)) do subprob
        set_optimizer(subprob, optimizer)
    end
    return nothing
end
function set_optimizer!(scenarioproblems::DistributedScenarioProblems, optimizer)
    isempty(scenarioproblems.scenarioproblems) && error("No remote scenario problems.")
    @sync begin
        for (i,w) in enumerate(workers())
            @async remotecall_fetch(
                w, scenarioproblems[w-1], optimizer) do sp, opt
                    set_optimizer!(fetch(sp), opt)
                end
        end
    end
    return nothing
end
function add_scenario!(scenarioproblems::ScenarioProblems{S}, scenario::S) where S <: AbstractScenario
    push!(scenarioproblems.scenarios, scenario)
    return nothing
end
function add_scenario!(scenarioproblems::DistributedScenarioProblems{S}, scenario::S) where S <: AbstractScenario
    isempty(scenarioproblems.scenarioproblems) && error("No remote scenario problems.")
    _, w = findmin(scenarioproblems.scenario_distribution)
    add_scenario!(scenarioproblems, scenario, w+1)
    return nothing
end
function add_scenario!(scenarioproblems::DistributedScenarioProblems{S}, scenario::S, w::Integer) where S <: AbstractScenario
    isempty(scenarioproblems.scenarioproblems) && error("No remote scenario problems.")
    remotecall_fetch(
        w,
        scenarioproblems[w-1],
        scenario) do sp, scenario
            add_scenario!(fetch(sp), scenario)
        end
    scenarioproblems.scenario_distribution[w-1] += 1
    return nothing
end
function add_scenario!(scenariogenerator::Function, scenarioproblems::ScenarioProblems)
    add_scenario!(scenarioproblems, scenariogenerator())
    return nothing
end
function add_scenario!(scenariogenerator::Function, scenarioproblems::DistributedScenarioProblems)
    isempty(scenarioproblems.scenarioproblems) && error("No remote scenario problems.")
    _, w = findmin(scenarioproblems.scenario_distribution)
    add_scenario!(scenariogenerator, scenarioproblems, w + 1)
    return nothing
end
function add_scenario!(scenariogenerator::Function, scenarioproblems::DistributedScenarioProblems, w::Integer)
    isempty(scenarioproblems.scenarioproblems) && error("No remote scenario problems.")
    remotecall_fetch(
        w,
        scenarioproblems[w-1],
        scenariogenerator) do sp, generator
            add_scenario!(fetch(sp), generator())
        end
    scenarioproblems.scenario_distribution[w] += 1
    return nothing
end
function add_scenarios!(scenarioproblems::ScenarioProblems{S}, scenarios::Vector{S}) where S <: AbstractScenario
    append!(scenarioproblems.scenarios, scenarios)
    return nothing
end
function add_scenarios!(scenariogenerator::Function, scenarioproblems::ScenarioProblems{S}, n::Integer) where S <: AbstractScenario
    for i = 1:n
        add_scenario!(scenarioproblems) do
            return scenariogenerator()
        end
    end
    return nothing
end
function add_scenarios!(scenarioproblems::DistributedScenarioProblems{S}, scenarios::Vector{S}) where S <: AbstractScenario
    isempty(scenarioproblems.scenarioproblems) && error("No remote scenario problems.")
    (nscen, extra) = divrem(length(scenarios), nworkers())
    start = 1
    stop = 0
    @sync begin
        for w in workers()
            n = nscen + (extra > 0)
            stop += n
            stop = min(stop, length(scenarios))
            scenario_range = start:stop
            @async remotecall_fetch(
                w,
                scenarioproblems[w-1],
                scenarios[scenario_range]) do sp, scenarios
                    add_scenarios!(fetch(sp), scenarios)
                end
            scenarioproblems.scenario_distribution[w-1] += n
            start = stop + 1
            extra -= 1
        end
    end
    return nothing
end
function add_scenarios!(scenarioproblems::DistributedScenarioProblems{S}, scenarios::Vector{S}, w::Integer) where S <: AbstractScenario
    isempty(scenarioproblems.scenarioproblems) && error("No remote scenario problems.")
    remotecall_fetch(
        w,
        scenarioproblems[w-1],
        scenarios) do sp, scenarios
            add_scenarios!(fetch(sp), scenarios)
        end
    scenarioproblems.scenario_distribution[w-1] += length(scenarios)
    return nothing
end
function add_scenarios!(scenariogenerator::Function, scenarioproblems::DistributedScenarioProblems, n::Integer)
    isempty(scenarioproblems.scenarioproblems) && error("No remote scenario problems.")
    (nscen, extra) = divrem(n, nworkers())
    @sync begin
        for w in workers()
            m = nscen + (extra > 0)
            @async remotecall_fetch(
                w,
                scenarioproblems[w-1],
                scenariogenerator,
                m) do sp, gen, n
                    add_scenarios!(gen, fetch(sp), n)
                end
            scenarioproblems.scenario_distribution[w-1] += m
            extra -= 1
        end
    end
    return nothing
end
function add_scenarios!(scenariogenerator::Function, scenarioproblems::DistributedScenarioProblems, n::Integer, w::Integer)
    isempty(scenarioproblems.scenarioproblems) && error("No remote scenario problems.")
    remotecall_fetch(
        w,
        scenarioproblems[w-1],
        scenariogenerator,
        n) do sp, gen
            add_scenarios!(gen, fetch(sp), n)
        end
    scenarioproblems.scenario_distribution[w-1] += n
    return nothing
end
function clear_scenarios!(scenarioproblems::ScenarioProblems)
    empty!(scenarioproblems.scenarios)
    return nothing
end
function clear_scenarios!(scenarioproblems::DistributedScenarioProblems)
    isempty(scenarioproblems.scenarioproblems) && error("No remote scenario problems.")
    @sync begin
        for w in workers()
            @async remotecall_fetch(
                w, scenarioproblems[w-1]) do sp
                    remove_scenarios!(fetch(sp))
                end
            scenarioproblems.scenario_distribution[w-1] = 0
        end
    end
    return nothing
end
function clear!(scenarioproblems::ScenarioProblems)
    map(scenarioproblems.problems) do subprob
        # Clear decisions
        if haskey(subprob.ext, :decisions)
            map(clear!, subprob.ext[:decisions])
        end
        # Clear model
        empty!(subprob)
    end
    empty!(scenarioproblems.problems)
    return nothing
end
function clear!(scenarioproblems::DistributedScenarioProblems)
    isempty(scenarioproblems.scenarioproblems) && error("No remote scenario problems.")
    @sync begin
        for w in workers()
            @async remotecall_fetch(
                w, scenarioproblems[w-1]) do sp
                    clear!(fetch(sp))
                end
        end
    end
    return nothing
end

function delete_known!(scenarioproblems::ScenarioProblems, index::MOI.VariableIndex)
    for subprob in subproblems(scenarioproblems)
        kref = KnownRef(subprob, index)
        delete(subprob, kref)
    end
    return nothing
end
function delete_known!(scenarioproblems::DistributedScenarioProblems, index::MOI.VariableIndex)
    isempty(scenarioproblems.scenarioproblems) && error("No remote scenario problems.")
    @sync begin
        for w in workers()
            @async remotecall_fetch(
                w, scenarioproblems[w-1], index) do sp, index
                    for subprob in fetch(sp).problems
                        kref = KnownRef(subprob, index)
                        delete(subprob, kref)
                    end
                end
        end
    end
    return nothing
end
function delete_knowns!(scenarioproblems::ScenarioProblems, indices::Vector{MOI.VariableIndex})
    for subprob in subproblems(scenarioproblems)
        krefs = KnownRef.(subprob, indices)
        delete(subprob, krefs)
    end
    return nothing
end
function delete_knowns!(scenarioproblems::DistributedScenarioProblems, indices::Vector{MOI.VariableIndex})
    isempty(scenarioproblems.scenarioproblems) && error("No remote scenario problems.")
    @sync begin
        for w in workers()
            @async remotecall_fetch(
                w, scenarioproblems[w-1], indices) do sp, indices
                    for subprob in fetch(sp).problems
                        krefs = KnownRef.(subprob, indices)
                        delete(subprob, krefs)
                    end
                end
        end
    end
    return nothing
end

function cache_solution!(cache::Dict{Symbol,SolutionCache}, scenarioproblems::ScenarioProblems, optimizer::MOI.AbstractOptimizer, stage::Integer)
    for i in 1:num_scenarios(scenarioproblems)
        key = Symbol(:node_solution_, stage, :_, i)
        subprob = subproblem(scenarioproblems, i)
        cache[key] = SolutionCache(backend(subprob))
        cache_model_attributes!(cache[key], optimizer, stage, i)
        variables = MOI.get(backend(subprob), MOI.ListOfVariableIndices())
        cache_variable_attributes!(cache[key], optimizer, variables, stage, i)
        ctypes = filter(t -> is_decision_type(t[1]), MOI.get(backend(subprob), MOI.ListOfConstraints()))
        constraints = mapreduce(vcat, ctypes) do (F, S)
            return MOI.get(backend(subprob), MOI.ListOfConstraintIndices{F,S}())
        end
        cache_constraint_attributes!(cache[key], optimizer, constraints, stage, i)
    end
end
function cache_solution!(cache::Dict{Symbol,SolutionCache}, scenarioproblems::DistributedScenarioProblems, optimizer::MOI.AbstractOptimizer, stage::Integer)
    for scenario_index in 1:num_scenarios(scenarioproblems)
        key = Symbol(:node_solution_, stage, :_, scenario_index)
        cache[key], variables, constraints = _prepare_subproblem_cache(scenarioproblems, scenario_index)
        cache_model_attributes!(cache[key], optimizer, stage, scenario_index)
        cache_variable_attributes!(cache[key], optimizer, variables, stage, scenario_index)
        cache_constraint_attributes!(cache[key], optimizer, constraints, stage, scenario_index)
    end
end
function _prepare_subproblem_cache(scenarioproblems::DistributedScenarioProblems, scenario_index::Integer)
    j = 0
    for w in workers()
        n = scenarioproblems.scenario_distribution[w-1]
        if scenario_index <= n + j
            return remotecall_fetch(
                w, scenarioproblems[w-1], scenario_index - j) do sp, i
                    subprob = fetch(sp).problems[i]
                    subcache = SolutionCache(backend(subprob))
                    variables = MOI.get(backend(subprob), MOI.ListOfVariableIndices())
                    ctypes = filter(t -> is_decision_type(t[1]), MOI.get(backend(subprob), MOI.ListOfConstraints()))
                    constraints = mapreduce(vcat, ctypes) do (F, S)
                        return MOI.get(backend(subprob), MOI.ListOfConstraintIndices{F,S}())
                    end
                    return subcache, variables, constraints
                end
        end
        j += n
    end
    throw(BoundsError(scenarioproblems, scenario_index))
end
# ========================== #

# Sampling #
# ========================== #
function sample!(scenarioproblems::ScenarioProblems{S}, sampler::AbstractSampler{S}, n::Integer) where S <: AbstractScenario
    _sample!(scenarioproblems, sampler, n, num_scenarios(scenarioproblems), 1/n)
end
function sample!(scenarioproblems::ScenarioProblems{S}, sampler::AbstractSampler{Scenario}, n::Integer) where S <: AbstractScenario
    _sample!(scenarioproblems, sampler, n, num_scenarios(scenarioproblems), 1/n)
end
function sample!(scenarioproblems::DistributedScenarioProblems{S}, sampler::AbstractSampler{S}, n::Integer) where S <: AbstractScenario
    isempty(scenarioproblems.scenarioproblems) && error("No remote scenario problems.")
    m = nscenarios(scenarioproblems)
    (nscen, extra) = divrem(n, nworkers())
    @sync begin
        for w in workers()
            d = nscen + (extra > 0)
            @async remotecall_fetch(
                w,
                scenarioproblems[w-1],
                sampler,
                d,
                m,
                1/n) do sp, sampler, n, m, π
                    _sample!(fetch(sp), sampler, n, m, π)
                end
            scenarioproblems.scenario_distribution[w-1] += d
            extra -= 1
        end
    end
    return nothing
end
function sample!(scenarioproblems::DistributedScenarioProblems{S}, sampler::AbstractSampler{Scenario}, n::Integer) where S <: AbstractScenario
    isempty(scenarioproblems.scenarioproblems) && error("No remote scenario problems.")
    m = nscenarios(scenarioproblems)
    (nscen, extra) = divrem(n, nworkers())
    @sync begin
        for w in workers()
            d = nscen + (extra > 0)
            @async remotecall_fetch(
                w,
                scenarioproblems[w-1],
                sampler,
                d,
                m,
                1/n) do sp, sampler, n, m, π
                    _sample!(fetch(sp), sampler, n, m, π)
                end
            scenarioproblems.scenario_distribution[w-1] += d
            extra -= 1
        end
    end
    return nothing
end
function _sample!(scenarioproblems::ScenarioProblems, sampler::AbstractSampler, n::Integer, m::Integer, π::AbstractFloat)
    if m > 0
        # Rescale probabilities of existing scenarios
        for scenario in scenarioproblems.scenarios
            p = probability(scenario) * m / (m+n)
            set_probability!(scenario, p)
        end
        π *= n/(m+n)
    end
    for i = 1:n
        add_scenario!(scenarioproblems) do
            return sample(sampler, π)
        end
    end
    return nothing
end
# ========================== #
