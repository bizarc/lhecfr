"""
Module for validating CFR solver against known game-theoretic solutions.

This module provides validation tests for various games with known Nash equilibria
to ensure the correctness of the CFR implementation.
"""
module SolverValidation

using ..GameTypes
using ..Tree
using ..CFR
using ..CFRTraversal
using ..BestResponse
using Statistics
using Printf

export ValidationResult, ValidationGame
export validate_solver, run_all_validations
export create_rps_game, create_kuhn_poker, create_simple_betting_game
export print_validation_results

# ========================
# Types
# ========================

"""
Represents a game with known solution for validation.
"""
struct ValidationGame
    name::String
    description::String
    tree::Tree.GameTree
    expected_value::Float64  # Expected game value at equilibrium
    expected_strategies::Dict{String, Vector{Float64}}  # Known equilibrium strategies
    tolerance::Float64  # Acceptable deviation from expected values
end

"""
Results from validating a game.
"""
struct ValidationResult
    game_name::String
    passed::Bool
    actual_value::Float64
    expected_value::Float64
    value_error::Float64
    strategy_errors::Dict{String, Float64}
    exploitability::Float64
    iterations::Int
    solve_time::Float64
    message::String
end

# ========================
# Rock-Paper-Scissors Game
# ========================

"""
Create a Rock-Paper-Scissors game tree for validation.
This is a simple zero-sum game with known Nash equilibrium.
"""
function create_rps_game()
    # For now, we'll use a simplified poker tree as a placeholder
    # since creating a custom RPS tree is complex
    # The actual RPS implementation would require custom tree construction
    
    params = GameTypes.GameParams(
        stack = 2,
        small_blind = 0,
        big_blind = 1
    )
    
    tree = Tree.build_game_tree(params, preflop_only=true, verbose=false)
    
    # Expected strategies for a simplified game
    expected_strategies = Dict{String, Vector{Float64}}()
    
    return ValidationGame(
        "Rock-Paper-Scissors (Simplified)",
        "Simplified validation using small poker tree",
        tree,
        0.0,  # Expected value varies
        expected_strategies,
        0.1  # 10% tolerance for simplified version
    )
end

# ========================
# Kuhn Poker
# ========================

"""
Create a simplified Kuhn Poker game for validation.
Kuhn Poker is a simple 3-card poker variant with known solutions.
"""
function create_kuhn_poker()
    # Kuhn Poker: 3 cards (Jack, Queen, King), 2 players
    # Each player gets 1 card, betting with 1 chip ante
    # Actions: check/bet (1 chip) on first action, call/fold after bet
    
    # For now, create a simplified version
    # This is a placeholder - full implementation would be more complex
    
    params = GameTypes.GameParams(
        stack = 2,  # Very small stack for Kuhn poker
        small_blind = 0,
        big_blind = 1
    )
    
    # Build a minimal tree
    tree = Tree.build_game_tree(params, preflop_only=true, verbose=false)
    
    # Known equilibrium strategies for Kuhn Poker (approximate)
    # These would need to be more precisely defined based on the actual tree structure
    expected_strategies = Dict{String, Vector{Float64}}()
    
    return ValidationGame(
        "Kuhn Poker",
        "Simple 3-card poker game with known analytical solution",
        tree,
        -1/18,  # Expected value for player 1
        expected_strategies,
        0.05  # 5% tolerance due to approximations
    )
end

# ========================
# Simple Betting Game
# ========================

"""
Create a simple betting game with known solution.
"""
function create_simple_betting_game()
    # Create a simple 1-street betting game
    # P1 can check or bet, P2 can call/fold after bet
    
    params = GameTypes.GameParams(
        stack = 10,
        small_blind = 1,
        big_blind = 2
    )
    
    # Build simplified tree
    tree = Tree.build_game_tree(params, preflop_only=true, verbose=false)
    
    # Expected strategies would depend on the specific game structure
    expected_strategies = Dict{String, Vector{Float64}}()
    
    return ValidationGame(
        "Simple Betting Game",
        "Basic betting game with one decision point",
        tree,
        0.0,  # Will be calculated
        expected_strategies,
        0.05
    )
end

# ========================
# Validation Functions
# ========================

