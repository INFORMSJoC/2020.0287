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

# Affine decision function #
# ========================== #
struct AffineDecisionObjectiveBridge{T} <: MOIB.Objective.AbstractBridge
    decision_function::AffineDecisionFunction{T}
end

function MOIB.Objective.bridge_objective(::Type{AffineDecisionObjectiveBridge{T}}, model::MOI.ModelLike,
                                         f::AffineDecisionFunction{T}) where T
    # All decisions have been mapped to the variable part terms
    # at this point.
    F = MOI.ScalarAffineFunction{T}
    # Set the bridged objective
    MOI.set(model, MOI.ObjectiveFunction{F}(), MOI.ScalarAffineFunction(f.variable_part.terms, zero(T)))
    # Save decision function to allow modifications
    return AffineDecisionObjectiveBridge{T}(f)
end

function MOIB.Objective.supports_objective_function(
    ::Type{<:AffineDecisionObjectiveBridge}, ::Type{<:AffineDecisionFunction})
    return true
end
MOIB.added_constrained_variable_types(::Type{<:AffineDecisionObjectiveBridge}) = Tuple{DataType}[]
function MOIB.added_constraint_types(::Type{<:AffineDecisionObjectiveBridge})
    return Tuple{DataType, DataType}[]
end
function MOIB.set_objective_function_type(::Type{AffineDecisionObjectiveBridge{T}}) where T
    return MOI.ScalarAffineFunction{T}
end

function MOI.get(::AffineDecisionObjectiveBridge, ::MOI.NumberOfVariables)
    return 0
end

function MOI.get(::AffineDecisionObjectiveBridge, ::MOI.ListOfVariableIndices)
    return MOI.VariableIndex[]
end


function MOI.delete(::MOI.ModelLike, ::AffineDecisionObjectiveBridge)
    # Nothing to delete
    return nothing
end

function MOI.set(::MOI.ModelLike, ::MOI.ObjectiveSense,
                 ::AffineDecisionObjectiveBridge, ::MOI.OptimizationSense)
    # Nothing to handle if sense changes
    return nothing
end

function MOI.get(model::MOI.ModelLike,
                 attr::MOIB.ObjectiveFunctionValue{F},
                 bridge::AffineDecisionObjectiveBridge{T}) where {T, F <: AffineDecisionFunction{T}}
    f = bridge.decision_function
    G = MOI.ScalarAffineFunction{T}
    obj_val = MOI.get(model, MOIB.ObjectiveFunctionValue{G}(attr.result_index))
    # Calculate and add constant
    return obj_val + f.variable_part.constant
end

function MOI.get(model::MOI.ModelLike, attr::MOI.ObjectiveFunction{F},
                 bridge::AffineDecisionObjectiveBridge{T}) where {T, F <: AffineDecisionFunction{T}}
    return bridge.decision_function
end

function MOI.modify(model::MOI.ModelLike, bridge::AffineDecisionObjectiveBridge{T}, change::MOI.ScalarConstantChange) where T
    f = bridge.decision_function
    # Modify constant of variable part
    f.variable_part.constant = change.new_constant
    return nothing
end

function MOI.modify(model::MOI.ModelLike, bridge::AffineDecisionObjectiveBridge{T}, change::MOI.ScalarCoefficientChange) where T
    f = bridge.decision_function
    # Modify variable part of decision function
    modify_coefficient!(f.variable_part.terms, change.variable, change.new_coefficient)
    # Modify the variable part of the mapped objective as well
    F = MOI.ScalarAffineFunction{T}
    MOI.modify(model, MOI.ObjectiveFunction{F}(), change)
    return nothing
end
