"""
    DeterministicEquivalent

Deterministic equivalent memory structure. Stochastic program is stored as one large optimization problem. Supported by any standard `AbstractOptimizer`.

"""
struct DeterministicEquivalent{N, M, S <: NTuple{M, Scenarios}} <: AbstractStochasticStructure{N}
    decisions::Decisions{N}
    scenarios::S
    model::JuMP.Model
    proxy::NTuple{N,JuMP.Model}

    function DeterministicEquivalent(decisions::Decisions{N}, scenarios::NTuple{M, Scenarios}) where {N, M}
        M == N - 1 || error("Inconsistent number of stages $N and number of scenario types $M")
        proxy = ntuple(Val{N}()) do _
            Model()
        end
        S = typeof(scenarios)
        return new{N,M,S}(decisions, scenarios, Model(), proxy)
    end
end

function StochasticStructure(decisions::Decisions{N}, scenario_types::ScenarioTypes{M}, ::Deterministic) where {N, M}
    scenarios = ntuple(Val(M)) do i
        Vector{scenario_types[i]}()
    end
    return DeterministicEquivalent(decisions, scenarios)
end

function StochasticStructure(decisions::Decisions{N}, scenarios::NTuple{M, Vector{<:AbstractScenario}}, ::Deterministic) where {N, M}
    return DeterministicEquivalent(decisions, scenarios)
end

# Base overloads #
# ========================== #
function Base.print(io::IO, structure::DeterministicEquivalent)
    print(io, "Deterministic equivalent problem\n")
    print(io, structure.model)
end
# ========================== #

# MOI #
# ========================== #
function MOI.get(structure::DeterministicEquivalent, attr::MOI.AbstractModelAttribute)
    return MOI.get(backend(structure.model), attr)
end
function MOI.get(structure::DeterministicEquivalent, attr::MOI.AbstractVariableAttribute, index::MOI.VariableIndex)
    return MOI.get(backend(structure.model), attr, index)
end
function MOI.get(structure::DeterministicEquivalent, attr::MOI.AbstractConstraintAttribute, ci::CI)
    return MOI.get(backend(structure.model), attr, ci)
end
function MOI.get(structure::DeterministicEquivalent, attr::MOI.AbstractConstraintAttribute, ci::CI{F,S}) where {F <: SingleDecision, S}
    con_ref = ConstraintRef(structure.model, ci)
    return MOI.get(structure.model, attr, con_ref)
end
function MOI.get(structure::DeterministicEquivalent{N}, attr::ScenarioDependentModelAttribute) where N
    n = num_scenarios(structure, attr.stage)
    1 <= attr.scenario_index <= n || error("Scenario index $attr.scenario_index not in range 1 to $n.")
    if attr.attr isa MOI.ObjectiveFunction
        return get_stage_objective(structure.decisions, attr.stage, attr.scenario_index)[2]
    elseif attr.attr isa MOI.ObjectiveFunctionType
        return typeof(get_stage_objective(structure.decisions, attr.stage, attr.scenario_index)[2])
    elseif attr.attr isa MOI.ObjectiveSense
        return get_stage_objective(structure.decisions, attr.stage, attr.scenario_index)[1]
    elseif attr.attr isa MOI.ObjectiveValue || attr.attr isa MOI.DualObjectiveValue
        return MOIU.eval_variables(get_stage_objective(structure.decisions, attr.stage, attr.scenario_index)[2]) do idx
            return MOI.get(backend(structure.model), MOI.VariablePrimal(), idx)
        end
    else
        # Most attributes are shared with the deterministic equivalent
        return MOI.get(backend(structure.model), attr.attr)
    end
end
function MOI.get(structure::DeterministicEquivalent, attr::ScenarioDependentVariableAttribute, index::MOI.VariableIndex)
    n = num_scenarios(structure, attr.stage)
    1 <= attr.scenario_index <= n || error("Scenario index $attr.scenario_index not in range 1 to $n.")
    mapped_vi = mapped_index(structure, index, attr.scenario_index)
    return MOI.get(backend(structure.model), attr.attr, mapped_vi)
end
function MOI.get(structure::DeterministicEquivalent, attr::ScenarioDependentConstraintAttribute, ci::CI)
    n = num_scenarios(structure, attr.stage)
    1 <= attr.scenario_index <= n || error("Scenario index $attr.scenario_index not in range 1 to $n.")
    mapped_ci = mapped_index(structure, ci, attr.scenario_index)
    return MOI.get(backend(structure.model), attr.attr, mapped_ci)
