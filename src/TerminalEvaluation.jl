"""
    TerminalEvaluation

Module for evaluating terminal nodes in the game tree, calculating utilities
based on pot distribution rules and hand strengths.
"""
module TerminalEvaluation

using ...GameTypes
using ..TreeNode
using ...Evaluator

"""
    PlayerInvestment

Tracks how much each player has invested in the pot.
"""
mutable struct PlayerInvestment
    player0::Float32  # SB/BTN investment
    player1::Float32  # BB investment
end

"""
    calculate_investments(node::GameNode, params::GameParams)

Calculate how much each player has invested to reach this node.
Uses a simpler approach: calculate based on pot size and action history.
"""
function calculate_investments(node::TreeNode.GameNode, params::GameTypes.GameParams)
    # For terminal nodes, we can calculate investments from pot and action history
    # The pot contains all investments from both players
    
    # Start with initial blinds
    investments = PlayerInvestment(
        Float32(params.small_blind),  # SB posts small blind
        Float32(params.big_blind)      # BB posts big blind
    )
    
    # If this is the root, return initial blinds
    if node.parent === nothing
        return investments
    end
    
    # Simple approach: for fold terminals, the pot tells us total invested
    # We need to figure out how much each player put in based on betting history
    if node.is_terminal && node.terminal_type == 1  # Fold
        # Count raises in the betting history to determine investments
        betting_history = node.betting_history
        
        # Track current bet level (how much to call)
        current_bet_p0 = Float32(params.small_blind)
        current_bet_p1 = Float32(params.big_blind)
        
        # Who acts first preflop? Player 0 (SB)
        current_player = 0
        
        for (i, action_char) in enumerate(betting_history)
            bet_size = TreeNode.get_bet_size(node.street, params)
            
            if action_char == 'c'  # Call or check
                if i == 1 && current_player == 0 && node.street == TreeNode.Preflop
                    # SB limping - needs to match BB
                    additional = Float32(params.big_blind) - current_bet_p0
                    investments.player0 += additional
                    current_bet_p0 = Float32(params.big_blind)
                elseif current_bet_p0 < current_bet_p1
                    # P0 calling P1's bet
                    additional = current_bet_p1 - current_bet_p0
                    investments.player0 += additional
                    current_bet_p0 = current_bet_p1
                elseif current_bet_p1 < current_bet_p0
                    # P1 calling P0's bet
                    additional = current_bet_p0 - current_bet_p1
                    investments.player1 += additional
                    current_bet_p1 = current_bet_p0
                end
            elseif action_char == 'r'  # Raise
                if current_player == 0
                    # P0 raises
                    new_bet_level = current_bet_p1 + bet_size
                    additional = new_bet_level - current_bet_p0
                    investments.player0 += additional
                    current_bet_p0 = new_bet_level
                else
                    # P1 raises
                    new_bet_level = current_bet_p0 + bet_size
                    additional = new_bet_level - current_bet_p1
                    investments.player1 += additional
                    current_bet_p1 = new_bet_level
                end
            elseif action_char == 'f'  # Fold
                # Folding player has already invested what they've put in
                break
            end
            
            # Alternate players
            current_player = 1 - current_player
        end
    else
        # For non-fold terminals, use the simpler pot division approach
        # Each player has invested half the pot on average (placeholder)
        total_pot = node.pot
        investments.player0 = total_pot / 2
        investments.player1 = total_pot / 2
    end
    
    return investments
end

"""
    evaluate_fold_utility(node::GameNode, params::GameParams)

Calculate utilities when one player folds.
The folding player loses their investment, the other player wins the pot.
"""
function evaluate_fold_utility(node::TreeNode.GameNode, params::GameTypes.GameParams)
    investments = calculate_investments(node, params)
    
    # Determine who folded based on the last action
    if length(node.action_history) > 0 && node.action_history[end] == GameTypes.Fold
        # The parent's player is who folded
        folding_player = node.parent !== nothing ? node.parent.player : 0
        
        if folding_player == 0
            # Player 0 (SB) folded, Player 1 (BB) wins
            # Player 0's utility is negative their investment
            # Player 1's utility is the pot minus their investment
            utility0 = -investments.player0
            utility1 = investments.player0  # What P1 wins from P0
        else
            # Player 1 (BB) folded, Player 0 (SB) wins
            utility0 = investments.player1  # What P0 wins from P1
            utility1 = -investments.player1
        end
    else
        # Shouldn't happen, but default to even split
        utility0 = 0.0f0
        utility1 = 0.0f0
    end
    
    return (utility0, utility1)
