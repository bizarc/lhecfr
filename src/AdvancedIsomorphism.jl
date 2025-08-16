"""
    AdvancedIsomorphism

Module for advanced card isomorphism including board texture equivalence
and turn/river canonicalization.
"""
module AdvancedIsomorphism

using ..GameTypes
using ..InfoSet

# --- Board Texture Classification ---

"""
Board texture categories for strategic equivalence.
"""
@enum BoardTexture begin
    # Flop Textures
    Rainbow           # Three different suits
    TwoTone          # Two cards of same suit
    Monotone         # Three cards of same suit
    
    # Connectivity
    Connected        # Cards in sequence (e.g., 9-10-J)
    Gapped           # One gap (e.g., 9-10-Q)
    Disconnected     # No connectivity
    
    # Pairing
    Paired           # Board has a pair
    Trips            # Board has trips
    Unpaired         # No pairs
    
    # Height
    HighCard         # Highest card A-K
    MediumCard       # Highest card Q-9
    LowCard          # Highest card 8-2
end

"""
    BoardFeatures

Comprehensive board texture features for canonicalization.
"""
struct BoardFeatures
    # Basic features
    num_suits::UInt8           # Number of different suits (1-4)
    max_suit_count::UInt8      # Maximum cards of same suit
    is_paired::Bool            # Has at least one pair
    is_trips::Bool             # Has trips
    
    # Connectivity features
    straight_draws::UInt8      # Number of possible straight draws
    straight_made::Bool        # Board contains a straight
    gaps::UInt8               # Number of rank gaps
    connectedness::Float32    # Connectivity score (0-1)
    
    # Rank distribution
    high_cards::UInt8         # Number of cards A-K
    medium_cards::UInt8       # Number of cards Q-9
    low_cards::UInt8          # Number of cards 8-2
    rank_spread::UInt8        # Highest rank - lowest rank
    
    # Canonical representation
    canonical_ranks::Vector{UInt8}  # Sorted, normalized ranks
    canonical_pattern::UInt32       # Bit pattern for quick comparison
end

"""
    classify_board(cards::Vector{GameTypes.Card}) -> BoardFeatures

Classify a board's texture and extract features for canonicalization.
"""
function classify_board(cards::Vector{GameTypes.Card})
    if isempty(cards)
        return BoardFeatures(
            0, 0, false, false,
            0, false, 0, 0.0f0,
            0, 0, 0, 0,
            UInt8[], UInt32(0)
        )
    end
    
    # Extract ranks and suits
    ranks = [card.rank for card in cards]
    suits = [card.suit for card in cards]
    
    # Count suits
    suit_counts = zeros(Int, 4)
    for suit in suits
        suit_counts[suit + 1] += 1
    end
    num_suits = count(x -> x > 0, suit_counts)
    max_suit_count = maximum(suit_counts)
    
    # Check for pairs/trips
    rank_counts = zeros(Int, 13)
    for rank in ranks
        rank_counts[rank + 1] += 1
    end
    max_rank_count = maximum(rank_counts)
    is_paired = max_rank_count >= 2
    is_trips = max_rank_count >= 3
    
    # Connectivity analysis
    sorted_ranks = sort(unique(ranks))
    gaps = count_gaps(sorted_ranks)
    straight_draws = count_straight_draws(sorted_ranks)
    straight_made = has_straight(sorted_ranks)
    connectedness = calculate_connectedness(sorted_ranks)
    
    # Rank distribution (0-12 where 0=2, 12=A)
    high_cards = count(r -> r >= 10, ranks)    # A, K, Q (12, 11, 10)
    medium_cards = count(r -> r >= 7 && r < 10, ranks)  # J, 10, 9 (9, 8, 7)
    low_cards = count(r -> r < 7, ranks)       # 8-2 (6-0)
    rank_spread = isempty(sorted_ranks) ? UInt8(0) : 
                  UInt8(sorted_ranks[end] - sorted_ranks[1])
    
    # Create canonical representation
    canonical_ranks = canonicalize_ranks(ranks, rank_counts)
    canonical_pattern = create_canonical_pattern(canonical_ranks, suit_counts)
    
    return BoardFeatures(
        UInt8(num_suits),
        UInt8(max_suit_count),
        is_paired,
        is_trips,
        UInt8(straight_draws),
        straight_made,
        UInt8(gaps),
        connectedness,
        UInt8(high_cards),
        UInt8(medium_cards),
        UInt8(low_cards),
        rank_spread,
        canonical_ranks,
        canonical_pattern
    )
end

"""
    count_gaps(sorted_ranks::Vector{<:Integer}) -> Int

Count the number of gaps in a sorted rank sequence.
"""
function count_gaps(sorted_ranks::Vector{<:Integer})
    if length(sorted_ranks) <= 1
        return 0
    end
    
    gaps = 0
    for i in 2:length(sorted_ranks)
        gap = sorted_ranks[i] - sorted_ranks[i-1] - 1
        if gap > 0
            gaps += gap
        end
    end
    return gaps
end

