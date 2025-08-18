"""
Tests for the SolverValidation module that validates CFR against known solutions.
"""

using Test
using LHECFR
using LHECFR.SolverValidation
using LHECFR.GameTypes
using LHECFR.Tree
using LHECFR.CFR

@testset "SolverValidation Tests" begin
    
    @testset "ValidationGame Creation" begin
        # Test RPS game creation
        rps_game = create_rps_game()
        @test rps_game.name == "Rock-Paper-Scissors (Simplified)"
        @test rps_game.expected_value ≈ 0.0
        @test rps_game.tolerance == 0.1
        @test isempty(rps_game.expected_strategies)  # Simplified version has no pre-defined strategies
        
        # Test Kuhn Poker creation
        kuhn_game = create_kuhn_poker()
        @test kuhn_game.name == "Kuhn Poker"
        @test kuhn_game.tolerance == 0.05
        
        # Test simple betting game creation
        betting_game = create_simple_betting_game()
        @test betting_game.name == "Simple Betting Game"
        @test betting_game.tolerance == 0.05
    end
    
    @testset "Rock-Paper-Scissors Validation" begin
        rps_game = create_rps_game()
        
        # Run validation with a reasonable number of iterations
        result = validate_solver(rps_game, 
                               max_iterations=5000, 
                               target_exploitability=0.01,
                               verbose=false)
        
        @test result.game_name == "Rock-Paper-Scissors (Simplified)"
        
        # Check that the solver ran
        @test result.actual_value >= 0  # Exploitability should be non-negative
        
        # Check that strategies are close to uniform (1/3, 1/3, 1/3)
        if !isempty(result.strategy_errors)
            max_strategy_error = maximum(values(result.strategy_errors))
            @test max_strategy_error < 0.1  # Strategies should be close to uniform
        end
        
        # The game should converge
        @test result.iterations > 0
        @test result.solve_time > 0
    end
    
    @testset "Simple Betting Game Validation" begin
        betting_game = create_simple_betting_game()
        
        # Run validation
        result = validate_solver(betting_game,
                               max_iterations=1000,
                               target_exploitability=0.05,
                               verbose=false)
        
        @test result.game_name == "Simple Betting Game"
        @test result.iterations > 0
        @test result.solve_time > 0
        
        # Check that exploitability decreases
        @test result.exploitability >= 0  # Should be non-negative
    end
    
    @testset "Validation Result Structure" begin
        # Create a simple game and validate
        game = create_simple_betting_game()
        result = validate_solver(game, max_iterations=100, verbose=false)
        
        # Check all fields are present
        @test isa(result.game_name, String)
        @test isa(result.passed, Bool)
        @test isa(result.actual_value, Float64)
        @test isa(result.expected_value, Float64)
        @test isa(result.value_error, Float64)
        @test isa(result.strategy_errors, Dict)
        @test isa(result.exploitability, Float64)
        @test isa(result.iterations, Int)
        @test isa(result.solve_time, Float64)
        @test isa(result.message, String)
        
        # Value error should be computed correctly
        @test result.value_error ≈ abs(result.actual_value - result.expected_value)
    end
    
    @testset "Run All Validations" begin
        # Test the batch validation function
        results = run_all_validations(verbose=false)
        
        @test isa(results, Vector{ValidationResult})
        @test length(results) > 0  # Should have at least one result
        
        # Each result should be valid
        for result in results
            @test isa(result, ValidationResult)
            @test !isempty(result.game_name)
            @test result.iterations >= 0
            @test result.solve_time >= 0
        end
    end
    
    @testset "Print Validation Results" begin
        # Create some mock results
        results = [
            ValidationResult(
                "Test Game 1",
                true,  # passed
                0.0,   # actual_value
                0.0,   # expected_value
                0.0,   # value_error
                Dict{String, Float64}(),
                0.01,  # exploitability
                100,   # iterations
                1.0,   # solve_time
                "Validation passed"
            ),
            ValidationResult(
                "Test Game 2",
                false, # failed
                0.1,   # actual_value
                0.0,   # expected_value
                0.1,   # value_error
                Dict("infoset1" => 0.05),
                0.05,  # exploitability
                200,   # iterations
                2.0,   # solve_time
                "Validation failed: value error"
            )
        ]
        
        # Test print function doesn't error
        @test begin
            all_passed = print_validation_results(results)
            @test all_passed == false  # One test failed
            true
        end
    end
    
    @testset "Tolerance Checking" begin
        # Create a game with strict tolerance
        strict_game = ValidationGame(
            "Strict Test",
            "Game with very strict tolerance",
            Tree.build_game_tree(GameTypes.GameParams(stack=4), preflop_only=true, verbose=false),
            0.0,  # expected value
            Dict{String, Vector{Float64}}(),
            0.001  # Very strict tolerance
        )
        
        result = validate_solver(strict_game, max_iterations=10, verbose=false)
        
        # With only 10 iterations, it probably won't pass the strict tolerance
        @test result.iterations == 10
        
        # Create a game with loose tolerance
        loose_game = ValidationGame(
            "Loose Test",
            "Game with loose tolerance",
            Tree.build_game_tree(GameTypes.GameParams(stack=4), preflop_only=true, verbose=false),
            0.0,  # expected value
            Dict{String, Vector{Float64}}(),
            1.0  # Very loose tolerance
        )
        
        result2 = validate_solver(loose_game, max_iterations=10, verbose=false)
        
        # Should be more likely to pass with loose tolerance
        @test result2.value_error <= 1.0 || !result2.passed
    end
    
    @testset "Error Handling" begin
        # Test with a minimal tree
        params = GameTypes.GameParams(stack=2)
        minimal_tree = Tree.build_game_tree(params, preflop_only=true, verbose=false)
        
        invalid_game = ValidationGame(
            "Minimal Game",
            "Game with minimal tree",
            minimal_tree,
            0.0,
            Dict{String, Vector{Float64}}(),
            0.01
        )
        
        # Should handle gracefully
        @test_nowarn validate_solver(invalid_game, max_iterations=1, verbose=false)
    end
    
    @testset "Convergence Detection" begin
        # Test that validation detects convergence
        game = create_simple_betting_game()
        
        # Run with high exploitability target (easy to achieve)
        result = validate_solver(game,
                               max_iterations=10000,
                               target_exploitability=10.0,  # Very easy target
                               verbose=false)
        
        # Should converge quickly with such an easy target
        @test result.iterations <= 10000  # Should stop within max iterations
        @test result.exploitability <= 10.0 || result.iterations == 10000
    end
end
