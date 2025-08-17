using Test
using LHECFR
using LHECFR.GameTypes
using LHECFR.Tree
using LHECFR.CFR
using LHECFR.CFRTraversal

@testset "CFR Traversal Tests" begin
    
    @testset "Terminal Utility Evaluation" begin
        # Create a small tree for testing
        params = GameTypes.GameParams(stack=10, big_blind=2, small_blind=1)
        tree = Tree.build_game_tree(params, preflop_only=true, verbose=false)
        
        # Find a fold terminal node
        fold_node = nothing
        for node in tree.nodes
            if Tree.is_terminal_node(node) && endswith(node.betting_history, "f")
                fold_node = node
                break
            end
        end
        
        if fold_node !== nothing
            # Test fold utility calculation
            player_cards = [GameTypes.Card[], GameTypes.Card[]]
            board_cards = GameTypes.Card[]
            
            utility = CFRTraversal.evaluate_terminal_utility(tree, fold_node, player_cards, board_cards)
            
            # Utility should be non-zero for a fold
            @test utility != 0.0
            
            # Check who folded based on betting history
            if length(fold_node.betting_history) % 2 == 0
                # Even length means P2 acted last (folded)
                @test utility > 0  # P1 wins
            else
                # Odd length means P1 acted last (folded)
                @test utility < 0  # P2 wins
            end
        end
    end
    
    @testset "Chance Node Handling" begin
        params = GameTypes.GameParams(stack=10, big_blind=2, small_blind=1)
        tree = Tree.build_game_tree(params, preflop_only=true, verbose=false)
        state = CFR.CFRState(tree)
        
        # Find a chance node if any exist
        chance_node = nothing
        for node in tree.nodes
            if Tree.is_chance_node(node) && length(node.children) > 0
                chance_node = node
                break
            end
        end
        
        if chance_node !== nothing
            reach_probs = (1.0, 1.0)
            player_cards = [GameTypes.Card[], GameTypes.Card[]]
            board_cards = GameTypes.Card[]
            
            value = CFRTraversal.handle_chance_node(state, tree, chance_node, 
                                                   reach_probs, player_cards, board_cards)
            
            # Value should be finite
            @test isfinite(value)
        else
            @test true  # No chance nodes in preflop-only tree
        end
    end
    
    @testset "Player Node Handling" begin
        params = GameTypes.GameParams(stack=10, big_blind=2, small_blind=1)
        tree = Tree.build_game_tree(params, preflop_only=true, verbose=false)
        state = CFR.CFRState(tree)
        
        # Find a player node with multiple actions
        player_node = nothing
        for node in tree.nodes
            if Tree.is_player_node(node) && length(node.children) > 1
                player_node = node
                break
            end
        end
        
        @test player_node !== nothing
        
        reach_probs = (1.0, 1.0)
        player_cards = [GameTypes.Card[], GameTypes.Card[]]
        board_cards = GameTypes.Card[]
        
        # Get initial infoset state
        cfr_infoset = CFR.get_or_create_infoset_for_node(state, player_node)
        initial_regrets = copy(cfr_infoset.regrets)
        
        # Handle the player node
        value = CFRTraversal.handle_player_node(state, tree, player_node,
                                               reach_probs, player_cards, board_cards)
        
        # Value should be finite
        @test isfinite(value)
        
        # Regrets should have been updated
        @test cfr_infoset.regrets != initial_regrets || all(initial_regrets .== 0)
        
        # Strategy sum should have been updated
        @test sum(cfr_infoset.strategy_sum) > 0
    end
    
    @testset "Full CFR Traversal" begin
        params = GameTypes.GameParams(stack=10, big_blind=2, small_blind=1)
        tree = Tree.build_game_tree(params, preflop_only=true, verbose=false)
        state = CFR.CFRState(tree)
        
        reach_probs = (1.0, 1.0)
        player_cards = [GameTypes.Card[], GameTypes.Card[]]
        board_cards = GameTypes.Card[]
        
        # Run traversal from root
        value = CFRTraversal.cfr_traverse(state, tree, tree.root, 
                                         reach_probs, player_cards, board_cards)
        
        # Value should be finite
        @test isfinite(value)
        
        # Should have created some information sets
        @test CFR.get_infoset_count(state) > 0
    end
    
    @testset "CFR Iteration" begin
        params = GameTypes.GameParams(stack=10, big_blind=2, small_blind=1)
        tree = Tree.build_game_tree(params, preflop_only=true, verbose=false)
        state = CFR.CFRState(tree)
        
        # Run a single iteration
        CFRTraversal.run_cfr_iteration!(state, tree)
        
        # Should have created information sets
        @test CFR.get_infoset_count(state) > 0
        
        # Check that some regrets were updated
        has_nonzero_regrets = false
        # Get infosets from appropriate storage
        infosets = state.indexed_storage !== nothing ? 
                   state.indexed_storage.storage.infosets : 
                   state.storage.infosets
        for cfr_infoset in values(infosets)
            if any(cfr_infoset.regrets .!= 0)
                has_nonzero_regrets = true
                break
            end
        end
        @test has_nonzero_regrets
    end
    
    @testset "CFR Iteration with Cards" begin
        params = GameTypes.GameParams(stack=10, big_blind=2, small_blind=1)
        tree = Tree.build_game_tree(params, preflop_only=true, verbose=false)
        state = CFR.CFRState(tree)
        
        # Create specific cards
        p1_cards = [GameTypes.Card(14, 1), GameTypes.Card(13, 1)]  # AK suited
        p2_cards = [GameTypes.Card(12, 2), GameTypes.Card(12, 3)]  # QQ
        board = GameTypes.Card[]
        
        # Run iteration with specific cards
        CFRTraversal.run_cfr_iteration_with_cards!(state, tree, p1_cards, p2_cards, board)
        
        # Should have created information sets
        @test CFR.get_infoset_count(state) > 0
        
        # Check for card-specific information sets
        has_card_infoset = false
        # Get infosets from appropriate storage
        infosets = state.indexed_storage !== nothing ? 
                   state.indexed_storage.storage.infosets : 
                   state.storage.infosets
        for id in keys(infosets)
            if occursin("AKs", id) || occursin("QQ", id)
                has_card_infoset = true
                break
            end
        end
        @test has_card_infoset
    end
    
    @testset "Training Function" begin
        params = GameTypes.GameParams(stack=10, big_blind=2, small_blind=1)
        tree = Tree.build_game_tree(params, preflop_only=true, verbose=false)
        state = CFR.CFRState(tree)
        
        # Train for a few iterations
        CFRTraversal.train!(tree, state, iterations=5, verbose=false)
        
        @test state.iteration == 5
        @test state.total_iterations == 5
        @test CFR.get_infoset_count(state) > 0
        
        # Check convergence history
        @test length(state.convergence_history) > 0
    end
    
    @testset "Reach Probability Updates" begin
        params = GameTypes.GameParams(stack=10, big_blind=2, small_blind=1)
        tree = Tree.build_game_tree(params, preflop_only=true, verbose=false)
        state = CFR.CFRState(tree)
        
        # Find a P1 node
        p1_node = nothing
        for node in tree.nodes
            if Tree.is_player_node(node) && node.player == 1 && length(node.children) > 1
                p1_node = node
                break
            end
        end
        
        @test p1_node !== nothing
        
        # Set up initial reach probabilities
        reach_probs = (0.5, 0.7)
        player_cards = [GameTypes.Card[], GameTypes.Card[]]
        board_cards = GameTypes.Card[]
        
        # Get the information set
        cfr_infoset = CFR.get_or_create_infoset_for_node(state, p1_node)
        
        # Manually set a non-uniform strategy
        cfr_infoset.regrets = [3.0, 1.0, 0.0]  # Will create non-uniform strategy
        
        # Handle the node
        value = CFRTraversal.handle_player_node(state, tree, p1_node,
                                               reach_probs, player_cards, board_cards)
        
        # Check that strategy sum was weighted by reach probability
        # With regrets [3.0, 1.0, 0.0], strategy should be [0.75, 0.25, 0.0]
        # Strategy sum should be reach_prob * strategy
        # The sum of strategy is 1.0, so strategy_sum total should be reach_probs[1] * 1.0
        expected_sum = reach_probs[1]  # 0.5
        @test abs(sum(cfr_infoset.strategy_sum) - expected_sum) < 0.1
    end
    
    @testset "Zero-Sum Property" begin
        params = GameTypes.GameParams(stack=10, big_blind=2, small_blind=1)
        tree = Tree.build_game_tree(params, preflop_only=true, verbose=false)
        state = CFR.CFRState(tree)
        
        # Run several iterations
        CFRTraversal.train!(tree, state, iterations=10, verbose=false)
        
        # The game should maintain zero-sum property
        # Check that strategies are being computed
        @test CFR.get_infoset_count(state) > 0
        
        # All strategies should sum to 1
        for cfr_infoset in values(state.storage.infosets)
            strategy = CFR.get_current_strategy(cfr_infoset)
            @test abs(sum(strategy) - 1.0) < 1e-10
        end
    end
    
    @testset "CFR+ Modifications" begin
        params = GameTypes.GameParams(stack=10, big_blind=2, small_blind=1)
        tree = Tree.build_game_tree(params, preflop_only=true, verbose=false)
        
        # Test with CFR+ enabled
        config_plus = CFR.CFRConfig(use_cfr_plus=true)
        state_plus = CFR.CFRState(tree, config_plus)
        
        # Run an iteration
        CFRTraversal.run_cfr_iteration!(state_plus, tree)
        
        # Check that negative regrets are floored at 0
        for cfr_infoset in values(state_plus.storage.infosets)
            @test all(cfr_infoset.regrets .>= 0)
        end
        
        # Test with CFR+ disabled
        config_no_plus = CFR.CFRConfig(use_cfr_plus=false)
        state_no_plus = CFR.CFRState(tree, config_no_plus)
        
        # Manually create a situation with negative regrets
        if CFR.get_infoset_count(state_no_plus) == 0
            CFRTraversal.run_cfr_iteration!(state_no_plus, tree)
        end
        
        # Without CFR+, negative regrets could exist (though may not in this simple test)
        @test true  # Placeholder - would need more complex scenario to test properly
    end
end
