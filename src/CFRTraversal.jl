"""
    CFRTraversal

Module implementing the core CFR traversal algorithm for computing
counterfactual values and updating regrets.
"""
module CFRTraversal

using ..GameTypes
using ..Tree
using ..Tree.TreeNode
using ..Tree.InfoSet
using ..Tree.InfoSetManager
using ..Tree.TerminalEvaluation
using ..CFR
using ..Evaluator

"""
    cfr_traverse(state::CFRState, tree::GameTree, node::GameNode, 
                reach_probs::Tuple{Float64, Float64},
                player_cards::Vector{Vector{Card}},
                board_cards::Vector{Card})

Main CFR traversal function that recursively walks the game tree,
computes counterfactual values, and updates regrets.

# Arguments
- `state`: The CFR state containing regrets and strategies
- `tree`: The game tree structure
- `node`: Current node being visited
- `reach_probs`: Tuple of (P1_reach, P2_reach) probabilities
- `player_cards`: Hole cards for each player [P1_cards, P2_cards]
- `board_cards`: Community cards on the board

# Returns
- Counterfactual value for the current player
"""
function cfr_traverse(state::CFR.CFRState, tree::Tree.GameTree, node::TreeNode.GameNode,
                     reach_probs::Tuple{Float64, Float64},
                     player_cards::Vector{Vector{GameTypes.Card}},
                     board_cards::Vector{GameTypes.Card})
    
    # Terminal node - return utility
    if TreeNode.is_terminal_node(node)
        return evaluate_terminal_utility(tree, node, player_cards, board_cards)
    end
    
    # Chance node - weighted average of children
    if TreeNode.is_chance_node(node)
        return handle_chance_node(state, tree, node, reach_probs, player_cards, board_cards)
    end
    
    # Player node - compute strategy and recurse
    return handle_player_node(state, tree, node, reach_probs, player_cards, board_cards)
end

"""
    evaluate_terminal_utility(tree::GameTree, node::GameNode,
                            player_cards::Vector{Vector{Card}},
                            board_cards::Vector{Card})

Evaluate the utility at a terminal node.
For fold nodes, uses the pot distribution.
For showdown nodes, evaluates hand strengths.
"""
function evaluate_terminal_utility(tree::Tree.GameTree, node::TreeNode.GameNode,
                                  player_cards::Vector{Vector{GameTypes.Card}},
                                  board_cards::Vector{GameTypes.Card})
    # Get utilities from terminal evaluation
    if node.utilities !== nothing
        # Utilities already computed
        return node.utilities[1]  # Return P1's utility
    end
    
    # Check if this is a fold
    if endswith(node.betting_history, "f")
        # Someone folded - use pot distribution
        # The folding player loses their investment
        last_actor = length(node.betting_history) % 2 == 0 ? 2 : 1
        folding_player = last_actor
        
        # Calculate investments - need GameParams for pot calculations
        params = tree.params
        investments = TerminalEvaluation.calculate_investments(node, params)
        
        # player0 in investments is SB/BTN (player 1 in our tree)
        # player1 in investments is BB (player 2 in our tree)
        if folding_player == 1
            # P1 (SB) folded, P2 (BB) wins pot
            # P1 loses their investment
            return -investments.player0
        else
            # P2 (BB) folded, P1 (SB) wins pot
            # P1 wins P2's investment
            return investments.player1
        end
    end
    
    # Showdown - evaluate hands to determine winner
    # Check if we have cards to evaluate
    if isempty(player_cards[1]) || isempty(player_cards[2]) || length(board_cards) < 5
        # No cards dealt or incomplete board - can't evaluate showdown
        # In a real implementation, we'd need to handle this case properly
        # For now, return 0 (neutral outcome)
        return 0.0
    end
    
    # Evaluate both hands
    p1_hand = (player_cards[1][1], player_cards[1][2])
    p2_hand = (player_cards[2][1], player_cards[2][2])
    board = (board_cards[1], board_cards[2], board_cards[3], board_cards[4], board_cards[5])
    
    p1_strength = Evaluator.rank7(p1_hand, board)
    p2_strength = Evaluator.rank7(p2_hand, board)
    
    # Calculate the pot
    params = tree.params
    investments = TerminalEvaluation.calculate_investments(node, params)
    total_pot = investments.player0 + investments.player1
    
    # Determine winner and return P1's utility
    if p1_strength > p2_strength
        # P1 wins the pot
        return total_pot - investments.player0  # P1's profit = pot - investment
    elseif p2_strength > p1_strength
        # P2 wins the pot
        return -investments.player0  # P1 loses their investment
    else
        # Split pot
        return (total_pot / 2.0) - investments.player0  # P1 gets half pot minus investment
    end
