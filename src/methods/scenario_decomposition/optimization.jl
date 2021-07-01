# Scenario-decomposition optimization #
# =================================== #
function optimize!(structure::ScenarioDecompositionStructure, optimizer::AbstractStructuredOptimizer, x₀::AbstractVector)
    # Sanity check
    supports_structure(optimizer, structure) || throw(UnsupportedStructure{typeof(optimizer), typeof(structure)}())
    # Load structure
    load_structure!(optimizer, structure, x₀)
    # Run structure-exploiting optimization procedure
    MOI.optimize!(optimizer)
    return nothing
end

function set_master_optimizer!(structure::ScenarioDecompositionStructure, optimizer)
    return nothing
end

function set_master_optimizer_attribute!(::ScenarioDecompositionStructure, ::MOI.AbstractOptimizerAttribute, value)
    return nothing
end

function set_subproblem_optimizer!(structure::ScenarioDecompositionStructure, optimizer)
    set_optimizer!(scenarioproblems(structure), optimizer)
    return nothing
end

function set_subproblem_optimizer_attribute!(structure::ScenarioDecompositionStructure, attr::MOI.AbstractOptimizerAttribute, value)
    MOI.set(scenarioproblems(structure), attr, value)
    return nothing
end

function cache_solution!(stochasticprogram::StochasticProgram{2}, structure::ScenarioDecompositionStructure{2}, optimizer::MOI.AbstractOptimizer)
    cache = solutioncache(stochasticprogram)
    # Cache main solution
    variables = decision_variables_at_stage(stochasticprogram, 1)
    constraints = decision_constraints_at_stage(stochasticprogram, 1)
    cache[:solution] = SolutionCache(optimizer, variables, constraints)
    # Cache first-stage solution
    cache[:node_solution_1] = SolutionCache(optimizer, variables, constraints)
    # Cache scenario-dependent solutions (Skip if more than 100 scenarios for performance)
    if num_scenarios(stochasticprogram) <= 100
        variables = decision_variables_at_stage(stochasticprogram, 2)
        constraints = decision_constraints_at_stage(stochasticprogram, 2)
        cache_solution!(cache, scenarioproblems(structure), optimizer, 2, variables, constraints)
    end
    return nothing
end