end
function MOI.get(structure::DeterministicEquivalent, attr::ScenarioDependentConstraintAttribute, ci::CI{F,S}) where {F <: SingleDecision, S}
    n = num_scenarios(structure, attr.stage)
    1 <= attr.scenario_index <= n || error("Scenario index $attr.scenario_index not in range 1 to $n.")
    mapped_vi = mapped_index(structure, MOI.VariableIndex(ci.value), attr.scenario_index)
    mapped_ci = CI{F,S}(mapped_vi.value)
    con_ref = ConstraintRef(structure.model, mapped_ci)
    return MOI.get(structure.model, attr.attr, con_ref)
end
function MOI.get(structure::DeterministicEquivalent, attr::ScenarioDependentConstraintAttribute, ci::CI{F,S}) where {F <: MOI.SingleVariable, S}
    n = num_scenarios(structure, attr.stage)
    1 <= attr.scenario_index <= n || error("Scenario index $attr.scenario_index not in range 1 to $n.")
    mapped_vi = mapped_index(structure, MOI.VariableIndex(ci.value), attr.scenario_index)
    mapped_ci = CI{F,S}(mapped_vi.value)
    return MOI.get(backend(structure.model), attr.attr, mapped_ci)
end

function MOI.set(structure::DeterministicEquivalent, attr::MOI.Silent, flag)
    MOI.set(backend(structure.model), attr, flag)
    return nothing
end
function MOI.set(structure::DeterministicEquivalent{N}, attr::MOI.AbstractModelAttribute, value) where N
    if attr isa MOI.ObjectiveFunction
        # Get full objective+sense
        dep_obj = copy(value)
        obj_sense = objective_sense(structure.model)
        # Update first-stage objective
        set_stage_objective!(structure.decisions, 1, 1, obj_sense, value)
        # Update main objective
        for (i, sub_objective) in enumerate(structure.decisions.stage_objectives[2])
            (sense, func) = sub_objective
            if obj_sense == sense
                dep_obj += probability(structure, 2, i) * func
            else
                dep_obj -= probability(structure, 2, i) * func
            end
        end
        MOI.set(backend(structure.model), attr, dep_obj)
    elseif attr isa MOI.ObjectiveSense
        # Get full objective+sense
        prev_sense, dep_obj = get_stage_objective(structure.decisions, 1, 1)
        # Update first-stage objective
        set_stage_objective!(structure.decisions, 1, 1, value, dep_obj)
        # Update main objective (if necessary)
        if value != prev_sense
            for (i, sub_objective) in enumerate(structure.decisions.stage_objectives[2])
                (sense, func) = sub_objective
                if value == sense
                    dep_obj += probability(structure, 2, i) * func
                else
                    dep_obj -= probability(structure, 2, i) * func
                end
            end
            MOI.set(backend(structure.model), MOI.ObjectiveFunction{typeof(dep_obj)}(), dep_obj)
        end
        MOI.set(backend(structure.model), MOI.ObjectiveSense(), value)
    else
        # Most attributes are shared with the deterministic equivalent
        MOI.set(backend(structure.model), attr, value)
    end
    return nothing
end
function MOI.set(structure::DeterministicEquivalent, attr::MOI.AbstractVariableAttribute,
                 index::MOI.VariableIndex, value)
    MOI.set(backend(structure.model), attr, index, value)
    return nothing
end
function MOI.set(structure::DeterministicEquivalent, attr::MOI.AbstractConstraintAttribute,
                 ci::MOI.ConstraintIndex, value)
    con_ref = ConstraintRef(structure.model, mapped_ci)
    MOI.set(structure.model, attr.attr, con_ref, value)
    return nothing
end
function MOI.set(structure::DeterministicEquivalent{N}, attr::ScenarioDependentModelAttribute, value) where N
    if attr.attr isa MOI.ObjectiveFunction
        # Get full objective+sense
        obj_sense = objective_sense(structure.model)
        dep_obj = objective_function(structure.model)
        # Update subobjective
        (sub_sense, prev_func) = get_stage_objective(structure.model, attr.stage, attr.scenario_index, Val{N}())
        set_stage_objective!(structure.decisions, attr.stage, attr.scenario_index, sub_sense, value)
        sub_obj = jump_function(structure.model, value)
        # Update main objective
        if obj_sense == sub_sense
            dep_obj += probability(structure, attr.stage, attr.scenario_index) * (sub_obj - prev_func)
        else
            dep_obj -= probability(structure, attr.stage, attr.scenario_index) * (sub_obj - prev_func)
        end
        set_objective_function(structure.model, dep_obj)
    elseif attr.attr isa MOI.ObjectiveSense
        # Get current
        (prev_sense, func) = get_stage_objective(structure.model, attr.stage, attr.scenario_index, Val{N}())
        if value == prev_sense
            # Nothing to do
            return nothing
        end
        # Get full objective+sense
        obj_sense = objective_sense(structure.model)
        dep_obj = objective_function(structure.model)
        # Update subobjective sense
        set_stage_objective!(structure.decisions, attr.stage, attr.scenario_index, value, moi_function(func))
        # Update main objective
        if value == obj_sense
            dep_obj += 2 * probability(structure, attr.stage, attr.scenario_index) * func
        else
            dep_obj -= 2 * probability(structure, attr.stage, attr.scenario_index) * func
        end
        set_objective_function(structure.model, dep_obj)
    else
        # Most attributes are shared with the deterministic equivalent
        MOI.set(backend(structure.model), attr.attr, value)
    end
    return nothing
