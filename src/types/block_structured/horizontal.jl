"""
    HorizontalStructure

Horizontal memory structure. Decomposes stochastic program by scenario.

"""
struct HorizontalStructure{N, M, SP <: NTuple{M, AbstractScenarioProblems}} <: AbstractBlockStructure{N}
    decisions::NTuple{N, Decisions}
    scenarioproblems::SP
    constraint_map::Dict{Tuple{CI, Int}, CI}

    function HorizontalStructure(decisions::NTuple{N, Decisions}, scenarioproblems::NTuple{M,AbstractScenarioProblems}) where {N, M}
        M == N - 1 || error("Inconsistent number of stages $N and number of scenario types $M")
        SP = typeof(scenarioproblems)
        return new{N,M,SP}(decisions, scenarioproblems, Dict{Tuple{CI, Int}, CI}())
    end
end

function StochasticStructure(decisions::NTuple{N, Decisions}, scenario_types::ScenarioTypes{M}, instantiation::Union{Horizontal, DistributedHorizontal}) where {N, M}
    scenarioproblems = ntuple(Val(M)) do i
        ScenarioProblems(scenario_types[i], instantiation)
    end
    return HorizontalStructure(decisions, scenarioproblems)
end

function StochasticStructure(decisions::NTuple{N, Decisions}, scenarios::NTuple{M, Vector{<:AbstractScenario}}, instantiation::Union{Horizontal, DistributedHorizontal}) where {N, M}
    scenarioproblems = ntuple(Val(M)) do i
        ScenarioProblems(scenarios[i], instantiation)
    end
    return HorizontalStructure(decisions, scenarioproblems)
end

# Base overloads #
# ========================== #
function Base.print(io::IO, structure::HorizontalStructure{2})
    print(io, "Horizontal scenario problems \n")
    print(io, "============== \n")
    for (id, subproblem) in enumerate(subproblems(structure, 2))
        @printf(io, "Subproblem %d (p = %.2f):\n", id, probability(scenario(structure, 2, id)))
        print(io, subproblem)
        print(io, "\n")
    end
end

# MOI #
# ========================== #
function MOI.get(structure::HorizontalStructure, attr::MOI.AbstractModelAttribute)
    if attr isa Union{MOI.ObjectiveFunctionType, MOI.ObjectiveSense}
        # Should be the same in all subproblems, query the first
        return MOI.get(structure, ScenarioDependentModelAttribute(2, 1, attr))
    end
    error("The horizontal structure is completely decomposed into subproblems. All model attributes are scenario dependent.")
end
function MOI.get(structure::HorizontalStructure, attr::MOI.AbstractVariableAttribute, index::MOI.VariableIndex)
    error("The horizontal structure is completely decomposed into subproblems. All model attributes are scenario dependent.")
end
function MOI.get(structure::HorizontalStructure, attr::MOI.AbstractConstraintAttribute, cindex::MOI.ConstraintIndex)
    error("The horizontal structure is completely decomposed into subproblems. All model attributes are scenario dependent.")
end
function MOI.get(structure::HorizontalStructure, attr::ScenarioDependentModelAttribute)
    n = num_scenarios(structure, attr.stage)
    1 <= attr.scenario_index <= n || error("Scenario index $attr.scenario_index not in range 1 to $n.")
    return MOI.get(scenarioproblems(structure, attr.stage), attr)
end
function MOI.get(structure::HorizontalStructure, attr::ScenarioDependentVariableAttribute, index::MOI.VariableIndex)
    n = num_scenarios(structure, attr.stage)
    1 <= attr.scenario_index <= n || error("Scenario index $attr.scenario_index not in range 1 to $n.")
    return MOI.get(scenarioproblems(structure, attr.stage), attr, index)
end
function MOI.get(structure::HorizontalStructure, attr::ScenarioDependentConstraintAttribute, ci::MOI.ConstraintIndex)
    n = num_scenarios(structure, attr.stage)
    1 <= attr.scenario_index <= n || error("Scenario index $attr.scenario_index not in range 1 to $n.")
    mapped_ci = structure.constraint_map[(ci, attr.scenario_index)]
    return MOI.get(scenarioproblems(structure, attr.stage), attr, mapped_ci)
