"""
    BettingSequence

Module for generating valid betting sequences in Limit Hold'em.
"""
module BettingSequence

using ..GameTypes
using ..TreeNode

# --- Betting Sequence Structure ---

"""
    Sequence
    
Represents a valid betting sequence in Limit Hold'em.
"""
struct Sequence
    actions::Vector{GameTypes.Action}
    is_terminal::Bool
    terminal_type::UInt8  # 0=not terminal, 1=fold, 2=showdown/next street
    final_pot::Float32
    last_player::UInt8
end

"""
    generate_betting_sequences(street::Street, initial_pot::Float32, params::GameTypes.GameParams)
    
Generate all valid betting sequences for a given street in Limit Hold'em.
Returns a vector of Sequence objects.
"""
function generate_betting_sequences(
    street::Street, 
    initial_pot::Float32, 
    params::GameTypes.GameParams;
    initial_facing_bet::Bool = false,
    initial_player::UInt8 = UInt8(1)  # BB acts first pre-flop in heads-up
)
    sequences = Sequence[]
    
    # Helper function to recursively generate sequences
    function generate_recursive(
        actions::Vector{GameTypes.Action},
        pot::Float32,
        current_player::UInt8,
        facing_bet::Bool,
        raises_this_street::UInt8
    )
        # Check for terminal conditions
        if length(actions) > 0
            last_action = actions[end]
            
            # Fold is always terminal
            if last_action == GameTypes.Fold
                push!(sequences, Sequence(
                    copy(actions),
                    true,
                    UInt8(1),  # fold terminal
                    pot,
                    current_player
                ))
                return
            end
            
            # Check if betting round is complete
            if is_betting_complete(actions, facing_bet)
                push!(sequences, Sequence(
                    copy(actions),
                    true,
                    UInt8(2),  # showdown/next street terminal
                    pot,
                    current_player
                ))
                return
            end
        end
        
        # Switch players for next action
        next_player = current_player == 0 ? UInt8(1) : UInt8(0)
        
        # Generate valid actions for current state
        if facing_bet
            # Can fold
            new_actions = copy(actions)
            push!(new_actions, GameTypes.Fold)
            generate_recursive(new_actions, pot, next_player, false, raises_this_street)
            
            # Can call
            bet_size = TreeNode.get_bet_size(street, params)
            new_pot = pot + bet_size
            new_actions = copy(actions)
            push!(new_actions, GameTypes.Call)
            generate_recursive(new_actions, new_pot, next_player, false, raises_this_street)
            
            # Can raise if not at cap
            if raises_this_street < params.max_raises_per_street
                new_pot = pot + 2 * bet_size  # Call + raise
                new_actions = copy(actions)
                push!(new_actions, GameTypes.BetOrRaise)
                generate_recursive(new_actions, new_pot, next_player, true, raises_this_street + UInt8(1))
            end
        else
            # Can check
            new_actions = copy(actions)
            push!(new_actions, GameTypes.Check)
            generate_recursive(new_actions, pot, next_player, false, raises_this_street)
            
            # Can bet if not at cap
            if raises_this_street < params.max_raises_per_street
                bet_size = TreeNode.get_bet_size(street, params)
                new_pot = pot + bet_size
                new_actions = copy(actions)
                push!(new_actions, GameTypes.BetOrRaise)
                generate_recursive(new_actions, new_pot, next_player, true, raises_this_street + UInt8(1))
            end
        end
    end
    
    # Start generation
    generate_recursive(
        GameTypes.Action[],
        initial_pot,
        initial_player,
        initial_facing_bet,
        UInt8(0)
    )
    
    return sequences
end

