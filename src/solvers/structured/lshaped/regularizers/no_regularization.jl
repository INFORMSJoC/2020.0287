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

# No regularization
# ------------------------------------------------------------
"""
    NoRegularization

Empty functor object for running an L-shaped algorithm without regularization.

"""
struct NoRegularization <: AbstractRegularization end

function initialize_regularization!(::AbstractLShaped, ::NoRegularization)
    return nothing
end

function restore_regularized_master!(::AbstractLShaped, ::NoRegularization)
    return nothing
end

function filter_variables!(::NoRegularization, ::Any)
    return nothing
end

function filter_constraints!(::NoRegularization, ::Any)
    return nothing
end

function log_regularization!(::AbstractLShaped, ::NoRegularization)
    return nothing
end

function log_regularization!(::AbstractLShaped, ::Integer, ::NoRegularization)
    return nothing
end

function take_step!(::AbstractLShaped, ::NoRegularization)
    return nothing
end

function decision(lshaped::AbstractLShaped, ::NoRegularization)
    return lshaped.x
end

function objective_value(lshaped::AbstractLShaped, ::NoRegularization)
    return lshaped.data.Q
end

function gap(lshaped::AbstractLShaped, ::NoRegularization)
    @unpack Q,θ = lshaped.data
    return abs(θ-Q)/(abs(Q)+1e-10)
end

# API
# ------------------------------------------------------------
"""
    DontRegularize

Factory object for [`NoRegularization`](@ref). Passed by default to `regularize` in `LShaped.Optimizer`.

"""
struct DontRegularize <: AbstractRegularizer end

function (::DontRegularize)(::DecisionMap, ::AbstractVector)
    return NoRegularization()
end

function str(::DontRegularize)
    return "L-shaped"
end
