abstract type AbstractScenarioProblems{S <: AbstractScenario} end

abstract type AbstractBlockStructure{N} <: AbstractStochasticStructure{N} end

# MOI #
# ========================== #
function MOI.is_valid(structure::AbstractBlockStructure, index::MOI.VariableIndex, stage::Integer, scenario_index::Integer)
    stage == 1 && error("There are no scenarios in the first stage.")
    n = num_scenarios(structure, stage)
    1 <= scenario_index <= n || error("Scenario index $scenario_index not in range 1 to $n.")
    return MOI.is_valid(scenarioproblems(structure, stage), index, scenario_index)
end

function MOI.delete(structure::AbstractBlockStructure{N}, index::MOI.VariableIndex, stage::Integer, scenario_index::Integer) where N
    1 <= stage <= N || error("Stage $stage not in range 1 to $N.")
    stage > 1 || error("There are no scenarios in the first stage.")
    n = num_scenarios(structure, stage)
    1 <= scenario_index <= n || error("Scenario index $scenario_index not in range 1 to $n.")
    MOI.delete(scenarioproblems(structure, stage), index, scenario_index)
    return nothing
end
function MOI.delete(structure::AbstractBlockStructure{N}, indices::Vector{MOI.VariableIndex}, stage::Integer, scenario_index::Integer) where N
    1 <= stage <= N || error("Stage $stage not in range 1 to $N.")
    stage > 1 || error("There are no scenarios in the first stage.")
    n = num_scenarios(structure, stage)
    1 <= scenario_index <= n || error("Scenario index $scenario_index not in range 1 to $n.")
    MOI.delete(scenarioproblems(structure, stage), indices, scenario_index)
    return nothing
end

# JuMP #
# ========================== #
function JuMP.objective_function_type(structure::AbstractBlockStructure{N}, stage::Integer, scenario_index::Integer) where N
    1 <= stage <= N || error("Stage $stage not in range 1 to $N.")
    stage > 1 || error("There are no scenarios in the first stage.")
    n = num_scenarios(structure, stage)
    1 <= scenario_index <= n || error("Scenario index $scenario_index not in range 1 to $n.")
    return objective_function_type(scenarioproblems(structure, stage), scenario_index)
end

function JuMP.objective_function(structure::AbstractBlockStructure{N},
                                 proxy::JuMP.Model,
                                 stage::Integer,
                                 scenario_index::Integer,
                                 FunType::Type{<:AbstractJuMPScalar}) where N
    1 <= stage <= N || error("Stage $stage not in range 1 to $N.")
    stage > 1 || error("There are no scenarios in the first stage.")
    n = num_scenarios(structure, stage)
    1 <= scenario_index <= n || error("Scenario index $scenario_index not in range 1 to $n.")
    objective::FunType = objective_function(scenarioproblems(structure, stage), proxy, scenario_index, FunType)
    return objective
end

function DecisionRef(proxy::JuMP.Model, structure::AbstractBlockStructure, index::VI, scenario_index::Integer)
    return DecisionRef(proxy, index)
end

# Getters #
# ========================== #
function scenarioproblems(structure::AbstractBlockStructure{N}, stage::Integer) where N
    1 < stage <= N || error("Stage $stage not in range 2 to $N.")
    stage == 1 && error("Stage 1 does not have scenario problems.")
    N == 2 && (stage == 2 || error("Stage $stage not available in two-stage model."))
    return structure.scenarioproblems[stage-1]
end
function scenarioproblems(structure::AbstractBlockStructure{2})
    return scenarioproblems(structure, 2)
end
function scenario_types(structure::AbstractBlockStructure{N}) where N
    return ntuple(Val{N-1}()) do s
        scenario_type(scenarioproblems(structure), s + 1)
    end
end
function decision(structure::AbstractBlockStructure{N}, index::MOI.VariableIndex, stage::Integer, scenario_index::Integer) where N
    stage > 1 || error("There are no scenarios in the first stage.")
    n = num_scenarios(structure, stage)
    1 <= scenario_index <= n || error("Scenario index $scenario_index not in range 1 to $n.")
    return decision(scenarioproblems(structure, stage), index, scenario_index)
end
function scenario(structure::AbstractBlockStructure, stage::Integer, scenario_index::Integer)
    scenario(scenarioproblems(structure, stage), scenario_index)
end
function scenarios(structure::AbstractBlockStructure, stage::Integer)
    scenarios(scenarioproblems(structure, stage))
