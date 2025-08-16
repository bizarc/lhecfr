module Evaluator
using ..GameTypes

# Hand category order (low→high) for packing:
# 0 HighCard, 1 OnePair, 2 TwoPair, 3 Trips, 4 Straight, 5 Flush, 6 FullHouse, 7 Quads, 8 StraightFlush
const CAT_HIGH       = 0
const CAT_PAIR       = 1
const CAT_TWOPAIR    = 2
const CAT_TRIPS      = 3
const CAT_STRAIGHT   = 4
const CAT_FLUSH      = 5
const CAT_FULLHOUSE  = 6
const CAT_QUADS      = 7
const CAT_STFLUSH    = 8

# Bit masks for straight detection (ranks 2..A mapped to bits 0..12)
# Includes wheel A-5 (bits for A,5,4,3,2)
const STRAIGHT_MASKS = let m = UInt32[]
    # Regular 5-in-a-row from A-high (14) down to 6-high (i.e., bits 12..8 down to 4..0)
    # Map rank r in 2..14 to bit (r-2). A-high straight is bits for 10,J,Q,K,A = 10..14 → 8..12
    for top in 14:-1:6
        low = top - 4
        push!(m, foldl(|, (UInt32(1) << (r-2) for r in low:top)))
    end
    # Wheel: A,2,3,4,5 → bits {12,0,1,2,3}
    push!(m, (UInt32(1)<<(14-2)) | (UInt32(1)<<(5-2)) | (UInt32(1)<<(4-2)) | (UInt32(1)<<(3-2)) | (UInt32(1)<<(2-2)))
    m
end

@inline function rank_to_bit(r::UInt8)::UInt32
    return UInt32(1) << (r - 2)  # 2→bit0, …, A(14)→bit12
end

# Pack a hand strength into a single Int:
# (category << 24) | (k1 << 16) | (k2 << 12) | (k3 << 8) | (k4 << 4) | k5
# Where ki are 4-bit fields for ranks (2..14) after biasing to 0..12. This gives a strict total order.
@inline function pack_hand(cat::Int, ks::NTuple{5,UInt8})::Int
    # bias ranks (2..14) to 0..12 for compact packing
    b = ntuple(i->UInt32(ks[i]-2), 5)
    return Int((UInt32(cat) << 24) | (b[1] << 16) | (b[2] << 12) | (b[3] << 8) | (b[4] << 4) | b[5])
end

# Extract top-k ranks from a rank mask (descending), return up to 5
@inline function topk_from_mask(mask::UInt32, k::Int)::NTuple{5,UInt8}
    res = UInt8[2,2,2,2,2]
    idx = 1
    # Iterate ranks high→low (A..2)
    @inbounds for r in 14:-1:2
        if (mask & rank_to_bit(UInt8(r))) != 0
            res[idx] = UInt8(r)
            idx += 1
            if idx > k; break; end
        end
    end
    # pad with 2s if fewer than k
    return (res[1], res[2], res[3], res[4], res[5])
end

@inline function has_straight_mask(mask::UInt32)::Tuple{Bool,UInt8}
    # Return (true, high_rank) if straight present, handling wheel properly
    @inbounds for i in 1:9  # 1..9 are non-wheel straights in our list
        sm = STRAIGHT_MASKS[i]
        if (mask & sm) == sm
            # top rank descends from A(14) to 6; i=1 → A-high (14), i=9 → 6-high
            top = UInt8(15 - i)  # 14,13,..,6
            return (true, top)
        end
    end
    # wheel is last entry
    smw = STRAIGHT_MASKS[end]
    if (mask & smw) == smw
        return (true, UInt8(5))  # 5-high straight
    end
    return (false, UInt8(0))
end

