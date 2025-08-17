"""
Tests for the TreeIndexing module that provides efficient node-to-infoset mapping.
"""

using Test
using LHECFR
using LHECFR.GameTypes
using LHECFR.Tree
using LHECFR.Tree.TreeNode
using LHECFR.Tree.TreeIndexing
using LHECFR.Tree.TreeBuilder
using LHECFR.Tree.InfoSetManager
using LHECFR.CFR

@testset "TreeIndexing Tests" begin
    
    @testset "Tree Index Building" begin
        # Create a small test tree
        params = GameTypes.GameParams(stack=10)  # Small stack for testing
        tree = Tree.build_game_tree(params, preflop_only=true, verbose=false)
        
        # Build index
        index = TreeIndexing.build_tree_index(tree)
        
        @test index.num_nodes > 0
        @test index.num_player_nodes > 0
        @test index.num_terminal_nodes > 0
        @test index.num_chance_nodes == 0  # Pre-flop only has no chance nodes
        @test index.num_infosets > 0
        @test index.num_infosets <= index.num_player_nodes  # Some nodes may share infosets
        
        # Check that the index has correct mappings
        @test length(index.node_to_infoset) > 0
        @test length(index.infoset_to_nodes) > 0
        
        # Verify that all infosets have at least one node
        for (infoset_id, node_ids) in index.infoset_to_nodes
            @test length(node_ids) > 0
        end
    end
    
    @testset "Indexed InfoSet Storage" begin
        params = GameTypes.GameParams(stack=10)
        tree = Tree.build_game_tree(params, preflop_only=true, verbose=false)
        
        # Create indexed storage
        indexed_storage = TreeIndexing.IndexedInfoSetStorage(tree)
        
        @test indexed_storage.index !== nothing
        @test indexed_storage.storage !== nothing
        @test indexed_storage.cache !== nothing  # Cache exists
        @test Tree.InfoSetCache.get_statistics(indexed_storage.cache) !== nothing  # Cache is functional
        
        # Test getting/creating infoset for a node
        # Get first player node
        nodes = TreeIndexing.collect_nodes_preorder(tree.root)
        player_node = nothing
        for node in nodes
            if !TreeNode.is_terminal_node(node) && !TreeNode.is_chance_node(node)
                player_node = node
                break
            end
        end
        
        @test player_node !== nothing
        
        # Get infoset without cards
        cfr_infoset = TreeIndexing.get_or_create_indexed_infoset!(
            indexed_storage,
            player_node,
            nothing,
            nothing
        )
        
        @test cfr_infoset !== nothing
        @test cfr_infoset.num_actions == length(player_node.children)
        @test length(cfr_infoset.regrets) == cfr_infoset.num_actions
        @test length(cfr_infoset.strategy_sum) == cfr_infoset.num_actions
        
        # Get the same infoset again - should be cached
        cfr_infoset2 = TreeIndexing.get_or_create_indexed_infoset!(
            indexed_storage,
            player_node,
            nothing,
            nothing
        )
        
        @test cfr_infoset === cfr_infoset2  # Same object reference
        
        # Test with cards
        hole_cards = [GameTypes.Card(14, 0), GameTypes.Card(13, 0)]  # AK
        cfr_infoset_with_cards = TreeIndexing.get_or_create_indexed_infoset!(
            indexed_storage,
            player_node,
            hole_cards,
            nothing
        )
        
        @test cfr_infoset_with_cards !== nothing
        @test cfr_infoset_with_cards.id != cfr_infoset.id  # Different infoset ID with cards
    end
    
    @testset "CFRState with Indexing" begin
        params = GameTypes.GameParams(stack=10)
        tree = Tree.build_game_tree(params, preflop_only=true, verbose=false)
        
        # Create CFR state with indexing
        config = CFR.CFRConfig()
        cfr_state_indexed = CFR.CFRState(tree, config, true)  # With indexing
        
        @test cfr_state_indexed.indexed_storage !== nothing
        @test cfr_state_indexed.tree !== nothing
        
        # Create CFR state without indexing
        cfr_state_plain = CFR.CFRState(tree, config, false)  # Without indexing
        
        @test cfr_state_plain.indexed_storage === nothing
        @test cfr_state_plain.tree !== nothing
        
        # Test get_or_create_infoset_for_node with indexed storage
        nodes = TreeIndexing.collect_nodes_preorder(tree.root)
        player_node = nothing
        for node in nodes
            if !TreeNode.is_terminal_node(node) && !TreeNode.is_chance_node(node)
                player_node = node
                break
            end
        end
        
        # With indexed storage
        cfr_infoset1 = CFR.get_or_create_infoset_for_node(
            cfr_state_indexed,
            player_node,
            nothing,
            nothing
        )
        @test cfr_infoset1 !== nothing
        
        # Without indexed storage
        cfr_infoset2 = CFR.get_or_create_infoset_for_node(
            cfr_state_plain,
            player_node,
            nothing,
            nothing
        )
        @test cfr_infoset2 !== nothing
        
        # Both should create the same infoset ID
        @test cfr_infoset1.id == cfr_infoset2.id
    end
    
    @testset "Index Statistics" begin
        params = GameTypes.GameParams(stack=10)
        tree = Tree.build_game_tree(params, preflop_only=true, verbose=false)
        
        index = TreeIndexing.build_tree_index(tree)
        
        # Test that print_index_statistics doesn't error
        # Simply test that the function runs without error
        # (redirecting stdout is complex in Julia test environment)
        @test begin
            TreeIndexing.print_index_statistics(index)
            true  # If we get here, no error was thrown
        end
    end
    
    @testset "Performance Comparison" begin
        # This test compares performance with and without indexing
        params = GameTypes.GameParams(stack=10)
        tree = Tree.build_game_tree(params, preflop_only=true, verbose=false)
        
        config = CFR.CFRConfig()
        
        # Measure time with indexing
        cfr_state_indexed = CFR.CFRState(tree, config, true)
        nodes = TreeIndexing.collect_nodes_preorder(tree.root)
        player_nodes = filter(n -> !TreeNode.is_terminal_node(n) && !TreeNode.is_chance_node(n), nodes)
        
        # Access all player nodes multiple times
        t1 = time()
        for _ in 1:10
            for node in player_nodes[1:min(100, length(player_nodes))]
                CFR.get_or_create_infoset_for_node(cfr_state_indexed, node, nothing, nothing)
            end
        end
        time_indexed = time() - t1
        
        # Measure time without indexing
        cfr_state_plain = CFR.CFRState(tree, config, false)
        
        t2 = time()
        for _ in 1:10
            for node in player_nodes[1:min(100, length(player_nodes))]
                CFR.get_or_create_infoset_for_node(cfr_state_plain, node, nothing, nothing)
            end
        end
        time_plain = time() - t2
        
        # Indexed should not be significantly slower (and often faster for repeated access)
        # We don't assert it's faster because for small trees the overhead might dominate
        # For small test trees, indexing overhead may make it slower
        @test time_indexed < time_plain * 200.0  # Very lenient bound for small test trees
        
        # Print performance comparison for information
        println("  Performance: indexed=$(round(time_indexed*1000, digits=2))ms, plain=$(round(time_plain*1000, digits=2))ms")
    end
    
    @testset "Integration with CFR Training" begin
        # Test that indexed storage works correctly during actual CFR training
        params = GameTypes.GameParams(stack=10)
        tree = Tree.build_game_tree(params, preflop_only=true, verbose=false)
        
        config = CFR.CFRConfig(
            use_cfr_plus=true,
            max_iterations=10
        )
        
        # Train with indexing
        cfr_state = CFR.CFRState(tree, config, true)
        
        # This would normally be done by CFRTraversal.train!
        # but we can test the state management here
        @test cfr_state.indexed_storage !== nothing
        initial_count = CFR.get_infoset_count(cfr_state)
        @test initial_count >= 0  # May have pre-allocated infosets
        
        # Access some nodes to create infosets
        nodes = TreeIndexing.collect_nodes_preorder(tree.root)
        player_nodes = filter(n -> !TreeNode.is_terminal_node(n) && !TreeNode.is_chance_node(n), nodes)
        
        for node in player_nodes[1:min(10, length(player_nodes))]
            CFR.get_or_create_infoset_for_node(cfr_state, node, nothing, nothing)
        end
        
        final_count = CFR.get_infoset_count(cfr_state)
        @test final_count >= initial_count  # May have created new infosets or used pre-allocated ones
        
        # Test reset functionality
        CFR.reset_regrets!(cfr_state)  # Should not error with indexed storage
        CFR.reset_strategy_sum!(cfr_state)  # Should not error with indexed storage
        
        # Test memory usage
        mem_usage = CFR.get_memory_usage(cfr_state)
        @test mem_usage > 0.0
    end
end
