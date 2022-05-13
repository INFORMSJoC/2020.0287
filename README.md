[![INFORMS Journal on Computing Logo](https://INFORMSJoC.github.io/logos/INFORMS_Journal_on_Computing_Header.jpg)](https://pubsonline.informs.org/journal/ijoc)

# StochasticPrograms

This archive is distributed in association with the [INFORMS Journal on
Computing](https://pubsonline.informs.org/journal/ijoc) under the
[MIT license](LICENSE.md).

The software, StochasticPrograms.jl, and data in this repository are associated with the paper
[Efficient Stochastic Programming in Julia](https://doi.org/10.1287/ijoc.2022.1158)
by M. Biel and M. Johansson.

This repository is a snapshot of the project, taken on 2021-07-01 from
[https://github.com/martinbiel/StochasticPrograms.jl](https://github.com/martinbiel/StochasticPrograms.jl) at commit
[`4bacecfc812b602fd338af22c1441e6ef481d722`](https://github.com/martinbiel/StochasticPrograms.jl/commit/4bacecfc812b602fd338af22c1441e6ef481d722),
and is provided for historical interest.

Readers are directed to [https://github.com/martinbiel/StochasticPrograms.jl](https://github.com/martinbiel/StochasticPrograms.jl)
for the actively developed project repository, and to
[https://martinbiel.github.io/StochasticPrograms.jl/latest/](https://martinbiel.github.io/StochasticPrograms.jl/latest/)
for the latest documentation.

## Cite

To cite this software, please cite the [paper]() using its DOI
and the software itself, using the following DOI.

[![DOI](https://zenodo.org/badge/319404787.svg)](https://zenodo.org/badge/latestdoi/319404787)

Below is the BibTex for citing this version of the code.

```
@article{stochasticprograms2021,
  author    = {Martin Biel and Mikael Johansson},
  title     = {StochasticPrograms.jl}, 
  publisher = {INFORMS Journal on Computing},
  year      = {2021},
  doi       = {10.5281/zenodo.5595111},
  url       = {https://github.com/INFORMSJoC/2020.0287},
}
```
## Description

StochasticPrograms.jl is a general purpose modeling framework for stochastic programming written in the Julia programming language. The framework includes both modeling tools and structure-exploiting optimization algorithms. Stochastic programming models can be efficiently formulated using expressive syntax and models can be instantiated, inspected, and analyzed interactively. The framework scales seamlessly to distributed environments. Small instances of a model can be run locally to ensure correctness, while larger instances are automatically distributed in a memory-efficient way onto supercomputers or clouds and solved using parallel optimization algorithms. These structure-exploiting solvers are based on variations of the classical L-shaped, progressive-hedging, and quasi-gradient algorithms.

## Installation

In Julia, the latest version of the framework can be installed as follows:
```julia
pkg> add StochasticPrograms
```
Afterwards, the functionality can be made available in a module or REPL through:
```julia
using StochasticPrograms
```

## Replicating

The code listings included in the paper are provided as separate Julia files in the `scripts` folder. To run the example in the paper, first install any 1.X version of Julia (e.g., 1.0 or 1.6) from [julialang.org](https://julialang.org/downloads). The provided `install.sh` script can be used to download the latest version of Julia (1.6.0) and then load `install.jl` which installs the StochasticPrograms.jl package as well as any other Julia packages necessary to run the examples. Alternatively, the `scripts` folder includes a `Manifest.toml` file that can be used to load a Julia environment that can run the examples. The benchmark code as well as data files for the large-scale SSN problem considered in the numerical experiments are included as well in the `scripts` folder. The experiments were run on a 32-core machine. To run the experiments in another setup, the `benchmark.jl` must be configured accordingly. A license is required to use Gurobi as a subproblem solver. Free third-party solvers can be used instead, but performance will be affected.

## A simple stochastic program

To showcase the use of StochasticPrograms we will walk through a simple example. The reader is otherwise referred to the [documentation](https://martinbiel.github.io/StochasticPrograms.jl/latest/) for a complete introduction of the software framework. We consider how to model, analyze, and solve a stochastic program using StochasticPrograms. In many examples, a `MathOptInterface` solver is required. Hence, we load the GLPK solver:
```julia
using GLPK
```
We also load Ipopt to solve quadratic problems:
```julia
using Ipopt
```

### Stochastic model definition

First, we define a stochastic model that describes a simple stochastic program:
```julia
@stochastic_model simple_model begin
    @stage 1 begin
        @decision(simple_model, x₁ >= 40)
        @decision(simple_model, x₂ >= 20)
        @objective(simple_model, Min, 100*x₁ + 150*x₂)
        @constraint(simple_model, x₁ + x₂ <= 120)
    end
    @stage 2 begin
        @uncertain q₁ q₂ d₁ d₂
        @recourse(simple_model, 0 <= y₁ <= d₁)
        @recourse(simple_model, 0 <= y₂ <= d₂)
        @objective(simple_model, Max, q₁*y₁ + q₂*y₂)
        @constraint(simple_model, 6*y₁ + 10*y₂ <= 60*x₁)
        @constraint(simple_model, 8*y₁ + 5*y₂ <= 80*x₂)
    end
end
```
The optimization models in the first and second stage are defined using JuMP syntax inside `@stage` blocks. Every first-stage variable is annotated with `@decision`. This allows us to use the variable in the second stage. The `@uncertain` annotation specifies that the variables `q₁`, `q₂`, `d₁` and `d₂` are uncertain. Instances of the uncertain variables will later be injected to create instances of the second stage model. We will consider two stochastic models of the uncertainty and showcase the main functionality of the framework for each.

### Instantiation

First, we create two instances of the random variable. For simple models this is conveniently achieved through the `Scenario` type, created as follows:
```julia
ξ₁ = @scenario q₁ = 24.0 q₂ = 28.0 d₁ = 500.0 d₂ = 100.0 probability = 0.4
```
and
```julia
ξ₂ = @scenario q₁ = 28.0 q₂ = 32.0 d₁ = 300.0 d₂ = 300.0 probability = 0.6
```
where the variable names should match those given in the `@uncertain` annotation. We are now ready to instantiate the stochastic program introduced above.
```julia
sp = instantiate(simple_model, [ξ₁, ξ₂], optimizer = GLPK.Optimizer)
```
```julia
Stochastic program with:
 * 2 decision variables
 * 2 recourse variables
 * 2 scenarios of type Scenario
Structure: Deterministic equivalent
Solver name: GLPK
```
We can now print and inspect the full stochastic program:
```julia
print(sp)
```
```julia
Deterministic equivalent problem
Min 100 x₁ + 150 x₂ - 9.600000000000001 y₁₁ - 11.200000000000001 y₂₁ - 16.8 y₁₂ - 19.2 y₂₂
Subject to
 x₁ ∈ Decisions
 x₂ ∈ Decisions
 y₁₁ ∈ RecourseDecisions
 y₂₁ ∈ RecourseDecisions
 y₁₂ ∈ RecourseDecisions
 y₂₂ ∈ RecourseDecisions
 x₁ ≥ 40.0
 x₂ ≥ 20.0
 y₁₁ ≥ 0.0
 y₂₁ ≥ 0.0
 y₁₂ ≥ 0.0
 y₂₂ ≥ 0.0
 x₁ + x₂ ≤ 120.0
 -60 x₁ + 6 y₁₁ + 10 y₂₁ ≤ 0.0
 -80 x₂ + 8 y₁₁ + 5 y₂₁ ≤ 0.0
 -60 x₁ + 6 y₁₂ + 10 y₂₂ ≤ 0.0
 -80 x₂ + 8 y₁₂ + 5 y₂₂ ≤ 0.0
 y₁₁ ≤ 500.0
 y₂₁ ≤ 100.0
 y₁₂ ≤ 300.0
 y₂₂ ≤ 300.0
Solver name: GLPK
```

### Optimization

The most common operation is to solve the instantiated stochastic program for an optimal first-stage decision. We instantiated the problem with the `GLPK` optimizer, so we can solve the problem directly:
```julia
optimize!(sp)
```
We can then query the resulting optimal value:
```julia
objective_value(sp)
```
```julia
-855.8333333333321
```
and the optimal first-stage decision:
```julia
optimal_decision(sp)
```
```julia
2-element Vector{Float64}:
 46.66666666666667
 36.25
```
Alternatively, we can solve the problem with a structure-exploiting solver. The framework provides both `LShaped` and `ProgressiveHedging` solvers. We first re-instantiate the problem using an L-shaped optimizer:
```julia
sp_lshaped = instantiate(simple_model, [ξ₁, ξ₂], optimizer = LShaped.Optimizer)
```
```julia
Stochastic program with:
 * 2 decision variables
 * 2 recourse variables
 * 2 scenarios of type Scenario
Structure: Stage-decomposition
Solver name: L-shaped with disaggregate cuts
```
It should be noted that the memory representation of the stochastic program is now different. Because we instantiated the model with an L-shaped optimizer it generated the program according to a stage-decomposition structure:
```julia
print(sp_lshaped)
```
```julia
First-stage
==============
Min 100 x₁ + 150 x₂
Subject to
 x₁ ∈ Decisions
 x₂ ∈ Decisions
 x₁ ≥ 40.0
 x₂ ≥ 20.0
 x₁ + x₂ ≤ 120.0

Second-stage
==============
Subproblem 1 (p = 0.40):
Max 24 y₁ + 28 y₂
Subject to
 x₁ ∈ Known(value = 40.0)
 x₂ ∈ Known(value = 20.0)
 y₁ ∈ RecourseDecisions
 y₂ ∈ RecourseDecisions
 y₁ ≥ 0.0
 y₂ ≥ 0.0
 y₁ ≤ 500.0
 y₂ ≤ 100.0
 -60 x₁ + 6 y₁ + 10 y₂ ≤ 0.0
 -80 x₂ + 8 y₁ + 5 y₂ ≤ 0.0

Subproblem 2 (p = 0.60):
Max 28 y₁ + 32 y₂
Subject to
 x₁ ∈ Known(value = 40.0)
 x₂ ∈ Known(value = 20.0)
 y₁ ∈ RecourseDecisions
 y₂ ∈ RecourseDecisions
 y₁ ≥ 0.0
 y₂ ≥ 0.0
 y₁ ≤ 300.0
 y₂ ≤ 300.0
 -60 x₁ + 6 y₁ + 10 y₂ ≤ 0.0
 -80 x₂ + 8 y₁ + 5 y₂ ≤ 0.0

Solver name: L-shaped with disaggregate cuts
```
To solve the problem with L-shaped, we must first specify internal optimizers that can solve emerging subproblems:
```julia
set_optimizer_attribute(sp_lshaped, MasterOptimizer(), GLPK.Optimizer)
set_optimizer_attribute(sp_lshaped, SubProblemOptimizer(), GLPK.Optimizer)
```
We can now run the optimization procedure:
```julia
optimize!(sp_lshaped)
```
```julia
L-Shaped Gap  Time: 0:00:01 (6 iterations)
  Objective:       -855.8333333333339
  Gap:             0.0
  Number of cuts:  7
  Iterations:      6
```
and verify that we get the same results:
```julia
objective_value(sp_lshaped)
```
```julia
-855.8333333333339
```
and
```julia
optimal_decision(sp_lshaped)
```
```julia
2-element Array{Float64,1}:
 46.66666666666673
 36.25000000000003
```
Likewise, we can solve the problem with progressive-hedging. Consider:
```julia
sp_progressivehedging = instantiate(simple_model, [ξ₁, ξ₂], optimizer = ProgressiveHedging.Optimizer)
```
```julia
Stochastic program with:
 * 2 decision variables
 * 2 recourse variables
 * 2 scenarios of type Scenario
Structure: Scenario-decomposition
Solver name: Progressive-hedging with fixed penalty
```
Now, the induced structure is the scenario-decomposition that decomposes the stochastic program completely into subproblems over the scenarios. Consider the printout:
```julia
print(sp_progressivehedging)
```
```julia
Scenario problems
==============
Subproblem 1 (p = 0.40):
Min 100 x₁ + 150 x₂ - 24 y₁ - 28 y₂
Subject to
 y₁ ≥ 0.0
 y₂ ≥ 0.0
 y₁ ≤ 500.0
 y₂ ≤ 100.0
 x₁ ∈ Decisions
 x₂ ∈ Decisions
 x₁ ≥ 40.0
 x₂ ≥ 20.0
 x₁ + x₂ ≤ 120.0
 -60 x₁ + 6 y₁ + 10 y₂ ≤ 0.0
 -80 x₂ + 8 y₁ + 5 y₂ ≤ 0.0

Subproblem 2 (p = 0.60):
Min 100 x₁ + 150 x₂ - 28 y₁ - 32 y₂
Subject to
 y₁ ≥ 0.0
 y₂ ≥ 0.0
 y₁ ≤ 300.0
 y₂ ≤ 300.0
 x₁ ∈ Decisions
 x₂ ∈ Decisions
 x₁ ≥ 40.0
 x₂ ≥ 20.0
 x₁ + x₂ ≤ 120.0
 -60 x₁ + 6 y₁ + 10 y₂ ≤ 0.0
 -80 x₂ + 8 y₁ + 5 y₂ ≤ 0.0

Solver name: Progressive-hedging with fixed penalty
```
To solve the problem with progressive-hedging, we must also specify an internal optimizers that can solve the subproblems:
```julia
set_optimizer_attribute(sp_progressivehedging, SubProblemOptimizer(), Ipopt.Optimizer)
set_suboptimizer_attribute(sp_progressivehedging, MOI.RawParameter("print_level"), 0) # Silence Ipopt
```
We can now run the optimization procedure:
```julia
optimize!(sp_progressivehedging)
```
```julia
Progressive Hedging Time: 0:00:07 (303 iterations)
  Objective:   -855.5842547490254
  Primal gap:  7.2622997706326046e-6
  Dual gap:    8.749063651111478e-6
  Iterations:  302
```
and verify that we get the same results:
```julia
objective_value(sp_progressivehedging)
```
```julia
-855.5842547490254
```
and
```julia
optimal_decision(sp_progressivehedging)
```
```julia
2-element Array{Float64,1}:
 46.65459574079722
 36.24298005619633
```

### Decision evaluation

Consider the following first-stage decision:
```julia
x = [40., 20.]
```
The expected result of taking this decision in the simple finite model can be determined through:
```julia
evaluate_decision(sp, x)
```
```julia
-470.39999999999964
```
Decision evaluation is supported by the other storage structures as well:
```julia
evaluate_decision(sp_lshaped, x)
```
```julia
-470.39999999999964
```
and
```julia
evaluate_decision(sp_progressivehedging, x)
```
```julia
-470.40000522896185
```

### Stochastic performance

Apart from solving the stochastic program, we can compute two classical measures of stochastic performance. The first measures the value of knowing the random outcome before making the decision. This is achieved by taking the expectation in the original model outside the minimization, to obtain the wait-and-see problem. Now, the first- and second-stage decisions are taken with knowledge about the uncertainty. If we assume that we know what the actual outcome will be, we would be interested in the optimal course of action in that scenario. This is the concept of wait-and-see models. For example if the first scenario is believed to be the actual outcome, we can define a wait-and-see model as follows:
```julia
ws = WS(sp, ξ₁)
print(ws)
```
```julia
Min 100 x₁ + 150 x₂ - 24 y₁ - 28 y₂
Subject to
 x₁ ∈ Decisions
 x₂ ∈ Decisions
 y₁ ∈ RecourseDecisions
 y₂ ∈ RecourseDecisions
 x₁ ≥ 40.0
 x₂ ≥ 20.0
 y₁ ≥ 0.0
 y₂ ≥ 0.0
 x₁ + x₂ ≤ 120.0
 -60 x₁ + 6 y₁ + 10 y₂ ≤ 0.0
 -80 x₂ + 8 y₁ + 5 y₂ ≤ 0.0
 y₁ ≤ 500.0
 y₂ ≤ 100.0
```
The optimal first-stage decision in this scenario can be determined through:
```julia
x₁ = wait_and_see_decision(sp, ξ₁)
```
```julia
2-element Vector{Float64}:
 40.0
 29.583333333333336
```
We can then evaluate this decision:
```julia
evaluate_decision(sp, x₁)
```
```julia
-762.5000000000014
```
The difference between the expected wait-and-see value and the value of the recourse problem is known as the **expected value of perfect information** (EVPI). The EVPI measures the expected loss of not knowing the exact outcome beforehand. It quantifies the value of having access to an accurate forecast. We calculate it in the framework through:
```julia
EVPI(sp)
```
```julia
662.9166666666679
```
EVPI is supported in the other structures as well:
```julia
EVPI(sp_lshaped)
```
```julia
662.9166666666661
```
and
```julia
EVPI(sp_progressivehedging)
```
```julia
663.165763660815
```

If the expectation in the original model is instead taken inside the second-stage objective function ``Q``, we obtain the expected-value-problem. The solution to the expected-value-problem is known as the **expected value decision**. We can compute it through
```julia
x̄ = expected_value_decision(sp)
```
```julia
2-element Vector{Float64}:
 71.45833333333334
 48.54166666666667
```
The expected result of taking the expected value decision is known as the **expected result of the expected value decision** (EEV). The difference between the value of the recourse problem and the expected result of the expected value decision is known as the **value of the stochastic solution** (VSS). The VSS measures the expected loss of ignoring the uncertainty in the problem. A large VSS indicates that the second stage is sensitive to the stochastic data. We calculate it using
```julia
VSS(sp)
```
```julia
286.91666666666515
```
VSS is supported in the other structures as well:
```julia
VSS(sp_lshaped)
```
```julia
286.91666666666606
```
and
```julia
VSS(sp_progressivehedging)
```
```julia
286.6675823650668
```