@inline function eval5(cards::NTuple{5,GameTypes.Card})::Int
    # Count ranks/suits and build masks
    rankCounts = zeros(UInt8, 15)  # index 2..14 used
    suitCounts = zeros(UInt8, 4)
    rankMask  = UInt32(0)
    suitMask  = zeros(UInt32, 4)  # per-suit rank masks

    @inbounds for i in 1:5
        c = cards[i]
        r = c.rank
        s = c.suit + 1 # 1..4
        rankCounts[Int(r)] += 1
        suitCounts[Int(s)] += 1
        b = rank_to_bit(r)
        rankMask |= b
        suitMask[Int(s)] |= b
    end

    # Check flush / straight / straight-flush
    flushSuit = 0
    @inbounds for s in 1:4
        if suitCounts[s] >= 5
            flushSuit = s; break
        end
    end

    if flushSuit != 0
        fmask = suitMask[flushSuit]
        haveSF, top = has_straight_mask(fmask)
        if haveSF
            # Straight flush; tiebreak by top card of straight
            return pack_hand(CAT_STFLUSH, (top, UInt8(2), UInt8(2), UInt8(2), UInt8(2)))
        end
    end

    # Multiples: collect ranks by their counts
    quads = UInt8(0); trips = UInt8[]
    pairs = UInt8[]
    singlesMask = UInt32(0)

    @inbounds for r in 14:-1:2
        cnt = rankCounts[Int(r)]
        if cnt == 4
            quads = UInt8(r)
        elseif cnt == 3
            push!(trips, UInt8(r))
        elseif cnt == 2
            push!(pairs, UInt8(r))
        elseif cnt == 1
            singlesMask |= rank_to_bit(UInt8(r))
        end
    end

    if quads != 0
        # Quads + highest kicker
        k = topk_from_mask(singlesMask, 1)
        return pack_hand(CAT_QUADS, (quads, k[1], UInt8(2), UInt8(2), UInt8(2)))
    end

    if length(trips) > 0 && (length(pairs) > 0 || length(trips) >= 2)
        # Full house: best trips + best pair (or second trips as pair)
        t = trips[1]
        p = length(pairs) > 0 ? pairs[1] : trips[2]
        return pack_hand(CAT_FULLHOUSE, (t, p, UInt8(2), UInt8(2), UInt8(2)))
    end

    if flushSuit != 0
        # Flush: top 5 cards of flush suit
        ks = topk_from_mask(suitMask[flushSuit], 5)
        return pack_hand(CAT_FLUSH, ks)
    end

    haveS, topS = has_straight_mask(rankMask)
    if haveS
        return pack_hand(CAT_STRAIGHT, (topS, UInt8(2), UInt8(2), UInt8(2), UInt8(2)))
    end

    if length(trips) > 0
        # Trips + two top kickers
        k = topk_from_mask(singlesMask, 2)
        return pack_hand(CAT_TRIPS, (trips[1], k[1], k[2], UInt8(2), UInt8(2)))
    end

    if length(pairs) >= 2
        # Two pair: top two pairs + best kicker
        p1, p2 = pairs[1], pairs[2]
        k = topk_from_mask(singlesMask, 1)
        return pack_hand(CAT_TWOPAIR, (p1, p2, k[1], UInt8(2), UInt8(2)))
    end

    if length(pairs) == 1
        # One pair + three kickers
        k = topk_from_mask(singlesMask, 3)
        return pack_hand(CAT_PAIR, (pairs[1], k[1], k[2], k[3], UInt8(2)))
    end

    # High card: top five singles
    ks = topk_from_mask(singlesMask, 5)
    return pack_hand(CAT_HIGH, ks)
end

# 7-card evaluator: choose best 5 of 7
@inline function rank7(hole::NTuple{2,GameTypes.Card}, board::NTuple{5,GameTypes.Card})::Int
    # Build a small local array of 7 cards
    c = Vector{GameTypes.Card}(undef, 7)
    c[1] = hole[1]; c[2] = hole[2]
    c[3] = board[1]; c[4] = board[2]; c[5] = board[3]; c[6] = board[4]; c[7] = board[5]

    best = typemin(Int)
    # Iterate all 21 5-card subsets (simple double loop)
    @inbounds for i1 in 1:3
        for i2 in (i1+1):4
            for i3 in (i2+1):5
                for i4 in (i3+1):6
                    for i5 in (i4+1):7
                        v = eval5( (c[i1], c[i2], c[i3], c[i4], c[i5]) )
                        if v > best; best = v; end
                    end
                end
            end
        end
    end
    return best
end

end # module