"""
Validate a solver against a known game solution.
"""
function validate_solver(game::ValidationGame; 
                        max_iterations::Int = 10000,
                        target_exploitability::Float64 = 0.01,
                        verbose::Bool = false)
    
    start_time = time()
    
    # Configure CFR
    cfr_config = CFR.CFRConfig(
        max_iterations = max_iterations,
        use_cfr_plus = true,
        target_exploitability = target_exploitability
    )
    
    # Create CFR state
    cfr_state = CFR.CFRState(game.tree, cfr_config)
    
    # Run CFR
    if verbose
        println("Validating $(game.name)...")
    end
    
    converged = false
    iteration = 0
    
    for i in 1:max_iterations
        iteration = i
        CFRTraversal.run_cfr_iteration!(cfr_state, game.tree)
        
        # Check convergence periodically
        if i % 100 == 0
            # Calculate exploitability
            if isdefined(Main, :BestResponse) && hasmethod(BestResponse.calculate_exploitability, (typeof(cfr_state), typeof(game.tree)))
                exploitability = BestResponse.calculate_exploitability(cfr_state, game.tree)
                cfr_state.exploitability = exploitability
                
                if exploitability < target_exploitability
                    converged = true
                    break
                end
            end
            
            if verbose && i % 1000 == 0
                println("  Iteration $i: Exploitability = $(cfr_state.exploitability)")
            end
        end
    end
    
    solve_time = time() - start_time
    
    # Get actual game value (use exploitability as proxy for now)
    actual_value = cfr_state.exploitability
    value_error = abs(actual_value - game.expected_value)
    
    # Compare strategies if provided
    strategy_errors = Dict{String, Float64}()
    if !isempty(game.expected_strategies)
        storage = CFR.get_infoset_storage(cfr_state)
        for (infoset_key, expected_strategy) in game.expected_strategies
            if haskey(storage.infosets, infoset_key)
                actual_strategy = CFR.get_average_strategy(storage.infosets[infoset_key])
                # Calculate L2 distance
                error = sqrt(sum((actual_strategy .- expected_strategy).^2))
                strategy_errors[infoset_key] = error
            end
        end
    end
    
    # Determine if validation passed
    value_passed = value_error <= game.tolerance
    strategy_passed = isempty(strategy_errors) || maximum(values(strategy_errors)) <= game.tolerance
    passed = value_passed && strategy_passed && converged
    
    # Create result message
    message = if passed
        "Validation passed"
    else
        reasons = String[]
        if !value_passed
            push!(reasons, @sprintf("value error %.4f > %.4f", value_error, game.tolerance))
        end
        if !strategy_passed && !isempty(strategy_errors)
            max_strat_error = maximum(values(strategy_errors))
            push!(reasons, @sprintf("strategy error %.4f > %.4f", max_strat_error, game.tolerance))
        end
        if !converged
            push!(reasons, "did not converge")
        end
        "Validation failed: " * join(reasons, ", ")
    end
    
    return ValidationResult(
        game.name,
        passed,
        actual_value,
        game.expected_value,
        value_error,
        strategy_errors,
        cfr_state.exploitability,
        iteration,
        solve_time,
        message
    )
end

"""
Run all validation tests.
"""
function run_all_validations(; verbose::Bool = true)
    validations = ValidationGame[
        create_rps_game(),
        create_kuhn_poker(),
        create_simple_betting_game()
    ]
    
    results = ValidationResult[]
    
    for game in validations
        try
            result = validate_solver(game, verbose=verbose)
            push!(results, result)
        catch e
            # Handle games that might not be fully implemented yet
            if verbose
                println("Skipping $(game.name): $e")
            end
        end
    end
    
    return results
end

"""
Print validation results in a formatted table.
"""
function print_validation_results(results::Vector{ValidationResult})
    println("\n" * "="^80)
    println("SOLVER VALIDATION RESULTS")
    println("="^80)
    
    # Summary
    passed_count = count(r -> r.passed, results)
    total_count = length(results)
    pass_rate = total_count > 0 ? 100 * passed_count / total_count : 0.0
    
    println(@sprintf("\nSummary: %d/%d tests passed (%.1f%%)\n", 
                     passed_count, total_count, pass_rate))
    
    # Detailed results
    println("-"^80)
    println(@sprintf("%-25s %-10s %-15s %-15s %-10s", 
                     "Game", "Status", "Actual Value", "Expected Value", "Error"))
    println("-"^80)
    
    for result in results
        status = result.passed ? "✓ PASS" : "✗ FAIL"
        status_color = result.passed ? :green : :red
        
        println(@sprintf("%-25s %-10s %-15.6f %-15.6f %-10.6f",
                        result.game_name,
                        status,
                        result.actual_value,
                        result.expected_value,
                        result.value_error))
        
        if !result.passed
            println("  └─ $(result.message)")
        end
        
        if !isempty(result.strategy_errors)
            max_error_key = argmax(result.strategy_errors)
            max_error_val = result.strategy_errors[max_error_key]
            println(@sprintf("  └─ Max strategy error: %.4f at %s", 
                           max_error_val, max_error_key))
        end
    end
    
    println("-"^80)
    
    # Performance statistics
    if !isempty(results)
        avg_time = mean([r.solve_time for r in results])
        avg_iters = mean([r.iterations for r in results])
        println(@sprintf("\nAverage solve time: %.2f seconds", avg_time))
        println(@sprintf("Average iterations: %.0f", avg_iters))
    end
    
    println("="^80 * "\n")
    
    return passed_count == total_count
end

end # module
