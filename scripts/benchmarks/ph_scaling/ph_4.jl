using Distributed
addprocs(4)

include("../benchmark.jl")

bm = prepare(ssn, ssn_sampler, x₀, solvers = [adaptive_progressive_hedging], num_scenarios = 6000)
res = benchmark(bm, "ph_4.json")
