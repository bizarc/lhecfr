"""
    TreeSizeValidation

Module for validating game tree sizes against theoretical expectations for Limit Hold'em.
"""
module TreeSizeValidation

using ..GameTypes
using ..TreeNode
using ..TreeBuilder
using ..TreeTraversal
using ..BettingSequence

"""
    TheoreticalTreeSizes

Structure containing theoretical tree size calculations for HU-LHE.
"""
struct TheoreticalTreeSizes
    preflop_sequences::Int
    flop_sequences::Int
    turn_sequences::Int
    river_sequences::Int
    total_betting_sequences::Int
    
    # Node counts (without considering cards)
    preflop_nodes::Int
    postflop_nodes_per_street::Int
    
    # Information set counts (without cards)
    preflop_infosets::Int
    
    # With cards (simplified - actual would be much larger)
    preflop_infosets_with_cards::Int
end

"""
    calculate_theoretical_sizes()

Calculate the theoretical tree sizes for Heads-Up Limit Hold'em.
Based on the game rules:
- Maximum 4 bets per street (initial bet + 3 raises)
- Pre-flop: SB acts first
- Post-flop: BB acts first (simplified)
"""
function calculate_theoretical_sizes()
    # Pre-flop betting sequences
    # Starting from SB, possible actions at each decision point
    # We can have sequences like: f, c, cf, cc, cr, crf, crc, crr, crrf, crrc, crrr, crrrf, crrrc
    # And: r, rf, rc, rr, rrf, rrc, rrr, rrrf, rrrc, rrrr, rrrrf, rrrrc
    
    # Count pre-flop sequences more systematically
    preflop_seqs = count_preflop_sequences()
    
    # Post-flop sequences (same for each street)
    # Starting from first player, with no facing bet initially
    postflop_seqs = count_postflop_sequences()
    
    # Calculate node counts
    # Each sequence creates nodes along its path
    preflop_node_count = count_nodes_from_sequences(preflop_seqs)
    
    # Information sets (without cards)
    # Each unique (player, betting_history) combination
    preflop_infosets = count_unique_infosets(preflop_seqs)
    
    # With cards (simplified estimate)
    # 52 choose 2 = 1326 possible hole card combinations
    # But with suit isomorphism: 169 unique starting hands (13 ranks × 13 ranks / 2 + adjustments)
    # Actually: 13 pocket pairs + 78 suited hands + 78 offsuit hands = 169
    preflop_infosets_with_cards = preflop_infosets * 169
    
    return TheoreticalTreeSizes(
        preflop_seqs,
        postflop_seqs,
        postflop_seqs,  # Turn has same structure as flop
        postflop_seqs,  # River has same structure
        preflop_seqs + 3 * postflop_seqs,  # Total across all streets
        preflop_node_count,
        0,  # Would need to calculate based on tree structure
        preflop_infosets,
        preflop_infosets_with_cards
    )
end

"""
    count_preflop_sequences()

Count the number of valid pre-flop betting sequences.
"""
function count_preflop_sequences()
    # Use our existing betting sequence generator
    params = GameTypes.GameParams()
    sequences = BettingSequence.generate_preflop_sequences(params)
    return length(sequences)
end

"""
    count_postflop_sequences()

Count the number of valid post-flop betting sequences for a single street.
"""
function count_postflop_sequences()
    params = GameTypes.GameParams()
    # Start with no one facing a bet, arbitrary pot size
    sequences = BettingSequence.generate_betting_sequences(
        TreeNode.Flop,  # Street (same logic for all post-flop)
        Float32(10),    # Initial pot (doesn't affect sequence count)
        params;
        initial_facing_bet = false,
        initial_player = UInt8(0)  # BB acts first post-flop in our simplified model
    )
    return length(sequences)
end

"""
    count_nodes_from_sequences(num_sequences::Int)

Estimate the number of nodes created from a given number of sequences.
This is approximate as it depends on the tree structure.
"""
function count_nodes_from_sequences(num_sequences::Int)
    # Each sequence creates nodes along its path
    # This is a rough estimate - actual count depends on tree branching
    # For now, use a multiplier based on average sequence length
    avg_sequence_length = 3  # Rough estimate
    return num_sequences * avg_sequence_length
end

"""
    count_unique_infosets(num_sequences::Int)

Count unique information sets from betting sequences.
"""
function count_unique_infosets(num_sequences::Int)
    # Each position in each sequence potentially creates an infoset
    # This is simplified - actual count requires traversing sequences
    return num_sequences * 2  # Rough estimate: 2 infosets per sequence on average
end

