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

@with_kw mutable struct LShapedData{T <: AbstractFloat}
    Q::T = 1e10
    θ::T = -1e10
    master_objective::AffineDecisionFunction{T} = zero(AffineDecisionFunction{T})
    no_objective::Bool = false
    num_cuts::Int = 0
    iterations::Int = 1
    consolidations::Int = 0
end

@with_kw mutable struct LShapedParameters{T <: AbstractFloat}
    τ::T = 1e-6
    cut_scaling::T = 1.0
    debug::Bool = false
    time_limit::T = Inf
    log::Bool = true
    keep::Bool = true
    offset::Int = 0
    indent::Int = 0
end

"""
    LShapedAlgorithm

Functor object for the L-shaped algorithm.

...
# Algorithm parameters
- `τ::AbstractFloat = 1e-6`: Relative tolerance for convergence checks.
- `debug::Bool = false`: Specifies if extra information should be saved for debugging purposes. Defaults to false for memory efficiency.
- `cut_scaling::AbstractFloat = 1.0`: Rescaling factor for cutting planes to improve numerical stability.
- `log::Bool = true`: Specifices if L-shaped procedure should be logged on standard output or not.
...
"""
struct LShapedAlgorithm{T <: AbstractFloat,
                        A <: AbstractVector,
                        ST <: StageDecompositionStructure,
                        M <: MOI.AbstractOptimizer,
                        E <: AbstractLShapedExecution,
                        F <: AbstractFeasibilityAlgorithm,
                        I <: AbstractIntegerAlgorithm,
                        R <: AbstractRegularization,
                        Agg <: AbstractAggregation,
                        C <: AbstractConsolidation} <: AbstractLShaped
    structure::ST
    num_subproblems::Int
    data::LShapedData{T}
    parameters::LShapedParameters{T}

    # Master
    master::M
    decisions::DecisionMap
    x::A
    Q_history::A

    # Execution
    execution::E

    # Feasibility
    feasibility::F

    # Integers
    integer::I

    # Regularization
    regularization::R

    # Cuts
    master_variables::Vector{MOI.VariableIndex}
    cut_constraints::Vector{CutConstraint}
    cuts::Vector{AnySparseOptimalityCut{T}}
    aggregation::Agg
    consolidation::C
    θ_history::A

    progress::ProgressThresh{T}

    function LShapedAlgorithm(structure::StageDecompositionStructure,
                              x₀::AbstractVector,
                              feasibility_strategy::AbstractFeasibilityStrategy,
                              integer_strategy::AbstractIntegerStrategy,
                              _execution::AbstractExecution,
                              regularizer::AbstractRegularizer,
                              aggregator::AbstractAggregator,
                              consolidator::AbstractConsolidator; kw...)
        # Sanity checks
        length(x₀) != num_decisions(structure, 1) && error("Incorrect length of starting guess, has ", length(x₀), " should be ", num_decisions(structure, 1))
        n = num_subproblems(structure, 2)
        n == 0 && error("No subproblems in stochastic program. Cannot run L-shaped procedure.")
        # Float types
        T = promote_type(eltype(x₀), Float32)
        x₀_ = convert(AbstractVector{T}, copy(x₀))
        A = typeof(x₀_)
        # Structure
        ST = typeof(structure)
        M = typeof(backend(structure.first_stage))
        # Feasibility
        feasibility_algorithm = master(feasibility_strategy, T)
        F = typeof(feasibility_algorithm)
        # Integers
        integer_algorithm = master(integer_strategy, T)
        I = typeof(integer_algorithm)
        # Execution policy
        execution = _execution(structure, feasibility_strategy, integer_strategy, T, A)
        E = typeof(execution)
        # Regularization policy
        regularization = regularizer(structure.decisions[1], x₀_)
        R = typeof(regularization)
        # Aggregation policy
        aggregation = aggregator(n, T)
        Agg = typeof(aggregation)
        # Consolidation policy
        consolidation = consolidator(T)
        C = typeof(consolidation)
        # Algorithm parameters
        params = LShapedParameters{T}(; kw...)

        lshaped = new{T,A,ST,M,E,F,I,R,Agg,C}(structure,
                                              n,
                                              LShapedData{T}(),
                                              params,
                                              backend(structure.first_stage),
                                              structure.decisions[1],
                                              x₀_,
                                              A(),
                                              execution,
                                              feasibility_algorithm,
                                              integer_algorithm,
                                              regularization,
                                              Vector{MOI.VariableIndex}(),
                                              Vector{CutConstraint}(),
                                              Vector{SparseOptimalityCut{T}}(),
                                              aggregation,
                                              consolidation,
                                              A(),
                                              ProgressThresh(T(1.0), 0.0, "$(indentstr(params.indent))L-Shaped Gap "))
        # Initialize solver
        initialize!(lshaped)
        return lshaped
    end
end

function show(io::IO, lshaped::LShapedAlgorithm)
    println(io, typeof(lshaped).name.name)
    println(io, "State:")
    show(io, lshaped.data)
    println(io, "Parameters:")
    show(io, lshaped.parameters)
end

function show(io::IO, ::MIME"text/plain", lshaped::LShapedAlgorithm)
    show(io, lshaped)
end

function (lshaped::LShapedAlgorithm)()
    # Reset timer
    lshaped.progress.tinit = lshaped.progress.tlast = time()
    # Start workers (if any)
    start_workers!(lshaped)
    # Start procedure
    while true
        status = iterate!(lshaped)
        if status !== nothing
            close_workers!(lshaped)
            return status
        end
    end
end
