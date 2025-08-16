"""
    InfoSet

Module for information set identification and management in the CFR solver.
An information set represents all game states that are indistinguishable to a player.
"""
module InfoSet

using ..GameTypes
using ..TreeNode

"""
    CardAbstraction

Represents cards in a canonical form for information set identification.
Handles suit isomorphism to reduce the number of unique information sets.
"""
struct CardAbstraction
    ranks::Vector{UInt8}  # Card ranks (2-14, where 14 = Ace)
    suits::Vector{UInt8}  # Canonical suit assignments (0-3)
    is_suited::Vector{Bool}  # Whether cards are suited (for 2-card hands)
end

"""
    InformationSet

Complete information set representation including all observable information.
"""
struct InformationSet
    player::UInt8
    street::TreeNode.Street
    betting_history::String
    hole_cards::Union{Nothing, CardAbstraction}  # Nothing before cards are dealt
    board_cards::Union{Nothing, CardAbstraction}  # Nothing pre-flop
    id::String  # Unique identifier string
end

"""
    canonicalize_hand(cards::Vector{Card})

Convert a hand to canonical form, handling suit isomorphism.
For hole cards, we only care about:
- Ranks of the cards
- Whether they are suited or not
- Relative suit relationships

Examples:
- A♠K♠ and A♥K♥ are equivalent (both suited AK)
- A♠K♥ and A♥K♠ are equivalent (both offsuit AK)
"""
function canonicalize_hand(cards::Vector{GameTypes.Card})
    if length(cards) == 0
        return nothing
    end
    
    # Extract ranks and suits
    ranks = [c.rank for c in cards]
    suits = [c.suit for c in cards]
    
    # Sort by rank (high to low) for consistent ordering
    perm = sortperm(ranks, rev=true)
    ranks = ranks[perm]
    suits = suits[perm]
    
    # For 2-card hands, determine if suited
    if length(cards) == 2
        # Pocket pairs cannot be suited (same rank)
        is_suited = [suits[1] == suits[2] && ranks[1] != ranks[2]]
        # Canonical suits: if suited, both get suit 0; if not, first gets 0, second gets 1
        canonical_suits = is_suited[1] ? [0, 0] : [0, 1]
    else
        # For board cards, we need to preserve more suit information
        # This is a simplified version - full implementation would handle
        # flush possibilities properly
        is_suited = Bool[]
        canonical_suits = canonicalize_suits(suits)
    end
    
    return CardAbstraction(UInt8.(ranks), UInt8.(canonical_suits), is_suited)
end

"""
    canonicalize_suits(suits::Vector{<:Integer})

Map suits to canonical representation preserving equivalence classes.
This is a simplified version - a full implementation would handle
all suit isomorphisms properly.
"""
function canonicalize_suits(suits::Vector{<:Integer})
    # Map each unique suit to a canonical number (0, 1, 2, 3)
    suit_map = Dict{Int, Int}()
    next_canonical = 0
    
    canonical_suits = Int[]
    for suit in suits
        if !haskey(suit_map, suit)
            suit_map[suit] = next_canonical
            next_canonical += 1
        end
        push!(canonical_suits, suit_map[suit])
    end
    
    return canonical_suits
end

"""
    cards_to_string(card_abs::CardAbstraction)

Convert card abstraction to string representation for information set ID.
"""
function cards_to_string(card_abs::CardAbstraction)
    if length(card_abs.ranks) == 0
        return ""
    end
    
    # Convert ranks to card notation (T=10, J=11, Q=12, K=13, A=14)
    rank_chars = ['2', '3', '4', '5', '6', '7', '8', '9', 'T', 'J', 'Q', 'K', 'A']
    
    parts = String[]
    for i in 1:length(card_abs.ranks)
        rank = card_abs.ranks[i]
        rank_char = rank <= 14 && rank >= 2 ? rank_chars[rank - 1] : '?'
        push!(parts, string(rank_char))
    end
    
    # Add suit information for hole cards
    if length(card_abs.ranks) == 2 && length(card_abs.is_suited) > 0
        suffix = card_abs.is_suited[1] ? "s" : "o"  # suited or offsuit
        return join(parts) * suffix
    end
    
    return join(parts, "")
end

"""
    create_infoset_id(player::UInt8, street::Street, betting_history::String,
                      hole_cards::Union{Nothing, Vector{Card}},
                      board_cards::Union{Nothing, Vector{Card}})

Create a unique information set identifier from game state.
"""
function create_infoset_id(player::UInt8, street::TreeNode.Street, betting_history::String,
                          hole_cards::Union{Nothing, Vector{GameTypes.Card}} = nothing,
                          board_cards::Union{Nothing, Vector{GameTypes.Card}} = nothing)
    parts = String[]
    
    # Player
    push!(parts, "P$player")
    
    # Street
    street_names = ["PRE", "FLOP", "TURN", "RIVER"]
    push!(parts, street_names[Int(street) + 1])
    
    # Hole cards (if any)
    if hole_cards !== nothing && length(hole_cards) > 0
        hole_abs = canonicalize_hand(hole_cards)
        if hole_abs !== nothing
            push!(parts, cards_to_string(hole_abs))
        end
    end
    
    # Board cards (if any)
    if board_cards !== nothing && length(board_cards) > 0
        board_abs = canonicalize_hand(board_cards)
        if board_abs !== nothing
            push!(parts, "B:" * cards_to_string(board_abs))
        end
    end
    
    # Betting history
    if length(betting_history) > 0
        push!(parts, betting_history)
    end
    
    return join(parts, "|")
end

"""
    create_infoset(node::GameNode, hole_cards::Union{Nothing, Vector{Card}} = nothing,
                   board_cards::Union{Nothing, Vector{Card}} = nothing)

Create an InformationSet from a game node and card information.
"""
function create_infoset(node::TreeNode.GameNode, 
                       hole_cards::Union{Nothing, Vector{GameTypes.Card}} = nothing,
                       board_cards::Union{Nothing, Vector{GameTypes.Card}} = nothing)
    player = node.player
    street = node.street
    betting_history = node.betting_history
    
    # Canonicalize cards
    hole_abs = hole_cards !== nothing ? canonicalize_hand(hole_cards) : nothing
    board_abs = board_cards !== nothing ? canonicalize_hand(board_cards) : nothing
    
    # Create ID
    id = create_infoset_id(player, street, betting_history, hole_cards, board_cards)
    
    return InformationSet(player, street, betting_history, hole_abs, board_abs, id)
end

"""
    get_infoset_id(node::GameNode, hole_cards::Union{Nothing, Vector{Card}} = nothing,
                   board_cards::Union{Nothing, Vector{Card}} = nothing)

Get just the information set ID string for a game state.
"""
function get_infoset_id(node::TreeNode.GameNode,
                       hole_cards::Union{Nothing, Vector{GameTypes.Card}} = nothing,
                       board_cards::Union{Nothing, Vector{GameTypes.Card}} = nothing)
    return create_infoset_id(node.player, node.street, node.betting_history, 
                           hole_cards, board_cards)
end

# Export types and functions
export CardAbstraction, InformationSet
export canonicalize_hand, canonicalize_suits, cards_to_string
export create_infoset_id, create_infoset, get_infoset_id

end # module