end

"""
    handle_chance_node(state::CFRState, tree::GameTree, node::GameNode,
                      reach_probs::Tuple{Float64, Float64},
                      player_cards::Vector{Vector{Card}},
                      board_cards::Vector{Card})

Handle a chance node by taking weighted average of child values.
"""
function handle_chance_node(state::CFR.CFRState, tree::Tree.GameTree, node::TreeNode.GameNode,
                          reach_probs::Tuple{Float64, Float64},
                          player_cards::Vector{Vector{GameTypes.Card}},
                          board_cards::Vector{GameTypes.Card})
    # For chance nodes, return average value over all possible outcomes
    # In poker, this would be dealing cards
    # For now, we'll assume uniform probability over children
    
    if length(node.children) == 0
        return 0.0
    end
    
    total_value = 0.0
    num_children = length(node.children)
    
    for child in node.children
        # Equal probability for each child (simplified)
        child_value = cfr_traverse(state, tree, child, reach_probs, player_cards, board_cards)
        total_value += child_value / num_children
    end
    
    return total_value
end

"""
    handle_player_node(state::CFRState, tree::GameTree, node::GameNode,
                      reach_probs::Tuple{Float64, Float64},
                      player_cards::Vector{Vector{Card}},
                      board_cards::Vector{Card})

Handle a player node by computing strategy, recursing on children,
and updating regrets.
"""
function handle_player_node(state::CFR.CFRState, tree::Tree.GameTree, node::TreeNode.GameNode,
                          reach_probs::Tuple{Float64, Float64},
                          player_cards::Vector{Vector{GameTypes.Card}},
                          board_cards::Vector{GameTypes.Card})
    current_player = Int(node.player)
    num_actions = length(node.children)
    
    if num_actions == 0
        return 0.0
    end
    
    # Get or create information set
    hole_cards = current_player == 1 ? player_cards[1] : player_cards[2]
    cfr_infoset = CFR.get_or_create_infoset_for_node(state, node, hole_cards, board_cards)
    
    # Get current strategy from regrets
    strategy = CFR.compute_strategy_from_regrets(cfr_infoset, state.config)
    
    # Compute counterfactual values for each action
    action_values = zeros(Float64, num_actions)
    
    for (i, child) in enumerate(node.children)
        # Update reach probabilities
        new_reach_probs = if current_player == 1
            (reach_probs[1] * strategy[i], reach_probs[2])
        else
            (reach_probs[1], reach_probs[2] * strategy[i])
        end
        
        # Recurse
        action_values[i] = cfr_traverse(state, tree, child, new_reach_probs, 
                                      player_cards, board_cards)
    end
    
    # Compute node value (expected value under current strategy)
    node_value = sum(strategy[i] * action_values[i] for i in 1:num_actions)
    
    # Update regrets and strategy sum
    if current_player == 1
        # Update regrets for P1
        opponent_reach = reach_probs[2]
        if opponent_reach > 0
            CFR.update_regrets!(state, cfr_infoset, action_values, node_value)
            CFR.update_strategy_sum!(state, cfr_infoset, strategy, reach_probs[1])
        end
    else
        # Update regrets for P2
        opponent_reach = reach_probs[1]
        if opponent_reach > 0
            # Negate values for P2 (zero-sum game)
            negated_values = -action_values
            negated_node_value = -node_value
            CFR.update_regrets!(state, cfr_infoset, negated_values, negated_node_value)
            CFR.update_strategy_sum!(state, cfr_infoset, strategy, reach_probs[2])
        end
    end
    
    return node_value
