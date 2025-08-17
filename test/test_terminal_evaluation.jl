using Test
using LHECFR
using LHECFR.GameTypes
using LHECFR.Tree
using LHECFR.CFR
using LHECFR.CFRTraversal
using LHECFR.Evaluator

@testset "Terminal Evaluation Tests" begin
    
    @testset "Fold Node Evaluation" begin
        # Create a small tree for testing
        params = GameTypes.GameParams(stack=10, big_blind=2, small_blind=1)
        tree = Tree.build_game_tree(params, preflop_only=true, verbose=false)
        
        # Find a fold terminal node
        fold_node = nothing
        for node in tree.nodes
            if Tree.is_terminal_node(node) && endswith(node.betting_history, "f")
                fold_node = node
                break
            end
        end
        
        @test fold_node !== nothing
        
        # Test fold evaluation without cards (should still work)
        player_cards = [GameTypes.Card[], GameTypes.Card[]]
        board_cards = GameTypes.Card[]
        
        utility = CFRTraversal.evaluate_terminal_utility(tree, fold_node, player_cards, board_cards)
        
        # Utility should be non-zero for a fold
        @test utility != 0.0
        
        # The magnitude should be reasonable (within the pot size)
        @test abs(utility) <= 10.0  # Maximum pot in our small stack game
    end
    
    @testset "Showdown Node Evaluation with Cards" begin
        params = GameTypes.GameParams(stack=100, big_blind=2, small_blind=1)
        # Use preflop-only tree for testing
        tree = Tree.build_game_tree(params, preflop_only=true, verbose=false)
        
        # Find a showdown terminal node (no fold at end)
        showdown_node = nothing
        for node in tree.nodes
            if Tree.is_terminal_node(node) && !endswith(node.betting_history, "f")
                showdown_node = node
                break
            end
        end
        
        if showdown_node !== nothing
            # Test with specific cards and a complete board
            p1_cards = [GameTypes.Card(14, 1), GameTypes.Card(14, 2)]  # AA (pocket aces)
            p2_cards = [GameTypes.Card(13, 1), GameTypes.Card(13, 3)]  # KK (pocket kings)
            board = [
                GameTypes.Card(2, 1),  # 2♠
                GameTypes.Card(3, 2),  # 3♥
                GameTypes.Card(4, 3),  # 4♦
                GameTypes.Card(7, 1),  # 7♠
                GameTypes.Card(8, 2)   # 8♥
            ]
            
            player_cards = [p1_cards, p2_cards]
            
            utility = CFRTraversal.evaluate_terminal_utility(tree, showdown_node, player_cards, board)
            
            # P1 (AA) should win against P2 (KK), so utility should be positive
            @test utility > 0
            
            # Test with cards where P2 wins
            p1_cards_weak = [GameTypes.Card(2, 0), GameTypes.Card(3, 0)]  # 23 offsuit
            p2_cards_strong = [GameTypes.Card(14, 1), GameTypes.Card(13, 1)]  # AK suited
            board_high = [
                GameTypes.Card(14, 2),  # A♥ (gives P2 a pair of aces)
                GameTypes.Card(13, 2),  # K♥ (gives P2 two pair)
                GameTypes.Card(7, 1),   # 7♠
                GameTypes.Card(8, 3),   # 8♦
                GameTypes.Card(9, 0)    # 9♣
            ]
            
            player_cards_2 = [p1_cards_weak, p2_cards_strong]
            
            utility_2 = CFRTraversal.evaluate_terminal_utility(tree, showdown_node, player_cards_2, board_high)
            
            # P2 has two pair (AA KK), P1 has nothing, so P1's utility should be negative
            @test utility_2 < 0
        else
            @test_skip "No showdown nodes found in tree"
        end
    end
    
    @testset "Split Pot Evaluation" begin
        params = GameTypes.GameParams(stack=10, big_blind=2, small_blind=1)
        tree = Tree.build_game_tree(params, preflop_only=true, verbose=false)
        
        # Find a showdown node
        showdown_node = nothing
        for node in tree.nodes
            if Tree.is_terminal_node(node) && !endswith(node.betting_history, "f")
                showdown_node = node
                break
            end
        end
        
        if showdown_node !== nothing
            # Test with identical hands (should split)
            p1_cards = [GameTypes.Card(14, 1), GameTypes.Card(13, 1)]  # AK suited
            p2_cards = [GameTypes.Card(14, 2), GameTypes.Card(13, 2)]  # AK suited (different suits)
            board = [
                GameTypes.Card(12, 0),  # Q♣
                GameTypes.Card(11, 0),  # J♣
                GameTypes.Card(10, 3),  # T♦
                GameTypes.Card(2, 3),   # 2♦
                GameTypes.Card(3, 3)    # 3♦
            ]
            
            player_cards = [p1_cards, p2_cards]
            
            utility = CFRTraversal.evaluate_terminal_utility(tree, showdown_node, player_cards, board)
            
            # With a split pot, P1's utility should be near 0 (gets back investment)
            # Allow small deviation due to rounding or odd pot sizes
            @test abs(utility) < 1.0
        end
    end
    
    @testset "Showdown without Complete Board" begin
        params = GameTypes.GameParams(stack=10, big_blind=2, small_blind=1)
        tree = Tree.build_game_tree(params, preflop_only=true, verbose=false)
        
        # Find a showdown node in preflop-only tree
        showdown_node = nothing
        for node in tree.nodes
            if Tree.is_terminal_node(node) && !endswith(node.betting_history, "f")
                showdown_node = node
                break
            end
        end
        
        if showdown_node !== nothing
            # Test with cards but no board (preflop showdown)
            p1_cards = [GameTypes.Card(14, 1), GameTypes.Card(14, 2)]  # AA
            p2_cards = [GameTypes.Card(13, 1), GameTypes.Card(13, 3)]  # KK
            board = GameTypes.Card[]  # No board cards
            
            player_cards = [p1_cards, p2_cards]
            
            utility = CFRTraversal.evaluate_terminal_utility(tree, showdown_node, player_cards, board)
            
            # Without a complete board, should return 0 (can't evaluate)
            @test utility == 0.0
        end
    end
    
    @testset "Hand Strength Comparison" begin
        # Test the evaluator directly
        
        # Royal flush vs straight flush
        hole1 = (GameTypes.Card(14, 1), GameTypes.Card(13, 1))  # A♠ K♠
        hole2 = (GameTypes.Card(9, 1), GameTypes.Card(8, 1))    # 9♠ 8♠
        board = (
            GameTypes.Card(12, 1),  # Q♠
            GameTypes.Card(11, 1),  # J♠
            GameTypes.Card(10, 1),  # T♠
            GameTypes.Card(2, 2),   # 2♥
            GameTypes.Card(3, 3)    # 3♦
        )
        
        strength1 = Evaluator.rank7(hole1, board)
        strength2 = Evaluator.rank7(hole2, board)
        
        # Royal flush beats straight flush
        @test strength1 > strength2
        
        # Full house vs flush
        hole3 = (GameTypes.Card(14, 1), GameTypes.Card(14, 2))  # A♠ A♥
        hole4 = (GameTypes.Card(7, 3), GameTypes.Card(6, 3))    # 7♦ 6♦
        board2 = (
            GameTypes.Card(14, 3),  # A♦
            GameTypes.Card(13, 3),  # K♦
            GameTypes.Card(13, 1),  # K♠
            GameTypes.Card(5, 3),   # 5♦
            GameTypes.Card(2, 2)    # 2♥
        )
        
        strength3 = Evaluator.rank7(hole3, board2)
        strength4 = Evaluator.rank7(hole4, board2)
        
        # Full house (AAA KK) beats flush
        @test strength3 > strength4
        
        # High card comparison
        hole5 = (GameTypes.Card(14, 1), GameTypes.Card(13, 2))  # A♠ K♥
        hole6 = (GameTypes.Card(14, 3), GameTypes.Card(12, 0))  # A♦ Q♣
        board3 = (
            GameTypes.Card(11, 1),  # J♠
            GameTypes.Card(9, 2),   # 9♥
            GameTypes.Card(7, 3),   # 7♦
            GameTypes.Card(5, 0),   # 5♣
            GameTypes.Card(3, 1)    # 3♠
        )
        
        strength5 = Evaluator.rank7(hole5, board3)
        strength6 = Evaluator.rank7(hole6, board3)
        
        # AK high beats AQ high
        @test strength5 > strength6
    end
    
    @testset "Pot Distribution Correctness" begin
        params = GameTypes.GameParams(stack=100, big_blind=2, small_blind=1)
        tree = Tree.build_game_tree(params, preflop_only=true, verbose=false)
        
        # Find specific betting sequences
        call_node = nothing
        raise_call_node = nothing
        
        for node in tree.nodes
            if Tree.is_terminal_node(node)
                if node.betting_history == "c" && call_node === nothing
                    call_node = node
                elseif node.betting_history == "rc" && raise_call_node === nothing
                    raise_call_node = node
                end
            end
        end
        
        if call_node !== nothing
            # Test simple call showdown
            p1_cards = [GameTypes.Card(14, 1), GameTypes.Card(14, 2)]  # AA
            p2_cards = [GameTypes.Card(2, 1), GameTypes.Card(3, 2)]    # 23
            board = [
                GameTypes.Card(7, 0), GameTypes.Card(8, 0), GameTypes.Card(9, 0),
                GameTypes.Card(10, 1), GameTypes.Card(11, 2)
            ]
            
            player_cards = [p1_cards, p2_cards]
            utility = CFRTraversal.evaluate_terminal_utility(tree, call_node, player_cards, board)
            
            # P1 wins with AA, pot is 2 BB (1 from each)
            # P1's investment is 1 BB, so profit should be 1 BB
            @test utility ≈ 1.0
        end
        
        if raise_call_node !== nothing
            # Test raise-call showdown
            p1_cards = [GameTypes.Card(7, 1), GameTypes.Card(6, 2)]  # 76 offsuit
            p2_cards = [GameTypes.Card(14, 1), GameTypes.Card(14, 2)]  # AA (pocket aces)
            board = [
                GameTypes.Card(12, 0), GameTypes.Card(11, 0), GameTypes.Card(4, 0),
                GameTypes.Card(3, 1), GameTypes.Card(2, 2)  # Q-J-4-3-2, no straight for 76
            ]
            
            player_cards = [p1_cards, p2_cards]
            utility = CFRTraversal.evaluate_terminal_utility(tree, raise_call_node, player_cards, board)
            
            # P2 wins with AA
            # In preflop rc: Both invest 4BB (raise to 4, call 4)
            # Pot is 8BB total, P1's investment is 4BB
            # P1 loses their 4BB investment
            @test utility ≈ -4.0
        end
    end
end
