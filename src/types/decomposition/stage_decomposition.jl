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
    StageDecompositionStructure

Vertical memory structure. Decomposes stochastic program by stages.

"""
struct StageDecompositionStructure{N, M, SP <: NTuple{M, AbstractScenarioProblems}} <: AbstractDecompositionStructure{N}
    decisions::Decisions{N}
    first_stage::JuMP.Model
    scenarioproblems::SP
    proxy::NTuple{N,JuMP.Model}

    function StageDecompositionStructure(decisions::Decisions{N}, scenarioproblems::NTuple{M,AbstractScenarioProblems}) where {N, M}
        M == N - 1 || error("Inconsistent number of stages $N and number of scenario types $M")
        SP = typeof(scenarioproblems)
        proxy = ntuple(Val{N}()) do _
            Model()
        end
        return new{N,M,SP}(decisions, Model(), scenarioproblems, proxy)
    end
end

function StochasticStructure(decisions::Decisions{N}, scenario_types::ScenarioTypes{M}, instantiation::Union{StageDecomposition, DistributedStageDecomposition}) where {N, M}
    scenarioproblems = ntuple(Val(M)) do i
        ScenarioProblems(scenario_types[i], instantiation)
    end
    return StageDecompositionStructure(decisions, scenarioproblems)
end

function StochasticStructure(decisions::Decisions{N}, scenarios::NTuple{M, Vector{<:AbstractScenario}}, instantiation::Union{StageDecomposition, DistributedStageDecomposition}) where {N, M}
    scenarioproblems = ntuple(Val(M)) do i
        ScenarioProblems(scenarios[i], instantiation)
    end
    return StageDecompositionStructure(decisions, scenarioproblems)
end

# Base overloads #
# ========================== #
function Base.print(io::IO, structure::StageDecompositionStructure{N}) where N
    print(io, "Stage 1\n")
    print(io, "============== \n")
    print(io, structure.first_stage)
    for stage in 2:N
        print(io, "\nStage $stage\n")
        print(io, "============== \n")
        for (id, subproblem) in enumerate(subproblems(structure, stage))
            @printf(io, "Subproblem %d (p = %.2f):\n", id, probability(structure, stage, id))
            print(io, subproblem)
            print(io, "\n")
        end
    end
end
function Base.print(io::IO, structure::StageDecompositionStructure{2})
    print(io, "First-stage \n")
    print(io, "============== \n")
    print(io, structure.first_stage)
    print(io, "\nSecond-stage \n")
    print(io, "============== \n")
    for (id, subproblem) in enumerate(subproblems(structure, 2))
        @printf(io, "Subproblem %d (p = %.2f):\n", id, probability(structure, 2, id))
        print(io, subproblem)
        print(io, "\n")
    end
end
# ========================== #

# MOI #
# ========================== #
function MOI.get(structure::StageDecompositionStructure, attr::MOI.AbstractModelAttribute)
    return MOI.get(backend(structure.first_stage), attr)
end
function MOI.get(structure::StageDecompositionStructure, attr::MOI.AbstractVariableAttribute, index::MOI.VariableIndex)
    return MOI.get(backend(structure.first_stage), attr, index)
end
function MOI.get(structure::StageDecompositionStructure, attr::Type{MOI.VariableIndex}, name::String)
    return MOI.get(backend(structure.first_stage), attr, name)
end
function MOI.get(structure::StageDecompositionStructure, attr::MOI.AbstractConstraintAttribute, ci::MOI.ConstraintIndex)
    if _function_type(ci) <: SingleDecision
        # Need to map constraint
        con_ref = ConstraintRef(structure.first_stage, ci)
        return MOI.get(structure.first_stage, attr, con_ref)
    end
    return MOI.get(backend(structure.first_stage), attr, ci)
end
function MOI.get(structure::StageDecompositionStructure, attr::ScenarioDependentModelAttribute)
    n = num_scenarios(structure, attr.stage)
    1 <= attr.scenario_index <= n || error("Scenario index $attr.scenario_index not in range 1 to $n.")
    return MOI.get(scenarioproblems(structure, attr.stage), attr)
end
function MOI.get(structure::StageDecompositionStructure, attr::ScenarioDependentVariableAttribute, index::MOI.VariableIndex)
    n = num_scenarios(structure, attr.stage)
    1 <= attr.scenario_index <= n || error("Scenario index $attr.scenario_index not in range 1 to $n.")
    return MOI.get(scenarioproblems(structure, attr.stage), attr, index)
end
function MOI.get(structure::StageDecompositionStructure, attr::ScenarioDependentConstraintAttribute, ci::MOI.ConstraintIndex)
    n = num_scenarios(structure, attr.stage)
    1 <= attr.scenario_index <= n || error("Scenario index $attr.scenario_index not in range 1 to $n.")
    return MOI.get(scenarioproblems(structure, attr.stage), attr, ci)
end

function MOI.set(structure::StageDecompositionStructure, attr::MOI.AbstractModelAttribute, value)
    MOI.set(backend(structure.first_stage), attr, value)
    return nothing
end
function MOI.set(structure::StageDecompositionStructure, attr::MOI.Silent, flag)
    # Silence master
    MOI.set(backend(structure.first_stage), attr, flag)
    # Silence subproblems
    MOI.set(scenarioproblems(structure), attr, flag)
    return nothing
end
function MOI.set(structure::StageDecompositionStructure, attr::MOI.AbstractVariableAttribute,
                 index::MOI.VariableIndex, value)
    MOI.set(backend(structure.first_stage), attr, index, value)
    return nothing
end
function MOI.set(structure::StageDecompositionStructure, attr::MOI.AbstractConstraintAttribute,
                 ci::MOI.ConstraintIndex, value)
    con_ref = ConstraintRef(structure.first_stage, ci)
    MOI.set(structure.first_stage, attr, con_ref, value)
    return nothing
end
function MOI.set(structure::StageDecompositionStructure, attr::ScenarioDependentModelAttribute, value)
    n = num_scenarios(structure, attr.stage)
    1 <= attr.scenario_index <= n || error("Scenario index $attr.scenario_index not in range 1 to $n.")
    MOI.set(scenarioproblems(structure, attr.stage), attr, value)
    return nothing
end
function MOI.set(structure::StageDecompositionStructure, attr::ScenarioDependentVariableAttribute,
                 index::MOI.VariableIndex, value)
    n = num_scenarios(structure, attr.stage)
    1 <= attr.scenario_index <= n || error("Scenario index $attr.scenario_index not in range 1 to $n.")
    MOI.set(scenarioproblems(structure, attr.stage), attr, index, value)
    return nothing
end
function MOI.set(structure::StageDecompositionStructure, attr::ScenarioDependentConstraintAttribute,
                 ci::MOI.ConstraintIndex, value)
    n = num_scenarios(structure, attr.stage)
    1 <= attr.scenario_index <= n || error("Scenario index $attr.scenario_index not in range 1 to $n.")
    MOI.set(scenarioproblems(structure, attr.stage), attr, ci, value)
    return nothing
end

function MOI.is_valid(structure::StageDecompositionStructure, index::MOI.VariableIndex, stage::Integer)
    stage == 1 || error("No scenario index specified.")
    return MOI.is_valid(backend(structure.first_stage), index)
end
function MOI.is_valid(structure::StageDecompositionStructure, index::MOI.VariableIndex, stage::Integer, scenario_index::Integer)
    stage == 1 && error("There are no scenarios in the first stage.")
    n = num_scenarios(structure, stage)
    1 <= scenario_index <= n || error("Scenario index $scenario_index not in range 1 to $n.")
    return MOI.is_valid(scenarioproblems(structure, stage), index, scenario_index)
end
function MOI.is_valid(structure::StageDecompositionStructure, ci::MOI.ConstraintIndex, stage::Integer)
    stage == 1 || error("No scenario index specified.")
    return MOI.is_valid(backend(structure.first_stage), ci)
end
function MOI.is_valid(structure::StageDecompositionStructure{N}, ci::MOI.ConstraintIndex, stage::Integer, scenario_index::Integer) where N
    1 <= stage <= N || error("Stage $stage not in range 1 to $N.")
    stage > 1 || error("There are no scenarios in the first stage.")
    n = num_scenarios(structure, stage)
    1 <= scenario_index <= n || error("Scenario index $scenario_index not in range 1 to $n.")
    return MOI.is_valid(scenarioproblems(structure, stage), ci, scenario_index)
end

function MOI.delete(structure::StageDecompositionStructure{N}, indices::Vector{MOI.VariableIndex}, stage::Integer) where N
    stage == 1 || error("No scenario index specified.")
    JuMP.delete(structure.first_stage, DecisionRef.(structure.first_stage, indices))
    # Remove known decisions
    for s in 2:N
        MOI.delete(scenarioproblems(structure, s), indices)
    end
    return nothing
end
function MOI.delete(structure::StageDecompositionStructure{N}, indices::Vector{MOI.VariableIndex}, stage::Integer, scenario_index::Integer) where N
    1 <= stage <= N || error("Stage $stage not in range 1 to $N.")
    stage > 1 || error("There are no scenarios in the first stage.")
    n = num_scenarios(structure, stage)
    1 <= scenario_index <= n || error("Scenario index $scenario_index not in range 1 to $n.")
    MOI.delete(scenarioproblems(structure, stage), indices, scenario_index)
    return nothing
end
function MOI.delete(structure::StageDecompositionStructure, ci::MOI.ConstraintIndex, stage::Integer)
    stage == 1 || error("No scenario index specified.")
    MOI.delete(backend(structure.first_stage), ci)
    return nothing
end
function MOI.delete(structure::StageDecompositionStructure, cis::Vector{<:MOI.ConstraintIndex}, stage::Integer)
    stage == 1 || error("No scenario index specified.")
    MOI.delete(backend(structure.first_stage), cis)
    return nothing
end
function MOI.delete(structure::StageDecompositionStructure{N}, ci::MOI.ConstraintIndex, stage::Integer, scenario_index::Integer) where N
    1 <= stage <= N || error("Stage $stage not in range 1 to $N.")
    stage > 1 || error("There are no scenarios in the first stage.")
    n = num_scenarios(structure, stage)
    1 <= scenario_index <= n || error("Scenario index $scenario_index not in range 1 to $n.")
    MOI.delete(scenarioproblems(structure, stage), ci, scenario_index)
    return nothing
end
function MOI.delete(structure::StageDecompositionStructure{N}, cis::Vector{<:MOI.ConstraintIndex}, stage::Integer, scenario_index::Integer) where N
    1 <= stage <= N || error("Stage $stage not in range 1 to $N.")
    stage > 1 || error("There are no scenarios in the first stage.")
    n = num_scenarios(structure, stage)
    1 <= scenario_index <= n || error("Scenario index $scenario_index not in range 1 to $n.")
    MOI.delete(scenarioproblems(structure, stage), cis, scenario_index)
    return nothing
end

# JuMP #
# ========================== #
function decision_dispatch(decision_function::Function,
                           structure::StageDecompositionStructure{N},
                           index::MOI.VariableIndex,
                           stage::Integer,
                           args...) where N
    1 <= stage <= N || error("Stage $stage not in range 1 to $N.")
    stage == 1 || error("No scenario index specified.")
    dref = DecisionRef(structure.first_stage, index)
    return decision_function(dref, args...)
end
function decision_dispatch!(decision_function!::Function,
                            structure::StageDecompositionStructure{N},
                            index::MOI.VariableIndex,
                            stage::Integer,
                            args...) where N
    1 <= stage <= N || error("Stage $stage not in range 1 to $N.")
    stage == 1 || error("No scenario index specified.")
    dref = DecisionRef(structure.first_stage, index)
    decision_function!(dref, args...)
    return nothing
end
function scenario_decision_dispatch(decision_function::Function,
                                    structure::StageDecompositionStructure{N},
                                    index::MOI.VariableIndex,
                                    stage::Integer,
                                    scenario_index::Integer,
                                    args...) where N
    1 <= stage <= N || error("Stage $stage not in range 1 to $N.")
    stage > 1 || error("There are no scenarios in the first stage.")
    n = num_scenarios(structure, stage)
    1 <= scenario_index <= n || error("Scenario index $scenario_index not in range 1 to $n.")
    return scenario_decision_dispatch(decision_function,
                                      scenarioproblems(structure, stage),
                                      index,
                                      scenario_index,
                                      args...)
end
function scenario_decision_dispatch!(decision_function!::Function,
                                     structure::StageDecompositionStructure{N},
                                     index::MOI.VariableIndex,
                                     stage::Integer,
                                     scenario_index::Integer,
                                     args...) where N
    1 <= stage <= N || error("Stage $stage not in range 1 to $N.")
    stage > 1 || error("There are no scenarios in the first stage.")
    n = num_scenarios(structure, stage)
    1 <= scenario_index <= n || error("Scenario index $scenario_index not in range 1 to $n.")
    scenario_decision_dispatch!(decision_function!,
                                scenarioproblems(structure, stage),
                                index,
                                scenario_index,
                                args...)
    return nothing
end
function JuMP.fix(structure::StageDecompositionStructure{N}, index::MOI.VariableIndex, stage::Integer, val::Number) where N
    dref = DecisionRef(structure.first_stage, index)
    fix(dref, val)
    update_decision_state!(scenarioproblems(structure), index, Known)
    return nothing
end
function JuMP.fix(structure::StageDecompositionStructure{N}, index::MOI.VariableIndex, stage::Integer, scenario_index::Integer, val::Number) where N
    1 <= stage <= N || error("Stage $stage not in range 1 to $N.")
    n = num_scenarios(structure, stage)
    1 <= scenario_index <= n || error("Scenario index $scenario_index not in range 1 to $n.")
    fix(scenarioproblems(structure, stage), index, scenario_index, val)
    return nothing
end
function JuMP.unfix(structure::StageDecompositionStructure{N}, index::MOI.VariableIndex, stage::Integer) where N
    dref = DecisionRef(structure.first_stage, index)
    unfix(dref)
    return nothing
end
function JuMP.unfix(structure::StageDecompositionStructure{N}, index::MOI.VariableIndex, stage::Integer, scenario_index::Integer) where N
    1 <= stage <= N || error("Stage $stage not in range 1 to $N.")
    n = num_scenarios(structure, stage)
    1 <= scenario_index <= n || error("Scenario index $scenario_index not in range 1 to $n.")
    unfix(scenarioproblems(structure, stage), index, scenario_index)
    return nothing
end
function JuMP.set_objective_sense(structure::StageDecompositionStructure, stage::Integer, sense::MOI.OptimizationSense)
    if stage == 1
        MOI.set(structure, MOI.ObjectiveSense(), sense)
    else
        # Every sub-objective in the given stage should be changed
        MOI.set(scenarioproblems(structure), MOI.ObjectiveSense(), sense)
    end
    return nothing
end
function JuMP.objective_function_type(structure::StageDecompositionStructure)
    return jump_function_type(structure.first_stage,
                              MOI.get(structure, MOI.ObjectiveFunctionType()))
end

function JuMP.objective_function(structure::StageDecompositionStructure, FunType::Type{<:AbstractJuMPScalar})
    MOIFunType = moi_function_type(FunType)
    func = MOI.get(structure.first_stage,
                   MOI.ObjectiveFunction{MOIFunType}())::MOIFunType
    return JuMP.jump_function(structure, 1, func)
end

function JuMP.objective_function(structure::StageDecompositionStructure, stage::Integer, FunType::Type{<:AbstractJuMPScalar})
    if stage == 1
        return objective_function(structure, FunType)
    else
        return objective_function(structure.proxy, FunType)
    end
end

function JuMP._moi_optimizer_index(structure::StageDecompositionStructure, index::VI)
    return decision_index(backend(structure.first_stage), index)
end
function JuMP._moi_optimizer_index(structure::StageDecompositionStructure, index::VI, scenario_index::Integer)
    return JuMP._moi_optimizer_index(scenarioproblems(structure), index, scenario_index)
end
function JuMP._moi_optimizer_index(structure::StageDecompositionStructure, ci::CI)
    return decision_index(backend(structure.first_stage), ci)
end

function JuMP.set_objective_coefficient(structure::StageDecompositionStructure{N}, index::VI, var_stage::Integer, stage::Integer, coeff::Real) where N
    1 <= stage <= N || error("Stage $stage not in range 1 to $N.")
    var_stage <= stage || error("Can only modify coefficient in current stage of decision or subsequent stages from where decision is taken.")
    if var_stage == 1
        if stage == 1
            dref = DecisionRef(structure.first_stage, index)
            set_objective_coefficient(structure.first_stage, dref, coeff)
        else
            set_objective_coefficient(scenarioproblems(structure, stage), index, coeff)
        end
    else
        for scenario_index in 1:num_scenarios(structure, stage)
            set_objective_coefficient(scenarioproblems(structure, stage), index, scenario_index, coeff)
        end
    end
    return nothing
end
function JuMP.set_objective_coefficient(structure::StageDecompositionStructure{N}, index::VI, var_stage::Integer, stage::Integer, scenario_index::Integer, coeff::Real) where N
    1 <= stage <= N || error("Stage $stage not in range 1 to $N.")
    n = num_scenarios(structure, stage)
    1 <= scenario_index <= n || error("Scenario index $scenario_index not in range 1 to $n.")
    if var_stage == 1
        set_objective_coefficient(scenarioproblems(structure, stage), index, scenario_index, coeff)
    else
        set_objective_coefficient(scenarioproblems(structure, stage), index, scenario_index, coeff)
    end
    return nothing
end

function JuMP.set_normalized_coefficient(structure::StageDecompositionStructure,
                                         ci::CI{F,S},
                                         index::VI,
                                         value) where {T, F <: Union{AffineDecisionFunction{T}, QuadraticDecisionFunction{T}}, S}
    MOI.modify(backend(structure.first_stage), ci,
               DecisionCoefficientChange(index, convert(T, value)))
    return nothing
end
function JuMP.set_normalized_coefficient(structure::StageDecompositionStructure{N},
                                         ci::CI{F,S},
                                         index::VI,
                                         var_stage::Integer,
                                         stage::Integer,
                                         scenario_index::Integer,
                                         value) where {N, T, F <: Union{AffineDecisionFunction{T}, QuadraticDecisionFunction{T}}, S}
    1 <= stage <= N || error("Stage $stage not in range 1 to $N.")
    stage > 1 || error("There are no scenarios in the first stage.")
    n = num_scenarios(structure, stage)
    1 <= scenario_index <= n || error("Scenario index $scenario_index not in range 1 to $n.")
    set_normalized_coefficient(scenarioproblems(structure, stage), ci, index, scenario_index, value)
    return nothing
end

function JuMP.normalized_coefficient(structure::StageDecompositionStructure{N},
                                     ci::CI{F,S},
                                     index::VI,
                                     var_stage::Integer,
                                     stage::Integer,
                                     scenario_index::Integer) where {N, T, F <: Union{AffineDecisionFunction{T}, QuadraticDecisionFunction{T}}, S}
    1 <= stage <= N || error("Stage $stage not in range 1 to $N.")
    stage > 1 || error("There are no scenarios in the first stage.")
    n = num_scenarios(structure, stage)
    1 <= scenario_index <= n || error("Scenario index $scenario_index not in range 1 to $n.")
    return normalized_coefficient(scenarioproblems(structure, stage), ci, index, scenario_index)
end

function JuMP.set_normalized_rhs(structure::StageDecompositionStructure,
                                 ci::CI{F,S},
                                 value) where {T,
                                               F <: Union{AffineDecisionFunction{T}, QuadraticDecisionFunction{T}},
                                               S <: MOIU.ScalarLinearSet{T}}
    MOI.set(backend(structure.first_stage), MOI.ConstraintSet(), ci,
            S(convert(T, value)))
    return nothing
end
function JuMP.set_normalized_rhs(structure::StageDecompositionStructure{N},
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
    set_normalized_rhs(scenarioproblems(structure, stage), ci, scenario_index, value)
    return nothing
end

function DecisionRef(structure::StageDecompositionStructure, index::VI)
    return DecisionRef(structure.first_stage, index)
end

function JuMP.jump_function(structure::StageDecompositionStructure{N},
                            stage::Integer,
                            f::MOI.AbstractFunction) where N
    1 <= stage <= N || error("Stage $stage not in range 1 to $N.")
    if stage == 1
        return JuMP.jump_function(structure.first_stage, f)
    else
        return JuMP.jump_function(structure.proxy[stage], f)
    end
end
function JuMP.jump_function(structure::StageDecompositionStructure{N},
                            stage::Integer,
                            scenario_index::Integer,
                            f::MOI.AbstractFunction) where N
    1 <= stage <= N || error("Stage $stage not in range 1 to $N.")
    return JuMP.jump_function(structure.proxy[stage], f)
end

# Getters #
# ========================== #
function structure_name(structure::StageDecompositionStructure)
    return "Stage-decomposition"
end

deferred_first_stage(structure::StageDecompositionStructure, ::Val{1}) = num_variables(first_stage(structure)) == 0

function decision(structure::StageDecompositionStructure{N}, index::MOI.VariableIndex, stage::Integer) where N
    stage == 1 || error("No scenario index specified.")
    return decision(structure.decisions, stage, index)
end
function decision(structure::StageDecompositionStructure{N}, index::MOI.VariableIndex, stage::Integer, scenario_index::Integer) where N
    stage > 1 || error("There are no scenarios in the first stage.")
    n = num_scenarios(structure, stage)
    1 <= scenario_index <= n || error("Scenario index $scenario_index not in range 1 to $n.")
    return decision(scenarioproblems(structure, stage), index, scenario_index)
end
# ========================== #

# Setters
# ========================== #
function update_known_decisions!(structure::StageDecompositionStructure)
    update_known_decisions!(structure.first_stage)
    return nothing
end
