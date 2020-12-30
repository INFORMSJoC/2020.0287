@define_scenario SimpleScenario = begin
    q₁::Float64
    q₂::Float64
    d₁::Float64
    d₂::Float64
end

ξ₁ = SimpleScenario(24.0, 28.0, 500.0, 100.0, probability = 0.4)
ξ₂ = SimpleScenario(28.0, 32.0, 300.0, 300.0, probability = 0.6)

simple_sp = StochasticProgram([ξ₁, ξ₂], Deterministic(), GLPK.Optimizer)

@first_stage simple_sp = begin
    @decision(model, x₁ >= 40)
    @decision(model, x₂ >= 20)
    @objective(model, Min, 100*x₁ + 150*x₂)
    @constraint(model, x₁ + x₂ <= 120)
end

@second_stage simple_sp = begin
    @known x₁ x₂
    @uncertain q₁ q₂ d₁ d₂ from SimpleScenario
    @recourse(model, 0 <= y₁ <= d₁)
    @recourse(model, 0 <= y₂ <= d₂)
    @objective(model, Max, q₁*y₁ + q₂*y₂)
    @constraint(model, 6*y₁ + 10*y₂ <= 60*x₁)
    @constraint(model, 8*y₁ + 5*y₂ <= 80*x₂)
end