end
function MOI.get(structure::HorizontalStructure, attr::ScenarioDependentConstraintAttribute, ci::CI{F,S}) where {F <: MOI.SingleVariable, S}
    n = num_scenarios(structure, attr.stage)
    1 <= attr.scenario_index <= n || error("Scenario index $attr.scenario_index not in range 1 to $n.")
    # Do not need to map here
    return MOI.get(scenarioproblems(structure, attr.stage), attr, ci)
end

function MOI.set(structure::HorizontalStructure{2}, attr::Union{MOI.AbstractModelAttribute, MOI.Silent}, value)
    # All subproblems should be updated
    MOI.set(scenarioproblems(structure), attr, value)
end
function MOI.set(structure::HorizontalStructure{2}, attr::MOI.AbstractVariableAttribute,
                 index::MOI.VariableIndex, value)
    # All subproblems should be updated
    MOI.set(scenarioproblems(structure), attr, index, value)
    return nothing
end
function MOI.set(structure::HorizontalStructure{2}, attr::MOI.AbstractConstraintAttribute,
                 ci::MOI.ConstraintIndex, value)
    # All subproblems should be updated
    MOI.set(scenarioproblems(structure), attr, ci, value)
    return nothing
end
function MOI.set(structure::HorizontalStructure{2}, attr::ScenarioDependentModelAttribute, value)
    n = num_scenarios(structure, attr.stage)
    1 <= attr.scenario_index <= n || error("Scenario index $attr.scenario_index not in range 1 to $n.")
    MOI.set(scenarioproblems(subproblem, attr.stage), attr, value)
    return nothing
end
function MOI.set(structure::HorizontalStructure{2}, attr::ScenarioDependentVariableAttribute,
                 index::MOI.VariableIndex, value)
    n = num_scenarios(structure, attr.stage)
    1 <= attr.scenario_index <= n || error("Scenario index $attr.scenario_index not in range 1 to $n.")
    MOI.set(scenarioproblems(structure, attr.stage), attr, index, value)
    return nothing
end
function MOI.set(structure::HorizontalStructure{2}, attr::ScenarioDependentConstraintAttribute,
                 ci::MOI.ConstraintIndex, value)
    n = num_scenarios(structure, attr.stage)
    1 <= attr.scenario_index <= n || error("Scenario index $attr.scenario_index not in range 1 to $n.")
    MOI.set(scenarioproblems(structure, attr.stage), attr, ci, value)
    return nothing
end

function MOI.is_valid(structure::HorizontalStructure{2}, index::MOI.VariableIndex, stage::Integer)
    stage == 1 || error("No scenario index specified.")
    # First-stage decision should be valid in all subproblems
    return all(MOI.is_valid(scenarioproblems(structure), index, scenario_index) for scenario_index in num_scenarios(structure))
end
function MOI.is_valid(structure::HorizontalStructure{2}, ci::MOI.ConstraintIndex, stage::Integer)
    stage == 1 || error("No scenario index specified.")
    # First-stage decision constraint should be valid in all subproblems
    return all(MOI.is_valid(scenarioproblems(structure), ci, scenario_index) for scenario_index in num_scenarios(structure))
end
function MOI.is_valid(structure::HorizontalStructure{N}, ci::MOI.ConstraintIndex, stage::Integer, scenario_index::Integer) where N
    1 <= stage <= N || error("Stage $stage not in range 1 to $N.")
    stage > 1 || error("There are no scenarios in the first stage.")
    n = num_scenarios(structure, stage)
    1 <= scenario_index <= n || error("Scenario index $scenario_index not in range 1 to $n.")
    if !haskey(structure.constraint_map, (ci, scenario_index))
        return false
    end
    mapped_ci = structure.constraint_map[(ci, scenario_index)]
    return MOI.is_valid(scenarioproblems(structure, stage), mapped_ci, scenario_index)
end

function MOI.add_constraint(structure::HorizontalStructure{2}, f::SingleDecision, s::MOI.AbstractSet)
    # Constraints should be added to every subproblem
    for scenario_index in 1:num_scenarios(structure)
        MOI.add_constraint(scenarioproblems(structure), f, s, scenario_index)
    end
    return nothing
