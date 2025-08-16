# test/test_eval.jl
using Test, LHECFR, LHECFR.GameTypes, LHECFR.Evaluator

@testset "Evaluator Tests" begin
    # Create cards for testing
    A♠ = GameTypes.Card(14,3); K♠ = GameTypes.Card(13,3)
    Q♠ = GameTypes.Card(12,3); J♠ = GameTypes.Card(11,3); T♠ = GameTypes.Card(10,3)
    A♥ = GameTypes.Card(14,2); K♥ = GameTypes.Card(13,2)
    Q♥ = GameTypes.Card(12,2); J♥ = GameTypes.Card(11,2); T♥ = GameTypes.Card(10,2)
    A♦ = GameTypes.Card(14,1); K♦ = GameTypes.Card(13,1); Q♦ = GameTypes.Card(12,1)
    J♦ = GameTypes.Card(11,1)
    A♣ = GameTypes.Card(14,0); K♣ = GameTypes.Card(13,0); J♣ = GameTypes.Card(11,0)
    _9♠ = GameTypes.Card(9,3); _8♠ = GameTypes.Card(8,3)
    _7♠ = GameTypes.Card(7,3); _6♠ = GameTypes.Card(6,3); _5♠ = GameTypes.Card(5,3)
    _4♠ = GameTypes.Card(4,3); _3♠ = GameTypes.Card(3,3); _2♠ = GameTypes.Card(2,3)
    _2♣ = GameTypes.Card(2,0); _3♦ = GameTypes.Card(3,1)
    _4♦ = GameTypes.Card(4,1); _5♦ = GameTypes.Card(5,1)
    _7♥ = GameTypes.Card(7,2); _8♣ = GameTypes.Card(8,0)
    
    @testset "5-card evaluator" begin
        # Test royal flush (strongest hand)
        royal_flush = Evaluator.eval5((A♠, K♠, Q♠, J♠, T♠))
        @test royal_flush > 0
        
        # Test straight flush
        straight_flush = Evaluator.eval5((_9♠, _8♠, _7♠, _6♠, _5♠))
        @test straight_flush > 0
        @test royal_flush > straight_flush  # Royal flush beats regular straight flush
        
        # Test four of a kind
        quads = Evaluator.eval5((A♠, A♥, A♦, A♣, K♠))
        @test quads > 0
        @test straight_flush > quads  # Straight flush beats quads
        
        # Test full house
        full_house = Evaluator.eval5((A♠, A♥, A♦, K♠, K♥))
        @test full_house > 0
        @test quads > full_house  # Quads beat full house
        
        # Test flush
        flush = Evaluator.eval5((A♠, K♠, Q♠, J♠, _9♠))
        @test flush > 0
        @test full_house > flush  # Full house beats flush
        
        # Test straight
        straight = Evaluator.eval5((A♠, K♥, Q♦, J♣, T♠))
        @test straight > 0
        @test flush > straight  # Flush beats straight
        
        # Test wheel (A-5 straight)
        wheel = Evaluator.eval5((A♠, _5♦, _4♦, _3♦, _2♣))
        @test wheel > 0
        
        # Test three of a kind
        trips = Evaluator.eval5((A♠, A♥, A♦, K♠, Q♥))
        @test trips > 0
        @test straight > trips  # Straight beats trips
        
        # Test two pair
        two_pair = Evaluator.eval5((A♠, A♥, K♠, K♥, Q♦))
        @test two_pair > 0
        @test trips > two_pair  # Trips beat two pair
        
        # Test one pair
        one_pair = Evaluator.eval5((A♠, A♥, K♠, Q♥, J♦))
        @test one_pair > 0
        @test two_pair > one_pair  # Two pair beats one pair
        
        # Test high card
        high_card = Evaluator.eval5((A♠, K♥, Q♦, J♣, _9♠))
        @test high_card > 0
        @test one_pair > high_card  # One pair beats high card
    end
    
    @testset "7-card evaluator" begin
        # Test royal flush from 7 cards
        rf_score = Evaluator.rank7((A♠,K♠), (Q♠,J♠,T♠,_2♣,_3♦))
        @test rf_score > 0  # Royal flush should be very strong
        
        # Test finding best 5 from 7 cards
        # Should find the flush (5 spades) from these 7 cards
        flush_score = Evaluator.rank7((A♠,K♠), (Q♠,_9♠,_7♠,A♥,K♥))
        @test flush_score > 0
        
        # Test that same hand values are equal
        hand1 = Evaluator.rank7((A♠,A♥), (A♦,K♠,Q♠,J♠,T♠))
        hand2 = Evaluator.rank7((A♠,A♥), (A♦,K♠,Q♠,J♠,T♠))
        @test hand1 == hand2
    end
    
    @testset "Hand rankings order" begin
        # Create example hands of each type
        rf = Evaluator.eval5((A♠, K♠, Q♠, J♠, T♠))           # Royal flush
        sf = Evaluator.eval5((_9♠, _8♠, _7♠, _6♠, _5♠))      # Straight flush
        quads = Evaluator.eval5((A♠, A♥, A♦, A♣, K♠))        # Four of a kind
        fh = Evaluator.eval5((A♠, A♥, A♦, K♠, K♥))           # Full house
        flush = Evaluator.eval5((A♠, K♠, Q♠, J♠, _9♠))       # Flush
        straight = Evaluator.eval5((T♠, _9♠, _8♣, _7♥, _6♠)) # Straight
        trips = Evaluator.eval5((A♠, A♥, A♦, K♠, Q♥))        # Three of a kind
        twop = Evaluator.eval5((A♠, A♥, K♠, K♥, Q♦))         # Two pair
        pair = Evaluator.eval5((A♠, A♥, K♠, Q♥, J♦))         # One pair
        high = Evaluator.eval5((A♠, K♥, Q♦, J♣, _9♠))        # High card
        
        # Verify the correct ordering
        @test rf > sf > quads > fh > flush > straight > trips > twop > pair > high
    end
end