end
function expected(structure::AbstractBlockStructure, stage::Integer)
    return expected(scenarioproblems(structure, stage))
end
function scenario_type(structure::AbstractBlockStructure, stage::Integer)
    return scenario_type(scenarioproblems(structure, stage))
end
function probability(structure::AbstractBlockStructure, stage::Integer, scenario_index::Integer)
    return probability(scenarioproblems(structure, stage), scenario_index)
end
function stage_probability(structure::AbstractBlockStructure, stage::Integer)
    return probability(scenarioproblems(structure, stage))
end
function subproblem(structure::AbstractBlockStructure, stage::Integer, scenario_index::Integer)
    return subproblem(scenarioproblems(structure, stage), scenario_index)
end
function subproblems(structure::AbstractBlockStructure, stage::Integer)
    return subproblems(scenarioproblems(structure, stage))
end
function num_subproblems(structure::AbstractBlockStructure, stage::Integer)
    return num_subproblems(scenarioproblems(structure, stage))
end
function num_scenarios(structure::AbstractBlockStructure, stage::Integer)
    return num_scenarios(scenarioproblems(structure, stage))
end
deferred(structure::AbstractBlockStructure{N}) where N = deferred(structure, Val(N))
deferred(structure::AbstractBlockStructure, ::Val{1}) = deferred_first_stage(structure)
function deferred(structure::AbstractBlockStructure, ::Val{N}) where N
    return deferred_stage(structure, N) || deferred(structure, Val(N-1))
end
deferred_first_stage(structure::AbstractBlockStructure) = false
function deferred_stage(structure::AbstractBlockStructure{N}, stage::Integer) where N
    1 <= stage <= N || error("Stage $stage not in range 1 to $N.")
    stage == 1 && return deferred_first_stage(structure)
    num_subproblems(structure, stage) < num_scenarios(structure, stage)
end
function distributed(structure::AbstractBlockStructure{N}, stage::Integer) where N
    1 <= stage <= N || error("Stage $stage not in range 1 to $N.")
    stage == 1 && return false
    return distributed(scenarioproblems(structure, stage))
end

# ========================== #

# Setters
# ========================== #
function update_decisions!(structure::AbstractBlockStructure, change::DecisionModification, stage::Integer, scenario_index::Integer)
    update_decisions!(scenarioproblems(structure, stage), change, scenario_index)
    return nothing
end
function add_scenario!(structure::AbstractBlockStructure, stage::Integer, scenario::AbstractScenario)
    add_scenario!(scenarioproblems(structure, stage), scenario)
    return nothing
end
function add_worker_scenario!(structure::AbstractBlockStructure, stage::Integer, scenario::AbstractScenario, w::Integer)
    add_scenario!(scenario(structure, stage), scenario, w)
    return nothing
end
function add_scenario!(scenariogenerator::Function, stage::Integer, structure::AbstractBlockStructure)
    add_scenario!(scenariogenerator, scenarioproblems(structure, stage))
    return nothing
end
function add_worker_scenario!(scenariogenerator::Function, stage::Integer, structure::AbstractBlockStructure, w::Integer)
    add_scenario!(scenariogenerator, scenarioproblems(structure, stage), w)
    return nothing
end
function add_scenarios!(structure::AbstractBlockStructure, stage::Integer, scenarios::Vector{<:AbstractScenario})
    add_scenarios!(scenarioproblems(structure, stage), scenarios)
    return nothing
end
function add_worker_scenarios!(structure::AbstractBlockStructure, stage::Integer, scenarios::Vector{<:AbstractScenario}, w::Integer)
    add_scenarios!(scenarioproblems(structure, stage), scenarios, w)
    return nothing
end
function add_scenarios!(scenariogenerator::Function, stage::Integer, structure::AbstractBlockStructure, n::Integer)
    add_scenarios!(scenariogenerator, scenarioproblems(structure, stage), n)
    return nothing
end
function add_worker_scenarios!(scenariogenerator::Function, stage::Integer, structure::AbstractBlockStructure, n::Integer, w::Integer)
    add_scenarios!(scenariogenerator, scenarioproblems(structure, stage), n, w)
    return nothing
end
function sample!(structure::AbstractBlockStructure, stage::Integer, sampler::AbstractSampler, n::Integer)
    sample!(scenarioproblems(structure, stage), sampler, n)
    return nothing
end
# ========================== #

# Includes
# ========================== #
include("scenarioproblems.jl")
include("vertical.jl")
include("horizontal.jl")
