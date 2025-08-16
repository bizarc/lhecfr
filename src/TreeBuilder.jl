"""
    TreeBuilder

Module for building game trees for Limit Hold'em.
"""
module TreeBuilder

using ..GameTypes
using ..TreeNode
using ..BettingSequence

# --- Game Tree Structure ---
"""
    GameTree
    
Complete game tree structure for Limit Hold'em.
"""
mutable struct GameTree
    params::GameTypes.GameParams
    root::TreeNode.GameNode                    # Root node of the tree
    nodes::Vector{TreeNode.GameNode}           # All nodes in the tree
    player_nodes::Vector{TreeNode.GameNode}    # Player decision nodes only
    terminal_nodes::Vector{TreeNode.GameNode}  # Terminal nodes only
    infoset_map::Dict{GameTypes.ISId, Vector{TreeNode.GameNode}}  # Map infoset ID to nodes
    num_infosets::Int                 # Total number of information sets
    
    # Statistics
    num_nodes::Int
    num_player_nodes::Int
    num_terminal_nodes::Int
    num_chance_nodes::Int
    
    function GameTree(params::GameTypes.GameParams)
        root = TreeNode.GameNode(
            1,  # id
            TreeNode.PlayerNode,
            UInt8(0),  # SB/BTN acts first pre-flop in heads-up
            TreeNode.Preflop,
            Float32(params.small_blind + params.big_blind),  # Initial pot
            UInt8(0),  # no raises yet
            false,  # SB not facing bet (they post blind)
            nothing  # no parent
        )
        
        new(
            params,
            root,
            [root],  # nodes list starts with root
            [root],  # player_nodes includes root (it's a player node)
            TreeNode.GameNode[],  # terminal_nodes to be populated
            Dict{GameTypes.ISId, Vector{TreeNode.GameNode}}(),
            0,  # num_infosets
            1,  # num_nodes (just root)
            1,  # num_player_nodes (root is a player node)
            0,  # num_terminal_nodes
            0   # num_chance_nodes
        )
    end
end

# --- Tree Building Functions ---

"""
    build_preflop_tree!(tree::GameTree, node::GameNode, sequence::Sequence, node_id_counter::Ref{Int})
    
Build the tree for a specific betting sequence starting from a node.
"""
function build_preflop_tree!(
    tree::GameTree, 
    current_node::TreeNode.GameNode,
    sequence::BettingSequence.Sequence,
    action_idx::Int,
    node_id_counter::Ref{Int}
)
    # Base case: we've processed all actions in the sequence
    if action_idx > length(sequence.actions)
        # This node should be terminal
        if sequence.is_terminal
            current_node.is_terminal = true
            current_node.terminal_type = sequence.terminal_type
            
            # Utilities will be calculated by TerminalEvaluation module
            # For now, set placeholder values
            if sequence.terminal_type == 1  # Fold
                # Will be properly calculated by evaluate_fold_utility
                current_node.utilities = nothing
            else  # Showdown/next street
                # Will be properly calculated by evaluate_showdown_utility
                current_node.utilities = nothing
            end
            
            push!(tree.terminal_nodes, current_node)
        end
        return current_node
    end
    
    # Get the next action in the sequence
    action = sequence.actions[action_idx]
    
    # Check if this action already has a child
    if haskey(current_node.action_to_child, action)
        # Follow existing child
        child_idx = current_node.action_to_child[action]
        child = current_node.children[child_idx]
        return build_preflop_tree!(tree, child, sequence, action_idx + 1, node_id_counter)
    end
    
    # Create new child node for this action
    node_id_counter[] += 1
    new_node_id = node_id_counter[]
    
    # Determine next player and game state
    next_player = current_node.player == 0 ? UInt8(1) : UInt8(0)
    
    # Update game state based on action
    new_pot = current_node.pot
    new_raises = current_node.raises_this_street
    new_facing_bet = false
    
    if action == GameTypes.Call
        bet_size = TreeNode.get_bet_size(current_node.street, tree.params)
        if current_node.facing_bet
            new_pot += bet_size
        elseif current_node.player == 0 && action_idx == 1
            # Special case: SB limping
            new_pot += Float32(tree.params.small_blind)
        end
    elseif action == GameTypes.BetOrRaise
        bet_size = TreeNode.get_bet_size(current_node.street, tree.params)
        if current_node.facing_bet
            new_pot += 2 * bet_size  # Call + raise
        else
            # Initial bet/raise
            if current_node.street == TreeNode.Preflop && current_node.player == 0
                # Special case: SB raising initially needs to match BB first
                # SB needs to add: (BB - SB) to match + bet_size to raise
                # = small_blind + bet_size total
                new_pot += Float32(tree.params.small_blind) + bet_size
            else
                new_pot += bet_size  # Just bet
            end
        end
        new_raises += UInt8(1)
        new_facing_bet = true
    elseif action == GameTypes.Fold
        # Terminal node after fold
        new_facing_bet = false
    end
    
    # Create the child node
    child = TreeNode.GameNode(
        new_node_id,
        TreeNode.PlayerNode,
        next_player,
        TreeNode.Preflop,
        new_pot,
        new_raises,
        new_facing_bet,
        current_node
    )
    
    # Add child to parent
    TreeNode.add_child!(current_node, child, action)
    
    # Add to tree's node list
    push!(tree.nodes, child)
    
    # Continue building recursively (this may mark the node as terminal)
    result = build_preflop_tree!(tree, child, sequence, action_idx + 1, node_id_counter)
    
    # Add to player_nodes only if not terminal after recursive processing
    if !child.is_terminal
        push!(tree.player_nodes, child)
    end
    
    return result
