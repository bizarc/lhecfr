module GameTypes
using Random

# --- Card encoding ---
const RANKS = UInt8[2,3,4,5,6,7,8,9,10,11,12,13,14]  # 11=J,12=Q,13=K,14=A
const SUITS = UInt8[0,1,2,3]  # ♣, ♦, ♥, ♠ (arbitrary)

struct Card
    rank::UInt8
    suit::UInt8
end

Base.show(io::IO, c::Card) = print(io, "Card($(c.rank),$(c.suit))")

# --- Game params for HU LHE ---
struct GameParams
    small_blind::Int
    big_blind::Int
    stack::Int
    max_raises_per_street::Int
    rake_milli_bb::Int  # optional rake model (in milli big blinds)
    function GameParams(; small_blind=1, big_blind=2, stack=200, max_raises_per_street=4, rake_milli_bb=0)
        new(small_blind, big_blind, stack, max_raises_per_street, rake_milli_bb)
    end
end

# Node / infoset ids
const NodeId = Int
const ISId   = Int

# Actions in LHE
@enum Action::UInt8 begin
    Fold=0
    Call=1
    BetOrRaise=2
    Check=3
end

# Simple betting state container (street, bets this street, facing bet?, etc.)
struct BettingState
    street::UInt8   # 0=pre,1=flop,2=turn,3=river
    raises_on_street::UInt8
    to_act::UInt8   # 0=SB/BTN, 1=BB
    pending_bet::Bool
end

end # module
