"""
    TreeTraversal

Module for traversing and analyzing game trees.
"""
module TreeTraversal

using ..GameTypes
using ..TreeNode
using ..TreeBuilder
using ..InfoSet

# --- Traversal Enums ---

"""
Traversal order for tree traversal operations.
"""
@enum TraversalOrder begin
    PreOrder    # Visit node, then children
    InOrder     # Visit left subtree, node, right subtree (for binary trees)
    PostOrder   # Visit children, then node
    LevelOrder  # Breadth-first traversal
end

# --- Core Traversal Functions ---

"""
    traverse_tree(tree::GameTree, visitor::Function; order::TraversalOrder = PreOrder)
    
Traverse the game tree and apply a visitor function to each node.
The visitor function should have signature: visitor(node::GameNode)

Arguments:
- `tree`: The game tree to traverse
- `visitor`: Function to apply to each node
- `order`: Traversal order (PreOrder, PostOrder, or LevelOrder)
"""
function traverse_tree(tree::TreeBuilder.GameTree, visitor::Function; order::TraversalOrder = PreOrder)
    traverse_tree(tree.root, visitor; order=order)
end

"""
    traverse_tree(node::GameNode, visitor::Function; order::TraversalOrder = PreOrder)
    
Traverse the tree starting from a given node.
"""
function traverse_tree(node::TreeNode.GameNode, visitor::Function; order::TraversalOrder = PreOrder)
    if order == PreOrder
        traverse_preorder(node, visitor)
    elseif order == PostOrder
        traverse_postorder(node, visitor)
    elseif order == LevelOrder
        traverse_levelorder(node, visitor)
    else
        error("InOrder traversal not applicable to non-binary trees")
    end
end

"""
    traverse_preorder(node::GameNode, visitor::Function)
    
Depth-first pre-order traversal (visit node before children).
"""
function traverse_preorder(node::TreeNode.GameNode, visitor::Function)
    visitor(node)
    for child in node.children
        traverse_preorder(child, visitor)
    end
end

"""
    traverse_postorder(node::GameNode, visitor::Function)
    
Depth-first post-order traversal (visit children before node).
"""
function traverse_postorder(node::TreeNode.GameNode, visitor::Function)
    for child in node.children
        traverse_postorder(child, visitor)
    end
    visitor(node)
end

"""
    traverse_levelorder(node::GameNode, visitor::Function)
    
Breadth-first (level-order) traversal.
"""
function traverse_levelorder(node::TreeNode.GameNode, visitor::Function)
    queue = [node]
    
    while !isempty(queue)
        current = popfirst!(queue)
        visitor(current)
        
        for child in current.children
            push!(queue, child)
        end
    end
end

# --- Filtered Traversal ---

"""
    traverse_filtered(tree::GameTree, visitor::Function, filter::Function; 
                     order::TraversalOrder = PreOrder)
    
Traverse only nodes that satisfy the filter condition.
Filter should have signature: filter(node::GameNode) -> Bool
"""
function traverse_filtered(tree::TreeBuilder.GameTree, visitor::Function, filter::Function; 
                          order::TraversalOrder = PreOrder)
    wrapped_visitor = node -> begin
        if filter(node)
            visitor(node)
        end
    end
    traverse_tree(tree, wrapped_visitor; order=order)
end

"""
    traverse_player_nodes(tree::GameTree, visitor::Function; player::Union{Nothing, UInt8} = nothing)
    
Traverse only player (decision) nodes, optionally for a specific player.
"""
function traverse_player_nodes(tree::TreeBuilder.GameTree, visitor::Function; 
                              player::Union{Nothing, UInt8} = nothing)
    filter = if player === nothing
        node -> TreeNode.is_player_node(node) && !node.is_terminal
    else
        node -> TreeNode.is_player_node(node) && !node.is_terminal && node.player == player
    end
    traverse_filtered(tree, visitor, filter)
end