end

"""
    build_postflop_subtrees!(tree::GameTree, node_id_counter::Ref{Int}, verbose::Bool)
    
Build post-flop subtrees for all pre-flop terminal nodes that transition to the flop.
"""
function build_postflop_subtrees!(tree::GameTree, node_id_counter::Ref{Int}, verbose::Bool)
    # Find all pre-flop terminal nodes that go to the flop (not folds)
    preflop_to_flop_nodes = filter(tree.terminal_nodes) do node
        node.street == TreeNode.Preflop && node.terminal_type == 2  # Goes to next street
    end
    
    if verbose
        println("  Found $(length(preflop_to_flop_nodes)) pre-flop nodes transitioning to flop")
    end
    
    # For each node going to flop, build the post-flop subtree
    for preflop_node in preflop_to_flop_nodes
        # Convert terminal node to non-terminal and build flop subtree
        build_street_subtree!(tree, preflop_node, TreeNode.Flop, node_id_counter)
    end
end

"""
    build_street_subtree!(tree::GameTree, parent_node::GameNode, street::Street, node_id_counter::Ref{Int})
    
Build the subtree for a specific street starting from a parent node.
"""
function build_street_subtree!(tree::GameTree, parent_node::TreeNode.GameNode, street::TreeNode.Street, node_id_counter::Ref{Int})
    # Parent node is no longer terminal
    parent_node.is_terminal = false
    parent_node.terminal_type = 0
    parent_node.utilities = nothing
    
    # Remove from terminal_nodes list if it was there
    filter!(n -> n !== parent_node, tree.terminal_nodes)
    
    # Add to player_nodes list since it's now a decision node
    if !(parent_node in tree.player_nodes)
        push!(tree.player_nodes, parent_node)
    end
    
    # Generate betting sequences for this street
    # Start with player 0 (first to act post-flop in heads-up)
    sequences = BettingSequence.generate_betting_sequences(street, parent_node.pot, tree.params,
                                           initial_facing_bet=false,
                                           initial_player=UInt8(0))
    
    # Build tree for each sequence
    for sequence in sequences
        build_postflop_tree!(tree, parent_node, sequence, street, 1, node_id_counter)
    end
end