end

"""
    run_cfr_iteration!(state::CFRState, tree::GameTree)

Run a single iteration of CFR, traversing the tree for both players.
"""
function run_cfr_iteration!(state::CFR.CFRState, tree::Tree.GameTree)
    # For now, we'll do a simplified version without actual card dealing
    # In a full implementation, we'd sample or iterate over all card combinations
    
    # Start with uniform reach probabilities
    initial_reach = (1.0, 1.0)
    
    # Empty cards for now (will be expanded with card dealing)
    player_cards = [GameTypes.Card[], GameTypes.Card[]]
    board_cards = GameTypes.Card[]
    
    # Traverse from root
    cfr_traverse(state, tree, tree.root, initial_reach, player_cards, board_cards)
end

"""
    run_cfr_iteration_with_cards!(state::CFRState, tree::GameTree,
                                 p1_cards::Vector{Card}, p2_cards::Vector{Card},
                                 board::Vector{Card})

Run a CFR iteration with specific cards dealt.
"""
function run_cfr_iteration_with_cards!(state::CFR.CFRState, tree::Tree.GameTree,
                                      p1_cards::Vector{GameTypes.Card},
                                      p2_cards::Vector{GameTypes.Card},
                                      board::Vector{GameTypes.Card})
    # Start with uniform reach probabilities
    initial_reach = (1.0, 1.0)
    
    # Set up player cards
    player_cards = [p1_cards, p2_cards]
    
    # Traverse from root
    cfr_traverse(state, tree, tree.root, initial_reach, player_cards, board)
end

"""
    compute_exploitability(state::CFRState, tree::GameTree)

Compute the exploitability of the current strategy profile.
Returns the sum of best response values for both players.
"""
function compute_exploitability(state::CFR.CFRState, tree::Tree.GameTree)
    # This is a simplified version
    # Full implementation would compute best response for each player
    # For now, return a placeholder
    return 0.0
end

"""
    train!(tree::GameTree, state::CFRState; kwargs...)

Main training function that runs CFR iterations.
This replaces the stub in CFR.jl.
"""
function train!(tree::Tree.GameTree, state::CFR.CFRState; 
               iterations::Int = 1000, verbose::Bool = true)
    state.total_iterations = iterations
    
    if verbose
        println("Starting CFR training for $iterations iterations...")
        println("Configuration:")
        println("  CFR+: $(state.config.use_cfr_plus)")
        println("  Linear weighting: $(state.config.use_linear_weighting)")
        println("  Sampling: $(state.config.use_sampling)")
        println("  Tree nodes: $(tree.num_nodes)")
    end
    
    for iter in 1:iterations
        state.iteration = iter
        
        # Run CFR iteration
        run_cfr_iteration!(state, tree)
        
        # Compute exploitability periodically
        if iter % max(1, iterations ÷ 10) == 0
            state.exploitability = compute_exploitability(state, tree)
            push!(state.convergence_history, state.exploitability)
        end
        
        if verbose
            CFR.print_progress(state)
        end
    end
    
    if verbose
        CFR.print_progress(state, force=true)
        println("Training complete!")
        println("Final information sets: $(CFR.get_infoset_count(state))")
    end
    
    return state
end

# Export functions
export cfr_traverse, evaluate_terminal_utility
export handle_chance_node, handle_player_node
export run_cfr_iteration!, run_cfr_iteration_with_cards!
export compute_exploitability, train!

end # module