end
function MOI.set(structure::DeterministicEquivalent, attr::ScenarioDependentVariableAttribute,
                 index::MOI.VariableIndex, value)
    n = num_scenarios(structure, attr.stage)
    1 <= attr.scenario_index <= n || error("Scenario index $attr.scenario_index not in range 1 to $n.")
    mapped_vi = mapped_index(structure, index, attr.scenario_index)
    MOI.set(backend(structure.model), attr.attr, mapped_vi, value)
    return nothing
end
function MOI.set(structure::DeterministicEquivalent, attr::ScenarioDependentConstraintAttribute,
                 ci::CI, value)
    n = num_scenarios(structure, attr.stage)
    1 <= attr.scenario_index <= n || error("Scenario index $attr.scenario_index not in range 1 to $n.")
    mapped_ci = mapped_index(structure, ci, attr.scenario_index)
    MOI.set(backend(structure.model), attr.attr, mapped_ci, value)
    return nothing
end
function MOI.set(structure::DeterministicEquivalent, attr::ScenarioDependentConstraintAttribute,
                 ci::CI{F,S}, value) where {F <: SingleDecision, S}
    n = num_scenarios(structure, attr.stage)
    1 <= attr.scenario_index <= n || error("Scenario index $attr.scenario_index not in range 1 to $n.")
    mapped_vi = mapped_index(structure, MOI.VariableIndex(ci.value), attr.scenario_index)
    mapped_ci = CI{F,S}(mapped_vi.value)
    con_ref = ConstraintRef(structure.model, mapped_ci)
    MOI.set(structure.model, attr.attr, con_ref, value)
    return nothing
end
function MOI.set(structure::DeterministicEquivalent, attr::ScenarioDependentConstraintAttribute,
                 ci::CI{F,S}, value) where {F <: MOI.SingleVariable, S}
    n = num_scenarios(structure, attr.stage)
    1 <= attr.scenario_index <= n || error("Scenario index $attr.scenario_index not in range 1 to $n.")
    mapped_vi = mapped_index(structure, MOI.VariableIndex(ci.value), attr.scenario_index)
    mapped_ci = CI{F,S}(mapped_vi.value)
    MOI.set(backend(structure.model), attr.attr, mapped_ci, value)
    return nothing
end

function MOI.is_valid(structure::DeterministicEquivalent, index::MOI.VariableIndex, stage::Integer)
    stage == 1 || error("No scenario index specified.")
    return MOI.is_valid(backend(structure.model), index)
end
function MOI.is_valid(structure::DeterministicEquivalent, index::MOI.VariableIndex, stage::Integer, scenario_index::Integer)
    stage > 1 || error("There are no scenarios in the first stage.")
    n = num_scenarios(structure, stage)
    1 <= scenario_index <= n || error("Scenario index $scenario_index not in range 1 to $n.")
    mapped_vi = mapped_index(structure, index, scenario_index)
    return MOI.is_valid(backend(structure.model), mapped_vi)
end
function MOI.is_valid(structure::DeterministicEquivalent, ci::MOI.ConstraintIndex{F,S}, stage::Integer) where {F, S}
    stage == 1 || error("No scenario index specified.")
    return MOI.is_valid(backend(structure.model), ci)
end
function MOI.is_valid(structure::DeterministicEquivalent, ci::MOI.ConstraintIndex{F,S}, stage::Integer, scenario_index::Integer) where {F, S}
    stage > 1 || error("There are no scenarios in the first stage.")
    n = num_scenarios(structure, stage)
    1 <= scenario_index <= n || error("Scenario index $scenario_index not in range 1 to $n.")
    mapped_ci = mapped_index(structure, ci, scenario_index)
    return MOI.is_valid(backend(structure.model), mapped_ci)
end
function MOI.delete(structure::DeterministicEquivalent, indices::Vector{MOI.VariableIndex}, stage::Integer)
    stage == 1 || error("No scenario index specified.")
    JuMP.delete(structure.model, DecisionRef.(structure.model, indices))
    return nothing
end
function MOI.delete(structure::DeterministicEquivalent{N}, indices::Vector{MOI.VariableIndex}, stage::Integer, scenario_index::Integer) where N
    1 <= stage <= N || error("Stage $stage not in range 1 to $N.")
    stage > 1 || error("There are no scenarios in the first stage.")
    n = num_scenarios(structure, stage)
    1 <= scenario_index <= n || error("Scenario index $scenario_index not in range 1 to $n.")
    mapped_indices = map(indices) do index
        return mapped_index(structure, index, scenario_index)
    end
    JuMP.delete(structure.model, DecisionRef.(structure.model, mapped_indices))
    return nothing
