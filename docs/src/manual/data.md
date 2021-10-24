# Stochastic data

Decoupling data design and model design is a fundamental principle in StochasticPrograms. This decoupling is achieved through data injection. By data we mean parameters in an optimization problem. In StochasticPrograms, this data is either deterministic and related to a specific stage, or uncertain and related to a specific scenario.

## Stage data

Stage data is related to parameters that always appear in the first or second stage of a stochastic program. These parameters are deterministic and are the same across all scenarios. Such parameters are conveniently included in stochastic models using [`@parameters`](@ref). To showcase, we consider a minimal stochastic program:
```math
\begin{aligned}
 \operatorname*{maximize}_{x \in \mathbb{R}} & \quad x + \operatorname{\mathbb{E}}_{\omega} \left[Q(x, \xi(\omega))\right] \\
 \text{s.t.} & \quad l_1 \leq x \leq u_1
\end{aligned}
```
where
```math
\begin{aligned}
 Q(x, \xi(\omega)) = \max_{y \in \mathbb{R}} & \quad q_{\omega} y \\
 \text{s.t.} & \quad y + x \leq U \\
 & \quad l_2 \leq y \leq u_2
\end{aligned}
```
and the stochastic variable
```math
  \xi(\omega) = q_{\omega}
```
takes on the value ``1`` or ``-1`` with equal probability. Here, the first stage contains the two parameters: ``l_1`` and ``u_1``. The second stage contains the three scenario-independent parameters: ``U``, ``l_2``, and ``u_2``. The following defines this problem in StochasticPrograms, with some chosen deault parameter values:
```@example parameters
using StochasticPrograms
using GLPK

sm = @stochastic_model begin
    @stage 1 begin
        @parameters begin
            l₁ = -1.
            u₁ = 1.
        end
        @decision(model, l₁ <= x <= u₁)
        @objective(model, Max, x)
    end
    @stage 2 begin
        @parameters begin
            U = 2.
            l₂ = -1.
            u₂ = 1.
        end
        @uncertain q
        @variable(model, l₂ <= y <= u₂)
        @objective(model, Max, q*y)
        @constraint(model, y + x <= U)
    end
end

ξ₁ = @scenario q = 1. probability = 0.5
ξ₂ = @scenario q = -1. probability = 0.5

sp = instantiate(sm, [ξ₁,ξ₂], optimizer = GLPK.Optimizer)

println(sp)

print("VRP = $(VRP(sp))")
```
Now, we can investigate the impact of the stage parameters by changing them slightly and reinstantiate the problem. This is achieved by supplying the new parameter values as keyword arguments to [`instantiate`](@ref):
```@example parameters
sp = instantiate(sm, [ξ₁,ξ₂], l₁ = -2., u₁ = 2., U = 2., l₂ = -0.5, u₂ = 0.5, optimizer = GLPK.Optimizer)

println(sp)

print("VRP = $(VRP(sp))")
```

## Scenario data

Any uncertain parameter in the second stage of a stochastic program should be included in some predefined [`AbstractScenario`](@ref) type. Hence, all uncertain parameters in a stochastic program must be identified before defining the models. In brief, StochasticPrograms demands two functions from this abstraction. The discrete probability of a given [`AbstractScenario`](@ref) occurring should be returned from [`probability`](@ref). Also, the expected scenario out of a collection of given [`AbstractScenario`](@ref)s should be returned by [`expected`](@ref). The predefined [`Scenario`](@ref) type adheres to this abstraction and is the recommended option for most models, as exemplified in the [Quick start](@ref).