"""
    traverse_terminal_nodes(tree::GameTree, visitor::Function)
    
Traverse only terminal nodes.
"""
function traverse_terminal_nodes(tree::TreeBuilder.GameTree, visitor::Function)
    traverse_filtered(tree, visitor, node -> node.is_terminal)
end

# --- Node Search Functions ---

"""
    find_node(tree::GameTree, predicate::Function) -> Union{GameNode, Nothing}
    
Find the first node that satisfies the predicate.
Predicate should have signature: predicate(node::GameNode) -> Bool
"""
function find_node(tree::TreeBuilder.GameTree, predicate::Function)
    result = Ref{Union{TreeNode.GameNode, Nothing}}(nothing)
    
    try
        traverse_tree(tree, node -> begin
            if predicate(node)
                result[] = node
                throw(:found)  # Early exit
            end
        end)
    catch e
        if e != :found
            rethrow(e)
        end
    end
    
    return result[]
end

"""
    find_all_nodes(tree::GameTree, predicate::Function) -> Vector{GameNode}
    
Find all nodes that satisfy the predicate.
"""
function find_all_nodes(tree::TreeBuilder.GameTree, predicate::Function)
    nodes = TreeNode.GameNode[]
    traverse_tree(tree, node -> begin
        if predicate(node)
            push!(nodes, node)
        end
    end)
    return nodes
end

"""
    find_node_by_id(tree::GameTree, id::NodeId) -> Union{GameNode, Nothing}
    
Find a node by its ID.
"""
function find_node_by_id(tree::TreeBuilder.GameTree, id::GameTypes.NodeId)
    find_node(tree, node -> node.id == id)
end

"""
    find_nodes_by_infoset(tree::GameTree, infoset_id::ISId) -> Vector{GameNode}
    
Find all nodes belonging to a specific information set.
"""
function find_nodes_by_infoset(tree::TreeBuilder.GameTree, infoset_id::GameTypes.ISId)
    get(tree.infoset_map, infoset_id, TreeNode.GameNode[])
end

# --- Path Finding ---

"""
    find_path(tree::GameTree, target::GameNode) -> Vector{GameNode}
    
Find the path from root to target node.
Returns empty vector if target is not in tree.
"""
function find_path(tree::TreeBuilder.GameTree, target::TreeNode.GameNode)
    path = TreeNode.GameNode[]
    
    function search(node::TreeNode.GameNode)::Bool
        push!(path, node)
        
        if node === target
            return true
        end
        
        for child in node.children
            if search(child)
                return true
            end
        end
        
        pop!(path)
        return false
    end
    
    if search(tree.root)
        return path
    else
        return TreeNode.GameNode[]
    end
end

"""
    find_path_to_id(tree::GameTree, target_id::NodeId) -> Vector{GameNode}
    
Find the path from root to the node with the given ID.
"""
function find_path_to_id(tree::TreeBuilder.GameTree, target_id::GameTypes.NodeId)
    target = find_node_by_id(tree, target_id)
    if target !== nothing
        return find_path(tree, target)
    else
        return TreeNode.GameNode[]
    end
end

"""
    get_ancestors(node::GameNode) -> Vector{GameNode}
    
Get all ancestors of a node (path from root to node's parent).
"""
function get_ancestors(node::TreeNode.GameNode)
    ancestors = TreeNode.GameNode[]
    current = node.parent
    
    while current !== nothing
        pushfirst!(ancestors, current)
        current = current.parent
    end
    
    return ancestors
end

"""
    get_siblings(node::GameNode) -> Vector{GameNode}
    
Get all siblings of a node (other children of the same parent).
"""
function get_siblings(node::TreeNode.GameNode)
    if node.parent === nothing
        return TreeNode.GameNode[]
    end
    
    return filter(child -> child !== node, node.parent.children)
end

# --- Tree Analysis ---