end
function MOI.delete(structure::DeterministicEquivalent, ci::MOI.ConstraintIndex, stage::Integer)
    stage == 1 || error("No scenario index specified.")
    MOI.delete(backend(structure.model), ci)
    return nothing
end
function MOI.delete(structure::DeterministicEquivalent, cis::Vector{<:MOI.ConstraintIndex}, stage::Integer)
    stage == 1 || error("No scenario index specified.")
    MOI.delete(backend(structure.model), cis)
    return nothing
end
function MOI.delete(structure::DeterministicEquivalent{N}, ci::MOI.ConstraintIndex, stage::Integer, scenario_index::Integer) where N
    1 <= stage <= N || error("Stage $stage not in range 1 to $N.")
    stage > 1 || error("There are no scenarios in the first stage.")
    n = num_scenarios(structure, stage)
    1 <= scenario_index <= n || error("Scenario index $scenario_index not in range 1 to $n.")
    mapped_ci = mapped_index(structure, ci, scenario_index)
    MOI.delete(backend(structure.model), mapped_ci)
    return nothing
end
function MOI.delete(structure::DeterministicEquivalent{N}, cis::Vector{<:MOI.ConstraintIndex}, stage::Integer, scenario_index::Integer) where N
    1 <= stage <= N || error("Stage $stage not in range 1 to $N.")
    stage > 1 || error("There are no scenarios in the first stage.")
    n = num_scenarios(structure, stage)
    1 <= scenario_index <= n || error("Scenario index $scenario_index not in range 1 to $n.")
    mapped_cis = map(cis) do ci
        return mapped_index(structure, ci, scenario_index)
    end
    MOI.delete(backend(structure.model), mapped_cis)
    return nothing
end

# JuMP #
# ========================== #
function decision_dispatch(decision_function::Function,
                           structure::DeterministicEquivalent{N},
                           index::MOI.VariableIndex,
                           stage::Integer,
                           args...) where N
    1 <= stage <= N || error("Stage $stage not in range 1 to $N.")
    stage == 1 || error("No scenario index specified.")
    dref = DecisionRef(structure.model, index)
    return decision_function(dref, args...)
end
function scenario_decision_dispatch(decision_function::Function,
                                    structure::DeterministicEquivalent{N},
                                    index::MOI.VariableIndex,
                                    stage::Integer,
                                    scenario_index::Integer,
                                    args...) where N
    1 <= stage <= N || error("Stage $stage not in range 1 to $N.")
    stage > 1 || error("There are no scenarios in the first stage.")
    n = num_scenarios(structure, stage)
    1 <= scenario_index <= n || error("Scenario index $scenario_index not in range 1 to $n.")
    mapped_vi = mapped_index(structure, index, scenario_index)
    dref = DecisionRef(structure.model, mapped_vi)
    return decision_function(dref, args...)
end
function decision_dispatch!(decision_function!::Function,
                            structure::DeterministicEquivalent{N},
                            index::MOI.VariableIndex,
                            stage::Integer,
                            args...) where N
    1 <= stage <= N || error("Stage $stage not in range 1 to $N.")
    stage == 1 || error("No scenario index specified.")
    dref = DecisionRef(structure.model, index)
    decision_function!(dref, args...)
    return nothing
end
function scenario_decision_dispatch!(decision_function!::Function,
                                     structure::DeterministicEquivalent{N},
                                     index::MOI.VariableIndex,
                                     stage::Integer,
                                     scenario_index::Integer,
                                     args...) where N
    1 <= stage <= N || error("Stage $stage not in range 1 to $N.")
    stage > 1 || error("There are no scenarios in the first stage.")
    n = num_scenarios(structure, stage)
    1 <= scenario_index <= n || error("Scenario index $scenario_index not in range 1 to $n.")
    mapped_vi = mapped_index(structure, index, scenario_index)
    dref = DecisionRef(structure.model, mapped_vi)
    decision_function!(dref, args...)
    return nothing
end

function JuMP.fix(structure::DeterministicEquivalent{N}, index::MOI.VariableIndex, stage::Integer, val::Number) where N
    dref = DecisionRef(structure.model, index)
    fix(dref, val)
    return nothing
end
function JuMP.fix(structure::DeterministicEquivalent{N}, index::MOI.VariableIndex, stage::Integer, scenario_index::Integer, val::Number) where N
    1 <= stage <= N || error("Stage $stage not in range 1 to $N.")
    n = num_scenarios(structure, stage)
    1 <= scenario_index <= n || error("Scenario index $scenario_index not in range 1 to $n.")
    # Fix mapped decision
    mapped_vi = mapped_index(structure, index, scenario_index)
    dref = DecisionRef(structure.model, mapped_vi)
    fix(dref, val)
    return nothing
