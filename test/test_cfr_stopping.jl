using Test
using LHECFR
using LHECFR.CFR
using LHECFR.CFRTraversal
using LHECFR.Tree
using LHECFR.GameTypes

@testset "CFR Stopping Criteria Tests" begin
    # Helper function to create a simple game tree
    function create_test_tree()
        params = GameTypes.GameParams(stack=10, big_blind=2, small_blind=1)
        return Tree.build_game_tree(params, preflop_only=true, verbose=false)
    end
    
    @testset "CFRConfig with Stopping Criteria" begin
        # Test default configuration
        config = CFR.CFRConfig()
        @test config.max_iterations == 1000000
        @test config.target_exploitability == 0.001
        @test config.max_time_seconds == Inf
        @test config.min_iterations == 100
        @test config.check_frequency == 100
        
        # Test custom configuration
        config = CFR.CFRConfig(
            max_iterations=500,
            target_exploitability=0.01,
            max_time_seconds=60.0,
            min_iterations=10,
            check_frequency=5
        )
        @test config.max_iterations == 500
        @test config.target_exploitability == 0.01
        @test config.max_time_seconds == 60.0
        @test config.min_iterations == 10
        @test config.check_frequency == 5
    end
    
    @testset "CFRState with Training Time Tracking" begin
        tree = create_test_tree()
        config = CFR.CFRConfig()
        state = CFR.CFRState(tree, config)
        
        @test state.training_start_time == 0.0
        @test state.stopping_reason == ""
    end
    
    @testset "should_stop Function" begin
        tree = create_test_tree()
        
        # Test: Should not stop before min_iterations
        config = CFR.CFRConfig(min_iterations=10)
        state = CFR.CFRState(tree, config)
        state.iteration = 5
        should_stop, reason = CFR.should_stop(state)
        @test !should_stop
        @test reason == ""
        
        # Test: Should stop at max_iterations
        state.iteration = 1000000
        should_stop, reason = CFR.should_stop(state)
        @test should_stop
        @test occursin("Maximum iterations", reason)
        
        # Test: Should stop when exploitability target reached
        config = CFR.CFRConfig(
            min_iterations=1,
            target_exploitability=0.01
        )
        state = CFR.CFRState(tree, config)
        state.iteration = 100
        state.exploitability = 0.005  # Below target
        should_stop, reason = CFR.should_stop(state)
        @test should_stop
        @test occursin("Target exploitability", reason)
        
        # Test: Should stop when time limit reached
        config = CFR.CFRConfig(
            min_iterations=1,
            max_time_seconds=1.0
        )
        state = CFR.CFRState(tree, config)
        state.iteration = 100
        state.training_start_time = time() - 2.0  # Started 2 seconds ago
        should_stop, reason = CFR.should_stop(state)
        @test should_stop
        @test occursin("Time limit", reason)
    end
    
    @testset "Training with Maximum Iterations" begin
        tree = create_test_tree()
        config = CFR.CFRConfig(
            max_iterations=10,
            min_iterations=1,
            check_frequency=1,
            target_exploitability=0.0  # Disable exploitability stopping
        )
        state = CFR.CFRState(tree, config)
        
        # Train with iteration limit
        CFRTraversal.train!(tree, state, verbose=false)
        
        @test state.iteration == 10
        @test state.stopping_reason == "Maximum iterations reached (10)"
        @test state.training_start_time > 0
    end
    
    @testset "Training with Time Limit" begin
        tree = create_test_tree()
        config = CFR.CFRConfig(
            max_iterations=1000000,
            max_time_seconds=0.1,  # Very short time limit
            min_iterations=1,
            check_frequency=1,
            target_exploitability=0.0  # Disable exploitability stopping
        )
        state = CFR.CFRState(tree, config)
        
        # Train with time limit
        CFRTraversal.train!(tree, state, verbose=false)
        
        @test state.iteration < 1000000  # Should stop before max iterations
        @test occursin("Time limit", state.stopping_reason)
        @test time() - state.training_start_time >= 0.1
    end
    
    @testset "Training with Exploitability Target" begin
        tree = create_test_tree()
        config = CFR.CFRConfig(
            max_iterations=1000,
            target_exploitability=1.0,  # Will be satisfied after ~100 iterations
            min_iterations=5,
            check_frequency=1
        )
        state = CFR.CFRState(tree, config)
        
        # Train with exploitability target
        CFRTraversal.train!(tree, state, verbose=false)
        
        @test state.iteration >= 5  # At least min_iterations
        @test state.iteration < 1000  # Should stop before max
        @test occursin("Target exploitability", state.stopping_reason)
    end
    
    @testset "get_training_stats Function" begin
        tree = create_test_tree()
        config = CFR.CFRConfig(max_iterations=10)
        state = CFR.CFRState(tree, config)
        
        # Before training
        stats = CFR.get_training_stats(state)
        @test stats["iterations"] == 0
        @test stats["elapsed_time"] == 0.0
        @test stats["iterations_per_second"] == 0.0
        
        # After training
        CFRTraversal.train!(tree, state, verbose=false)
        stats = CFR.get_training_stats(state)
        @test stats["iterations"] == 10
        @test stats["elapsed_time"] > 0
        @test stats["iterations_per_second"] > 0
        @test stats["stopping_reason"] == "Maximum iterations reached (10)"
        @test stats["infosets"] > 0
    end
    
    @testset "Check Frequency" begin
        tree = create_test_tree()
        config = CFR.CFRConfig(
            max_iterations=100,
            min_iterations=1,
            check_frequency=25,  # Check every 25 iterations
            target_exploitability=0.0  # Disable exploitability stopping
        )
        state = CFR.CFRState(tree, config)
        
        CFRTraversal.train!(tree, state, verbose=false)
        
        # Convergence history should have entries at check frequency intervals
        @test length(state.convergence_history) <= 5  # 100/25 + 1 for final
        @test state.iteration == 100
    end
    
    @testset "Override Iterations Parameter" begin
        tree = create_test_tree()
        config = CFR.CFRConfig(max_iterations=1000)
        state = CFR.CFRState(tree, config)
        
        # Override with explicit iterations parameter
        CFRTraversal.train!(tree, state, iterations=5, verbose=false)
        
        @test state.iteration == 5
        @test state.total_iterations == 5
    end
end

# Run the tests
println("\n=== Running CFR Stopping Criteria Tests ===")