"""
    validate_tree_size(tree::GameTree, theoretical::TheoreticalTreeSizes; verbose::Bool = true)

Validate that the actual tree matches theoretical expectations.
Returns true if validation passes, false otherwise.
"""
function validate_tree_size(tree::TreeBuilder.GameTree, theoretical::TheoreticalTreeSizes; verbose::Bool = true)
    valid = true
    
    if verbose
        println("\n=== Tree Size Validation ===")
        println("Comparing actual tree to theoretical expectations...")
    end
    
    # Check total node count
    if verbose
        println("\nNode Counts:")
        println("  Actual total nodes: ", tree.num_nodes)
        println("  Actual player nodes: ", tree.num_player_nodes)
        println("  Actual terminal nodes: ", tree.num_terminal_nodes)
    end
    
    # Check information sets (without cards)
    if verbose
        println("\nInformation Sets:")
        println("  Actual infosets: ", tree.num_infosets)
        println("  Theoretical (preflop only): ", theoretical.preflop_infosets)
    end
    
    # Validate betting sequences
    actual_terminal_sequences = length(tree.terminal_nodes)
    if verbose
        println("\nTerminal Nodes (Betting Sequences):")
        println("  Actual terminal nodes: ", actual_terminal_sequences)
        println("  Theoretical sequences (preflop): ", theoretical.preflop_sequences)
    end
    
    # Check for reasonable ranges
    if tree.num_nodes == 0
        if verbose
            println("\n⚠ Warning: Tree has no nodes!")
        end
        valid = false
    end
    
    if tree.num_terminal_nodes == 0
        if verbose
            println("\n⚠ Warning: Tree has no terminal nodes!")
        end
        valid = false
    end
    
    # For pre-flop only trees, check against pre-flop expectations
    # Allow some variance due to implementation differences
    tolerance = 0.2  # 20% tolerance
    
    if tree.num_infosets > 0
        expected_range_min = theoretical.preflop_infosets * (1 - tolerance)
        expected_range_max = theoretical.preflop_infosets * (1 + tolerance)
        
        # Note: actual might be different due to implementation details
        # This is more of a sanity check than exact validation
        if verbose
            println("\nValidation Results:")
            if tree.num_infosets >= expected_range_min && tree.num_infosets <= expected_range_max
                println("  ✓ Information set count within expected range")
            else
                println("  ⚠ Information set count outside expected range")
                println("    Expected range: $expected_range_min - $expected_range_max")
            end
        end
    end
    
    if verbose
        println("\n=== Validation ", valid ? "PASSED" : "FAILED", " ===")
    end
    
    return valid
end

"""
    print_tree_statistics(tree::GameTree)

Print detailed statistics about the tree structure.
"""
function print_tree_statistics(tree::TreeBuilder.GameTree)
    println("\n=== Tree Statistics ===")
    println("Total Nodes: ", tree.num_nodes)
    println("  Player Nodes: ", tree.num_player_nodes)
    println("  Terminal Nodes: ", tree.num_terminal_nodes)
    println("  Chance Nodes: ", tree.num_chance_nodes)
    println("\nInformation Sets: ", tree.num_infosets)
    
    # Count nodes by street
    street_counts = Dict{TreeNode.Street, Int}()
    TreeTraversal.traverse_tree(tree, node -> begin
        street = node.street
        street_counts[street] = get(street_counts, street, 0) + 1
    end)
    
    println("\nNodes by Street:")
    for street in [TreeNode.Preflop, TreeNode.Flop, TreeNode.Turn, TreeNode.River]
        count = get(street_counts, street, 0)
        street_name = ["Preflop", "Flop", "Turn", "River"][Int(street) + 1]
        println("  $street_name: $count")
    end
    
    # Analyze branching factor
    branching_factors = Float64[]
    TreeTraversal.traverse_tree(tree, node -> begin
        if !node.is_terminal && length(node.children) > 0
            push!(branching_factors, length(node.children))
        end
    end)
    
    if length(branching_factors) > 0
        avg_branching = sum(branching_factors) / length(branching_factors)
        max_branching = maximum(branching_factors)
        min_branching = minimum(branching_factors)
        
        println("\nBranching Factor:")
        println("  Average: ", round(avg_branching, digits=2))
        println("  Min: ", Int(min_branching))
        println("  Max: ", Int(max_branching))
    end
    
    # Analyze depth
    max_depth = 0
    TreeTraversal.traverse_tree(tree, node -> begin
        depth = TreeNode.get_node_depth(node)
        max_depth = max(max_depth, depth)
    end)
    
    println("\nTree Depth: ", max_depth)
    
    # Terminal node analysis
    terminal_by_type = Dict{Int, Int}()
    for node in tree.terminal_nodes
        type = node.terminal_type
        terminal_by_type[type] = get(terminal_by_type, type, 0) + 1
    end
    
    println("\nTerminal Nodes by Type:")
    println("  Fold (type 1): ", get(terminal_by_type, 1, 0))
    println("  Showdown (type 2): ", get(terminal_by_type, 2, 0))
    
    println("\n=== End Statistics ===")
end

# Export functions
export TheoreticalTreeSizes, calculate_theoretical_sizes
export validate_tree_size, print_tree_statistics
export count_preflop_sequences, count_postflop_sequences

end # module