end
function JuMP.unfix(structure::DeterministicEquivalent{N}, index::MOI.VariableIndex, stage::Integer) where N
    dref = DecisionRef(structure.model, index)
    unfix(dref)
    return nothing
end
function JuMP.unfix(structure::DeterministicEquivalent{N}, index::MOI.VariableIndex, stage::Integer, scenario_index::Integer) where N
    1 <= stage <= N || error("Stage $stage not in range 1 to $N.")
    n = num_scenarios(structure, stage)
    1 <= scenario_index <= n || error("Scenario index $scenario_index not in range 1 to $n.")
    # Unfix mapped decision
    mapped_vi = mapped_index(structure, index, scenario_index)
    dref = DecisionRef(structure.model, mapped_vi)
    unfix(dref)
    return nothing
end

function JuMP.set_objective_sense(structure::DeterministicEquivalent, stage::Integer, sense::MOI.OptimizationSense)
    if stage == 1
        # Changing the first-stage sense modifies the whole objective as usual
        MOI.set(structure, MOI.ObjectiveSense(), sense)
    else
        # Every sub-objective in the given stage should be changed
        for scenario_index in 1:num_scenarios(structure, stage)
            attr = ScenarioDependentModelAttribute(stage, scenario_index, MOI.ObjectiveSense())
            MOI.set(structure, attr, sense)
        end
    end
    return nothing
end

function JuMP.objective_function_type(structure::DeterministicEquivalent)
    return jump_function_type(structure.model,
                              MOI.get(structure, MOI.ObjectiveFunctionType()))
end
function JuMP.objective_function_type(structure::DeterministicEquivalent{N}, stage::Integer, scenario_index::Integer) where N
    1 <= stage <= N || error("Stage $stage not in range 1 to $N.")
    stage > 1 || error("There are no scenarios in the first stage.")
    n = num_scenarios(structure, stage)
    1 <= scenario_index <= n || error("Scenario index $scenario_index not in range 1 to $n.")
    attr = ScenarioDependentModelAttribute(stage, scenario_index, MOI.ObjectiveFunctionType())
    return jump_function_type(structure.model,
                              MOI.get(structure, attr))
end

function JuMP.objective_function(structure::DeterministicEquivalent, FunType::Type{<:AbstractJuMPScalar})
    MOIFunType = moi_function_type(FunType)
    func = MOI.get(structure,
                   MOI.ObjectiveFunction{MOIFunType}())::MOIFunType
    return JuMP.jump_function(structure, 1, func)
end
function JuMP.objective_function(structure::DeterministicEquivalent{N}, stage::Integer, FunType::Type{<:AbstractJuMPScalar}) where N
    if stage == 1
        (sense, obj::FunType) = get_stage_objective(structure.model, 1, Val{N}())
        return obj
    else
        return objective_function(structure.proxy, FunType)
    end
end
function JuMP.objective_function(structure::DeterministicEquivalent{N},
                                 stage::Integer,
                                 scenario_index::Integer,
                                 FunType::Type{<:AbstractJuMPScalar}) where N
    1 <= stage <= N || error("Stage $stage not in range 1 to $N.")
    stage > 1 || error("There are no scenarios in the first stage.")
    n = num_scenarios(structure, stage)
    1 <= scenario_index <= n || error("Scenario index $scenario_index not in range 1 to $n.")
    MOIFunType = moi_function_type(FunType)
    attr = ScenarioDependentModelAttribute(stage, scenario_index, MOI.ObjectiveFunction{MOIFunType}())
    func = MOI.get(structure, attr)::MOIFunType
    return JuMP.jump_function(structure, stage, scenario_index, func)
end

function JuMP._moi_optimizer_index(structure::DeterministicEquivalent, index::VI)
    return decision_index(backend(structure.model), index)
end
function JuMP._moi_optimizer_index(structure::DeterministicEquivalent, index::VI, scenario_index::Integer)
    mapped_vi = mapped_index(structure, index, scenario_index)
    return decision_index(backend(structure.model), mapped_vi)
end
function JuMP._moi_optimizer_index(structure::DeterministicEquivalent, ci::CI)
    return decision_index(backend(structure.model), ci)
end
function JuMP._moi_optimizer_index(structure::DeterministicEquivalent, ci::CI{F,S}) where {F <: SingleDecision, S}
    inner = mapped_constraint(structure.decisions, ci)
    inner.value == 0 && error("Constraint $ci not properly mapped.")
    return decision_index(backend(structure.model), inner)
end
function JuMP._moi_optimizer_index(structure::DeterministicEquivalent, ci::CI, scenario_index::Integer)
    mapped_ci = mapped_index(structure, ci, scenario_index)
    return decision_index(backend(structure.model), mapped_ci)
