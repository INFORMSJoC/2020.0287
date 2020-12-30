using Distributed
addprocs(16)

include("../benchmark.jl")

bm = prepare(ssn, ssn_sampler, x₀, solvers = [lshaped, async_lshaped, tr_with_partial_aggregation, lv_with_kmedoids_aggregation], num_scenarios = 6000)
res = benchmark(bm, "ls_16.json")
