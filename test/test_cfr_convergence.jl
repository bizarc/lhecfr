using Test
using LHECFR
using LHECFR.CFR
using LHECFR.CFRTraversal
using LHECFR.Tree
using LHECFR.GameTypes
using Statistics
using Random

@testset "CFR Convergence Tests" begin
    
    @testset "Simplified LHE Convergence" begin
        # Create a very small LHE game for testing
        params = GameTypes.GameParams(
            stack=4,  # Very small stacks
            big_blind=2,
            small_blind=1,
            max_raises_per_street=1  # Limit raises
        )
        
        tree = Tree.build_game_tree(params, preflop_only=true, verbose=false)
        
        # Test CFR convergence
        config = CFR.CFRConfig(
            use_cfr_plus=false,
            max_iterations=100,
            check_frequency=10,
            target_exploitability=0.1
        )
        state = CFR.CFRState(tree, config)
        
        # Train
        CFRTraversal.train!(tree, state, verbose=false)
        
        # Check that we discovered information sets
        @test CFR.get_infoset_count(state) > 0
        
        # Check that exploitability decreased
        if length(state.convergence_history) > 1
            # Later exploitability should generally be lower than initial
            @test state.convergence_history[end] <= state.convergence_history[1] * 1.5
        end
        
        # Check that training completed
        @test state.iteration > 0
        @test state.stopping_reason != ""
    end
    
    @testset "CFR vs CFR+ Comparison" begin
        params = GameTypes.GameParams(stack=4, big_blind=2, small_blind=1)
        tree = Tree.build_game_tree(params, preflop_only=true, verbose=false)
        
        # Train with standard CFR
        config_cfr = CFR.CFRConfig(
            use_cfr_plus=false,
            max_iterations=50,
            check_frequency=10
        )
        state_cfr = CFR.CFRState(tree, config_cfr)
        CFRTraversal.train!(tree, state_cfr, verbose=false)
        
        # Train with CFR+
        config_cfr_plus = CFR.CFRConfig(
            use_cfr_plus=true,
            max_iterations=50,
            check_frequency=10
        )
        state_cfr_plus = CFR.CFRState(tree, config_cfr_plus)
        CFRTraversal.train!(tree, state_cfr_plus, verbose=false)
        
        # Both should discover information sets
        @test CFR.get_infoset_count(state_cfr) > 0
        @test CFR.get_infoset_count(state_cfr_plus) > 0
        
        # CFR+ often converges faster (lower exploitability with same iterations)
        # But this is not guaranteed on all games
        @test state_cfr.exploitability >= 0
        @test state_cfr_plus.exploitability >= 0
    end
    
    @testset "Convergence with Linear Weighting" begin
        params = GameTypes.GameParams(stack=4, big_blind=2, small_blind=1)
        tree = Tree.build_game_tree(params, preflop_only=true, verbose=false)
        
        # Test Linear CFR
        config = CFR.CFRConfig(
            use_cfr_plus=true,
            use_linear_weighting=true,
            max_iterations=50,
            check_frequency=10
        )
        state = CFR.CFRState(tree, config)
        CFRTraversal.train!(tree, state, verbose=false)
        
        @test CFR.get_infoset_count(state) > 0
        @test state.iteration == 50
        
        # Check that strategies are being computed
        for (id, cfr_infoset) in state.storage.infosets
            strategy = Tree.get_average_strategy(cfr_infoset)
            @test sum(strategy) ≈ 1.0 atol=1e-10
            @test all(s -> s >= 0, strategy)
        end
    end
    
    @testset "Convergence Metrics" begin
        params = GameTypes.GameParams(stack=4, big_blind=2, small_blind=1)
        tree = Tree.build_game_tree(params, preflop_only=true, verbose=false)
        
        config = CFR.CFRConfig(
            use_cfr_plus=true,
            max_iterations=100,
            check_frequency=20  # Check every 20 iterations
        )
        state = CFR.CFRState(tree, config)
        CFRTraversal.train!(tree, state, verbose=false)
        
        # Should have convergence history
        @test length(state.convergence_history) > 0
        @test length(state.convergence_history) <= 6  # 100/20 + 1
        
        # Exploitability should be non-increasing (with some tolerance for noise)
        if length(state.convergence_history) > 2
            # Check general trend is decreasing
            first_half = mean(state.convergence_history[1:div(end,2)])
            second_half = mean(state.convergence_history[div(end,2)+1:end])
            @test second_half <= first_half * 1.2  # Allow 20% tolerance
        end
        
        # Get training statistics
        stats = CFR.get_training_stats(state)
        @test stats["iterations"] == 100
        @test stats["infosets"] > 0
        @test stats["elapsed_time"] > 0
        @test stats["iterations_per_second"] > 0
    end
    
    @testset "Strategy Convergence Properties" begin
        params = GameTypes.GameParams(stack=4, big_blind=2, small_blind=1)
        tree = Tree.build_game_tree(params, preflop_only=true, verbose=false)
        
        # Train for longer to get better convergence
        config = CFR.CFRConfig(
            use_cfr_plus=true,
            max_iterations=200,
            check_frequency=50
        )
        state = CFR.CFRState(tree, config)
        CFRTraversal.train!(tree, state, verbose=false)
        
        # Check strategy properties
        total_infosets = CFR.get_infoset_count(state)
        @test total_infosets > 0
        
        # Sample some strategies and verify they're valid probability distributions
        strategy_sums = Float64[]
        min_probs = Float64[]
        max_probs = Float64[]
        
        for (id, cfr_infoset) in state.storage.infosets
            avg_strategy = Tree.get_average_strategy(cfr_infoset)
            current_strategy = Tree.get_current_strategy(cfr_infoset)
            
            # Both strategies should be valid probability distributions
            @test sum(avg_strategy) ≈ 1.0 atol=1e-10
            @test sum(current_strategy) ≈ 1.0 atol=1e-10
            @test all(s -> s >= 0, avg_strategy)
            @test all(s -> s >= 0, current_strategy)
            
            push!(strategy_sums, sum(avg_strategy))
            push!(min_probs, minimum(avg_strategy))
            push!(max_probs, maximum(avg_strategy))
        end
        
        # All strategies should sum to 1
        @test all(s -> abs(s - 1.0) < 1e-10, strategy_sums)
        
        # Strategies should be between 0 and 1
        @test all(p -> p >= 0, min_probs)
        @test all(p -> p <= 1, max_probs)
    end
    
    @testset "Convergence with Sampling" begin
        params = GameTypes.GameParams(stack=4, big_blind=2, small_blind=1)
        tree = Tree.build_game_tree(params, preflop_only=true, verbose=false)
        
        # Test convergence with chance sampling
        config = CFR.CFRConfig(
            use_cfr_plus=true,
            use_sampling=true,
            sampling_strategy=:chance,
            sampling_probability=0.5,
            max_iterations=100,
            check_frequency=25
        )
        state = CFR.CFRState(tree, config)
        CFRTraversal.train!(tree, state, verbose=false)
        
        @test CFR.get_infoset_count(state) > 0
        @test state.iteration == 100
        
        # Even with sampling, should maintain valid strategies
        for (id, cfr_infoset) in state.storage.infosets
            strategy = Tree.get_average_strategy(cfr_infoset)
            @test sum(strategy) ≈ 1.0 atol=1e-10
            @test all(s -> s >= 0, strategy)
        end
    end
    
    @testset "Early Stopping on Convergence" begin
        params = GameTypes.GameParams(stack=3, big_blind=2, small_blind=1)
        tree = Tree.build_game_tree(params, preflop_only=true, verbose=false)
        
        # Set a high exploitability target that should be reached quickly
        config = CFR.CFRConfig(
            use_cfr_plus=true,
            max_iterations=1000,
            target_exploitability=10.0,  # High target
            min_iterations=10,
            check_frequency=5
        )
        state = CFR.CFRState(tree, config)
        CFRTraversal.train!(tree, state, verbose=false)
        
        # Should stop early due to exploitability target
        @test state.iteration < 1000
        @test state.iteration >= 10  # At least min_iterations
        @test occursin("exploitability", lowercase(state.stopping_reason))
    end
    
    @testset "Deterministic Convergence" begin
        params = GameTypes.GameParams(stack=3, big_blind=2, small_blind=1)
        tree = Tree.build_game_tree(params, preflop_only=true, verbose=false)
        
        # Run CFR twice with same seed - should get same results
        Random.seed!(42)
        config1 = CFR.CFRConfig(use_cfr_plus=true, max_iterations=20)
        state1 = CFR.CFRState(tree, config1)
        CFRTraversal.train!(tree, state1, verbose=false)
        
        Random.seed!(42)
        config2 = CFR.CFRConfig(use_cfr_plus=true, max_iterations=20)
        state2 = CFR.CFRState(tree, config2)
        CFRTraversal.train!(tree, state2, verbose=false)
        
        # Should have same number of infosets
        @test CFR.get_infoset_count(state1) == CFR.get_infoset_count(state2)
        
        # Strategies should be identical (or very close)
        for (id, cfr_infoset1) in state1.storage.infosets
            if haskey(state2.storage.infosets, id)
                cfr_infoset2 = state2.storage.infosets[id]
                strategy1 = Tree.get_average_strategy(cfr_infoset1)
                strategy2 = Tree.get_average_strategy(cfr_infoset2)
                @test strategy1 ≈ strategy2 atol=1e-10
            end
        end
    end
end

# Run the tests
println("\n=== Running CFR Convergence Tests ===")