end
function MOI.add_constraint(structure::HorizontalStructure{2}, f::SingleDecision, s::MOI.AbstractSet, stage::Integer, scenario_index::Integer)
    stage == 1 && error("There are no scenarios in the first stage.")
    n = num_scenarios(structure, 2)
    1 <= scenario_index <= n || error("Scenario index $scenario_index not in range 1 to $n.")
    new_ci = MOI.add_constraint(scenarioproblems(structure), f, s, scenario_index)
    # Add to map
    ci = CI{SingleDecision,typeof(s)}(f.decision.value)
    structure.constraint_map[(ci, scenario_index)] = new_ci
    return nothing
end

function MOI.delete(structure::HorizontalStructure{2}, index::MOI.VariableIndex, stage::Integer)
    stage == 1 || error("No scenario index specified.")
    # First-stage decision should be removed from every subproblem
    for scenario_index in 1:num_scenarios(structure)
        MOI.delete(scenarioproblems(structure), index, scenario_index)
    end
    return nothing
end
function MOI.delete(structure::HorizontalStructure{2}, indices::Vector{MOI.VariableIndex}, stage::Integer)
    stage == 1 || error("No scenario index specified.")
    # First-stage decision should be removed from every subproblem
    for scenario_index in 1:num_scenarios(structure)
        MOI.delete(scenarioproblems(structure), indices, scenario_index)
    end
    return nothing
end
function MOI.delete(structure::HorizontalStructure{2}, ci::MOI.ConstraintIndex, stage::Integer)
    stage == 1 || error("No scenario index specified.")
    # First-stage decision constraints should be removed from every subproblem
    for scenario_index in 1:num_scenarios(structure)
        MOI.delete(scenarioproblems(structure), ci, scenario_index)
    end
    return nothing
end
function MOI.delete(structure::HorizontalStructure{2}, cis::Vector{<:MOI.ConstraintIndex}, stage::Integer)
    stage == 1 || error("No scenario index specified.")
    # First-stage decision constraints should be removed from every subproblem
    for scenario_index in 1:num_scenarios(structure)
        MOI.delete(scenarioproblems(structure), cis, scenario_index)
    end
    return nothing
end
function MOI.delete(structure::HorizontalStructure{N}, ci::MOI.ConstraintIndex, stage::Integer, scenario_index::Integer) where N
    1 <= stage <= N || error("Stage $stage not in range 1 to $N.")
    stage > 1 || error("There are no scenarios in the first stage.")
    n = num_scenarios(structure, stage)
    1 <= scenario_index <= n || error("Scenario index $scenario_index not in range 1 to $n.")
    mapped_ci = structure.constraint_map[(ci, scenario_index)]
    MOI.delete(scenarioproblems(structure, stage), mapped_ci, scenario_index)
    return nothing
end
function MOI.delete(structure::HorizontalStructure{N}, cis::Vector{<:MOI.ConstraintIndex}, stage::Integer, scenario_index::Integer) where N
    1 <= stage <= N || error("Stage $stage not in range 1 to $N.")
    stage > 1 || error("There are no scenarios in the first stage.")
    n = num_scenarios(structure, stage)
    1 <= scenario_index <= n || error("Scenario index $scenario_index not in range 1 to $n.")
    mapped_cis = map(ci -> structure.constraint_map[(ci, scenario_index)], cis)
    MOI.delete(scenarioproblems(structure, stage), mapped_cis, scenario_index)
    return nothing
end

# JuMP #
# ========================== #
function JuMP.fix(structure::HorizontalStructure{2}, index::MOI.VariableIndex, stage::Integer, val::Number)
    d = decision(structure, index, stage)
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
    for scenario_index in 1:num_scenarios(structure)
        fix(scenarioproblems(structure), index, scenario_index, val)
    end
    return nothing
end
function JuMP.fix(structure::HorizontalStructure{N}, index::MOI.VariableIndex, stage::Integer, scenario_index::Integer, val::Number) where N
    1 <= stage <= N || error("Stage $stage not in range 1 to $N.")
    n = num_scenarios(structure, stage)
    1 <= scenario_index <= n || error("Scenario index $scenario_index not in range 1 to $n.")
    fix(scenarioproblems(structure, stage), index, scenario_index, val)
    return nothing
end
function JuMP.unfix(structure::HorizontalStructure{2}, index::MOI.VariableIndex, stage::Integer)
    for scenario_index in 1:num_scenarios(structure)
        unfix(scenarioproblems(structure), index, scenario_index)
    end
    return nothing
