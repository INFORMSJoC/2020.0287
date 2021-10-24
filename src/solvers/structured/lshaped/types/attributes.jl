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

# Attributes #
# ========================== #
"""
    AbstractLShapedAttribute

Abstract supertype for attribute objects specific to the L-shaped algorithm.
"""
abstract type AbstractLShapedAttribute <: AbstractStructuredOptimizerAttribute end
"""
    FeasibilityStrategy

An optimizer attribute for specifying a strategy for dealing with second-stage feasibility the L-shaped algorithm. Options are:

- [`IgnoreFeasibility`](@ref) (default)
- [`FeasibilityCuts`](@ref)
"""
struct FeasibilityStrategy <: AbstractLShapedAttribute end
"""
    IntegerStrategy

An optimizer attribute for specifying a strategy for dealing with integers the L-shaped algorithm. Options are:

- [`IgnoreIntegers`](@ref) (default)
- [`CombinatorialCuts`](@ref)
- [`Convexification`](@ref)
"""
struct IntegerStrategy <: AbstractLShapedAttribute end
"""
    Regularizer

An optimizer attribute for specifying a regularization procedure to be used in the L-shaped algorithm. Options are:

- [`NoRegularization`](@ref):  L-shaped algorithm (default)
- [`RegularizedDecomposition`](@ref):  Regularized decomposition ?RegularizedDecomposition for parameter descriptions.
- [`TrustRegion`](@ref):  Trust-region ?TrustRegion for parameter descriptions.
- [`LevelSet`](@ref):  Level-set ?LevelSet for parameter descriptions.
"""
struct Regularizer <: AbstractLShapedAttribute end
"""
    Aggregator

An optimizer attribute for specifying an aggregation procedure to be used in the L-shaped algorithm. Options are:

- [`NoAggregation`](@ref):  Multi-cut L-shaped algorithm (default)
- [`PartialAggregation`](@ref):  ?PartialAggregation for parameter descriptions.
- [`FullAggregation`](@ref):  ?FullAggregation for parameter descriptions.
- [`DynamicAggregation`](@ref):  ?DynamicAggregation for parameter descriptions.
- [`ClusterAggregation`](@ref):  ?ClusterAggregation for parameter descriptions.
- [`HybridAggregation`](@ref):  ?HybridAggregation for parameter descriptions.
"""
struct Aggregator <: AbstractLShapedAttribute end
"""
    Consolidator

An optimizer attribute for specifying a consolidation procedure to be used in the L-shaped algorithm. Options are:

- [`NoConsolidation`](@ref) (default)
- [`Consolidation`](@ref)
"""
struct Consolidator <: AbstractLShapedAttribute end
"""
    IntegerParameter

Abstract supertype for integer-specific attributes.
"""
abstract type IntegerParameter <: AbstractLShapedAttribute end
"""
    RegularizationParameter

Abstract supertype for regularization-specific attributes.
"""
abstract type RegularizationParameter <: AbstractLShapedAttribute end
"""
    AggregationParameter

Abstract supertype for aggregation-specific attributes.
"""
abstract type AggregationParameter <: AbstractLShapedAttribute end
"""
    ConsolidationParameter

Abstract supertype for consolidation-specific attributes.
"""
abstract type ConsolidationParameter <: AbstractLShapedAttribute end