"""
    get_subtree_size(node::GameNode) -> Int
    
Count the total number of nodes in the subtree rooted at the given node.
"""
function get_subtree_size(node::TreeNode.GameNode)
    count = Ref(0)
    traverse_tree(node, _ -> count[] += 1)
    return count[]
end

"""
    get_subtree_depth(node::GameNode) -> Int
    
Get the maximum depth of the subtree rooted at the given node.
"""
function get_subtree_depth(node::TreeNode.GameNode)
    if isempty(node.children)
        return 0
    end
    
    return 1 + maximum(get_subtree_depth(child) for child in node.children)
end

"""
    collect_nodes_at_depth(tree::GameTree, depth::Int) -> Vector{GameNode}
    
Collect all nodes at a specific depth from the root.
"""
function collect_nodes_at_depth(tree::TreeBuilder.GameTree, target_depth::Int)
    nodes = TreeNode.GameNode[]
    
    function collect_at_depth(node::TreeNode.GameNode, current_depth::Int)
        if current_depth == target_depth
            push!(nodes, node)
        elseif current_depth < target_depth
            for child in node.children
                collect_at_depth(child, current_depth + 1)
            end
        end
    end
    
    collect_at_depth(tree.root, 0)
    return nodes
end

"""
    get_leaves(tree::GameTree) -> Vector{GameNode}
    
Get all leaf nodes (nodes with no children).
"""
function get_leaves(tree::TreeBuilder.GameTree)
    find_all_nodes(tree, node -> isempty(node.children))
end

"""
    print_tree_structure(tree::GameTree; max_depth::Int = 3)
    
Print a visual representation of the tree structure.
"""
function print_tree_structure(tree::TreeBuilder.GameTree; max_depth::Int = 3)
    println("\nTree Structure (up to depth $max_depth):")
    print_tree_structure(tree.root, max_depth=max_depth)
end

"""
    print_tree_structure(node::GameNode; max_depth::Int = 3)
    
Print a visual representation of the tree structure starting from a node.
"""
function print_tree_structure(node::TreeNode.GameNode; max_depth::Int = 3)
    function print_node(n::TreeNode.GameNode, depth::Int, prefix::String)
        if depth > max_depth
            return
        end
        
        # Create node description
        desc = if n.is_terminal
            "Terminal ($(n.terminal_type == 1 ? "Fold" : "Showdown")) Pot: $(n.pot)"
        else
            "P$(n.player) Pot: $(n.pot) Facing: $(n.facing_bet)"
        end
        
        println(prefix, "Node ", n.id, ": ", desc)
        
        # Print children
        for (action, child_idx) in n.action_to_child
            child = n.children[child_idx]
            action_str = if action == GameTypes.Fold
                "Fold"
            elseif action == GameTypes.Call
                "Call"
            elseif action == GameTypes.Check
                "Check"
            elseif action == GameTypes.BetOrRaise
                "Raise"
            else
                "Unknown"
            end
            
            child_prefix = prefix * "  " * action_str * " -> "
            print_node(child, depth + 1, child_prefix)
        end
    end
    
    print_node(node, 0, "")
end

