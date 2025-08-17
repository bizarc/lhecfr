using Test
using LHECFR
using LHECFR.GameTypes
using LHECFR.Tree

@testset "Tree Memory Tests" begin
    params = GameTypes.GameParams()
    
    @testset "Compact Tree Representation" begin
        # Build a small tree for testing
        tree = Tree.build_game_tree(params, preflop_only=true, verbose=false)
        Tree.update_tree_statistics!(tree, verbose=false)
        
        # Compress the tree
        compact_tree = Tree.compress_tree(tree)
        
        @test compact_tree !== nothing
        @test compact_tree.num_nodes == tree.num_nodes
        @test compact_tree.num_player_nodes == tree.num_player_nodes
        @test compact_tree.num_terminal_nodes == tree.num_terminal_nodes
        @test compact_tree.num_infosets == tree.num_infosets
        
        # Check memory savings
        @test compact_tree.memory_used > 0
        @test length(compact_tree.nodes) == tree.num_nodes
        @test length(compact_tree.betting_histories) > 0
        
        # Decompress and verify
        decompressed_tree = Tree.decompress_tree(compact_tree, params)
        
        @test decompressed_tree.num_nodes == tree.num_nodes
        @test decompressed_tree.num_player_nodes == tree.num_player_nodes
        @test decompressed_tree.num_terminal_nodes == tree.num_terminal_nodes
        
        # Verify root properties match
        @test decompressed_tree.root.pot == tree.root.pot
        @test decompressed_tree.root.player == tree.root.player
        @test decompressed_tree.root.street == tree.root.street
    end
    
    @testset "Bit Packing/Unpacking" begin
        # Test packing and unpacking of node information
        player = UInt8(1)
        street = Tree.Flop
        terminal_type = 2
        facing_bet = true
        is_terminal = false
        num_children = 3
        betting_history_idx = UInt32(42)
        utilities_idx = UInt16(7)
        
        packed = Tree.TreeMemory.pack_node_info(
            player, street, terminal_type, facing_bet, is_terminal,
            num_children, betting_history_idx, utilities_idx
        )
        
        unpacked = Tree.TreeMemory.unpack_node_info(packed)
        
        @test unpacked[1] == player
        @test unpacked[2] == street
        @test unpacked[3] == terminal_type
        @test unpacked[4] == facing_bet
        @test unpacked[5] == is_terminal
        @test unpacked[6] == num_children
        @test unpacked[7] == betting_history_idx
        @test unpacked[8] == utilities_idx
    end
    
    @testset "Node Pool" begin
        pool = Tree.NodePool(100)
        
        @test pool.allocated == 0
        @test pool.max_size == 100
        
        # Allocate some nodes
        node1 = Tree.allocate_node!(pool,
            GameTypes.NodeId(1),
            Tree.PlayerNode,
            UInt8(0),
            Tree.Preflop,
            Float32(3.0),
            UInt8(0),
            false,
            nothing
        )
        
        @test node1 !== nothing
        @test pool.allocated == 1
        
        node2 = Tree.allocate_node!(pool,
            GameTypes.NodeId(2),
            Tree.PlayerNode,
            UInt8(1),
            Tree.Preflop,
            Float32(3.0),
            UInt8(0),
            false,
            nothing
        )
        
        @test pool.allocated == 2
        
        # Free a node
        Tree.free_node!(pool, node1)
        @test length(pool.free_indices) == 1
        
        # Allocate again - should reuse freed slot
        node3 = Tree.allocate_node!(pool,
            GameTypes.NodeId(3),
            Tree.PlayerNode,
            UInt8(0),
            Tree.Preflop,
            Float32(4.0),
            UInt8(0),
            false,
            nothing
        )
        
        @test pool.allocated == 2  # Should not increase
    end
    
    @testset "Lazy Tree Construction" begin
        # Create a lazy tree with limited expansion
        lazy_tree = Tree.LazyTree(params, expansion_depth=2, max_depth=5)
        
        @test lazy_tree !== nothing
        @test lazy_tree.root !== nothing
        @test lazy_tree.expansion_depth == 2
        @test lazy_tree.max_depth == 5
        @test lazy_tree.nodes_created > 0
        
        # Root should have children (expanded to depth 2)
        @test !isempty(lazy_tree.root.children)
        
        # Check that expansion stops at the specified depth
        function count_depth_nodes(node, depth, target_depth)
            if depth == target_depth
                return 1
            elseif depth > target_depth
                return 0
            end
            
            count = 0
            for child in node.children
                count += count_depth_nodes(child, depth + 1, target_depth)
            end
            return count
        end
        
        # Should have nodes at depth 0, 1, and 2
        @test count_depth_nodes(lazy_tree.root, 0, 0) == 1  # Root
        @test count_depth_nodes(lazy_tree.root, 0, 1) > 0  # Children
        @test count_depth_nodes(lazy_tree.root, 0, 2) > 0  # Grandchildren
        
        # Can manually expand nodes further
        if !isempty(lazy_tree.root.children)
            child = lazy_tree.root.children[1]
            if !isempty(child.children)
                grandchild = child.children[1]
                original_children = length(grandchild.children)
                Tree.expand_node!(lazy_tree, grandchild)
                # If not terminal, should have children after expansion
                if !grandchild.is_terminal
                    @test length(grandchild.children) >= original_children
                end
            end
        end
    end
    
    @testset "Tree Pruning" begin
        # Build a tree for pruning
        tree = Tree.build_game_tree(params, preflop_only=true, verbose=false)
        Tree.update_tree_statistics!(tree, verbose=false)
        
        original_nodes = tree.num_nodes
        
        # Prune by depth
        max_nodes = div(original_nodes, 2)  # Try to reduce to half
        Tree.prune_tree!(tree, max_nodes=max_nodes, strategy=:depth)
        
        # Should have fewer nodes after pruning
        @test tree.num_nodes <= original_nodes
        
        # Root should still exist
        @test tree.root !== nothing
        
        # All remaining non-terminal nodes should have valid children
        Tree.traverse_tree(tree, node -> begin
            if !node.is_terminal
                for child in node.children
                    @test child !== nothing
                    @test child.parent === node
                end
            end
        end)
    end
    
    @testset "Memory Statistics" begin
        tree = Tree.build_game_tree(params, preflop_only=true, verbose=false)
        Tree.update_tree_statistics!(tree, verbose=false)
        
        stats = Tree.memory_stats(tree)
        
        @test haskey(stats, :regular_memory)
        @test haskey(stats, :compact_memory)
        @test haskey(stats, :savings_percent)
        @test haskey(stats, :nodes)
        @test haskey(stats, :bytes_per_node)
        @test haskey(stats, :compact_bytes_per_node)
        
        @test stats[:regular_memory] > 0
        @test stats[:compact_memory] > 0
        @test stats[:compact_memory] < stats[:regular_memory]  # Should save memory
        @test stats[:savings_percent] > 0  # Should have some savings
        @test stats[:nodes] == tree.num_nodes
        @test stats[:bytes_per_node] > stats[:compact_bytes_per_node]
    end
    
    @testset "Large Tree Memory Test" begin
        # Build a slightly larger tree to test memory efficiency
        tree = Tree.build_game_tree(params, preflop_only=false, verbose=false)
        Tree.update_tree_statistics!(tree, verbose=false)
        
        if tree.num_nodes > 100  # Only test if we have a decent-sized tree
            stats = Tree.memory_stats(tree)
            
            # Compact representation should provide significant savings
            @test stats[:savings_percent] > 30  # At least 30% savings
            
            # Test compression/decompression preserves tree structure
            compact = Tree.compress_tree(tree)
            decompressed = Tree.decompress_tree(compact, params)
            
            # Spot check some nodes
            @test length(decompressed.nodes) == length(tree.nodes)
            @test decompressed.root.pot == tree.root.pot
            
            # Check that terminal nodes are preserved
            original_terminals = filter(n -> n.is_terminal, tree.nodes)
            decompressed_terminals = filter(n -> n.is_terminal, decompressed.nodes)
            @test length(decompressed_terminals) == length(original_terminals)
        end
    end
    
    @testset "Edge Cases" begin
        # Test with minimal tree
        minimal_tree = Tree.GameTree(params)
        @test minimal_tree.root !== nothing
        
        compact = Tree.compress_tree(minimal_tree)
        @test length(compact.nodes) == 1
        @test compact.num_nodes == 1
        
        # Test lazy tree with depth 0 (root only)
        lazy_minimal = Tree.LazyTree(params, expansion_depth=0, max_depth=1)
        @test lazy_minimal.root !== nothing
        @test lazy_minimal.nodes_created == 1
        
        # Test pruning on already small tree
        small_tree = Tree.GameTree(params)
        Tree.prune_tree!(small_tree, max_nodes=1000, strategy=:depth)
        @test small_tree.num_nodes == 1  # Should remain unchanged
    end
end