"""
    count_straight_draws(sorted_ranks::Vector{<:Integer}) -> Int

Count possible straight draws on the board.
"""
function count_straight_draws(sorted_ranks::Vector{<:Integer})
    if length(sorted_ranks) < 3
        return 0
    end
    
    draws = 0
    # Check each possible 5-card window
    for start_rank in 0:8  # 0 (2) through 8 (10) can start straights
        cards_in_window = 0
        for rank in sorted_ranks
            if rank >= start_rank && rank < start_rank + 5
                cards_in_window += 1
            end
        end
        if cards_in_window >= 3  # Need at least 3 for a draw
            draws += 1
        end
    end
    
    # Check wheel (A-2-3-4-5)
    wheel_cards = 0
    for rank in sorted_ranks
        if rank == 12 || rank <= 3  # A, 2, 3, 4, 5
            wheel_cards += 1
        end
    end
    if wheel_cards >= 3
        draws += 1
    end
    
    return draws
end

"""
    has_straight(sorted_ranks::Vector{<:Integer}) -> Bool

Check if the board contains a made straight.
"""
function has_straight(sorted_ranks::Vector{<:Integer})
    if length(sorted_ranks) < 5
        return false
    end
    
    # Check for regular straights
    for i in 1:length(sorted_ranks)-4
        if sorted_ranks[i+4] - sorted_ranks[i] == 4
            return true
        end
    end
    
    # Check for wheel
    if 12 in sorted_ranks && 0 in sorted_ranks && 
       1 in sorted_ranks && 2 in sorted_ranks && 3 in sorted_ranks
        return true
    end
    
    return false
end

"""
    calculate_connectedness(sorted_ranks::Vector{<:Integer}) -> Float32

Calculate a connectedness score from 0 (disconnected) to 1 (straight).
"""
function calculate_connectedness(sorted_ranks::Vector{<:Integer})
    if length(sorted_ranks) <= 1
        return 0.0f0
    end
    
    total_gaps = count_gaps(sorted_ranks)
    max_possible_gaps = sorted_ranks[end] - sorted_ranks[1] - (length(sorted_ranks) - 1)
    
    if max_possible_gaps == 0
        return 1.0f0  # Perfect connectivity
    end
    
    return 1.0f0 - Float32(total_gaps) / Float32(max_possible_gaps)
end

"""
    canonicalize_ranks(ranks::Vector{UInt8}, rank_counts::Vector{Int}) -> Vector{UInt8}

Create a canonical representation of ranks that preserves strategic equivalence.
"""
function canonicalize_ranks(ranks::Vector{UInt8}, rank_counts::Vector{Int})
    # Group ranks by frequency (trips, pairs, singles)
    trips = UInt8[]
    pairs = UInt8[]
    singles = UInt8[]
    
    for (idx, count) in enumerate(rank_counts)
        if count >= 3
            push!(trips, UInt8(idx - 1))
        elseif count == 2
            push!(pairs, UInt8(idx - 1))
        elseif count == 1
            push!(singles, UInt8(idx - 1))
        end
    end
    
    # Sort each group in descending order
    sort!(trips, rev=true)
    sort!(pairs, rev=true)
    sort!(singles, rev=true)
    
    # Combine in canonical order: trips, pairs, singles
    canonical = vcat(trips, pairs, singles)
    
    # Map to normalized ranks
    rank_map = Dict{UInt8, UInt8}()
    next_rank = UInt8(12)  # Start from Ace
    
    for rank in canonical
        if !haskey(rank_map, rank)
            rank_map[rank] = next_rank
            next_rank = next_rank > 0 ? next_rank - 1 : UInt8(0)
        end
    end
    
    # Apply mapping to original ranks
    return [get(rank_map, r, UInt8(0)) for r in ranks]
end

"""
    create_canonical_pattern(canonical_ranks::Vector{UInt8}, suit_counts::Vector{Int}) -> UInt32

Create a bit pattern representing the canonical board for quick comparison.
"""
function create_canonical_pattern(canonical_ranks::Vector{UInt8}, suit_counts::Vector{Int})
    pattern = UInt32(0)
    
    # Encode ranks (13 bits each for up to 5 cards = 65 bits, so we compress)
    for (i, rank) in enumerate(canonical_ranks)
        if i <= 5  # Maximum 5 community cards
            pattern |= UInt32(rank) << (4 * (i - 1))
        end
    end
    
    # Encode suit pattern (4 bits)
    suit_pattern = UInt32(0)
    for (i, count) in enumerate(suit_counts)
        if count > 0
            suit_pattern |= UInt32(min(count, 3)) << (2 * (i - 1))
        end
    end
    pattern |= suit_pattern << 20
    
    return pattern
end

# --- Turn/River Canonicalization ---