end
function JuMP._moi_optimizer_index(structure::DeterministicEquivalent, ci::CI{F,S}, scenario_index::Integer) where {F <: SingleDecision, S}
    mapped_vi = mapped_index(structure, MOI.VariableIndex(ci.value), scenario_index)
    mapped_ci = CI{F,S}(mapped_vi.value)
    inner = mapped_constraint(structure.decisions, mapped_ci)
    inner.value == 0 && error("Constraint $mapped_ci not properly mapped.")
    return decision_index(backend(structure.model), inner)
end

function JuMP.set_objective_coefficient(structure::DeterministicEquivalent{N}, index::VI, var_stage::Integer, stage::Integer, coeff::Real) where N
    1 <= stage <= N || error("Stage $stage not in range 1 to $N.")
    var_stage <= stage || error("Can only modify coefficient in current stage of decision or subsequent stages from where decision is taken.")
    if var_stage == 1 && stage == 1
        # Use temporary model to apply modification
        obj = get_stage_objective(structure.model, 1, Val{N}())[2]
        moi_obj = moi_function(obj)
        m = Model()
        MOI.set(backend(m), MOI.ObjectiveFunction{typeof(moi_obj)}(), moi_obj)
        dref = DecisionRef(m, index)
        set_objective_coefficient(m, dref, coeff)
        obj = objective_function(m)
        F = moi_function_type(typeof(obj))
        # Modify full objective
        MOI.set(structure, MOI.ObjectiveFunction{F}(), moi_function(obj))
    elseif (var_stage == 1 && stage > 1) || var_stage > 1
        for scenario_index in 1:num_scenarios(structure, stage)
            # Use temporary model to apply modification
            obj = get_stage_objective(structure.model, stage, scenario_index, Val{N}())[2]
            moi_obj = moi_function(obj)
            m = Model()
            MOI.set(backend(m), MOI.ObjectiveFunction{typeof(moi_obj)}(), moi_obj)
            dref = DecisionRef(m, index)
            set_objective_coefficient(m, dref, coeff)
            obj = objective_function(m)
            attr = ScenarioDependentModelAttribute(stage, scenario_index, MOI.ObjectiveFunction{typeof(obj)}())
            MOI.set(structure, attr, obj)
        end
    end
    return nothing
end
function JuMP.set_objective_coefficient(structure::DeterministicEquivalent{N}, index::VI, var_stage::Integer, stage::Integer, scenario_index::Integer, coeff::Real) where N
    1 <= stage <= N || error("Stage $stage not in range 1 to $N.")
    stage > 1 || error("There are no scenarios in the first stage.")
    n = num_scenarios(structure, stage)
    1 <= scenario_index <= n || error("Scenario index $scenario_index not in range 1 to $n.")
    if var_stage == 1
        # Use temporary model to apply modification
        obj = get_stage_objective(structure.model, stage, scenario_index, Val{N}())[2]
        moi_obj = moi_function(obj)
        m = Model()
        MOI.set(backend(m), MOI.ObjectiveFunction{typeof(moi_obj)}(), moi_obj)
        dref = DecisionRef(m, index)
        set_objective_coefficient(m, dref, coeff)
        obj = objective_function(m)
        F = moi_function_type(typeof(obj))
        attr = ScenarioDependentModelAttribute(stage, scenario_index, MOI.ObjectiveFunction{F}())
        MOI.set(structure, attr, moi_function(obj))
    else
        # Use temporary model to apply modification
        sense, obj = get_stage_objective(structure.model, stage, scenario_index, Val{N}())
        moi_obj = moi_function(obj)
        m = Model()
        MOI.set(backend(m), MOI.ObjectiveFunction{typeof(moi_obj)}(), moi_obj)
        mapped_vi = mapped_index(structure, index, scenario_index)
        dref = DecisionRef(m, mapped_vi)
        set_objective_coefficient(m, dref, coeff)
        obj = objective_function(m)
        set_stage_objective!(structure.decisions, stage, scenario_index, sense, moi_function(obj))
        # Set coefficient of mapped second-stage variable
        dref = DecisionRef(structure.model, mapped_vi)
        set_objective_coefficient(structure.model, dref, probability(structure, stage, scenario_index) * coeff)
    end
    return nothing
end

function JuMP.set_normalized_coefficient(structure::DeterministicEquivalent,
                                         ci::CI{F,S},
                                         index::VI,
                                         value) where {T, F <: Union{AffineDecisionFunction{T}, QuadraticDecisionFunction{T}}, S}
    MOI.modify(backend(structure.model), ci,
               DecisionCoefficientChange(index, convert(T, value)))
    return nothing