end
function JuMP.unfix(structure::HorizontalStructure{N}, index::MOI.VariableIndex, stage::Integer, scenario_index::Integer) where N
    1 <= stage <= N || error("Stage $stage not in range 1 to $N.")
    n = num_scenarios(structure, stage)
    1 <= scenario_index <= n || error("Scenario index $scenario_index not in range 1 to $n.")
    unfix(scenarioproblems(structure, stage), index, scenario_index)
    return nothing
end

function JuMP.objective_function_type(structure::HorizontalStructure)
    error("The horizontal structure is completely decomposed into subproblems. All model attributes are scenario dependent.")
end

function JuMP.objective_function(structure::HorizontalStructure, FunType::Type{<:AbstractJuMPScalar})
    error("The horizontal structure is completely decomposed into subproblems. All model attributes are scenario dependent.")
end

function JuMP.objective_function(structure::HorizontalStructure, proxy::JuMP.Model, stage::Integer, FunType::Type{<:AbstractJuMPScalar})
    return objective_function(proxy, FunType)
end

function JuMP.optimizer_index(structure::HorizontalStructure, index::VI)
    return index
end
function JuMP.optimizer_index(structure::HorizontalStructure, index::VI, scenario_index::Integer)
    return index
end
function JuMP.optimizer_index(structure::HorizontalStructure, ci::CI)
    return ci
end
function JuMP.optimizer_index(structure::HorizontalStructure, ci::CI{F,S}, scenario_index::Integer) where {F,S}
    return CI{F,S}(structure.constraint_map[(ci, scenario_index)].value)
end

function JuMP.set_objective_coefficient(structure::HorizontalStructure{2}, index::VI, var_stage::Integer, stage::Integer, coeff::Real)
    if var_stage == 1
        if stage == 1
            # Modification should be applied in every subproblem
            for scenario_index in 1:num_scenarios(structure)
                set_objective_coefficient(scenarioproblems(structure), index, scenario_index, coeff)
            end
        else
            error("The horizontal structure is completely decomposed into subproblems. Can only modify first-stage part of objective for first-stage.")
        end
    else
        error("Decision is scenario dependent, consider `set_objective_coefficient(sp, dvar, stage, scenario_index, coeff)`.")
    end
    return nothing
end
function JuMP.set_objective_coefficient(structure::HorizontalStructure{N}, index::VI, var_stage::Integer, stage::Integer, scenario_index::Integer, coeff::Real) where N
    1 <= stage <= N || error("Stage $stage not in range 1 to $N.")
    stage > 1 || error("There are no scenarios in the first stage.")
    n = num_scenarios(structure, stage)
    1 <= scenario_index <= n || error("Scenario index $scenario_index not in range 1 to $n.")
    set_objective_coefficient(scenarioproblems(structure, stage), index, scenario_index, coeff)
    return nothing
end

function JuMP.set_normalized_coefficient(structure::HorizontalStructure,
                                         ci::CI{F,S},
                                         index::VI,
                                         value) where {T, F <: Union{AffineDecisionFunction{T}, QuadraticDecisionFunction{T}}, S}
    # Modification should be applied in every subproblem
    for scenario_index in 1:num_scenarios(structure)
        set_normalized_coefficient(scenarioproblems(structure), ci, index, scenario_index, value)
    end
    return nothing
end
function JuMP.set_normalized_coefficient(structure::HorizontalStructure{N},
                                         ci::CI{F,S},
                                         index::VI,
                                         stage::Integer,
                                         scenario_index::Integer,
                                         value) where {N, T, F <: Union{AffineDecisionFunction{T}, QuadraticDecisionFunction{T}}, S}
    1 <= stage <= N || error("Stage $stage not in range 1 to $N.")
    stage > 1 || error("There are no scenarios in the first stage.")
    n = num_scenarios(structure, stage)
    1 <= scenario_index <= n || error("Scenario index $scenario_index not in range 1 to $n.")
    mapped_ci = structure.constraint_map[(ci, scenario_index)]
    set_normalized_coefficient(scenarioproblems(structure, stage), mapped_ci, index, scenario_index, value)
    return nothing
end