"""
    is_betting_complete(actions::Vector{GameTypes.Action}, facing_bet::Bool)
    
Check if a betting round is complete based on the action sequence.
Betting is complete when:
- Both players have acted at least once
- The last action was a call or check that equalizes the bets
- Or both players have checked
"""
function is_betting_complete(actions::Vector{GameTypes.Action}, facing_bet::Bool)
    if length(actions) < 2
        return false
    end
    
    last_action = actions[end]
    
    # If last action was a call, betting is complete
    if last_action == GameTypes.Call
        return true
    end
    
    # If both players checked, betting is complete
    if last_action == GameTypes.Check && length(actions) >= 2
        second_last = actions[end-1]
        if second_last == GameTypes.Check
            return true
        end
    end
    
    return false
end

"""
    generate_preflop_sequences(params::GameTypes.GameParams)
    
Generate all valid pre-flop betting sequences for heads-up Limit Hold'em.
In heads-up, SB posts small blind, BB posts big blind, then SB acts first.
"""
function generate_preflop_sequences(params::GameTypes.GameParams)
    # In heads-up LHE:
    # - SB/BTN posts small blind
    # - BB posts big blind
    # - SB/BTN acts first (position 0)
    # - BB is facing a bet (the blind)
    
    initial_pot = Float32(params.small_blind + params.big_blind)
    
    # Note: In our representation, player 0 is SB/BTN, player 1 is BB
    # Pre-flop starts with SB/BTN acting first (player 0)
    # But BB (player 1) is facing the initial bet
    
    # We need to handle the special case of pre-flop where:
    # - If SB calls, they're calling the BB
    # - If SB raises, BB faces a raise
    # - If SB folds, BB wins
    
    sequences = Sequence[]
    
    # Generate sequences starting with SB to act
    function generate_preflop_recursive(
        actions::Vector{GameTypes.Action},
        pot::Float32,
        current_player::UInt8,
        facing_bet::Bool,
        raises_this_street::UInt8,
        sb_has_acted::Bool
    )
        # Terminal conditions
        if length(actions) > 0
            last_action = actions[end]
            
            # Fold is terminal
            if last_action == GameTypes.Fold
                push!(sequences, Sequence(
                    copy(actions),
                    true,
                    UInt8(1),  # fold terminal
                    pot,
                    current_player
                ))
                return
            end
            
            # Check if betting is complete
            if sb_has_acted && is_preflop_betting_complete(actions)
                push!(sequences, Sequence(
                    copy(actions),
                    true,
                    UInt8(2),  # go to flop
                    pot,
                    current_player
                ))
                return
            end
        end
        
        bet_size = Float32(params.big_blind)  # Pre-flop uses small bets (1 BB)
        
        if current_player == 0  # SB/BTN to act
            if !sb_has_acted
                # SB's first action: can fold, call (limp), or raise
                
                # Fold
                new_actions = copy(actions)
                push!(new_actions, GameTypes.Fold)
                generate_preflop_recursive(new_actions, pot, UInt8(1), false, raises_this_street, true)
                
                # Call (limp) - SB calls the BB
                new_pot = pot + Float32(params.small_blind)  # SB adds 1 more SB to match BB
                new_actions = copy(actions)
                push!(new_actions, GameTypes.Call)
                generate_preflop_recursive(new_actions, new_pot, UInt8(1), false, raises_this_street, true)
                
                # Raise - SB raises to 2 BB total
                if raises_this_street < params.max_raises_per_street
                    new_pot = pot + Float32(params.big_blind + params.small_blind)  # SB adds 3 SB total
                    new_actions = copy(actions)
                    push!(new_actions, GameTypes.BetOrRaise)
                    generate_preflop_recursive(new_actions, new_pot, UInt8(1), true, raises_this_street + UInt8(1), true)
                end
            else
                # SB acting again (after BB's action)
                if facing_bet
                    # Fold
                    new_actions = copy(actions)
                    push!(new_actions, GameTypes.Fold)
                    generate_preflop_recursive(new_actions, pot, UInt8(1), false, raises_this_street, true)
                    
                    # Call
                    new_pot = pot + bet_size
                    new_actions = copy(actions)
                    push!(new_actions, GameTypes.Call)
                    generate_preflop_recursive(new_actions, new_pot, UInt8(1), false, raises_this_street, true)
                    
                    # Raise if not at cap
                    if raises_this_street < params.max_raises_per_street
                        new_pot = pot + 2 * bet_size
                        new_actions = copy(actions)
                        push!(new_actions, GameTypes.BetOrRaise)
                        generate_preflop_recursive(new_actions, new_pot, UInt8(1), true, raises_this_street + UInt8(1), true)
                    end
                end
            end
        else  # BB to act (player 1)
            if facing_bet
                # BB facing a raise
                
                # Fold
                new_actions = copy(actions)
                push!(new_actions, GameTypes.Fold)
                generate_preflop_recursive(new_actions, pot, UInt8(0), false, raises_this_street, sb_has_acted)
                
                # Call
                new_pot = pot + bet_size
                new_actions = copy(actions)
                push!(new_actions, GameTypes.Call)
                generate_preflop_recursive(new_actions, new_pot, UInt8(0), false, raises_this_street, sb_has_acted)
                
                # Re-raise if not at cap
                if raises_this_street < params.max_raises_per_street
                    new_pot = pot + 2 * bet_size
                    new_actions = copy(actions)
                    push!(new_actions, GameTypes.BetOrRaise)
                    generate_preflop_recursive(new_actions, new_pot, UInt8(0), true, raises_this_street + UInt8(1), sb_has_acted)
                end
            else
                # BB after SB limps - can check or raise
                
                # Check (end pre-flop betting)
                new_actions = copy(actions)
                push!(new_actions, GameTypes.Check)
                generate_preflop_recursive(new_actions, pot, UInt8(0), false, raises_this_street, sb_has_acted)
                
                # Raise
                if raises_this_street < params.max_raises_per_street
                    new_pot = pot + bet_size
                    new_actions = copy(actions)
                    push!(new_actions, GameTypes.BetOrRaise)
                    generate_preflop_recursive(new_actions, new_pot, UInt8(0), true, raises_this_street + UInt8(1), sb_has_acted)
                end
            end
        end
    end
    
    # Start with SB to act first
    generate_preflop_recursive(
        GameTypes.Action[],
        initial_pot,
        UInt8(0),  # SB acts first
        false,  # SB not facing bet initially (they post blind)
        UInt8(0),  # no raises yet
        false  # SB hasn't acted yet
    )
    
    return sequences