"""
    assign_infoset_ids!(tree::GameTree; verbose::Bool = true, 
                       include_cards::Bool = false,
                       hole_cards_fn::Union{Nothing, Function} = nothing,
                       board_cards_fn::Union{Nothing, Function} = nothing)
    
Assign information set IDs to all nodes in the tree.
Nodes in the same information set get the same ID.

If include_cards is true, hole_cards_fn and board_cards_fn should be functions
that take a GameNode and return Vector{Card} or nothing.
"""
function assign_infoset_ids!(tree::TreeBuilder.GameTree; verbose::Bool = true,
                           include_cards::Bool = false,
                           hole_cards_fn::Union{Nothing, Function} = nothing,
                           board_cards_fn::Union{Nothing, Function} = nothing)
    
    infoset_counter = Ref(0)
    infoset_mapping = Dict{String, GameTypes.ISId}()
    
    traverse_tree(tree, node -> begin
        if !TreeNode.is_terminal_node(node) && TreeNode.is_player_node(node)
            # Create infoset key
            if include_cards && hole_cards_fn !== nothing
                # Use full information set including cards
                hole_cards = hole_cards_fn(node)
                board_cards = board_cards_fn !== nothing ? board_cards_fn(node) : nothing
                key = InfoSet.get_infoset_id(node, hole_cards, board_cards)
            else
                # Backward compatibility: just use player and betting history
                key = string(node.player, ":", node.betting_history)
            end
            
            if !haskey(infoset_mapping, key)
                infoset_counter[] += 1
                infoset_mapping[key] = infoset_counter[]
            end
            
            node.infoset_id = infoset_mapping[key]
            
            # Add to tree's infoset map
            if !haskey(tree.infoset_map, node.infoset_id)
                tree.infoset_map[node.infoset_id] = TreeNode.GameNode[]
            end
            push!(tree.infoset_map[node.infoset_id], node)
        end
    end)
    
    tree.num_infosets = infoset_counter[]
    
    if verbose
        println("  Information sets: ", infoset_counter[])
        if include_cards
            println("    (Including card information)")
        else
            println("    (Betting history only)")
        end
    end
end

"""
    update_tree_statistics!(tree::GameTree; verbose::Bool = true)
    
Update the statistics in the game tree after construction.
"""
function update_tree_statistics!(tree::TreeBuilder.GameTree; verbose::Bool = true)
    # Use mutable references to count nodes
    tree_stats = Dict{Symbol, Int}(
        :total => 0,
        :player => 0,
        :terminal => 0,
        :chance => 0
    )
    
    # Count nodes by traversing the tree
    traverse_tree(tree, node -> begin
        tree_stats[:total] += 1
        if TreeNode.is_terminal_node(node)
            tree_stats[:terminal] += 1
        elseif TreeNode.is_player_node(node)
            tree_stats[:player] += 1
        elseif TreeNode.is_chance_node(node)
            tree_stats[:chance] += 1
        end
    end)
    
    # Validate counts - allow minor discrepancies due to ordering
    if length(tree.nodes) != tree_stats[:total]
        @warn "Node count mismatch: stored=$(length(tree.nodes)) vs counted=$(tree_stats[:total])"
    end
    if length(tree.player_nodes) != tree_stats[:player]
        @warn "Player node count mismatch: stored=$(length(tree.player_nodes)) vs counted=$(tree_stats[:player])"
    end
    if length(tree.terminal_nodes) != tree_stats[:terminal]
        @warn "Terminal node count mismatch: stored=$(length(tree.terminal_nodes)) vs counted=$(tree_stats[:terminal])"
    end
    
    # Update tree statistics
    tree.num_nodes = tree_stats[:total]
    tree.num_player_nodes = tree_stats[:player]
    tree.num_terminal_nodes = tree_stats[:terminal]
    tree.num_chance_nodes = tree_stats[:chance]
    
    # Print statistics for debugging
    if verbose
        println("Tree Statistics:")
        println("  Total nodes: ", tree_stats[:total])
        println("  Player nodes: ", tree_stats[:player])
        println("  Terminal nodes: ", tree_stats[:terminal])
        println("  Chance nodes: ", tree_stats[:chance])
    end
end

# Export functions
export TraversalOrder, PreOrder, PostOrder, LevelOrder
export traverse_tree, traverse_preorder, traverse_postorder, traverse_levelorder
export traverse_filtered, traverse_player_nodes, traverse_terminal_nodes
export find_node, find_all_nodes, find_node_by_id, find_nodes_by_infoset
export find_path, find_path_to_id, get_ancestors, get_siblings
export get_subtree_size, get_subtree_depth, collect_nodes_at_depth, get_leaves
export print_tree_structure
export assign_infoset_ids!, update_tree_statistics!

end # module
