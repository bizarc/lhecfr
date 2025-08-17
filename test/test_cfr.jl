using Test
using LHECFR
using LHECFR.GameTypes
using LHECFR.Tree
using LHECFR.CFR

@testset "CFR Module Tests" begin
    
    @testset "CFRConfig Creation" begin
        # Default configuration
        config = CFR.CFRConfig()
        @test config.use_cfr_plus == true
        @test config.use_linear_weighting == false
        @test config.use_sampling == false
        @test config.sampling_probability == 1.0
        @test config.prune_threshold == -1e9
        @test config.discount_factor == 1.0
        
        # Custom configuration
        config2 = CFR.CFRConfig(
            use_cfr_plus = false,
            use_linear_weighting = true,
            use_sampling = true,
            sampling_probability = 0.5,
            prune_threshold = -100.0,
            discount_factor = 0.99
        )
        @test config2.use_cfr_plus == false
        @test config2.use_linear_weighting == true
        @test config2.use_sampling == true
        @test config2.sampling_probability == 0.5
        @test config2.prune_threshold == -100.0
        @test config2.discount_factor == 0.99
    end
    
    @testset "CFRState Creation" begin
        # Create a small game tree for testing
        params = GameTypes.GameParams(stack=10, big_blind=2, small_blind=1)
        tree = Tree.build_game_tree(params, preflop_only=true, verbose=false)
        
        # Create CFR state with default config
        state = CFR.CFRState(tree)
        @test state.iteration == 0
        @test state.total_iterations == 0
        @test isinf(state.exploitability)
        @test isempty(state.convergence_history)
        @test state.config.use_cfr_plus == true
        
        # Create CFR state with custom config
        config = CFR.CFRConfig(use_cfr_plus=false)
        state2 = CFR.CFRState(tree, config)
        @test state2.config.use_cfr_plus == false
    end
    
    @testset "Information Set Management" begin
        params = GameTypes.GameParams(stack=10, big_blind=2, small_blind=1)
        tree = Tree.build_game_tree(params, preflop_only=true, verbose=false)
        state = CFR.CFRState(tree)
        
        # Get a player node from the tree
        player_node = nothing
        for node in tree.nodes
            if Tree.is_player_node(node) && length(node.children) > 0
                player_node = node
                break
            end
        end
        @test player_node !== nothing
        
        # Get or create information set for the node
        cfr_infoset = CFR.get_or_create_infoset_for_node(state, player_node)
        @test cfr_infoset !== nothing
        @test cfr_infoset.num_actions == length(player_node.children)
        @test all(cfr_infoset.regrets .== 0.0)
        
        # Get the same infoset again - should be cached
        cfr_infoset2 = CFR.get_or_create_infoset_for_node(state, player_node)
        @test cfr_infoset === cfr_infoset2
        
        # Check infoset count
        @test CFR.get_infoset_count(state) == 1
        
        # With hole cards
        hole_cards = [GameTypes.Card(14, 1), GameTypes.Card(13, 1)]  # AK suited
        cfr_infoset3 = CFR.get_or_create_infoset_for_node(state, player_node, hole_cards)
        @test cfr_infoset3 !== nothing
        @test occursin("AKs", cfr_infoset3.id)
        @test CFR.get_infoset_count(state) == 2  # Different infoset with cards
    end
    
    @testset "Regret Matching Strategy Computation" begin
        params = GameTypes.GameParams(stack=10, big_blind=2, small_blind=1)
        tree = Tree.build_game_tree(params, preflop_only=true, verbose=false)
        state = CFR.CFRState(tree)
        
        # Find a player node
        player_node = nothing
        for node in tree.nodes
            if Tree.is_player_node(node) && length(node.children) > 0
                player_node = node
                break
            end
        end
        
        # Get initial strategy (should be uniform)
        strategy = CFR.get_strategy(state, player_node)
        @test length(strategy) == length(player_node.children)
        @test all(strategy .≈ 1.0 / length(strategy))
        @test sum(strategy) ≈ 1.0
        
        # Manually set some regrets to test regret matching
        cfr_infoset = CFR.get_or_create_infoset_for_node(state, player_node)
        cfr_infoset.regrets = [3.0, 0.0, 1.0]  # Assuming 3 actions
        
        # Get strategy based on regrets
        strategy2 = CFR.get_strategy(state, player_node)
        @test strategy2[1] ≈ 3.0/4.0  # 3/(3+0+1)
        @test strategy2[2] ≈ 0.0/4.0
        @test strategy2[3] ≈ 1.0/4.0
        @test sum(strategy2) ≈ 1.0
    end
    
    @testset "Regret Updates" begin
        params = GameTypes.GameParams(stack=10, big_blind=2, small_blind=1)
        tree = Tree.build_game_tree(params, preflop_only=true, verbose=false)
        config = CFR.CFRConfig(use_cfr_plus=true)
        state = CFR.CFRState(tree, config)
        state.iteration = 1
        
        # Find a player node with 3 actions
        player_node = nothing
        for node in tree.nodes
            if Tree.is_player_node(node) && length(node.children) == 3
                player_node = node
                break
            end
        end
        
        if player_node !== nothing
            cfr_infoset = CFR.get_or_create_infoset_for_node(state, player_node)
            
            # Test regret update
            action_utilities = [5.0, 2.0, 3.0]
            node_utility = 3.0  # Utility of current strategy
            
            CFR.update_regrets!(state, cfr_infoset, action_utilities, node_utility)
            
            # With CFR+, negative regrets should be floored at 0
            @test cfr_infoset.regrets[1] ≈ 2.0  # 5.0 - 3.0
            @test cfr_infoset.regrets[2] ≈ 0.0  # 2.0 - 3.0 = -1.0 floored to 0
            @test cfr_infoset.regrets[3] ≈ 0.0  # 3.0 - 3.0
            @test cfr_infoset.last_iteration == 1
        end
    end
    
    @testset "Strategy Sum Updates" begin
        params = GameTypes.GameParams(stack=10, big_blind=2, small_blind=1)
        tree = Tree.build_game_tree(params, preflop_only=true, verbose=false)
        state = CFR.CFRState(tree)
        state.iteration = 1
        
        # Find a player node
        player_node = nothing
        for node in tree.nodes
            if Tree.is_player_node(node) && length(node.children) > 0
                player_node = node
                break
            end
        end
        
        cfr_infoset = CFR.get_or_create_infoset_for_node(state, player_node)
        
        # Update strategy sum
        strategy = [0.5, 0.3, 0.2]
        reach_prob = 0.1
        CFR.update_strategy_sum!(state, cfr_infoset, strategy, reach_prob)
        
        @test cfr_infoset.strategy_sum[1] ≈ 0.05  # 0.5 * 0.1
        @test cfr_infoset.strategy_sum[2] ≈ 0.03  # 0.3 * 0.1
        @test cfr_infoset.strategy_sum[3] ≈ 0.02  # 0.2 * 0.1
        
        # Get average strategy
        avg_strategy = CFR.get_average_strategy(state, player_node)
        total = sum(cfr_infoset.strategy_sum)
        @test avg_strategy[1] ≈ 0.05/total
        @test avg_strategy[2] ≈ 0.03/total
        @test avg_strategy[3] ≈ 0.02/total
        @test sum(avg_strategy) ≈ 1.0
    end
    
    @testset "Linear CFR Weighting" begin
        params = GameTypes.GameParams(stack=10, big_blind=2, small_blind=1)
        tree = Tree.build_game_tree(params, preflop_only=true, verbose=false)
        config = CFR.CFRConfig(use_linear_weighting=true)
        state = CFR.CFRState(tree, config)
        
        # Find a player node
        player_node = nothing
        for node in tree.nodes
            if Tree.is_player_node(node) && length(node.children) == 3
                player_node = node
                break
            end
        end
        
        if player_node !== nothing
            cfr_infoset = CFR.get_or_create_infoset_for_node(state, player_node)
            
            # Update with iteration 5
            state.iteration = 5
            strategy = [0.4, 0.3, 0.3]
            reach_prob = 0.1
            CFR.update_strategy_sum!(state, cfr_infoset, strategy, reach_prob)
            
            # With linear weighting, weight should be iteration * reach_prob
            expected_weight = 5 * 0.1
            @test cfr_infoset.strategy_sum[1] ≈ 0.4 * expected_weight
            @test cfr_infoset.strategy_sum[2] ≈ 0.3 * expected_weight
            @test cfr_infoset.strategy_sum[3] ≈ 0.3 * expected_weight
        end
    end
    
    @testset "Reset Functions" begin
        params = GameTypes.GameParams(stack=10, big_blind=2, small_blind=1)
        tree = Tree.build_game_tree(params, preflop_only=true, verbose=false)
        state = CFR.CFRState(tree)
        
        # Create a few information sets with data
        for node in tree.nodes[1:min(5, length(tree.nodes))]
            if Tree.is_player_node(node) && length(node.children) > 0
                cfr_infoset = CFR.get_or_create_infoset_for_node(state, node)
                cfr_infoset.regrets = [1.0, 2.0, 3.0]
                cfr_infoset.strategy_sum = [0.1, 0.2, 0.3]
            end
        end
        
        # Reset regrets
        CFR.reset_regrets!(state)
        for cfr_infoset in values(state.storage.infosets)
            @test all(cfr_infoset.regrets .== 0.0)
            @test !all(cfr_infoset.strategy_sum .== 0.0)  # Should not be reset
        end
        
        # Reset strategy sums
        CFR.reset_strategy_sum!(state)
        for cfr_infoset in values(state.storage.infosets)
            @test all(cfr_infoset.strategy_sum .== 0.0)
        end
    end
    
    @testset "Memory Usage and Statistics" begin
        params = GameTypes.GameParams(stack=10, big_blind=2, small_blind=1)
        tree = Tree.build_game_tree(params, preflop_only=true, verbose=false)
        state = CFR.CFRState(tree)
        
        # Initially should have no information sets
        @test CFR.get_infoset_count(state) == 0
        @test CFR.get_memory_usage(state) == 0  # No memory when empty
        
        # Create some information sets
        count = 0
        for node in tree.nodes
            if Tree.is_player_node(node) && length(node.children) > 0
                CFR.get_or_create_infoset_for_node(state, node)
                count += 1
                if count >= 3
                    break
                end
            end
        end
        
        @test CFR.get_infoset_count(state) == count
        @test CFR.get_memory_usage(state) > 0
    end
    
    @testset "Strategy for Terminal Nodes" begin
        params = GameTypes.GameParams(stack=10, big_blind=2, small_blind=1)
        tree = Tree.build_game_tree(params, preflop_only=true, verbose=false)
        state = CFR.CFRState(tree)
        
        # Find a terminal node
        terminal_node = nothing
        for node in tree.nodes
            if Tree.is_terminal_node(node)
                terminal_node = node
                break
            end
        end
        @test terminal_node !== nothing
        
        # Terminal nodes should return empty strategy
        strategy = CFR.get_strategy(state, terminal_node)
        @test isempty(strategy)
        
        avg_strategy = CFR.get_average_strategy(state, terminal_node)
        @test isempty(avg_strategy)
    end
    
    @testset "Pruning with Threshold" begin
        params = GameTypes.GameParams(stack=10, big_blind=2, small_blind=1)
        tree = Tree.build_game_tree(params, preflop_only=true, verbose=false)
        config = CFR.CFRConfig(prune_threshold=-10.0)
        state = CFR.CFRState(tree, config)
        
        # Find a player node with 3 actions
        player_node = nothing
        for node in tree.nodes
            if Tree.is_player_node(node) && length(node.children) == 3
                player_node = node
                break
            end
        end
        
        if player_node !== nothing
            cfr_infoset = CFR.get_or_create_infoset_for_node(state, player_node)
            
            # Set regrets with one below threshold
            cfr_infoset.regrets = [5.0, -15.0, 2.0]  # Middle action below -10
            
            strategy = CFR.compute_strategy_from_regrets(cfr_infoset, state.config)
            
            # Action 2 should be pruned (regret < -10)
            @test strategy[2] ≈ 0.0
            # Other actions should be renormalized
            @test strategy[1] ≈ 5.0/7.0  # 5/(5+2)
            @test strategy[3] ≈ 2.0/7.0
            @test sum(strategy) ≈ 1.0
        end
    end
    
    # Note: train! function is now tested in test_cfr_traversal.jl
    # since it's implemented in the CFRTraversal module
end
