"""
    TreeValidation

Module for validating and analyzing game trees.
"""
module TreeValidation

using ..GameTypes
using ..TreeNode
using ..TreeBuilder
using ..TreeTraversal

"""
    validate_tree(tree::GameTree)
    
Validate the constructed game tree for correctness.
"""
function validate_tree(tree::TreeBuilder.GameTree)
    errors = String[]
    
    # Check all nodes are reachable from root
    reachable = Set{GameTypes.NodeId}()
    TreeTraversal.traverse_tree(tree, node -> push!(reachable, node.id))
    
    for node in tree.nodes
        if !(node.id in reachable)
            push!(errors, "Node $(node.id) is not reachable from root")
        end
    end
    
    # Check parent-child relationships
    for node in tree.nodes
        for child in node.children
            if child.parent !== node
                push!(errors, "Inconsistent parent-child relationship: $(node.id) -> $(child.id)")
            end
        end
    end
    
    # Check terminal nodes
    for node in tree.terminal_nodes
        if !node.is_terminal
            push!(errors, "Node $(node.id) in terminal_nodes but is_terminal is false")
        end
        if length(node.children) > 0
            push!(errors, "Terminal node $(node.id) has children")
        end
    end
    
    # Check player nodes
    for node in tree.player_nodes
        if node.is_terminal
            push!(errors, "Node $(node.id) in player_nodes but is terminal")
        end
        if !TreeNode.is_player_node(node)
            push!(errors, "Node $(node.id) in player_nodes but is not a player node")
        end
    end
    
    if length(errors) > 0
        println("Tree validation errors:")
        for error in errors
            println("  - ", error)
        end
        return false
    end
    
    return true
end

"""
    print_tree_summary(tree::GameTree)
    
Print a summary of the game tree structure and statistics.
"""
function print_tree_summary(tree::TreeBuilder.GameTree)
    println("\n" * "="^60)
    println("GAME TREE SUMMARY")
    println("="^60)
    
    println("\nTree Parameters:")
    println("  Small blind: ", tree.params.small_blind)
    println("  Big blind: ", tree.params.big_blind)
    println("  Max raises per street: ", tree.params.max_raises_per_street)
    
    println("\nTree Statistics:")
    println("  Total nodes: ", tree.num_nodes)
    println("  Player nodes: ", tree.num_player_nodes)
    println("  Terminal nodes: ", tree.num_terminal_nodes)
    println("  Chance nodes: ", tree.num_chance_nodes)
    println("  Information sets: ", tree.num_infosets)
    
    # Count nodes by street
    street_counts = Dict{TreeNode.Street, Int}()
    TreeTraversal.traverse_tree(tree, node -> begin
        if !haskey(street_counts, node.street)
            street_counts[node.street] = 0
        end
        street_counts[node.street] += 1
    end)
    
    println("\nNodes by Street:")
    for street in [TreeNode.Preflop, TreeNode.Flop, TreeNode.Turn, TreeNode.River]
        if haskey(street_counts, street)
            street_name = if street == TreeNode.Preflop
                "Pre-flop"
            elseif street == TreeNode.Flop
                "Flop"
            elseif street == TreeNode.Turn
                "Turn"
            else
                "River"
            end
            println("  $street_name: ", street_counts[street])
        end
    end
    
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
    
    println("\nTerminal Node Types:")
    println("  Folds: ", fold_count)
    println("  Showdowns: ", showdown_count)
    
    println("\nValidation:")
    is_valid = validate_tree(tree)
    println("  Tree is valid: ", is_valid)
    println("="^60)
end

"""
    check_tree_integrity(tree::GameTree)
    
Perform integrity checks on the tree structure.
Returns (is_valid::Bool, issues::Vector{String})
"""
function check_tree_integrity(tree::TreeBuilder.GameTree)
    issues = String[]
    
    # Check that root is in nodes list
    if !(tree.root in tree.nodes)
        push!(issues, "Root node not in nodes list")
    end
    
    # Check for duplicate node IDs
    id_set = Set{GameTypes.NodeId}()
    for node in tree.nodes
        if node.id in id_set
            push!(issues, "Duplicate node ID: $(node.id)")
        end
        push!(id_set, node.id)
    end
    
    # Check that all player_nodes are in nodes
    for pnode in tree.player_nodes
        if !(pnode in tree.nodes)
            push!(issues, "Player node $(pnode.id) not in main nodes list")
        end
    end
    
    # Check that all terminal_nodes are in nodes
    for tnode in tree.terminal_nodes
        if !(tnode in tree.nodes)
            push!(issues, "Terminal node $(tnode.id) not in main nodes list")
        end
    end
    
    # Check pot values are non-negative
    for node in tree.nodes
        if node.pot < 0
            push!(issues, "Node $(node.id) has negative pot: $(node.pot)")
        end
    end
    
    # Check that betting history is consistent
    for node in tree.nodes
        if node.parent !== nothing
            expected_len = length(node.parent.betting_history) + 1
            if length(node.betting_history) != expected_len
                push!(issues, "Node $(node.id) has inconsistent betting history length")
            end
        end
    end
    
    is_valid = length(issues) == 0
    return (is_valid, issues)
end

"""
    analyze_branching_factor(tree::GameTree)
    
Analyze the branching factor of the tree.
Returns statistics about the tree structure.
"""
function analyze_branching_factor(tree::TreeBuilder.GameTree)
    total_children = 0
    max_children = 0
    nodes_with_children = 0
    
    TreeTraversal.traverse_tree(tree, node -> begin
        num_children = length(node.children)
        if num_children > 0
            total_children += num_children
            nodes_with_children += 1
            max_children = max(max_children, num_children)
        end
    end)
    
    avg_branching = nodes_with_children > 0 ? total_children / nodes_with_children : 0
    
    return Dict(
        :average_branching_factor => avg_branching,
        :max_branching_factor => max_children,
        :nodes_with_children => nodes_with_children
    )
end

# Export functions
export validate_tree, print_tree_summary
export check_tree_integrity, analyze_branching_factor

end # module
