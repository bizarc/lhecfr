using Test
using LHECFR
using LHECFR.GameTypes
using LHECFR.Tree

@testset "Tree Traversal Tests" begin
    params = GameTypes.GameParams()
    
    # Build a small test tree
    tree = Tree.build_game_tree(params, preflop_only=true, verbose=false)
    Tree.update_tree_statistics!(tree, verbose=false)
    Tree.assign_infoset_ids!(tree, verbose=false)
    
    @testset "Basic Traversal Orders" begin
        # Test pre-order traversal (default)
        preorder_nodes = Tree.GameNode[]
        Tree.traverse_tree(tree, node -> push!(preorder_nodes, node))
        @test length(preorder_nodes) == tree.num_nodes
        @test preorder_nodes[1] === tree.root  # Root should be first in pre-order
        
        # Test explicit pre-order
        preorder_explicit = Tree.GameNode[]
        Tree.traverse_tree(tree, node -> push!(preorder_explicit, node), order=Tree.PreOrder)
        @test preorder_nodes == preorder_explicit
        
        # Test post-order traversal
        postorder_nodes = Tree.GameNode[]
        Tree.traverse_tree(tree, node -> push!(postorder_nodes, node), order=Tree.PostOrder)
        @test length(postorder_nodes) == tree.num_nodes
        # In post-order, all children should appear before their parent
        for (i, node) in enumerate(postorder_nodes)
            for child in node.children
                child_idx = findfirst(n -> n === child, postorder_nodes)
                @test child_idx !== nothing
                @test child_idx < i  # Child should appear before parent
            end
        end
        
        # Test level-order (breadth-first) traversal
        levelorder_nodes = Tree.GameNode[]
        Tree.traverse_tree(tree, node -> push!(levelorder_nodes, node), order=Tree.LevelOrder)
        @test length(levelorder_nodes) == tree.num_nodes
        @test levelorder_nodes[1] === tree.root
        
        # Verify level-order property: nodes at depth d appear before nodes at depth d+1
        for i in 1:length(levelorder_nodes)-1
            depth_i = Tree.get_node_depth(levelorder_nodes[i])
            depth_next = Tree.get_node_depth(levelorder_nodes[i+1])
            @test depth_next >= depth_i
            @test depth_next <= depth_i + 1
        end
    end
    
    @testset "Filtered Traversal" begin
        # Test player node traversal
        player_nodes = Tree.GameNode[]
        Tree.traverse_player_nodes(tree, node -> push!(player_nodes, node))
        @test all(node -> Tree.is_player_node(node) && !node.is_terminal, player_nodes)
        @test length(player_nodes) == tree.num_player_nodes
        
        # Test player-specific traversal
        p0_nodes = Tree.GameNode[]
        Tree.traverse_player_nodes(tree, node -> push!(p0_nodes, node), player=UInt8(0))
        @test all(node -> node.player == 0 && !node.is_terminal, p0_nodes)
        
        p1_nodes = Tree.GameNode[]
        Tree.traverse_player_nodes(tree, node -> push!(p1_nodes, node), player=UInt8(1))
        @test all(node -> node.player == 1 && !node.is_terminal, p1_nodes)
        
        # Player 0 and 1 nodes should be disjoint and sum to total player nodes
        @test length(p0_nodes) + length(p1_nodes) == length(player_nodes)
        
        # Test terminal node traversal
        terminal_nodes = Tree.GameNode[]
        Tree.traverse_terminal_nodes(tree, node -> push!(terminal_nodes, node))
        @test all(node -> node.is_terminal, terminal_nodes)
        @test length(terminal_nodes) == tree.num_terminal_nodes
        
        # Test custom filter
        high_pot_nodes = Tree.GameNode[]
        Tree.traverse_filtered(tree, 
            node -> push!(high_pot_nodes, node),
            node -> node.pot > 4.0f0)
        @test all(node -> node.pot > 4.0f0, high_pot_nodes)
    end
    
    @testset "Node Search" begin
        # Test find_node
        target_pot = 6.0f0
        found = Tree.find_node(tree, node -> node.pot == target_pot)
        if found !== nothing
            @test found.pot == target_pot
        end
        
        # Test find_all_nodes
        all_terminals = Tree.find_all_nodes(tree, node -> node.is_terminal)
        @test length(all_terminals) == tree.num_terminal_nodes
        @test all(node -> node.is_terminal, all_terminals)
        
        # Test find_node_by_id
        if !isempty(tree.nodes)
            test_id = tree.nodes[div(length(tree.nodes), 2)].id
            found_by_id = Tree.find_node_by_id(tree, test_id)
            @test found_by_id !== nothing
            @test found_by_id.id == test_id
        end
        
        # Test find_nodes_by_infoset
        if !isempty(tree.infoset_map)
            test_infoset_id = first(keys(tree.infoset_map))
            nodes_in_infoset = Tree.find_nodes_by_infoset(tree, test_infoset_id)
            @test !isempty(nodes_in_infoset)
            @test all(node -> node.infoset_id == test_infoset_id, nodes_in_infoset)
        end
    end
    
    @testset "Path Finding" begin
        # Find a terminal node for testing
        terminal = Tree.find_node(tree, node -> node.is_terminal)
        @test terminal !== nothing
        
        if terminal !== nothing
            # Test find_path
            path = Tree.find_path(tree, terminal)
            @test !isempty(path)
            @test path[1] === tree.root
            @test path[end] === terminal
            
            # Verify path connectivity
            for i in 1:length(path)-1
                @test path[i+1] in path[i].children
            end
            
            # Test find_path_to_id
            path_by_id = Tree.find_path_to_id(tree, terminal.id)
            @test path == path_by_id
            
            # Test get_ancestors
            if length(path) > 1
                test_node = path[end-1]  # Parent of terminal
                ancestors = Tree.get_ancestors(test_node)
                @test length(ancestors) == length(path) - 2  # Exclude test_node and its child
                if !isempty(ancestors)
                    @test ancestors[1] === tree.root
                end
            end
        end
        
        # Test path to non-existent node
        fake_path = Tree.find_path_to_id(tree, GameTypes.NodeId(999999))
        @test isempty(fake_path)
    end
    
    @testset "Sibling Relationships" begin
        # Find a node with siblings
        node_with_siblings = Tree.find_node(tree, 
            node -> node.parent !== nothing && length(node.parent.children) > 1)
        
        if node_with_siblings !== nothing
            siblings = Tree.get_siblings(node_with_siblings)
            @test node_with_siblings ∉ siblings
            @test all(sib -> sib.parent === node_with_siblings.parent, siblings)
            @test length(siblings) == length(node_with_siblings.parent.children) - 1
        end
        
        # Root has no siblings
        root_siblings = Tree.get_siblings(tree.root)
        @test isempty(root_siblings)
    end
    
    @testset "Subtree Analysis" begin
        # Test subtree size
        root_size = Tree.get_subtree_size(tree.root)
        @test root_size == tree.num_nodes
        
        # Terminal nodes have subtree size 1
        terminal = Tree.find_node(tree, node -> node.is_terminal)
        if terminal !== nothing
            @test Tree.get_subtree_size(terminal) == 1
        end
        
        # Test subtree depth
        root_depth = Tree.get_subtree_depth(tree.root)
        @test root_depth >= 0
        
        # Terminal nodes have depth 0
        if terminal !== nothing
            @test Tree.get_subtree_depth(terminal) == 0
        end
        
        # Test collect_nodes_at_depth
        depth_0_nodes = Tree.collect_nodes_at_depth(tree, 0)
        @test length(depth_0_nodes) == 1
        @test depth_0_nodes[1] === tree.root
        
        depth_1_nodes = Tree.collect_nodes_at_depth(tree, 1)
        @test all(node -> node.parent === tree.root, depth_1_nodes)
        @test Set(depth_1_nodes) == Set(tree.root.children)
        
        # Test get_leaves
        leaves = Tree.get_leaves(tree)
        @test all(node -> isempty(node.children), leaves)
        # All terminal nodes should be leaves
        @test all(node -> node.is_terminal || isempty(node.children), leaves)
    end
    
    @testset "Traversal Correctness" begin
        # Verify that all traversal orders visit all nodes exactly once
        orders = [Tree.PreOrder, Tree.PostOrder, Tree.LevelOrder]
        
        for order in orders
            visited = Set{Tree.GameNode}()
            Tree.traverse_tree(tree, node -> push!(visited, node), order=order)
            @test length(visited) == tree.num_nodes
        end
        
        # Verify filtered traversal doesn't miss nodes
        all_nodes = Set{Tree.GameNode}()
        Tree.traverse_filtered(tree,
            node -> push!(all_nodes, node),
            node -> true)  # Accept all nodes
        @test length(all_nodes) == tree.num_nodes
    end
    
    @testset "Edge Cases" begin
        # Test with single-node tree (root only)
        small_params = GameTypes.GameParams()
        small_tree = Tree.GameTree(small_params)
        
        # Root-only tree tests
        @test Tree.get_subtree_size(small_tree.root) == 1
        @test Tree.get_subtree_depth(small_tree.root) == 0
        @test isempty(Tree.get_siblings(small_tree.root))
        @test isempty(Tree.get_ancestors(small_tree.root))
        
        leaves = Tree.get_leaves(small_tree)
        @test length(leaves) == 1
        @test leaves[1] === small_tree.root
        
        # Test empty search results
        no_match = Tree.find_node(tree, node -> node.pot > 1000000.0f0)
        @test no_match === nothing
        
        no_matches = Tree.find_all_nodes(tree, node -> node.pot > 1000000.0f0)
        @test isempty(no_matches)
    end
end
