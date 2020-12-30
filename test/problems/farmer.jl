farmer = @stochastic_model begin
    @stage 1 begin
        @parameters begin
            Crops = [:wheat, :corn, :beets]
            Cost = Dict(:wheat=>150, :corn=>230, :beets=>260)
            Budget = 500
        end
        @decision(model, x[c in Crops] >= 0)
        @objective(model, Min, sum(Cost[c]*x[c] for c in Crops))
        @constraint(model, sum(x[c] for c in Crops) <= Budget)
    end
    @stage 2 begin
        @parameters begin
            Crops = [:wheat, :corn, :beets]
            Required = Dict(:wheat=>200, :corn=>240, :beets=>0)
            PurchasePrice = Dict(:wheat=>238, :corn=>210)
            SellPrice = Dict(:wheat=>170, :corn=>150, :beets=>36, :extra_beets=>10)
        end
        @uncertain ξ[c in Crops]
        @recourse(model, y[p in setdiff(Crops, [:beets])] >= 0)
        @recourse(model, w[s in Crops ∪ [:extra_beets]] >= 0)
        @objective(model, Min, sum(PurchasePrice[p] * y[p] for p in setdiff(Crops, [:beets]))
                   - sum(SellPrice[s] * w[s] for s in Crops ∪ [:extra_beets]))
        @constraint(model, minimum_requirement[p in setdiff(Crops, [:beets])],
            ξ[p] * x[p] + y[p] - w[p] >= Required[p])
        @constraint(model, minimum_requirement_beets,
            ξ[:beets] * x[:beets] - w[:beets] - w[:extra_beets] >= Required[:beets])
        @constraint(model, beets_quota, w[:beets] <= 6000)
    end
end

Crops = [:wheat, :corn, :beets]
ξ₁ = @scenario ξ[c in Crops] = [3.0, 3.6, 24.0] probability = 1/3
ξ₂ = @scenario ξ[c in Crops] = [2.5, 3.0, 20.0] probability = 1/3
ξ₃ = @scenario ξ[c in Crops] = [2.0, 2.4, 16.0] probability = 1/3

farmer_res = SPResult([170,80,250], Dict(1 => [0., 0., 310., 48, 6000, 0.], 2 => [0., 0., 225., 0., 5000, 0.], 3 => [0., 48., 140., 0., 4000, 0.]), -108390, -115405.56, 7015.56, 1150, -118600, -107240)
push!(problems, (farmer, [ξ₁,ξ₂,ξ₃], farmer_res,"Farmer"))