end
function JuMP.set_normalized_coefficient(structure::DeterministicEquivalent{N},
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
    mapped_vi = if var_stage == 1
        mapped_vi = index
    else
        mapped_vi = mapped_index(structure, index, scenario_index)
    end
    mapped_ci = mapped_index(structure, ci, scenario_index)
    MOI.modify(backend(structure.model), mapped_ci,
               DecisionCoefficientChange(mapped_vi, convert(T, value)))
    return nothing
end

function JuMP.normalized_coefficient(structure::DeterministicEquivalent{N},
                                     ci::CI{F,S},
                                     index::VI,
                                     var_stage::Integer,
                                     stage::Integer,
                                     scenario_index::Integer) where {N, T, F <: Union{AffineDecisionFunction{T}, QuadraticDecisionFunction{T}}, S}
    1 <= stage <= N || error("Stage $stage not in range 1 to $N.")
    stage > 1 || error("There are no scenarios in the first stage.")
    n = num_scenarios(structure, stage)
    1 <= scenario_index <= n || error("Scenario index $scenario_index not in range 1 to $n.")
    mapped_ci = mapped_index(structure, ci, scenario_index)
    f = MOI.get(structure, MOI.ConstraintFunction(), mapped_ci)::F
    dref = if var_stage == 1
        dref = DecisionRef(structure.model, index)
    else
        mapped_vi = mapped_index(structure, index, scenario_index)
        dref = DecisionRef(structure.model, mapped_vi)
    end
    return JuMP._affine_coefficient(jump_function(structure.model, f), dref)
end

function JuMP.set_normalized_rhs(structure::DeterministicEquivalent,
                                 ci::CI{F,S},
                                 value) where {T,
                                               F <: Union{AffineDecisionFunction{T}, QuadraticDecisionFunction{T}},
                                               S <: MOIU.ScalarLinearSet{T}}
    MOI.set(backend(structure.model), MOI.ConstraintSet(), ci,
            S(convert(T, value)))
    return nothing
end
function JuMP.set_normalized_rhs(structure::DeterministicEquivalent{N},
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
    mapped_ci = mapped_index(structure, ci, scenario_index)
    MOI.set(backend(structure.model), MOI.ConstraintSet(), mapped_ci,
            S(convert(T, value)))
    return nothing
end

function DecisionRef(structure::DeterministicEquivalent, index::VI)
    return DecisionRef(structure.model, index)
end
function DecisionRef(structure::DeterministicEquivalent, index::VI, stage::Integer, scenario_index::Integer)
    mapped_vi = mapped_index(structure, index, scenario_index)
    return DecisionRef(structure.model, mapped_vi)
end
function DecisionRef(structure::DeterministicEquivalent{N}, index::VI, at_stage::Integer, stage::Integer, scenario_index::Integer) where N
    1 <= stage <= N || error("Stage $stage not in range 1 to $N.")
    at_stage > 1 || error("There are no scenarios in the first stage.")
    n = num_scenarios(structure, at_stage)
    1 <= scenario_index <= n || error("Scenario index $scenario_index not in range 1 to $n.")
    return DecisionRef(structure.model, index)
end

function JuMP.jump_function(structure::DeterministicEquivalent{N},
                            stage::Integer,
                            f::MOI.AbstractFunction) where N
    1 <= stage <= N || error("Stage $stage not in range 1 to $N.")
    if stage == 1
        return JuMP.jump_function(structure.model, f)
    else
        return JuMP.jump_function(structure.proxy[stage], f)
    end
end
function JuMP.jump_function(structure::DeterministicEquivalent{N},
                            stage::Integer,
                            scenario_index::Integer,
                            f::MOI.AbstractFunction) where N
    1 <= stage <= N || error("Stage $stage not in range 1 to $N.")
    return JuMP.jump_function(structure.model, f)
end

function JuMP.relax_integrality(structure::DeterministicEquivalent)
    unrelax = relax_decision_integrality(structure.model)
    return unrelax
end

# Getters #
# ========================== #
function structure_name(structure::DeterministicEquivalent)
    return "Deterministic equivalent"
end
function scenario_types(structure::DeterministicEquivalent{N}) where N
    return ntuple(Val{N-1}()) do i
        eltype(structure.scenarios[i])
    end
end
function proxy(structure::DeterministicEquivalent{N}, stage::Integer) where N
    1 <= stage <= N || error("Stage $stage not in range 1 to $N.")
    return structure.proxy[stage]
end
function decision(structure::DeterministicEquivalent{N}, index::MOI.VariableIndex, stage::Integer) where N
    stage == 1 || error("No scenario index specified.")
    return decision(structure.decisions, stage, index)
end
function decision(structure::DeterministicEquivalent{N}, index::MOI.VariableIndex, stage::Integer, scenario_index::Integer) where N
    stage > 1 || error("There are no scenarios in the first stage.")
    n = num_scenarios(structure, stage)
    1 <= scenario_index <= n || error("Scenario index $scenario_index not in range 1 to $n.")
    mapped_vi = mapped_index(structure, index, scenario_index)
    return decision(structure.decisions, stage, mapped_vi)
end
function scenario(structure::DeterministicEquivalent{N}, stage::Integer, scenario_index::Integer) where N
    return structure.scenarios[stage-1][scenario_index]
end
function scenarios(structure::DeterministicEquivalent{N}, stage::Integer) where N
    return structure.scenarios[stage-1]
end
function subproblem(structure::DeterministicEquivalent, stage::Integer, scenario_index::Integer)
    error("The determinstic equivalent is not decomposed into subproblems.")
end
function subproblems(structure::DeterministicEquivalent, stage::Integer)
    error("The determinstic equivalent is not decomposed into subproblems.")
end
function num_subproblems(structure::DeterministicEquivalent, stage::Integer)
    return 0
end
function deferred(structure::DeterministicEquivalent)
    return num_variables(structure.model) == 0
end
# ========================== #

# Setters
# ========================== #
function update_known_decisions!(structure::DeterministicEquivalent)
    update_known_decisions!(structure.model)
    return nothing
end
function update_known_decisions!(structure::DeterministicEquivalent, stage::Integer, scenario_index::Integer)
    stage > 1 || error("There are no scenarios in the first stage.")
    n = num_scenarios(structure, stage)
    1 <= scenario_index <= n || error("Scenario index $scenario_index not in range 1 to $n.")
    update_known_decisions!(structure.model)
    return nothing
end

function add_scenario!(structure::DeterministicEquivalent, stage::Integer, scenario::AbstractScenario)
    push!(scenarios(structure, stage), scenario)
    return nothing
end
function add_worker_scenario!(structure::DeterministicEquivalent, stage::Integer, scenario::AbstractScenario, w::Integer)
    add_scenario!(structure, scenario, stage)
    return nothing
end
function add_scenario!(scenariogenerator::Function, structure::DeterministicEquivalent, stage::Integer)
    add_scenario!(structure, stage, scenariogenerator())
    return nothing
end
function add_worker_scenario!(scenariogenerator::Function, structure::DeterministicEquivalent, stage::Integer, w::Integer)
    add_scenario!(scenariogenerator, structure, stage)
    return nothing
end
function add_scenarios!(structure::DeterministicEquivalent, stage::Integer, _scenarios::Vector{<:AbstractScenario})
    append!(scenarios(structure, stage), _scenarios)
    return nothing
end
function add_worker_scenarios!(structure::DeterministicEquivalent, stage::Integer, scenarios::Vector{<:AbstractScenario}, w::Integer)
    add_scenarios!(structure, scenarios, stasge)
    return nothing
end
function add_scenarios!(scenariogenerator::Function, structure::DeterministicEquivalent, stage::Integer, n::Integer)
    for i = 1:n
        add_scenario!(structure, stage) do
            return scenariogenerator()
        end
    end
    return nothing
end
function add_worker_scenarios!(scenariogenerator::Function, structure::DeterministicEquivalent, stage::Integer, n::Integer, w::Integer)
    add_scenarios!(scenariogenerator, structure, n, stage)
    return nothing
end
function sample!(structure::DeterministicEquivalent, stage::Integer, sampler::AbstractSampler, n::Integer)
    sample!(scenarios(structure, stage), sampler, n)
    return nothing
end
# ========================== #

# Indices
# ========================== #
function mapped_index(structure::DeterministicEquivalent{2}, index::MOI.VariableIndex, scenario_index::Integer)
    # The initial number of first-stage decisions is always given by
    num_first_stage_decisions = MOI.get(structure.proxy[1], MOI.NumberOfConstraints{MOI.SingleVariable,SingleDecisionSet{Float64}}())
    # Calculate offset from first-stage auxilliary variables (first-stage decisions are included in second-stage proxy, so deduct them)
    first_stage_offset = MOI.get(structure.proxy[1], MOI.NumberOfVariables()) - num_first_stage_decisions
    # Calculate offset from extra counts of first-stage decisions from second-stage proxy
    first_stage_decision_offset = -(scenario_index - 1) * num_first_stage_decisions
    # Calculate offset from second-stage variables
    scenario_offset = (scenario_index - 1) * MOI.get(structure.proxy[2], MOI.NumberOfVariables())
    return MOI.VariableIndex(index.value + first_stage_offset + first_stage_decision_offset + scenario_offset)
end
function mapped_index(structure::DeterministicEquivalent{2}, ci::CI{F,S}, scenario_index::Integer) where {F,S}
    first_stage_offset = MOI.get(structure.proxy[1], MOI.NumberOfConstraints{F,S}())
    scenario_offset = (scenario_index - 1) * MOI.get(structure.proxy[2], MOI.NumberOfConstraints{F,S}())
    return CI{F,S}(ci.value + first_stage_offset + scenario_offset)
end