Instances of [`Scenario`](@ref) that match an [`@uncertain`](@ref) declaration are conveniently created using the [`@scenario`](@ref) macro. The syntax of these macros match, as is shown in the examples below. The following is a declaration of four scalar uncertain values:
```julia
@uncertain q₁ q₂ d₁ d₂
```
which is paired with a matching instantiation of a scenario containing these scalars:
```@example parameters
ξ₁ = @scenario q₁ = 24.0 q₂ = 28.0 d₁ = 500.0 d₂ = 100.0 probability = 0.4
```
Below, an equivalent formulation is given that instead defines a random vector.
```julia
@uncertain ξ[i in 1:4]
```
paired with
```@example parameters
ξ₁ = @scenario ξ[i in 1:4] = [24.0, 28.0, 500.0, 100.0] probability = 0.4
```
Multidimensional random data is also supported. A simple example is given below.
```julia
@uncertain ξ[i in 1:2, j in 1:3]
```
paired with
```@example parameters
ξ₁ = @scenario ξ[i in 1:2, j in 1:3] = rand(2, 3) probability = rand()
```
The assignment syntax is used to directly create the random matrix. The dimensions of the RHS must match the index declaration, which in turn must match the [`@uncertain`](@ref) declaration. It is also possible to construct more complex examples using JuMP's container syntax. For example,
```julia
@uncertain ξ[i in 1:3, k in [:a, :b, :c]]
```
and
```@example parameters
data = Dict((1, :a) => 1.0, (2, :a) => 2.0, (3, :a) => 3.0,
            (1, :b) => 4.0, (2, :b) => 5.0, (3, :b) => 6.0,
            (1, :c) => 7.0, (2, :c) => 8.0, (3, :c) => 9.0)
ξ₁ = @scenario ξ[i in 1:3, k in [:a, :b, :c]] data[i,k] probability = rand()
```
or the shorthand:
```@example parameters
ξ₁ = @scenario ξ[i in 1:3, k in [:a, :b, :c]] = [1. 2. 3.;
                                                 4. 5. 6.;
                                                 7. 8. 9] probability = rand()
```
Triangular and conditional indexing work as well:
```julia
@uncertain ξ[i in 1:3, j in 1:3; i <= j]
```
and
```@example parameters
ξ₁ = @scenario ξ[i in 1:3, j in 1:3; i <= j] i+j probability = rand()
```
Error checking is performed during model instantiation to ensure that all provided scenarios adhere to the [`@uncertain`](@ref) declaration.

In addition, StochasticPrograms provides a convenience macro, [`@define_scenario`](@ref), for creating scenario types that also adhere to the scenario abstraction. The following is an alternative way to define a scenario structure for the simple problem introduced in the [Quick start](@ref):
```@example simple
using StochasticPrograms

@define_scenario SimpleScenario = begin
    q₁::Float64
    q₂::Float64
    d₁::Float64
    d₂::Float64
end
```
Now, ``\xi_1`` and ``\xi_2`` can be created through:
```@example simple
ξ₁ = SimpleScenario(24.0, 28.0, 500.0, 100.0, probability = 0.4)
```
and
```@example simple
ξ₂ = SimpleScenario(28.0, 32.0, 300.0, 300.0, probability = 0.6)
```
The defined `SimpleScenario`s automatically have the [`AbstractScenario`] functionality. For example, we can check the discrete probability of a given scenario occuring:
```@example simple
probability(ξ₁)
```
Moreover, we can form the expected scenario out of a given set:
```@example simple
ξ̄ = expected([ξ₁, ξ₂])
```
To use the defined scenario in a model, the following [`@uncertain`](@ref) syntax is used:
```julia
@uncertain ξ from SimpleScenario
```

There are some caveats to note. First, the autogenerated requires an additive zero element of the introduced scenario type. For simple numeric types this is autogenerated as well. However, say that we want to extend the above scenario with some vector parameter of size 2:
```@example
using StochasticPrograms

@define_scenario ExampleScenario = begin
    X::Float64
    Y::Vector{Float64}
end
```
In this case, we must provide an implementation of `zero` using [`@zero`](@ref):
```@example
using StochasticPrograms

@define_scenario ExampleScenario = begin
    X::Float64
    Y::Vector{Float64}

    @zero begin
        return ExampleScenario(0.0, [0.0, 0.0])
    end
end

s₁ = ExampleScenario(1., ones(2), probability = 0.5)
s₂ = ExampleScenario(5., -ones(2), probability = 0.5)

println("Probability of s₁: $(probability(s₁))")

s = expected([s₁, s₂])

println("Expectation over s₁ and s₂: $s")
println("Expectated X: $(s.scenario.X)")
println("Expectated Y: $(s.scenario.Y)")
```
Another caveat is that the [`expected`](@ref) function can only be auto generated for fields that support addition and scalar multiplication with `Float64`. Consider:
```@example
using StochasticPrograms

@define_scenario ExampleScenario = begin
    X::Float64
    Y::Vector{Float64}
    Z::Int

    @zero begin
        return ExampleScenario(0.0, [0.0, 0.0], 0)
    end
end
```
Again, the solution is to provide an implementation of [`expected`](@ref), this time using [`@expectation`](@ref):
```@example
using StochasticPrograms

@define_scenario ExampleScenario = begin
    X::Float64
    Y::Vector{Float64}
    Z::Int

    @zero begin
        return ExampleScenario(0.0, [0.0, 0.0], 0)
    end

    @expectation begin
        X = sum([probability(s)*s.X for s in scenarios])
        Y = sum([probability(s)*s.Y for s in scenarios])
        Z = sum([round(Int, probability(s)*s.Z) for s in scenarios])
        return ExampleScenario(X, Y, Z)
    end
end

s₁ = ExampleScenario(1., ones(2), 1, probability = 0.5)
s₂ = ExampleScenario(5., -ones(2), -1, probability = 0.5)

println("Probability of s₁: $(probability(s₁))")

s = expected([s₁, s₂])

println("Expectation over s₁ and s₂: $s")
println("Expectated X: $(s.scenario.X)")
println("Expectated Y: $(s.scenario.Y)")
println("Expectated Z: $(s.scenario.Z)")
```
For most problems, [`@define_scenario`](@ref) will probably be adequate. Otherwise consider defining [Custom scenarios](@ref).

