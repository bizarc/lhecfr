"""
    Tree

Main module for game tree construction and manipulation in Limit Hold'em.
This module orchestrates the various tree-related submodules.
"""
module Tree

using ..GameTypes

# Include submodules in dependency order
include("TreeNode.jl")
include("BettingSequence.jl")
include("InfoSet.jl")
include("TreeBuilder.jl")
include("TreeTraversal.jl")
include("TreeValidation.jl")
include("TerminalEvaluation.jl")
include("TreeSizeValidation.jl")
include("TreeMemory.jl")

# Import submodules for easier access
using .TreeNode
using .BettingSequence
using .InfoSet
using .TreeBuilder
using .TreeTraversal
using .TreeValidation
using .TerminalEvaluation
using .TreeSizeValidation
using .TreeMemory

# Re-export all types and functions from submodules

# From TreeNode
export NodeType, ChanceNode, PlayerNode, TerminalNode
export Street, Preflop, Flop, Turn, River
export GameNode
export add_child!, update_betting_history, get_valid_actions
export is_player_node, is_chance_node, is_terminal_node
export get_current_player, calculate_pot_after_action, get_bet_size
export get_node_depth

# From BettingSequence  
export Sequence
export generate_betting_sequences, is_betting_complete
export generate_preflop_sequences, is_preflop_betting_complete
export count_betting_sequences

# From InfoSet
export CardAbstraction, InformationSet
export canonicalize_hand, canonicalize_suits, cards_to_string
export create_infoset_id, create_infoset, get_infoset_id

# From TreeBuilder
export GameTree
export build_preflop_tree!, build_postflop_subtrees!, build_street_subtree!, build_postflop_tree!
export build_game_tree

# From TreeTraversal
export TraversalOrder, PreOrder, PostOrder, LevelOrder
export traverse_tree, traverse_preorder, traverse_postorder, traverse_levelorder
export traverse_filtered, traverse_player_nodes, traverse_terminal_nodes
export find_node, find_all_nodes, find_node_by_id, find_nodes_by_infoset
export find_path, find_path_to_id, get_ancestors, get_siblings
export get_subtree_size, get_subtree_depth, collect_nodes_at_depth, get_leaves
export print_tree_structure
export assign_infoset_ids!, update_tree_statistics!

# From TreeValidation
export validate_tree, print_tree_summary
export check_tree_integrity, analyze_branching_factor

# From TerminalEvaluation
export PlayerInvestment
export calculate_investments
export evaluate_fold_utility, evaluate_showdown_utility
export evaluate_terminal_node!, evaluate_all_terminals!

# From TreeSizeValidation
export TheoreticalTreeSizes, calculate_theoretical_sizes
export validate_tree_size, print_tree_statistics
export count_preflop_sequences, count_postflop_sequences

# From TreeMemory
export CompactNode, CompactTree, compress_tree, decompress_tree
export NodePool, allocate_node!, free_node!
export LazyTree, expand_node!, expand_to_depth!
export prune_tree!, prune_by_depth!, prune_randomly!, prune_by_importance!
export memory_stats

# Convenience function that combines tree building with statistics and validation
"""
    build_and_validate_tree(params::GameParams; preflop_only::Bool = false, verbose::Bool = true)
    
Build a complete game tree with validation and statistics.
This is a convenience function that combines tree building, statistics update, 
information set assignment, and validation.
"""
function build_and_validate_tree(params::GameTypes.GameParams; preflop_only::Bool = false, verbose::Bool = true, evaluate_terminals::Bool = true)
    # Build the tree
    tree = TreeBuilder.build_game_tree(params, preflop_only=preflop_only, verbose=verbose)
    
    # Update statistics
    TreeTraversal.update_tree_statistics!(tree, verbose=verbose)
    
    # Assign information set IDs
    TreeTraversal.assign_infoset_ids!(tree, verbose=verbose)
    
    # Evaluate terminal nodes
    if evaluate_terminals
        TerminalEvaluation.evaluate_all_terminals!(tree, params)
        if verbose
            println("  Terminal nodes evaluated: ", length(tree.terminal_nodes))
        end
    end
    
    # Validate if requested
    if verbose
        is_valid = TreeValidation.validate_tree(tree)
        if !is_valid
            @warn "Tree validation failed!"
        end
    end
    
    return tree
end

export build_and_validate_tree

end # module Tree