end

"""
    is_preflop_betting_complete(actions::Vector{GameTypes.Action})
    
Check if pre-flop betting is complete.
Special handling for pre-flop where blinds are already posted.
"""
function is_preflop_betting_complete(actions::Vector{GameTypes.Action})
    if length(actions) < 2
        return false
    end
    
    last_action = actions[end]
    
    # If last action was call, betting is complete
    if last_action == GameTypes.Call
        return true
    end
    
    # If BB checks after SB limps, betting is complete
    if last_action == GameTypes.Check
        return true
    end
    
    return false
end

"""
    count_betting_sequences(street::Street, params::GameTypes.GameParams)
    
Count the number of valid betting sequences for a given street.
Useful for validating tree construction.
"""
function count_betting_sequences(street::Street, params::GameTypes.GameParams)
    if street == TreeNode.Preflop
        sequences = generate_preflop_sequences(params)
    else
        # Post-flop streets start with no one facing a bet
        initial_pot = Float32(10)  # Placeholder pot size
        sequences = generate_betting_sequences(street, initial_pot, params, 
                                              initial_facing_bet=false, 
                                              initial_player=UInt8(1))  # BB acts first post-flop
    end
    return length(sequences)
end

# Export functions
export Sequence
export generate_betting_sequences, is_betting_complete
export generate_preflop_sequences, is_preflop_betting_complete
export count_betting_sequences

end # module