## Sampling

```@setup sampling
using Random
Random.seed!(1)
```
Typically, we do not have exact knowledge of all possible future scenarios. However, we often have access to some model of the uncertainty. For example, scenarios could originate from:

 - A stochastic variable with known distribution
 - A time series fitted to data
 - A nerual network prediction

Even if the exact scenario distribution is unknown, or not all possible scenarios are available, we can still formulate a stochastic program that approximates the model we wish to formulate. This is achieved through a technique called *sampled average approximation*, which is based on sampling. The idea is to sample a large number ``n`` of scenarios with equal probability ``\frac{1}{n}`` and then use them to generate and solve a stochastic program. By the law of large numbers, the result will converge with probability ``1`` to the "true" solution with increasing ``n``.

StochasticPrograms accepts [`AbstractSampler`](@ref) objects in place of [`AbstractScenario`](@ref). However, an [`AbstractSampler`](@ref) is always linked to some underlying [`AbstractScenario`](@ref) type, which is reflected in the resulting stochastic program as well.

The most basic sampler is the included [`Sampler`](@ref), which is used to sample basic [`Scenario`](@ref)s. Consider
```@example simplesampler
using StochasticPrograms

sampler = Sampler() do
    return Scenario(q₁ = 24.0 + randn(), q₂ = 28.0 + randn(), d₁ = 500.0 + randn(), d₂ = 100 + randn(), probability = rand())
end

sampler()
```
Samplers can also be conveniently created using [`@sampler`](@ref). We can define a simple scenario type and a simple sampler as follows:
```@example sampling
using StochasticPrograms

@define_scenario ExampleScenario = begin
    w::Float64
end

@sampler ExampleSampler = begin
    w::Float64

    ExampleSampler(w::AbstractFloat) = new(w)

    @sample ExampleScenario begin
        w = sampler.w
        return ExampleScenario(w*randn(), probability = rand())
    end
end
```
This creates a new [`AbstractSampler`](@ref) type called `ExampleSampler`, which samples `ExampleScenario`s. Now, we can create a sampler object and sample a scenario
```@example sampling
sampler = ExampleSampler(2.)

ξ = sampler()

println(ξ)
println("ξ: $(ξ.w)")
```
Now, lets create a stochastic model using the `ExampleScenario` type:
```@example sampling
sm = @stochastic_model begin
    @stage 1 begin
        @decision(model, x >= 0)
        @objective(model, Min, x)
    end
    @stage 2 begin
        @uncertain w from ExampleScenario
        @variable(model, y)
        @objective(model, Min, y)
        @constraint(model, y + x == w)
    end
end
```
Now, we can sample ``5`` scenarios using the first sampler to generate ``5`` subproblems:
```@example sampling
sp = instantiate(sm, sampler, 5)
```
Printing yields:
```@example sampling
print(sp)
```
Sampled stochastic programs are solved as usual:
```@example sampling
using GLPK

set_optimizer(sp, GLPK.Optimizer)

optimize!(sp)

println("optimal decision: $(optimal_decision(sp))")
println("optimal value: $(objective_value(sp))")
```
Again, if the functionality offered by [`@sampler`](@ref) is not adequate, consider [Custom scenarios](@ref).

## Custom scenarios

```@setup custom
using Random
Random.seed!(1)
```

More complex scenario designs are probably not implementable using [`@define_scenario`](@ref). However, it is still possible to create a custom scenario type as long as:

 - The type is a subtype of [`AbstractScenario`](@ref)
 - The type implements [`probability`](@ref)
 - The type implements [`expected`](@ref), which should return an additive zero element if given an empty array

The restriction on [`expected`](@ref) is there to support taking expectations in a distributed environment. We are also free to define custom sampler objects, as long as:

 - The sampler type is a subtype of [`AbstractSampler`](@ref)
 - The sampler type implements a functor call that performs the sampling

See the [Continuous scenario distribution](@ref) for an example of custom scenario/sampler implementations.
