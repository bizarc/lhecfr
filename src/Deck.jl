module Deck
using ..GameTypes

# 52-card deck creation / iteration
function full_deck()
    cards = GameTypes.Card[]
    for s in GameTypes.SUITS, r in GameTypes.RANKS
        push!(cards, GameTypes.Card(r, s))
    end
    cards
end

end # module