"""
    canonicalize_turn_card(flop::Vector{GameTypes.Card}, turn::GameTypes.Card) -> UInt8

Canonicalize a turn card relative to the flop texture.
Returns a category representing the strategic impact.
"""
function canonicalize_turn_card(flop::Vector{GameTypes.Card}, turn::GameTypes.Card)
    flop_features = classify_board(flop)
    combined = vcat(flop, [turn])
    turn_features = classify_board(combined)
    
    # Categorize turn card impact
    # 1. Pairing: Did it pair the board?
    if !flop_features.is_paired && turn_features.is_paired
        return UInt8(1)  # Board pairing turn
    end
    
    # 2. Flush: Did it complete/advance flush draws?
    if turn_features.max_suit_count > flop_features.max_suit_count
        if turn_features.max_suit_count == 4
            return UInt8(2)  # Flush completing turn
        else
            return UInt8(3)  # Flush advancing turn
        end
    end
    
    # 3. Straight: Did it complete/advance straight draws?
    if !flop_features.straight_made && turn_features.straight_made
        return UInt8(4)  # Straight completing turn
    elseif turn_features.straight_draws > flop_features.straight_draws
        return UInt8(5)  # Straight advancing turn
    end
    
    # 4. Rank category (0-12 where 0=2, 12=A)
    if turn.rank >= 10  # A, K, Q
        return UInt8(6)  # High card turn
    elseif turn.rank >= 7  # J, 10, 9
        return UInt8(7)  # Medium card turn
    else
        return UInt8(8)  # Low card turn
    end
end

"""
    canonicalize_river_card(flop::Vector{GameTypes.Card}, turn::GameTypes.Card, 
                          river::GameTypes.Card) -> UInt8

Canonicalize a river card relative to the flop+turn texture.
"""
function canonicalize_river_card(flop::Vector{GameTypes.Card}, turn::GameTypes.Card, 
                                river::GameTypes.Card)
    board_4cards = vcat(flop, [turn])
    features_4cards = classify_board(board_4cards)
    
    board_5cards = vcat(board_4cards, [river])
    features_5cards = classify_board(board_5cards)
    
    # Similar categorization as turn, but relative to 4-card board
    # 1. Board pairing
    if !features_4cards.is_paired && features_5cards.is_paired
        return UInt8(1)
    elseif features_4cards.is_paired && features_5cards.is_trips
        return UInt8(2)  # Board trips
    end
    
    # 2. Flush completion
    if features_5cards.max_suit_count == 5 && features_4cards.max_suit_count < 5
        return UInt8(3)
    elseif features_5cards.max_suit_count == 4 && features_4cards.max_suit_count < 4
        return UInt8(4)
    end
    
    # 3. Straight completion
    if !features_4cards.straight_made && features_5cards.straight_made
        return UInt8(5)
    end
    
    # 4. Rank-based categories (0-12 where 0=2, 12=A)
    if river.rank >= 10  # A, K, Q
        return UInt8(6)
    elseif river.rank >= 7  # J, 10, 9
        return UInt8(7)
    else
        return UInt8(8)
    end
end

# --- Isomorphic Board Mapping ---

"""
    BoardIsomorphism

Maps strategically equivalent boards to canonical representations.
"""
struct BoardIsomorphism
    flop_map::Dict{UInt32, UInt32}      # Flop pattern -> canonical
    turn_map::Dict{Tuple{UInt32, UInt8}, UInt32}  # (Flop, Turn) -> canonical
    river_map::Dict{Tuple{UInt32, UInt8}, UInt32} # (Turn pattern, River) -> canonical
end

"""
    create_isomorphism_maps() -> BoardIsomorphism

Create mapping tables for board isomorphisms.
"""
function create_isomorphism_maps()
    # In practice, these would be pre-computed and loaded
    # For now, return empty maps
    return BoardIsomorphism(
        Dict{UInt32, UInt32}(),
        Dict{Tuple{UInt32, UInt8}, UInt32}(),
        Dict{Tuple{UInt32, UInt8}, UInt32}()
    )
end

"""
    get_canonical_board(cards::Vector{GameTypes.Card}, iso_maps::BoardIsomorphism) -> UInt32

Get the canonical representation of a board using isomorphism maps.
"""
function get_canonical_board(cards::Vector{GameTypes.Card}, iso_maps::BoardIsomorphism)
    features = classify_board(cards)
    
    num_cards = length(cards)
    if num_cards == 3  # Flop
        return get(iso_maps.flop_map, features.canonical_pattern, features.canonical_pattern)
    elseif num_cards == 4  # Turn
        flop_pattern = classify_board(cards[1:3]).canonical_pattern
        turn_cat = canonicalize_turn_card(cards[1:3], cards[4])
        key = (flop_pattern, turn_cat)
        return get(iso_maps.turn_map, key, features.canonical_pattern)
    elseif num_cards == 5  # River
        turn_pattern = classify_board(cards[1:4]).canonical_pattern
        river_cat = canonicalize_river_card(cards[1:3], cards[4], cards[5])
        key = (turn_pattern, river_cat)
        return get(iso_maps.river_map, key, features.canonical_pattern)
    else
        return features.canonical_pattern
    end
end

# Export functions
export BoardTexture, BoardFeatures
export classify_board, count_gaps, count_straight_draws
export has_straight, calculate_connectedness
export canonicalize_ranks, create_canonical_pattern
export canonicalize_turn_card, canonicalize_river_card
export BoardIsomorphism, create_isomorphism_maps, get_canonical_board

end # module
