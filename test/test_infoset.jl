using Test
using LHECFR
using LHECFR.GameTypes
using LHECFR.Tree

@testset "InfoSet Module Tests" begin
    # Create test cards
    A♠ = GameTypes.Card(14, 0)  # Ace of spades
    A♥ = GameTypes.Card(14, 1)  # Ace of hearts
    A♦ = GameTypes.Card(14, 2)  # Ace of diamonds
    A♣ = GameTypes.Card(14, 3)  # Ace of clubs
    K♠ = GameTypes.Card(13, 0)  # King of spades
    K♥ = GameTypes.Card(13, 1)  # King of hearts
    K♦ = GameTypes.Card(13, 2)  # King of diamonds
    K♣ = GameTypes.Card(13, 3)  # King of clubs
    Q♦ = GameTypes.Card(12, 2)  # Queen of diamonds
    Q♣ = GameTypes.Card(12, 3)  # Queen of clubs
    Q♥ = GameTypes.Card(12, 1)  # Queen of hearts
    J♣ = GameTypes.Card(11, 3)  # Jack of clubs
    J♥ = GameTypes.Card(11, 1)  # Jack of hearts
    T♠ = GameTypes.Card(10, 0)  # Ten of spades
    T♥ = GameTypes.Card(10, 1)  # Ten of hearts
    
    @testset "Card Canonicalization" begin
        # Test suited hands
        @testset "Suited Hands" begin
            # A♠K♠ and A♥K♥ should be equivalent (both suited AK)
            abs1 = Tree.canonicalize_hand([A♠, K♠])
            abs2 = Tree.canonicalize_hand([A♥, K♥])
            
            @test abs1.ranks == abs2.ranks
            @test abs1.is_suited == abs2.is_suited
            @test abs1.is_suited[1] == true
            
            # Cards should be ordered by rank (high to low)
            @test abs1.ranks == [14, 13]  # A, K
        end
        
        @testset "Offsuit Hands" begin
            # A♠K♥ and A♥K♠ should be equivalent (both offsuit AK)
            abs1 = Tree.canonicalize_hand([A♠, K♥])
            abs2 = Tree.canonicalize_hand([A♥, K♠])
            
            @test abs1.ranks == abs2.ranks
            @test abs1.is_suited == abs2.is_suited
            @test abs1.is_suited[1] == false
        end
        
        @testset "Order Independence" begin
            # K♠A♠ should give same result as A♠K♠ (cards ordered by rank)
            abs1 = Tree.canonicalize_hand([K♠, A♠])
            abs2 = Tree.canonicalize_hand([A♠, K♠])
            
            @test abs1.ranks == abs2.ranks
            @test abs1.ranks == [14, 13]  # A, K (high to low)
        end
    end
    
    @testset "Card String Representation" begin
        @testset "Hole Cards" begin
            # Suited AK
            abs = Tree.canonicalize_hand([A♠, K♠])
            @test Tree.cards_to_string(abs) == "AKs"
            
            # Offsuit AK
            abs = Tree.canonicalize_hand([A♠, K♥])
            @test Tree.cards_to_string(abs) == "AKo"
            
            # Pocket pair
            abs = Tree.canonicalize_hand([A♠, A♥])
            @test Tree.cards_to_string(abs) == "AAo"  # Pairs are offsuit
            
            # Lower cards
            abs = Tree.canonicalize_hand([Q♦, J♣])
            @test Tree.cards_to_string(abs) == "QJo"
            
            # Ten represented as T
            abs = Tree.canonicalize_hand([A♠, T♠])
            @test Tree.cards_to_string(abs) == "ATs"
        end
        
        @testset "Board Cards" begin
            # Flop
            abs = Tree.canonicalize_hand([A♠, K♥, Q♦])
            str = Tree.cards_to_string(abs)
            @test str == "AKQ"
            
            # Full board
            abs = Tree.canonicalize_hand([A♠, K♥, Q♦, J♣, T♠])
            str = Tree.cards_to_string(abs)
            @test str == "AKQJT"
        end
    end
    
    @testset "Information Set ID Creation" begin
        params = GameTypes.GameParams()
        
        # Create a simple test node
        node = Tree.GameNode(
            1,                    # id
            Tree.PlayerNode,      # node_type
            UInt8(0),            # player (SB)
            Tree.Preflop,        # street
            Float32(3),          # pot
            UInt8(0),            # raises_this_street
            false,               # facing_bet
            nothing              # parent
        )
        node.betting_history = "rc"
        
        @testset "Without Cards" begin
            # Just betting history
            id = Tree.get_infoset_id(node)
            @test contains(id, "P0")         # Player 0
            @test contains(id, "PRE")        # Preflop
            @test contains(id, "rc")         # Betting history
        end
        
        @testset "With Hole Cards" begin
            # Add hole cards
            hole_cards = [A♠, K♠]
            id = Tree.get_infoset_id(node, hole_cards)
            
            @test contains(id, "P0")         # Player 0
            @test contains(id, "PRE")        # Preflop
            @test contains(id, "AKs")        # Suited AK
            @test contains(id, "rc")         # Betting history
        end
        
        @testset "Post-flop with Board" begin
            # Create flop node
            flop_node = Tree.GameNode(
                2,                    # id
                Tree.PlayerNode,      # node_type
                UInt8(1),            # player (BB)
                Tree.Flop,           # street
                Float32(10),         # pot
                UInt8(0),            # raises_this_street
                false,               # facing_bet
                nothing              # parent
            )
            flop_node.betting_history = "rcc"
            
            hole_cards = [A♠, K♠]
            board_cards = [Q♦, J♣, T♠]
            
            id = Tree.get_infoset_id(flop_node, hole_cards, board_cards)
            
            @test contains(id, "P1")         # Player 1
            @test contains(id, "FLOP")       # Flop
            @test contains(id, "AKs")        # Hole cards
            @test contains(id, "B:")         # Board indicator
            @test contains(id, "QJT")        # Board cards
            @test contains(id, "rcc")        # Betting history
        end
    end
    
    @testset "Suit Isomorphism" begin
        # All these should produce the same canonical form
        hands = [
            [A♠, K♠],  # Spades
            [A♥, K♥],  # Hearts
            [A♦, K♦],  # Diamonds
            [A♣, K♣],  # Clubs
        ]
        
        abstractions = [Tree.canonicalize_hand(h) for h in hands]
        ids = [Tree.cards_to_string(a) for a in abstractions]
        
        # All should be "AKs"
        @test all(id == "AKs" for id in ids)
        
        # Canonical suits should be the same
        for i in 2:length(abstractions)
            @test abstractions[1].suits == abstractions[i].suits
        end
    end
    
    @testset "Tree Integration" begin
        params = GameTypes.GameParams()
        tree = Tree.build_game_tree(params, preflop_only=true, verbose=false)
        
        @testset "Basic InfoSet Assignment" begin
            # Assign without cards (backward compatibility)
            Tree.assign_infoset_ids!(tree, verbose=false, include_cards=false)
            
            # Check that all player nodes have infoset IDs
            player_nodes_with_ids = 0
            Tree.traverse_tree(tree, node -> begin
                if Tree.is_player_node(node) && !node.is_terminal
                    @test node.infoset_id > 0
                    player_nodes_with_ids += 1
                end
            end)
            
            @test player_nodes_with_ids > 0
            @test tree.num_infosets > 0
        end
        
        @testset "InfoSet Assignment with Cards" begin
            # Create a mock function that returns different hole cards
            # based on node ID to simulate different deals
            hole_cards_fn = node -> begin
                # Use node ID to deterministically assign different cards
                if node.id % 4 == 0
                    node.player == 0 ? [A♠, K♠] : [Q♦, Q♣]
                elseif node.id % 4 == 1
                    node.player == 0 ? [A♥, A♦] : [J♣, T♠]
                elseif node.id % 4 == 2
                    node.player == 0 ? [K♥, Q♥] : [A♣, K♣]
                else
                    node.player == 0 ? [J♣, J♥] : [T♠, T♥]
                end
            end
            
            # Assign with cards
            Tree.assign_infoset_ids!(tree, verbose=false, include_cards=true, 
                                   hole_cards_fn=hole_cards_fn)
            
            # Check that infoset IDs now include card info
            Tree.traverse_tree(tree, node -> begin
                if Tree.is_player_node(node) && !node.is_terminal
                    # For player nodes, check that we have numeric IDs
                    @test node.infoset_id > 0
                end
            end)
            
            # Store the number of infosets with cards
            num_infosets_with_cards = tree.num_infosets
            
            # Reassign without cards
            Tree.assign_infoset_ids!(tree, verbose=false, include_cards=false)
            num_infosets_without_cards = tree.num_infosets
            
            # In a preflop-only tree, each betting situation is unique,
            # so the number of infosets doesn't change when adding cards
            # (each node already has a unique player:history combination)
            @test num_infosets_with_cards == num_infosets_without_cards
            
            # But verify that the infoset IDs themselves are different
            # when cards are included
            sample_node = nothing
            Tree.traverse_tree(tree, node -> begin
                if Tree.is_player_node(node) && !node.is_terminal && sample_node === nothing
                    sample_node = node
                end
            end)
            
            if sample_node !== nothing
                id_without_cards = string(sample_node.player, ":", sample_node.betting_history)
                id_with_cards = Tree.get_infoset_id(sample_node, [A♠, K♠])
                
                # The IDs should be different (cards add extra info)
                @test id_without_cards != id_with_cards
                @test contains(id_with_cards, "AKs")  # Should include card info
            end
        end
    end
end
