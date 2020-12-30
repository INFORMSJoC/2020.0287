using StochasticPrograms
using JuMP
using GLPK
using Distributed
using Distributions
using LinearAlgebra
using Logging
using Test

import StochasticPrograms: probability, expected

include("decisions/decisions.jl")
TestDecisionVariable.runtests()
TestDecisionConstraint.runtests()
TestDecisionObjective.runtests()
TestSolve.runtests()
include("problems/problem_load.jl")
include("functional_tests.jl")
include("solver_tests.jl")
include("distributed/distributed_tests.jl")
