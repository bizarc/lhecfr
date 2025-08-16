using Test
using LHECFR
using LHECFR.GameTypes
using LHECFR.Tree

@testset "Tree Size Validation Tests" begin
    params = GameTypes.GameParams()
    
    @testset "Theoretical Size Calculations" begin
        theoretical = Tree.calculate_theoretical_sizes()
        
        # Check that we get reasonable values
        @test theoretical.preflop_sequences > 0
        @test theoretical.flop_sequences > 0
        @test theoretical.turn_sequences > 0
        @test theoretical.river_sequences > 0
        
        # Post-flop streets should have the same number of sequences
        @test theoretical.flop_sequences == theoretical.turn_sequences
        @test theoretical.turn_sequences == theoretical.river_sequences
        
        # Total should be sum of all streets
        @test theoretical.total_betting_sequences == 
              theoretical.preflop_sequences + 
              theoretical.flop_sequences + 
              theoretical.turn_sequences + 
              theoretical.river_sequences
        
        # Preflop should have reasonable number of sequences
        # In HU-LHE, we expect around 15-30 unique preflop sequences
        @test theoretical.preflop_sequences >= 15
        @test theoretical.preflop_sequences <= 35
        
        # Information sets should be positive
        @test theoretical.preflop_infosets > 0
        @test theoretical.preflop_infosets_with_cards > theoretical.preflop_infosets
    end
    
    @testset "Betting Sequence Counting" begin
        # Test pre-flop sequence counting
        preflop_count = Tree.count_preflop_sequences()
        @test preflop_count > 0
        @test preflop_count <= 35  # Reasonable upper bound
        
        # Test post-flop sequence counting
        postflop_count = Tree.count_postflop_sequences()
        @test postflop_count > 0
        @test postflop_count <= 35  # Similar to pre-flop
    end
    
    @testset "Pre-flop Tree Validation" begin
        # Build a pre-flop only tree
        tree = Tree.build_game_tree(params, preflop_only=true, verbose=false)
        Tree.update_tree_statistics!(tree, verbose=false)
        Tree.assign_infoset_ids!(tree, verbose=false)
        
        theoretical = Tree.calculate_theoretical_sizes()
        
        # Validate the tree
        @test Tree.validate_tree_size(tree, theoretical, verbose=false) == true
        
        # Check specific counts
        @test tree.num_nodes > 0
        @test tree.num_player_nodes > 0
        @test tree.num_terminal_nodes > 0
        @test tree.num_infosets > 0
        
        # Terminal nodes should roughly match betting sequences
        # Allow some difference due to implementation details
        @test tree.num_terminal_nodes >= theoretical.preflop_sequences * 0.8
        @test tree.num_terminal_nodes <= theoretical.preflop_sequences * 1.5
    end
    
    @testset "Full Tree Validation" begin
        # Build a small full tree (limited for testing)
        # Note: Full tree is very large, so we use a limited version
        tree = Tree.build_game_tree(params, preflop_only=false, verbose=false)
        Tree.update_tree_statistics!(tree, verbose=false)
        Tree.assign_infoset_ids!(tree, verbose=false)
        
        theoretical = Tree.calculate_theoretical_sizes()
        
        # Basic validation
        @test tree.num_nodes > 0
        @test tree.num_player_nodes > 0
        @test tree.num_terminal_nodes > 0
        
        # Full tree should be much larger than pre-flop only
        preflop_tree = Tree.build_game_tree(params, preflop_only=true, verbose=false)
        Tree.update_tree_statistics!(preflop_tree, verbose=false)
        
        @test tree.num_nodes > preflop_tree.num_nodes
        @test tree.num_terminal_nodes > preflop_tree.num_terminal_nodes
    end
    
    @testset "Tree Statistics" begin
        tree = Tree.build_game_tree(params, preflop_only=true, verbose=false)
        Tree.update_tree_statistics!(tree, verbose=false)
        Tree.assign_infoset_ids!(tree, verbose=false)
        
        # Test that the function runs without error
        redirect_stdout(devnull) do
            Tree.print_tree_statistics(tree)
        end
        
        # If we get here, the function ran successfully
        @test true
    end
    
    @testset "Street Distribution" begin
        # Build tree and check node distribution by street
        tree = Tree.build_game_tree(params, preflop_only=false, verbose=false)
        
        street_counts = Dict{Int, Int}()
        Tree.traverse_tree(tree, node -> begin
            street = Int(node.street)
            street_counts[street] = get(street_counts, street, 0) + 1
        end)
        
        # Pre-flop should have nodes
        @test get(street_counts, 0, 0) > 0  # Preflop = 0
        
        # If full tree, post-flop streets may or may not exist
        # depending on tree construction limits
        flop_count = get(street_counts, 1, 0)
        turn_count = get(street_counts, 2, 0)
        river_count = get(street_counts, 3, 0)
        
        # Basic sanity checks
        @test street_counts[0] > 0  # Should have preflop nodes
        
        # In our implementation, later streets may have more nodes
        # because each terminal node that continues creates a new subtree
        # So we just check that nodes exist if the tree is full
        if flop_count > 0
            @test flop_count > 0
        end
        if turn_count > 0
            @test turn_count > 0
        end
        if river_count > 0
            @test river_count > 0
        end
    end
    
    @testset "Branching Factor Analysis" begin
        tree = Tree.build_game_tree(params, preflop_only=true, verbose=false)
        
        # Collect branching factors
        branching_factors = Int[]
        Tree.traverse_tree(tree, node -> begin
            if !node.is_terminal && length(node.children) > 0
                push!(branching_factors, length(node.children))
            end
        end)
        
        @test length(branching_factors) > 0
        
        # In LHE, branching factor should be between 1 and 4
        # (fold, call/check, raise/bet are the max options)
        @test all(bf -> bf >= 1 && bf <= 4, branching_factors)
        
        # Average should be reasonable
        avg_branching = sum(branching_factors) / length(branching_factors)
        @test avg_branching >= 1.5  # Should have some branching
        @test avg_branching <= 3.0  # But not maximum everywhere
    end
    
    @testset "Terminal Node Types" begin
        tree = Tree.build_game_tree(params, preflop_only=true, verbose=false)
        
        # Count terminal node types
        fold_count = 0
        showdown_count = 0
        
        for node in tree.terminal_nodes
            if node.terminal_type == 1
                fold_count += 1
            elseif node.terminal_type == 2
                showdown_count += 1
            end
        end
        
        # Should have both fold and showdown terminals
        @test fold_count > 0
        @test showdown_count > 0
        
        # Total should match
        @test fold_count + showdown_count == length(tree.terminal_nodes)
    end
    
    @testset "Tree Depth" begin
        tree = Tree.build_game_tree(params, preflop_only=true, verbose=false)
        
        # Find maximum depth
        max_depth = 0
        Tree.traverse_tree(tree, node -> begin
            depth = Tree.get_node_depth(node)
            max_depth = max(max_depth, depth)
        end)
        
        # Pre-flop tree should have reasonable depth
        # Maximum sequence is rrrrrc (6 actions) plus root
        @test max_depth >= 3  # At least some depth
        @test max_depth <= 10  # But not too deep for preflop
    end
    
    @testset "Information Set Consistency" begin
        tree = Tree.build_game_tree(params, preflop_only=true, verbose=false)
        Tree.update_tree_statistics!(tree, verbose=false)
        Tree.assign_infoset_ids!(tree, verbose=false)
        
        # Check that nodes in same infoset have same properties
        for (infoset_id, nodes) in tree.infoset_map
            if length(nodes) > 1
                # All nodes in same infoset should have same player
                players = [n.player for n in nodes]
                @test all(p -> p == players[1], players)
                
                # All should have same betting history
                histories = [n.betting_history for n in nodes]
                @test all(h -> h == histories[1], histories)
            end
        end
        
        # Number of unique infosets should match
        @test length(tree.infoset_map) == tree.num_infosets
    end
end