"""
    build_postflop_tree!(tree::GameTree, parent_node::GameNode, sequence::Sequence, 
                         street::Street, action_idx::Int, node_id_counter::Ref{Int})
    
Build the post-flop tree recursively for a given betting sequence.
"""
function build_postflop_tree!(tree::GameTree, parent_node::TreeNode.GameNode, sequence::BettingSequence.Sequence,
                              street::TreeNode.Street, action_idx::Int, node_id_counter::Ref{Int})
    current_node = parent_node
    created_nodes = TreeNode.GameNode[]  # Track nodes created in this call
    
    # Process each action in the sequence
    for i in action_idx:length(sequence.actions)
        action = sequence.actions[i]
        
        # Check if child already exists
        if haskey(current_node.action_to_child, action)
            # Child exists, traverse to it
            child_idx = current_node.action_to_child[action]
            current_node = current_node.children[child_idx]
        else
            # Create new child node
            node_id_counter[] += 1
            
            # Determine next player
            next_player = UInt8(1 - current_node.player)
            
            # Calculate pot after action
            new_pot = TreeNode.calculate_pot_after_action(current_node, action, tree.params)
            
            # Update betting state
            new_raises = current_node.raises_this_street
            new_facing_bet = current_node.facing_bet
            new_last_aggressor = current_node.last_aggressor
            
            if action == GameTypes.Check
                new_facing_bet = false
            elseif action == GameTypes.Call
                new_facing_bet = false
            elseif action == GameTypes.BetOrRaise
                new_raises += UInt8(1)
                new_facing_bet = true
                new_last_aggressor = current_node.player
            end
            
            # Create child node
            child = TreeNode.GameNode(
                node_id_counter[],
                TreeNode.PlayerNode,
                next_player,
                street,
                new_pot,
                new_raises,
                new_facing_bet,
                current_node
            )
            child.last_aggressor = new_last_aggressor
            
            # Update action history
            child.action_history = copy(current_node.action_history)
            push!(child.action_history, action)
            
            # Update betting history
            child.betting_history = TreeNode.update_betting_history(current_node.betting_history, action)
            
            # Add child to parent
            TreeNode.add_child!(current_node, child, action)
            
            # Add to tree's nodes list
            push!(tree.nodes, child)
            
            # Track this node for later categorization
            push!(created_nodes, child)
            
            current_node = child
        end
    end
    
    # Check if this node should be terminal
    if sequence.is_terminal
        current_node.is_terminal = true
        current_node.terminal_type = sequence.terminal_type
        
        # Utilities will be calculated by TerminalEvaluation module
        if sequence.terminal_type == 1  # Fold
            # Will be properly calculated by evaluate_fold_utility
            current_node.utilities = nothing
        elseif street == TreeNode.River
            # Showdown on river - will be calculated by evaluate_showdown_utility
            current_node.utilities = nothing
            # River showdowns are truly terminal
            push!(tree.terminal_nodes, current_node)
        else
            # Go to next street
            current_node.terminal_type = 2
            
            # Build next street subtree
            next_street = TreeNode.Street(Int(street) + 1)
            if next_street <= TreeNode.River
                build_street_subtree!(tree, current_node, next_street, node_id_counter)
            end
        end
        
        # Add to terminal nodes if fold (type 1)
        if current_node.terminal_type == 1
            push!(tree.terminal_nodes, current_node)
        end
    end
    
    # Add created nodes to player_nodes list (except if terminal, and avoid duplicates)
    for node in created_nodes
        if !node.is_terminal && !(node in tree.player_nodes)
            push!(tree.player_nodes, node)
        end
    end
    
    return current_node
end

"""
    build_game_tree(params::GameParams; preflop_only::Bool = false, verbose::Bool = true)
    
Build the complete game tree for Limit Hold'em.
Supports both pre-flop only and full game tree construction.
"""
function build_game_tree(params::GameTypes.GameParams; preflop_only::Bool = false, verbose::Bool = true)
    # Initialize tree with root node
    tree = GameTree(params)
    
    # Node ID counter (root is 1)
    node_id_counter = Ref(1)
    
    # Generate all pre-flop betting sequences
    sequences = BettingSequence.generate_preflop_sequences(params)
    
    # Build tree from sequences
    for sequence in sequences
        # Start from root for each sequence
        build_preflop_tree!(tree, tree.root, sequence, 1, node_id_counter)
    end
    
    # If not preflop_only, build post-flop subtrees
    if !preflop_only
        if verbose
            println("Building post-flop tree...")
        end
        build_postflop_subtrees!(tree, node_id_counter, verbose)
    end
    
    # Note: Statistics update and infoset assignment must be done
    # by the caller after tree building is complete
    return tree
end

# Export types and functions
export GameTree
export build_preflop_tree!, build_postflop_subtrees!, build_street_subtree!, build_postflop_tree!
export build_game_tree

end # module
