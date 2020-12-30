# SingleDecision #
# ========================== #
const FixingConstraint{T} = CI{MOI.ScalarAffineFunction{T}, MOI.EqualTo{T}}
mutable struct SingleDecisionConstraintBridge{T, S <: MOI.AbstractScalarSet} <: MOIB.Constraint.AbstractBridge
    constraint::CI{MOI.SingleVariable, S}
    fixing_constraint::FixingConstraint{T}
    decision::SingleDecision
end

function MOIB.Constraint.bridge_constraint(::Type{SingleDecisionConstraintBridge{T,S}},
                                           model,
                                           f::SingleDecision,
                                           set::S) where {T, S <: MOI.AbstractScalarSet}
    # Perform the bridge mapping manually
    g = MOIB.bridged_variable_function(model, f.decision)
    mapped_variable = MOI.SingleVariable(only(g.terms).variable_index)
    # Add the bridged constraint
    constraint = MOI.add_constraint(model,
                                    mapped_variable,
                                    set)
    # Check state of decision
    fixing_constraint = if !iszero(g.constant)
        # Decision initially fixed
        fixing_constraint =
            MOI.add_constraint(model,
                               MOI.ScalarAffineFunction{T}([only(g.terms)], zero(T)),
                               MOI.EqualTo(g.constant))
    else
        fixing_constraint = FixingConstraint{T}(0)
    end
    # Save the constraint index and the decision to allow modifications
    return SingleDecisionConstraintBridge{T,S}(constraint, fixing_constraint, f)
end

function MOIB.Constraint.bridge_constraint(::Type{SingleDecisionConstraintBridge{T,FreeDecision}},
                                           model,
                                           f::SingleDecision,
                                           set::FreeDecision) where T
    # Do not need to add constraint, just save bridge handle fixing
    constraint = CI{MOI.SingleVariable, FreeDecision}(0)
    return SingleDecisionConstraintBridge{T,FreeDecision}(constraint, FixingConstraint{T}(0), f)
end

function MOI.supports_constraint(::Type{<:SingleDecisionConstraintBridge{T}},
                                 ::Type{SingleDecision},
                                 ::Type{<:MOI.AbstractScalarSet}) where T
    return true
end
function MOIB.added_constrained_variable_types(::Type{<:SingleDecisionConstraintBridge})
    return Tuple{DataType}[]
end
function MOIB.added_constraint_types(::Type{<:SingleDecisionConstraintBridge{T,S}}) where {T,S}
    return [(MOI.SingleVariable, S), (MOI.ScalarAffineFunction{T}, MOI.EqualTo{T})]
end
function MOIB.Constraint.concrete_bridge_type(::Type{<:SingleDecisionConstraintBridge{T}},
                              ::Type{SingleDecision},
                              S::Type{<:MOI.AbstractScalarSet}) where T
    return SingleDecisionConstraintBridge{T,S}
end

MOI.get(b::SingleDecisionConstraintBridge{T,S}, ::MOI.NumberOfConstraints{MOI.SingleVariable, S}) where {T,S} = 1
MOI.get(b::SingleDecisionConstraintBridge{T}, ::MOI.NumberOfConstraints{MOI.ScalarAffineFunction{T}, MOI.EqualTo{T}}) where T =
    b.fixing_constraint.value == 0 ? 0 : 1
MOI.get(b::SingleDecisionConstraintBridge{T}, ::MOI.ListOfConstraintIndices{MOI.SingleVariable, S}) where {T,S} = [b.constraint]
MOI.get(b::SingleDecisionConstraintBridge{T}, ::MOI.ListOfConstraintIndices{MOI.ScalarAffineFunction{T}, MOI.EqualTo{T}}) where {T} =
    b.fixing_constraint.value == 0 ? FixingConstraint{T}[] : [b.fixing_constraint]

function MOI.get(model::MOI.ModelLike, attr::MOI.AbstractConstraintAttribute,
                 bridge::SingleDecisionConstraintBridge)
    return MOI.get(model, attr, bridge.constraint)
end

function MOI.delete(model::MOI.ModelLike, bridge::SingleDecisionConstraintBridge)
    if bridge.constraint.value != 0
        MOI.delete(model, bridge.constraint)
    end
    return nothing
end

function MOI.set(model::MOI.ModelLike, ::MOI.ConstraintSet,
                 bridge::SingleDecisionConstraintBridge{T,S}, change::S) where {T, S <: MOI.AbstractScalarSet}
    MOI.set(model, MOI.ConstraintSet(), bridge.constraint, change)
    return nothing
end

function MOI.modify(model::MOI.ModelLike, bridge::SingleDecisionConstraintBridge{T,S}, change::DecisionStateChange) where {T,S}
    # Perform the bridge mapping manually
    if bridge.decision.decision != change.decision
        # Decision not in constraint, nothing to do
        return nothing
    end
    # Switch on state transition
    if change.new_state == NotTaken
        if bridge.fixing_constraint.value != 0
            # Remove the fixing constraint
            MOI.delete(model, bridge.fixing_constraint)
            bridge.fixing_constraint = FixingConstraint{T}(0)
        end
    end
    if change.new_state == Taken
        if bridge.fixing_constraint.value != 0
            # Remove any existing fixing constraint
            MOI.delete(model, bridge.fixing_constraint)
        end
        # Perform the bridge mapping manually
        aff = MOIB.bridged_variable_function(model, bridge.decision.decision)
        f = MOI.ScalarAffineFunction{T}([only(aff.terms)], zero(T))
        # Get the decision value
        set = MOI.EqualTo(aff.constant)
        # Add a fixing constraint to ensure that fixed decision is feasible.
        bridge.fixing_constraint = MOI.add_constraint(model, f, set)
    end
    return nothing
end