end

"""
    evaluate_showdown_utility(node::GameNode, params::GameParams, 
                             player0_cards::Vector{Card}, player1_cards::Vector{Card},
                             board_cards::Vector{Card})

Calculate utilities at showdown based on hand strengths.
Note: In the current implementation, we don't have actual cards yet,
so this returns placeholder values. This will be updated when we add card dealing.
"""
function evaluate_showdown_utility(node::TreeNode.GameNode, params::GameTypes.GameParams,
                                 player0_cards::Union{Nothing, Vector{GameTypes.Card}} = nothing,
                                 player1_cards::Union{Nothing, Vector{GameTypes.Card}} = nothing,
                                 board_cards::Union{Nothing, Vector{GameTypes.Card}} = nothing)
    investments = calculate_investments(node, params)
    
    # If we don't have cards yet (current implementation), return placeholder
    if player0_cards === nothing || player1_cards === nothing
        # Placeholder: split the pot evenly (0 EV for both)
        # This will be replaced with actual hand evaluation
        return (0.0f0, 0.0f0)
    end
    
    # Evaluate hands
    all_cards0 = vcat(player0_cards, board_cards)
    all_cards1 = vcat(player1_cards, board_cards)
    
    if length(all_cards0) == 7 && length(all_cards1) == 7
        # River showdown - evaluate 7-card hands
        rank0 = Evaluator.rank7(all_cards0...)
        rank1 = Evaluator.rank7(all_cards1...)
    elseif length(all_cards0) >= 5
        # Earlier streets - evaluate best 5-card hand
        # For now, just use the first 5 cards (placeholder)
        rank0 = Evaluator.eval5(all_cards0[1:5]...)
        rank1 = Evaluator.eval5(all_cards1[1:5]...)
    else
        # Not enough cards, shouldn't happen
        return (0.0f0, 0.0f0)
    end
    
    # Lower rank is better in our evaluator
    total_pot = investments.player0 + investments.player1
    
    if rank0 < rank1
        # Player 0 wins
        utility0 = total_pot - investments.player0  # Net profit
        utility1 = -investments.player1            # Net loss
    elseif rank1 < rank0
        # Player 1 wins
        utility0 = -investments.player0            # Net loss
        utility1 = total_pot - investments.player1  # Net profit
    else
        # Split pot
        half_pot = total_pot / 2
        utility0 = half_pot - investments.player0
        utility1 = half_pot - investments.player1
    end
    
    return (utility0, utility1)
end

"""
    evaluate_terminal_node!(node::GameNode, params::GameParams)

Evaluate a terminal node and set its utilities.
This is the main entry point for terminal node evaluation.
"""
function evaluate_terminal_node!(node::TreeNode.GameNode, params::GameTypes.GameParams)
    if !node.is_terminal
        error("Cannot evaluate non-terminal node")
    end
    
    if node.terminal_type == 1
        # Fold terminal
        node.utilities = evaluate_fold_utility(node, params)
    elseif node.terminal_type == 2
        # Showdown terminal
        # For now, use placeholder since we don't have cards yet
        node.utilities = evaluate_showdown_utility(node, params)
    else
        # Unknown terminal type
        node.utilities = (0.0f0, 0.0f0)
    end
    
    return node.utilities
end

"""
    evaluate_all_terminals!(tree::GameTree)

Evaluate all terminal nodes in the game tree.
"""
function evaluate_all_terminals!(tree, params::GameTypes.GameParams)
    for node in tree.terminal_nodes
        evaluate_terminal_node!(node, params)
    end
end

# Export functions
export PlayerInvestment
export calculate_investments
export evaluate_fold_utility, evaluate_showdown_utility
export evaluate_terminal_node!, evaluate_all_terminals!

end # module
