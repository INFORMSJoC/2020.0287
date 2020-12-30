"""
    SMPSScenario

Conveniece type that adheres to the [`AbstractScenario`](@ref) abstraction. Obtained when reading scenarios specified in SMPS format.

See also: [`SMPSSampler`](@ref)
"""
struct SMPSScenario{T <: AbstractFloat, M <: AbstractMatrix} <: AbstractScenario
    probability::Probability
    Δq::Vector{T}
    ΔT::M
    ΔW::M
    Δh::Vector{T}
    ΔC::M
    Δd₁::Vector{T}
    Δd₂::Vector{T}
end

function Base.zero(::Type{SMPSScenario{T}}) where T <: AbstractFloat
    return SMPSScenario(Probability(1.0),
                        AdditiveZeroArray{T,1}(),
                        AdditiveZeroArray{T,2}(),
                        AdditiveZeroArray{T,2}(),
                        AdditiveZeroArray{T,1}(),
                        AdditiveZeroArray{T,2}(),
                        AdditiveZeroArray{T,1}(),
                        AdditiveZeroArray{T,1}())
end

function StochasticPrograms.expected(scenarios::Vector{<:SMPSScenario{T}}) where T <: AbstractFloat
    isempty(scenarios) && return zero(SMPSScenario{T})
    expected = reduce(scenarios) do ξ₁, ξ₂
        SMPSScenario(Probability(1.0),
                     probability(ξ₁) * ξ₁.Δq + probability(ξ₂) * ξ₂.Δq,
                     probability(ξ₁) * ξ₁.ΔT + probability(ξ₂) * ξ₂.ΔT,
                     probability(ξ₁) * ξ₁.ΔW + probability(ξ₂) * ξ₂.ΔW,
                     probability(ξ₁) * ξ₁.Δh + probability(ξ₂) * ξ₂.Δh,
                     probability(ξ₁) * ξ₁.ΔC + probability(ξ₂) * ξ₂.ΔC,
                     probability(ξ₁) * ξ₁.Δd₁ + probability(ξ₂) * ξ₂.Δd₁,
                     probability(ξ₁) * ξ₁.Δd₂ + probability(ξ₂) * ξ₂.Δd₂)
    end
    return StochasticPrograms.ExpectedScenario(expected)
end

function StochasticPrograms.scenariotext(io::IO, scenario::SMPSScenario)
    print(io, " and underlying data:\n\n")
    println(io, "Δq = $(scenario.Δq)")
    println(io, "ΔT = $(scenario.ΔT)")
    println(io, "ΔW = $(scenario.ΔW)")
    println(io, "Δh = $(scenario.Δh)")
    println(io, "ΔC = $(scenario.ΔC)")
    println(io, "Δd₁ = $(scenario.Δd₁)")
    print(io, "Δd₂ = $(scenario.Δd₂)")
    return io
end
