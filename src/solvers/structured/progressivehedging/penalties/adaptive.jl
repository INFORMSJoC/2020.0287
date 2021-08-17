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

# AdaptivePenalization penalty
# ------------------------------------------------------------
@with_kw mutable struct AdaptiveData{T <: AbstractFloat}
    r::T = 1.0
end

@with_kw mutable struct AdaptiveParameters{T <: AbstractFloat}
    ζ::T = 0.1
    γ₁::T = 1e-5
    γ₂::T = 0.01
    γ₃::T = 0.25
    σ::T = 1e-5
    α::T = 0.95
    θ::T = 1.1
    ν::T = 0.1
    β::T = 1.1
    η::T = 1.25
end

"""
    AdaptivePenalization

Functor object for using adaptive penalty in a progressive-hedging algorithm. Create by supplying an [`Adaptive`](@ref) object through `penalty` in the `ProgressiveHedgingSolver` factory function and then pass to a `StochasticPrograms.jl` model.

...
# Parameters
- `ζ::T = 0.1`: Used to calculate the initial penalty. Non-anticipativity in the initial decision is enforced more as ζ increase.
- `γ₁::T = 1e-5`: Tolerance for primal changes being significant
- `γ₂::T = 0.01`: Tolerance for primal changes dominating dual changes
- `γ₃::T = 0.25`: Tolerance for dual changes dominating primal changes
- `σ::T = 1e-5`: Tolerance for the quadratic penalty dominating the Lagrangian
- `α::T = 0.95`: Penalty decrease after primal changes dominating dual changes
- `θ::T = 1.1`: Penalty increase after dual changes dominating primal changes
- `ν::T = 0.1`: Tolerance for significant non-anticipativity violation
- `β::T = 1.1`: Penalty increase after increased non-anticipativity violation
- `η::T = 1.25`: Default penalty increase in the default case
...
"""
struct AdaptivePenalization{T <: AbstractFloat} <: AbstractPenalization
    data::AdaptiveData{T}
    parameters::AdaptiveParameters{T}

    function AdaptivePenalization(r::AbstractFloat; kw...)
        T = typeof(r)
        return new{T}(AdaptiveData{T}(; r = r), AdaptiveParameters{T}(;kw...))
    end
end
function penalty(::AbstractProgressiveHedging, penalty::AdaptivePenalization)
    return penalty.data.r
end
function initialize_penalty!(ph::AbstractProgressiveHedging, penalty::AdaptivePenalization)
    update_dual_gap!(ph)
    @unpack δ₂ = ph.data
    @unpack ζ = penalty.parameters
    penalty.data.r = max(1., 2 * ζ *abs(calculate_objective_value(ph)))/max(1., δ₂)
end
function update_penalty!(ph::AbstractProgressiveHedging, penalty::AdaptivePenalization)
    @unpack δ₁, δ₂ = ph.data
    @unpack r = penalty.data
    @unpack γ₁, γ₂, γ₃, σ, α, θ, ν, β, η = penalty.parameters

    δ₂_prev = length(ph.dual_gaps) > 0 ? ph.dual_gaps[end] : Inf

    μ = if δ₁/norm(ph.ξ,2)^2 >= γ₁
        if (δ₁-δ₂)/(1e-10 + δ₂) > γ₂
            α
        elseif (δ₂-δ₁)/(1e-10 + δ₁) > γ₃
            θ
        else
            1.
        end
    elseif δ₂ > δ₂_prev
        if (δ₂-δ₂_prev)/δ₂_prev > ν
            β
        else
            1.
        end
    else
        η
    end
    penalty.data.r = μ*r
end

# API
# ------------------------------------------------------------
"""
    Adaptive

Factory object for [`AdaptivePenalization`](@ref). Pass to `penalty` in the `ProgressiveHedgingSolver` factory function. See ?AdaptivePenalization for parameter descriptions.

"""
struct Adaptive{T <: AbstractFloat} <: AbstractPenalizer
    r::T
    parameters::Dict{Symbol,Any}

    function Adaptive(r::AbstractFloat; kw...)
        T = typeof(r)
        return new{T}(r, Dict{Symbol,Any}(kw))
    end
end
Adaptive(; kw...) = Adaptive(1.0; kw...)

function (adaptive::Adaptive)()
    return AdaptivePenalization(adaptive.r; adaptive.parameters...)
end

function str(::Adaptive)
    return "adaptive penalty"
end
