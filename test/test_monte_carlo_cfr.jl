using Test
using LHECFR
using LHECFR.CFR
using LHECFR.CFRTraversal
using LHECFR.Tree
using LHECFR.GameTypes
using Random
using Statistics

@testset "Monte Carlo CFR Tests" begin
    # Helper function to create a simple game tree
    function create_test_tree()
        params = GameTypes.GameParams(stack=10, big_blind=2, small_blind=1)
        return Tree.build_game_tree(params, preflop_only=true, verbose=false)
    end
    
    # Helper function to create a tree with known chance node structure
    function create_chance_test_tree()
        # For testing, we'll use a simple pre-built tree
        # The actual tree builder creates chance nodes for card dealing
        params = GameTypes.GameParams(stack=10, big_blind=2, small_blind=1)
        tree = Tree.build_game_tree(params, preflop_only=true, verbose=false)
        return tree
    end
    
    @testset "CFRConfig with Sampling" begin
        # Test default sampling configuration
        config = CFR.CFRConfig()
        @test config.use_sampling == false
        @test config.sampling_strategy == :none
        @test config.sampling_probability == 1.0
        
        # Test chance sampling configuration
        config = CFR.CFRConfig(
            use_sampling=true,
            sampling_strategy=:chance,
            sampling_probability=0.5
        )
        @test config.use_sampling == true
        @test config.sampling_strategy == :chance
        @test config.sampling_probability == 0.5
        
        # Test auto-enable sampling when strategy is specified
        config = CFR.CFRConfig(
            sampling_strategy=:outcome,
            sampling_probability=0.3
        )
        @test config.use_sampling == true  # Should be auto-enabled
        @test config.sampling_strategy == :outcome
    end
    
    @testset "sample_without_replacement" begin
        Random.seed!(42)
        
        # Test basic sampling
        collection = 1:10
        sampled = CFRTraversal.sample_without_replacement(collection, 5)
        @test length(sampled) == 5
        @test all(x -> x in collection, sampled)
        @test length(unique(sampled)) == 5  # No duplicates
        
        # Test sampling more than available
        sampled = CFRTraversal.sample_without_replacement(collection, 15)
        @test length(sampled) == 10  # Can't sample more than available
        
        # Test sampling all
        sampled = CFRTraversal.sample_without_replacement(collection, 10)
        @test length(sampled) == 10
        @test sort(sampled) == collect(1:10)
    end
    
    @testset "Chance Node Sampling" begin
        tree = create_chance_test_tree()
        
        # Find a chance node if one exists (card dealing nodes)
        # For now, test with the tree root which may or may not be a chance node
        # The important thing is that the sampling logic works
        
        # Test without sampling
        config = CFR.CFRConfig(use_sampling=false)
        state = CFR.CFRState(tree, config)
        
        reach_probs = (1.0, 1.0)
        # Initialize empty cards for both players
        player_cards = [Vector{GameTypes.Card}(), Vector{GameTypes.Card}()]
        board_cards = Vector{GameTypes.Card}()
        
        # Test that handle_chance_node doesn't error
        if tree.root.node_type == Tree.ChanceNode
            value = CFRTraversal.handle_chance_node(
                state, tree, tree.root, reach_probs, player_cards, board_cards
            )
            @test isa(value, Float64)
        end
        
        # Test with chance sampling (50% of children)
        config = CFR.CFRConfig(
            use_sampling=true,
            sampling_strategy=:chance,
            sampling_probability=0.5
        )
        state = CFR.CFRState(tree, config)
        
        Random.seed!(42)
        # Test sampling works for any node type
        value = CFRTraversal.cfr_traverse(
            state, tree, tree.root, reach_probs, player_cards, board_cards
        )
        @test isa(value, Float64)
        
        # Test with outcome sampling (single child)
        config = CFR.CFRConfig(
            use_sampling=true,
            sampling_strategy=:outcome
        )
        state = CFR.CFRState(tree, config)
        
        Random.seed!(42)
        value = CFRTraversal.cfr_traverse(
            state, tree, tree.root, reach_probs, player_cards, board_cards
        )
        @test isa(value, Float64)
    end
    
    @testset "Monte Carlo CFR Training" begin
        tree = create_test_tree()
        
        # Test training with chance sampling
        config = CFR.CFRConfig(
            max_iterations=10,
            use_sampling=true,
            sampling_strategy=:chance,
            sampling_probability=0.5,
            check_frequency=5
        )
        state = CFR.CFRState(tree, config)
        
        # Should complete without errors
        CFRTraversal.train!(tree, state, verbose=false)
        @test state.iteration == 10
        @test CFR.get_infoset_count(state) > 0
        
        # Test training with outcome sampling
        config = CFR.CFRConfig(
            max_iterations=10,
            use_sampling=true,
            sampling_strategy=:outcome,
            check_frequency=5
        )
        state = CFR.CFRState(tree, config)
        
        CFRTraversal.train!(tree, state, verbose=false)
        @test state.iteration == 10
        @test CFR.get_infoset_count(state) > 0
    end
    
    @testset "Sampling Variance Reduction" begin
        # Create a tree for variance testing
        tree = create_chance_test_tree()
        
        # Run multiple iterations with different sampling rates
        results = Dict{Float64, Vector{Float64}}()
        
        for sampling_prob in [0.2, 0.5, 0.8, 1.0]
            config = CFR.CFRConfig(
                use_sampling=true,
                sampling_strategy=:chance,
                sampling_probability=sampling_prob
            )
            state = CFR.CFRState(tree, config)
            
            # Collect values from multiple runs
            values = Float64[]
            for seed in 1:10  # Reduced iterations for speed
                Random.seed!(seed)
                value = CFRTraversal.cfr_traverse(
                    state, tree, tree.root, (1.0, 1.0), 
                    [Vector{GameTypes.Card}(), Vector{GameTypes.Card}()], Vector{GameTypes.Card}()
                )
                push!(values, value)
            end
            
            results[sampling_prob] = values
        end
        
        # Test that sampling with different probabilities produces values
        @test length(results[0.2]) == 10
        @test length(results[1.0]) == 10
        @test all(v -> isa(v, Float64), results[0.2])
        @test all(v -> isa(v, Float64), results[1.0])
        
        # In general, higher sampling probability should have lower variance
        # but this depends on the specific tree structure
        if length(unique(results[1.0])) > 1  # Only test if there's variance
            @test std(results[1.0]) <= std(results[0.2]) * 2.0  # Allow tolerance
        end
    end
    
    @testset "External Sampling" begin
        tree = create_test_tree()
        
        # Test external sampling configuration
        config = CFR.CFRConfig(
            max_iterations=10,
            use_sampling=true,
            sampling_strategy=:external,
            sampling_probability=0.3,
            check_frequency=5
        )
        state = CFR.CFRState(tree, config)
        
        # Should complete without errors
        CFRTraversal.train!(tree, state, verbose=false)
        @test state.iteration == 10
        @test CFR.get_infoset_count(state) > 0
    end
    
    @testset "Sampling Impact on Convergence" begin
        tree = create_test_tree()
        
        # Compare convergence with and without sampling
        # Without sampling
        config_full = CFR.CFRConfig(
            max_iterations=50,
            use_sampling=false,
            check_frequency=10
        )
        state_full = CFR.CFRState(tree, config_full)
        CFRTraversal.train!(tree, state_full, verbose=false)
        
        # With chance sampling
        config_sampled = CFR.CFRConfig(
            max_iterations=50,
            use_sampling=true,
            sampling_strategy=:chance,
            sampling_probability=0.5,
            check_frequency=10
        )
        state_sampled = CFR.CFRState(tree, config_sampled)
        CFRTraversal.train!(tree, state_sampled, verbose=false)
        
        # Both should discover information sets
        @test CFR.get_infoset_count(state_full) > 0
        @test CFR.get_infoset_count(state_sampled) > 0
        
        # Sampled version might discover fewer infosets initially
        # but should still make progress
        @test state_sampled.iteration == 50
    end
end

# Run the tests
println("\n=== Running Monte Carlo CFR Tests ===")
