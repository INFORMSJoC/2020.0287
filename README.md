[![INFORMS Journal on Computing Logo](https://INFORMSJoC.github.io/logos/INFORMS_Journal_on_Computing_Header.jpg)](https://pubsonline.informs.org/journal/ijoc)

# StochasticPrograms

This archive is distributed in association with the [INFORMS Journal on
Computing](https://pubsonline.informs.org/journal/ijoc) under the
[MIT license](LICENSE.md).

The software, StochasticPrograms.jl, and data in this repository are associated with the paper
[Efficient Stochastic Programming in Julia]()
by M. Biel and M. Johansson.

This repository is a snapshot of the project, taken on 2021-07-01 from
[https://github.com/martinbiel/StochasticPrograms.jl](https://github.com/martinbiel/StochasticPrograms.jl) at commit
[`302400e4de2708d5fba50fedeb134c33f128b808`](https://github.com/martinbiel/StochasticPrograms.jl/commit/302400e4de2708d5fba50fedeb134c33f128b808),
and is provided for historical interest.

Readers are directed to [https://github.com/martinbiel/StochasticPrograms.jl](https://github.com/martinbiel/StochasticPrograms.jl)
for the actively developed project repository, and to
[https://martinbiel.github.io/StochasticPrograms.jl/latest/](https://martinbiel.github.io/StochasticPrograms.jl/latest/)
for the latest documentation.

## Cite

To cite this software, please cite the [paper]() using its DOI
and the software itself, using the following DOI.

<!-- [![DOI](https://zenodo.org/badge/290669197.svg)](https://zenodo.org/badge/latestdoi/290669197) -->

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

The code listings included in the paper are provided as separate Julia files in the `scripts` folder. To run the example in the paper, first install any 1.X version of Julia (e.g., 1.0 or 1.6) from [julialang.org](https://julialang.org/downloads). The provided `install.sh` script can be used to download the latest version of Julia (1.6.0) and then load `install.jl` which installs the StochasticPrograms.jl package as well as any other Julia packages necessary to run the examples. The benchmark code as well as data files for the large-scale SSN problem considered in the numerical experiments are included as well in the `scripts` folder. The experiments were run on a 32-core machine. To run the experiments in another setup, the `benchmark.jl` must be configured accordingly. A license is required to use Gurobi as a subproblem solver. Free third-party solvers can be used instead, but performance will be affected.

## A simple stochastic program

To showcase the use of StochasticPrograms we will walk through a simple example. The reader is otherwise referred to the [documentation](https://martinbiel.github.io/StochasticPrograms.jl/latest/) for a complete introduction of the software framework. Consider the following stochastic program: (taken from [Introduction to Stochastic Programming](https://link.springer.com/book/10.1007%2F978-1-4614-0237-4)).

```math
\begin{aligned}
 \operatorname*{minimize}_{x_1, x_2 \in \mathbb{R}} & \quad 100x_1 + 150x_2 + \operatorname{\mathbb{E}}_{\omega} \left[Q(x_1,x_2,\xi(\omega))\right] \\
 \text{s.t.} & \quad x_1+x_2 \leq 120 \\
 & \quad x_1 \geq 40 \\
 & \quad x_2 \geq 20
\end{aligned}
```
where
```math
\begin{aligned}
 Q(x_1,x_2,\xi(\omega)) = \min_{y_1,y_2 \in \mathbb{R}} & \quad q_1(\omega)y_1 + q_2(\omega)y_2 \\
 \text{s.t.} & \quad 6y_1+10y_2 \leq 60x_1 \\
 & \quad 8y_1 + 5y_2 \leq 80x_2 \\
 & \quad 0 \leq y_1 \leq d_1(\omega) \\
 & \quad 0 \leq y_2 \leq d_2(\omega)
\end{aligned}
```
and the stochastic variable
```math
  \xi(\omega) = \begin{pmatrix}
     q_1(\omega) & q_2(\omega) & d_1(\omega) & d_2(\omega)
  \end{pmatrix}^T
```
parameterizes the second-stage model. In the following, we consider how to model, analyze, and solve this stochastic program using StochasticPrograms. In many examples, a `MathOptInterface` solver is required. Hence, we load the GLPK solver:
```julia
using GLPK
```
We also load Ipopt to solve quadratic problems:
```julia
using Ipopt
```

### Stochastic model definition

First, we define a stochastic model that describes the introduced stochastic program above.
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

### Finite sample space

First, let ``\xi`` be a discrete distribution, taking on the value
```math
  \xi_1 = \begin{pmatrix}
    24 & 28 & 500 & 100
  \end{pmatrix}^T
```
with probability ``0.4`` and
```math
  \xi_1 = \begin{pmatrix}
    28 & 32 & 300 & 300
  \end{pmatrix}^T
```
with probability ``0.6``.

#### Instantiation

First, we create the two instances ``\xi_1`` and ``\xi_2`` of the random variable. For simple models this is conveniently achieved through the `Scenario` type. ``\xi_1`` and ``\xi_2`` can be created as follows:
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
By default, the stochastic program is instantiated with a deterministic equivalent structure. It is straightforward to work out the extended form because the example problem is small:
```math
\begin{aligned}
 \operatorname*{minimize}_{x_1, x_2, y_{11}, y_{21}, y_{12}, y_{22} \in \mathbb{R}} & \quad 100x_1 + 150x_2 - 9.6y_{11} - 11.2y_{21} - 16.8y_{12} - 19.2y_{22}  \\
 \text{s.t.} & \quad x_1 + x_2 \leq 120 \\
 & \quad 6 y_{11} + 10 y_{21} \leq 60 x_1 \\
 & \quad 8 y_{11} + 5 y_{21} \leq 80 x_2 \\
 & \quad 6 y_{12} + 10 y_{22} \leq 60 x_1 \\
 & \quad 8 y_{12} + 5 y_{22} \leq 80 x_2 \\
 & \quad x_1 \geq 40 \\
 & \quad x_2 \geq 20 \\
 & \quad 0 \leq y_{11} \leq 500 \\
 & \quad 0 \leq y_{21} \leq 100 \\
 & \quad 0 \leq y_{12} \leq 300 \\
 & \quad 0 \leq y_{22} \leq 300
\end{aligned}
```
We can print the stochastic program and confirm that it indeed models the example recourse problem given above:
```julia
print(sp)
```

#### Optimization

The most common operation is to solve the instantiated stochastic program for an optimal first-stage decision. We instantiated the problem with the `GLPK` optimizer, so we can solve the problem directly:
```julia
optimize!(sp)
```
We can then query the resulting optimal value:
```julia
objective_value(sp)
```
and the optimal first-stage decision:
```julia
optimal_decision(sp)
```
Alternatively, we can solve the problem with a structure-exploiting solver. The framework provides both `LShaped` and `ProgressiveHedging` solvers. We first re-instantiate the problem using an L-shaped optimizer:
```julia
sp_lshaped = instantiate(simple_model, [ξ₁, ξ₂], optimizer = LShaped.Optimizer)
```
It should be noted that the memory representation of the stochastic program is now different. Because we instantiated the model with an L-shaped optimizer it generated the program according to a stage-decomposition structure:
```julia
print(sp_lshaped)
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
and
```julia
-855.8333333333339
```
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

#### Decision evaluation

Decision evaluation is an important concept in stochastic programming. The expected result of taking a given first-stage decision ``x`` is given by
```math
V(x) = c^T x + \operatorname{\mathbb{E}}_{\omega} \left[Q(x,\xi(\omega))\right]
```
If the sample space is finite, the above expressions has a closed form that is readily calculated. Consider the following first-stage decision:
```julia
x = [40., 20.]
```
The expected result of taking this decision in the simple finite model can be determined through:
```julia
evaluate_decision(sp, x)
```
Internally, this fixes all occurances of the first-stage variables in the deterministic equivalent and solves the resulting problem. An equivalent approach is to fix the decisions manually:
```julia
another_sp = instantiate(simple_model, [ξ₁, ξ₂], optimizer = GLPK.Optimizer)
fix.(all_decision_variables(another_sp, 1), x)
optimize!(another_sp)
objective_value(another_sp)
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
In a stage-decomposition structure, the occurances of first-stage decisions in the second-stage subproblems are treated as known decisions with parameter values that can be set. We can explicitly create such a subproblem to clearly see this in action:
```julia
print(outcome_model(sp, x, ξ₁))
```
Moreover, we can evaluate the result of the decision in a given scenario, i.e. solving a single outcome model, through:
```julia
evaluate_decision(sp, x, ξ₁)
```

#### Stochastic performance

Apart from solving the stochastic program, we can compute two classical measures of stochastic performance. The first measures the value of knowing the random outcome before making the decision. This is achieved by taking the expectation in the original model outside the minimization, to obtain the wait-and-see problem:
```math
\mathrm{EWS} = \operatorname{\mathbb{E}}_{\omega}\left[
  \begin{aligned}
    \min_{x \in \mathbb{R}^n} & \quad c^T x + Q(x,\xi(\omega)) \\
    \text{s.t.} & \quad Ax = b \\
    & \quad x \geq 0.
  \end{aligned}\right]
```
Now, the first- and second-stage decisions are taken with knowledge about the uncertainty. If we assume that we know what the actual outcome will be, we would be interested in the optimal course of action in that scenario. This is the concept of wait-and-see models. For example if ``ξ₁`` is believed to be the actual outcome, we can define a wait-and-see model as follows:
```julia
ws = WS(sp, ξ₁)
print(ws)
```
The optimal first-stage decision in this scenario can be determined through:
```julia
x₁ = wait_and_see_decision(sp, ξ₁)
```
We can evaluate this decision:
```julia
evaluate_decision(sp, x₁)
```
The outcome is of course worse than taking the optimal decision. However, it would perform better if ``ξ₁`` is the actual outcome:
```julia
evaluate_decision(sp, x₁, ξ₁)
```
as compared to:
```julia
evaluate_decision(sp, optimal_decision(sp), ξ₁)
```
The difference between the expected wait-and-see value and the value of the recourse problem is known as the **expected value of perfect information**:
```math
\mathrm{EVPI} = \mathrm{EWS} - \mathrm{VRP}.
```
The EVPI measures the expected loss of not knowing the exact outcome beforehand. It quantifies the value of having access to an accurate forecast. We calculate it in the framework through:
```julia
EVPI(sp)
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
We can also compute EWS directly using `EWS`. Note, that the scenario-decomposition structure is ideal for solving wait-and-see type problems.

If the expectation in the original model is instead taken inside the second-stage objective function ``Q``, we obtain the expected-value-problem:
```math
\begin{aligned}
    \operatorname*{minimize}_{x \in \mathbb{R}^n} & \quad c^T x + Q(x,\operatorname{\mathbb{E}}_{\omega}[\xi(\omega)]) \\
    \text{s.t.} & \quad Ax = b \\
    & \quad x \geq 0.
  \end{aligned}
```
The solution to the expected-value-problem is known as the **expected value decision**, and is denote by ``\bar{x}``. We can compute it through
```julia
x̄ = expected_value_decision(sp)
```
The expected result of taking the expected value decision is known as the **expected result of the expected value decision**:
```math
\mathrm{EEV} = c^T \bar{x} + \operatorname{\mathbb{E}}_{\xi}{Q(\bar{x},\xi(\omega))}.
```
The difference between the value of the recourse problem and the expected result of the expected value decision is known as the **value of the stochastic solution**:
```math
\mathrm{VSS} = \mathrm{EEV} - \mathrm{VRP}.
```
The VSS measures the expected loss of ignoring the uncertainty in the problem. A large VSS indicates that the second stage is sensitive to the stochastic data. We calculate it using
```julia
VSS(sp)
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
We can also compute EEV directly using `EEV`. Note, that the stage-decomposition structure is ideal for solving VSS type problems.

### Infinite sample space

In the above, the probability space consists of only two scenarios and the stochastic program can hence be represented in a closed form. If it instead holds that ``\xi`` follows say a normal distribution, then it is no longer possible to represent the full stochastic program since this would require infinite scenarios. We then revert to sampling-based techniques. For example, let ``\xi \sim \mathcal{N}(\mu, \Sigma)`` with
```math
\mu = \begin{pmatrix}
 24 \\
 32 \\
 400 \\
 200
\end{pmatrix}, \quad \Sigma = \begin{pmatrix}
 2 & 0.5 & 0 & 0 \\
 0.5 & 1 & 0 & 0 \\
 0 & 0 & 50 & 20 \\
 0 & 0 & 20 & 30
\end{pmatrix}
```

### Instantiation
To approximate the resulting stochastic program in StochasticPrograms, we first create a sampler object capable of generating scenarios from this distribution. This is most conveniently achieved using the `@sampler` macro:
```julia
using Distributions

@sampler SimpleSampler = begin
    N::MvNormal

    SimpleSampler(μ, Σ) = new(MvNormal(μ, Σ))

    @sample Scenario begin
        x = rand(sampler.N)
        return Scenario(q₁ = x[1], q₂ = x[2], d₁ = x[3], d₂ = x[4])
    end
end

μ = [24, 32, 400, 200]
Σ = [2 0.5 0 0
     0.5 1 0 0
     0 0 50 20
     0 0 20 30]

sampler = SimpleSampler(μ, Σ)
```
Now, we can use the same stochastic model created before and the created sampler object to generate a sampled approximation of the stochastic program. For now, we create a small sampled model of just 5 scenarios:
```julia
sampled_sp = instantiate(simple_model, sampler, 5, optimizer = GLPK.Optimizer)
```
An optimal solution to this sampled model approximates the optimal solution to the infinite model in the sense that the empirical average second-stage cost converges pointwise with probability one to the true optimal value as the number of sampled scenarios goes to infinity. Moreoever, we can apply a central limit theorem to calculate confidence intervals around the objective value, as well as around the EVPI and VSS. This is the basis for the technique known as sample average approximation. In the following, we show how we can achieve approximations of the finite sample space functionality. Note that most operations are now performed directly on the `simple_model` object together with a supplied sampler object.

#### Optimization

To approximately solve the stochastic program over normally distributed scenarios, we must first set a sample-based solver. The framework provides the `SAA` solver:
```julia
set_optimizer(simple_model, SAA.Optimizer)
```
We must first set an instance optimizer that can solve emerging sampled instances:
```julia
set_optimizer_attribute(simple_model, InstanceOptimizer(), GLPK.Optimizer)
```
Note, that we can use a structure-exploiting solver for the instance optimizer. We now set a desired confidence level and the number of samples:
```julia
set_optimizer_attribute(simple_model, Confidence(), 0.9)
set_optimizer_attribute(simple_model, NumSamples(), 100)
set_optimizer_attribute(simple_model, NumEvalSamples(), 300)
```
We can now calculate a confidence interval around the optimal value through:
```julia
confidence_interval(simple_model, sampler)
```
The optimization procedure provided by `SAA` iteratively calculates confidence intervals for growing sample sizes until a desired relative tolerance is reached:
```julia
set_optimizer_attribute(simple_model, RelativeTolerance(), 5e-2)
```
We can now optimize the model:
```julia
optimize!(simple_model, sampler)
```
```julia
SAA gap Time: 0:00:03 (4 iterations)
  Confidence interval:  Confidence interval (p = 95%): [-1095.65 − -1072.36]
  Relative error:       0.021487453807842415
  Sample size:          64
```
and query the result:
```julia
objective_value(simple_model);objective_value(simple_model);
```
```julia
objective_value(simple_model) = Confidence interval (p = 95%): [-1095.65 − -1072.36]
```
Note, that we can just replace the sampler object to use another model of the uncertainty.

#### Decision evaluation

If the sample space is infinite, or if the underlying random variable ``\xi`` is continuous, a first-stage decision also can only be evaluated in a stochastic sense. For example, note the result of evaluating the decision on the sampled model created above:
```julia
evaluate_decision(sampled_sp, x)
```
and compare it to the result of evaluating it on another sampled model of similar size:
```julia
another_sp = instantiate(simple_model, sampler, 5, optimizer = GLPK.Optimizer)
evaluate_decision(another_sp, x)
```
which, if any, of these values should be a candidate for the true value of ``V(x)``? A more precise result is obtained by evaluating the decision using a sampled-based approach:
```julia
evaluate_decision(simple_model, x, sampler)
```

#### Stochastic performance

Using the same techniques as above, we can calculate confidence intervals around the EVPI and VSS:
```julia
EVPI(simple_model, sampler)
```
```julia
Confidence interval (p = 99%): [32.96 − 144.51]
```
and
```julia
VSS(simple_model, sampler)
```
```julia
Warning: VSS is not statistically significant to the chosen confidence level and tolerance
Confidence interval (p = 95%): [-0.05 − 0.05]
```
Note, that the VSS is not statistically significant. This is not surprising for a normally distributed uncertainty model. The expected value decision is expected to perform well.