function JuMP.normalized_coefficient(structure::HorizontalStructure{N},
                                     ci::CI{F,S},
                                     index::VI,
                                     stage::Integer,
                                     scenario_index::Integer) where {N, T, F <: Union{AffineDecisionFunction{T}, QuadraticDecisionFunction{T}}, S}
    1 <= stage <= N || error("Stage $stage not in range 1 to $N.")
    stage > 1 || error("There are no scenarios in the first stage.")
    n = num_scenarios(structure, stage)
    1 <= scenario_index <= n || error("Scenario index $scenario_index not in range 1 to $n.")
    mapped_ci = structure.constraint_map[(ci, scenario_index)]
    return normalized_coefficient(scenarioproblems(structure, stage), mapped_ci, index, scenario_index)
end

function JuMP.set_normalized_rhs(structure::HorizontalStructure,
                                 ci::CI{F,S},
                                 value) where {T,
                                               F <: Union{AffineDecisionFunction{T}, QuadraticDecisionFunction{T}},
                                               S <: MOIU.ScalarLinearSet{T}}
    # Modification should be applied in every subproblem
    for scenario_index in 1:num_scenarios(structure)
        set_normalized_rhs(scenarioproblems(structure), ci, scenario_index, value)
    end
    return nothing
end
function JuMP.set_normalized_rhs(structure::HorizontalStructure{N},
                                 ci::CI{F,S},
                                 stage::Integer,
                                 scenario_index::Integer,
                                 value) where {N,
                                               T,
                                               F <: Union{AffineDecisionFunction{T}, QuadraticDecisionFunction{T}},
                                               S <: MOIU.ScalarLinearSet{T}}
    1 <= stage <= N || error("Stage $stage not in range 1 to $N.")
    stage > 1 || error("There are no scenarios in the first stage.")
    n = num_scenarios(structure, stage)
    1 <= scenario_index <= n || error("Scenario index $scenario_index not in range 1 to $n.")
    mapped_ci = structure.constraint_map[(ci, scenario_index)]
    set_normalized_rhs(scenarioproblems(structure, stage), mapped_ci, scenario_index, value)
    return nothing
end

function DecisionRef(proxy::JuMP.Model, structure::HorizontalStructure, index::VI)
    return DecisionRef(proxy, index)
end

function KnownRef(proxy::JuMP.Model, structure::HorizontalStructure, index::VI, at_stage::Integer, scenario_index::Integer)
    at_stage > 1 || error("There are no scenarios in the first at_stage.")
    n = num_scenarios(structure, at_stage)
    1 <= scenario_index <= n || error("Scenario index $scenario_index not in range 1 to $n.")
    # Although technically known, decision acts as DecisionRef in horizontal structure
    return DecisionRef(proxy, index)
end

function JuMP.jump_function(structure::HorizontalStructure{N},
                            proxy::JuMP.Model,
                            stage::Integer,
                            f::MOI.AbstractFunction) where N
    1 <= stage <= N || error("Stage $stage not in range 1 to $N.")
    return JuMP.jump_function(proxy, f)
end

# Getters #
# ========================== #
function structure_name(structure::HorizontalStructure)
    return "Horizontal"
end

function decision(structure::HorizontalStructure{N}, index::MOI.VariableIndex, stage::Integer) where N
    stage == 1 || error("No scenario index specified.")
    return decision(structure.decisions[stage], index)
end

# Setters #
# ========================== #
function update_decisions!(structure::HorizontalStructure{2}, change::DecisionModification)
    # Modification should be applied in every subproblem
    for scenario_index in 1:num_scenarios(structure)
        update_decisions!(scenarioproblems(structure), change, scenario_index)
    end
    return nothing
end

function untake_decisions!(structure::HorizontalStructure{2,1,NTuple{1,SP}}) where SP <: ScenarioProblems
    if untake_decisions!(structure.decisions[1])
        update_decisions!(scenarioproblems(structure), DecisionsStateChange())
    end
    return nothing
end
function untake_decisions!(structure::HorizontalStructure{2,1,NTuple{1,SP}}) where SP <: DistributedScenarioProblems
    sp = scenarioproblems(structure)
    @sync begin
        for (i,w) in enumerate(workers())
            @async remotecall_fetch(
                w, sp[w-1], sp.decisions[w-1]) do sp, d
                    if untake_decisions!(fetch(d))
                        update_decisions!(fetch(sp), DecisionsStateChange())
                    end
                end
        end
    end
    return nothing
end
