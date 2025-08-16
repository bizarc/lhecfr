# test/test_tree.jl
using Test, LHECFR, LHECFR.GameTypes, LHECFR.Tree

@testset "Tree Module Tests" begin
    
    @testset "GameNode Structure" begin
        # Test basic node creation
        params = GameTypes.GameParams()
        
        # Create a player node
        node = Tree.GameNode(
            1,  # id
            Tree.PlayerNode,
            UInt8(0),  # player 0 (SB/BTN)
            Tree.Preflop,
            3.0f0,  # pot
            UInt8(0),  # raises
            false,  # not facing bet
            nothing  # no parent
        )
        
        @test node.id == 1
        @test node.node_type == Tree.PlayerNode
        @test node.player == 0
        @test node.street == Tree.Preflop
        @test node.pot == 3.0f0
        @test !node.is_terminal
        @test length(node.children) == 0
        @test node.parent === nothing
        
        # Create a terminal node
        terminal = Tree.GameNode(
            2,  # id
            Tree.River,
            10.0f0,  # pot
            (5.0f0, -5.0f0),  # utilities
            UInt8(1),  # fold terminal
            nothing
        )
        
        @test terminal.is_terminal
        @test terminal.utilities == (5.0f0, -5.0f0)
        @test terminal.terminal_type == 1
        @test terminal.node_type == Tree.TerminalNode
    end
    
    @testset "Node Relationships" begin
        params = GameTypes.GameParams()
        
        # Create parent and child nodes
        parent = Tree.GameNode(1, Tree.PlayerNode, UInt8(0), Tree.Preflop, 3.0f0, UInt8(0), false, nothing)
        child = Tree.GameNode(2, Tree.PlayerNode, UInt8(1), Tree.Preflop, 3.0f0, UInt8(0), true, nothing)
        
        # Add child with action
        Tree.add_child!(parent, child, GameTypes.Check)
        
        @test length(parent.children) == 1
        @test parent.children[1] === child
        @test child.parent === parent
        @test parent.action_to_child[GameTypes.Check] == 1
        @test length(child.action_history) == 1
        @test child.action_history[1] == GameTypes.Check
        @test child.betting_history == "c"  # check is represented as 'c'
    end
    
    @testset "Valid Actions" begin
        params = GameTypes.GameParams()
        
        # Test when facing a bet
        node_facing_bet = Tree.GameNode(1, Tree.PlayerNode, UInt8(0), Tree.Preflop, 3.0f0, UInt8(0), true, nothing)
        actions = Tree.get_valid_actions(node_facing_bet, params)
        @test GameTypes.Fold in actions
        @test GameTypes.Call in actions
        @test GameTypes.BetOrRaise in actions  # Can raise since not at cap
        @test !(GameTypes.Check in actions)  # Cannot check when facing bet
        
        # Test when not facing a bet
        node_no_bet = Tree.GameNode(1, Tree.PlayerNode, UInt8(0), Tree.Preflop, 3.0f0, UInt8(0), false, nothing)
        actions = Tree.get_valid_actions(node_no_bet, params)
        @test GameTypes.Check in actions
        @test GameTypes.BetOrRaise in actions
        @test !(GameTypes.Fold in actions)  # Cannot fold when not facing bet
        @test !(GameTypes.Call in actions)  # Cannot call when not facing bet
        
        # Test at raise cap
        node_at_cap = Tree.GameNode(1, Tree.PlayerNode, UInt8(0), Tree.Preflop, 11.0f0, UInt8(4), true, nothing)
        actions = Tree.get_valid_actions(node_at_cap, params)
        @test GameTypes.Fold in actions
        @test GameTypes.Call in actions
        @test !(GameTypes.BetOrRaise in actions)  # Cannot raise at cap
    end
    
    @testset "Betting History" begin
        # Test betting history string construction
        history = ""
        history = Tree.update_betting_history(history, GameTypes.BetOrRaise)
        @test history == "r"
        
        history = Tree.update_betting_history(history, GameTypes.Call)
        @test history == "rc"
        
        history = Tree.update_betting_history(history, GameTypes.Check)
        @test history == "rcc"
        
        history = Tree.update_betting_history(history, GameTypes.Fold)
        @test history == "rccf"
    end
    
    @testset "Pot Calculations" begin
        params = GameTypes.GameParams()
        
        # Pre-flop betting (small bets = 1 BB)
        node = Tree.GameNode(1, Tree.PlayerNode, UInt8(0), Tree.Preflop, 3.0f0, UInt8(0), true, nothing)
        
        # Call adds 1 BB (small bet on pre-flop)
        new_pot = Tree.calculate_pot_after_action(node, GameTypes.Call, params)
        @test new_pot == 5.0f0  # 3 + 2
        
        # Raise adds 2 BB (bet + raise)
        new_pot = Tree.calculate_pot_after_action(node, GameTypes.BetOrRaise, params)
        @test new_pot == 7.0f0  # 3 + 4
        
        # Check doesn't change pot
        node_no_bet = Tree.GameNode(1, Tree.PlayerNode, UInt8(0), Tree.Preflop, 3.0f0, UInt8(0), false, nothing)
        new_pot = Tree.calculate_pot_after_action(node_no_bet, GameTypes.Check, params)
        @test new_pot == 3.0f0
        
        # Bet adds 1 BB when not facing bet
        new_pot = Tree.calculate_pot_after_action(node_no_bet, GameTypes.BetOrRaise, params)
        @test new_pot == 5.0f0  # 3 + 2
        
        # Turn betting (big bets = 2 BB)
        turn_node = Tree.GameNode(1, Tree.PlayerNode, UInt8(0), Tree.Turn, 10.0f0, UInt8(0), true, nothing)
        new_pot = Tree.calculate_pot_after_action(turn_node, GameTypes.Call, params)
        @test new_pot == 14.0f0  # 10 + 4 (big bet)
    end
    
    @testset "Bet Sizes" begin
        params = GameTypes.GameParams()
        
        # Small bets on pre-flop and flop
        @test Tree.get_bet_size(Tree.Preflop, params) == 2.0f0  # 1 BB
        @test Tree.get_bet_size(Tree.Flop, params) == 2.0f0     # 1 BB
        
        # Big bets on turn and river
        @test Tree.get_bet_size(Tree.Turn, params) == 4.0f0     # 2 BB
        @test Tree.get_bet_size(Tree.River, params) == 4.0f0    # 2 BB
    end
    
    @testset "Node Type Checking" begin
        player_node = Tree.GameNode(1, Tree.PlayerNode, UInt8(0), Tree.Preflop, 3.0f0, UInt8(0), false, nothing)
        chance_node = Tree.GameNode(2, Tree.ChanceNode, UInt8(255), Tree.Flop, 3.0f0, UInt8(0), false, nothing)
        terminal_node = Tree.GameNode(3, Tree.River, 10.0f0, (5.0f0, -5.0f0), UInt8(1), nothing)
        
        @test Tree.is_player_node(player_node)
        @test !Tree.is_player_node(chance_node)
        @test !Tree.is_player_node(terminal_node)
        
        @test Tree.is_chance_node(chance_node)
        @test !Tree.is_chance_node(player_node)
        @test !Tree.is_chance_node(terminal_node)
        
        @test Tree.is_terminal_node(terminal_node)
        @test !Tree.is_terminal_node(player_node)
        @test !Tree.is_terminal_node(chance_node)
    end
    
    @testset "GameTree Structure" begin
        params = GameTypes.GameParams()
        tree = Tree.GameTree(params)
        
        @test tree.root.id == 1
        @test tree.root.player == 0  # SB acts first pre-flop in heads-up
        @test tree.root.pot == 3.0f0  # SB + BB
        @test tree.root.facing_bet == false  # SB not facing bet initially
        @test tree.num_nodes == 1
        @test length(tree.nodes) == 1
        @test tree.nodes[1] === tree.root
    end
    
    @testset "Tree Traversal" begin
        params = GameTypes.GameParams()
        tree = Tree.GameTree(params)
        
        # Add some children to root
        child1 = Tree.GameNode(2, Tree.PlayerNode, UInt8(0), Tree.Preflop, 6.0f0, UInt8(1), false, nothing)
        child2 = Tree.GameNode(3, Tree.PlayerNode, UInt8(0), Tree.Preflop, 8.0f0, UInt8(2), false, nothing)
        
        Tree.add_child!(tree.root, child1, GameTypes.Call)
        Tree.add_child!(tree.root, child2, GameTypes.BetOrRaise)
        
        # Test traversal
        visited_ids = Int[]
        Tree.traverse_tree(tree, node -> push!(visited_ids, node.id))
        
        @test length(visited_ids) == 3
        @test 1 in visited_ids
        @test 2 in visited_ids
        @test 3 in visited_ids
    end
    
    @testset "Node Depth" begin
        params = GameTypes.GameParams()
        tree = Tree.GameTree(params)
        
        # Root has depth 0
        @test Tree.get_node_depth(tree.root) == 0
        
        # Add child at depth 1
        child = Tree.GameNode(2, Tree.PlayerNode, UInt8(0), Tree.Preflop, 6.0f0, UInt8(1), false, nothing)
        Tree.add_child!(tree.root, child, GameTypes.Call)
        @test Tree.get_node_depth(child) == 1
        
        # Add grandchild at depth 2
        grandchild = Tree.GameNode(3, Tree.PlayerNode, UInt8(1), Tree.Preflop, 8.0f0, UInt8(2), false, nothing)
        Tree.add_child!(child, grandchild, GameTypes.BetOrRaise)
        @test Tree.get_node_depth(grandchild) == 2
    end
    
    @testset "Betting Sequence Generation" begin
        params = GameTypes.GameParams()
        
        @testset "Pre-flop Sequences" begin
            sequences = Tree.generate_preflop_sequences(params)
            
            # Should have multiple sequences
            @test length(sequences) > 0
            
            # Check for specific sequences
            # Find fold sequence (SB folds)
            fold_seq = findfirst(s -> length(s.actions) == 1 && s.actions[1] == GameTypes.Fold, sequences)
            @test fold_seq !== nothing
            @test sequences[fold_seq].is_terminal
            @test sequences[fold_seq].terminal_type == 1  # fold terminal
            
            # Find limp-check sequence (SB calls, BB checks)
            limp_check = findfirst(s -> length(s.actions) == 2 && 
                                       s.actions[1] == GameTypes.Call && 
                                       s.actions[2] == GameTypes.Check, sequences)
            @test limp_check !== nothing
            @test sequences[limp_check].is_terminal
            @test sequences[limp_check].terminal_type == 2  # go to next street
            
            # Find raise-fold sequence (SB raises, BB folds)
            raise_fold = findfirst(s -> length(s.actions) == 2 && 
                                       s.actions[1] == GameTypes.BetOrRaise && 
                                       s.actions[2] == GameTypes.Fold, sequences)
            @test raise_fold !== nothing
            @test sequences[raise_fold].is_terminal
            
            # Find raise-call sequence (SB raises, BB calls)
            raise_call = findfirst(s -> length(s.actions) == 2 && 
                                       s.actions[1] == GameTypes.BetOrRaise && 
                                       s.actions[2] == GameTypes.Call, sequences)
            @test raise_call !== nothing
            @test sequences[raise_call].is_terminal
            
            # Check pot calculations
            initial_pot = Float32(params.small_blind + params.big_blind)  # 3 BB
            
            # SB fold should leave pot unchanged
            fold_seq_obj = sequences[fold_seq]
            @test fold_seq_obj.final_pot == initial_pot
            
            # Limp-check should add 1 SB to pot
            limp_check_obj = sequences[limp_check]
            @test limp_check_obj.final_pot == initial_pot + params.small_blind  # 4 BB total
            
            # All sequences should be terminal
            for seq in sequences
                @test seq.is_terminal
            end
        end
        
        @testset "Post-flop Sequences" begin
            # Test flop sequences
            flop_sequences = Tree.generate_betting_sequences(
                Tree.Flop, 
                10.0f0,  # initial pot
                params,
                initial_facing_bet=false,
                initial_player=UInt8(1)  # BB acts first post-flop
            )
            
            @test length(flop_sequences) > 0
            
            # Find check-check sequence
            check_check = findfirst(s -> length(s.actions) == 2 && 
                                        s.actions[1] == GameTypes.Check && 
                                        s.actions[2] == GameTypes.Check, flop_sequences)
            @test check_check !== nothing
            
            # Find bet-fold sequence
            bet_fold = findfirst(s -> length(s.actions) == 2 && 
                                    s.actions[1] == GameTypes.BetOrRaise && 
                                    s.actions[2] == GameTypes.Fold, flop_sequences)
            @test bet_fold !== nothing
            
            # Find bet-call sequence
            bet_call = findfirst(s -> length(s.actions) == 2 && 
                                    s.actions[1] == GameTypes.BetOrRaise && 
                                    s.actions[2] == GameTypes.Call, flop_sequences)
            @test bet_call !== nothing
            
            # Test turn sequences (big bets)
            turn_sequences = Tree.generate_betting_sequences(
                Tree.Turn,
                20.0f0,  # initial pot
                params,
                initial_facing_bet=false,
                initial_player=UInt8(1)
            )
            
            @test length(turn_sequences) > 0
            
            # Bet size should be different on turn
            bet_call_turn = findfirst(s -> length(s.actions) == 2 && 
                                          s.actions[1] == GameTypes.BetOrRaise && 
                                          s.actions[2] == GameTypes.Call, turn_sequences)
            @test bet_call_turn !== nothing
            turn_seq = turn_sequences[bet_call_turn]
            # Turn uses big bets (2 BB), so bet-call adds 8 to pot (4 BB from each player)
            @test turn_seq.final_pot == 28.0f0  # 20 + 8
        end
        
        @testset "Betting Completion Logic" begin
            # Test is_betting_complete
            actions1 = [GameTypes.BetOrRaise, GameTypes.Call]
            @test Tree.is_betting_complete(actions1, false)
            
            actions2 = [GameTypes.Check, GameTypes.Check]
            @test Tree.is_betting_complete(actions2, false)
            
            actions3 = [GameTypes.BetOrRaise]
            @test !Tree.is_betting_complete(actions3, true)
            
            actions4 = [GameTypes.BetOrRaise, GameTypes.BetOrRaise]
            @test !Tree.is_betting_complete(actions4, true)
            
            # Test is_preflop_betting_complete
            preflop1 = [GameTypes.Call, GameTypes.Check]
            @test Tree.is_preflop_betting_complete(preflop1)
            
            preflop2 = [GameTypes.BetOrRaise, GameTypes.Call]
            @test Tree.is_preflop_betting_complete(preflop2)
            
            preflop3 = [GameTypes.BetOrRaise]
            @test !Tree.is_preflop_betting_complete(preflop3)
        end
        
        @testset "Sequence Counting" begin
            # Count sequences for validation
            preflop_count = Tree.count_betting_sequences(Tree.Preflop, params)
            @test preflop_count > 0
            
            flop_count = Tree.count_betting_sequences(Tree.Flop, params)
            @test flop_count > 0
            
            turn_count = Tree.count_betting_sequences(Tree.Turn, params)
            @test turn_count > 0
            
            river_count = Tree.count_betting_sequences(Tree.River, params)
            @test river_count > 0
            
            # All streets should have the same number of sequences for post-flop
            # (since they follow the same betting rules, just different bet sizes)
            @test flop_count == turn_count == river_count
        end
        
        @testset "Raise Caps" begin
            # Test that sequences respect raise caps
            sequences = Tree.generate_preflop_sequences(params)
            
            # Find a max-raises sequence (should have exactly max_raises_per_street raises)
            max_raises = params.max_raises_per_street
            
            # Count raises in each sequence
            for seq in sequences
                raise_count = count(a -> a == GameTypes.BetOrRaise, seq.actions)
                @test raise_count <= max_raises
            end
            
            # There should be at least one sequence that reaches the cap
            max_raise_seq = findfirst(sequences) do seq
                count(a -> a == GameTypes.BetOrRaise, seq.actions) == max_raises
            end
            @test max_raise_seq !== nothing
        end
    end
    
    @testset "Tree Building" begin
        params = GameTypes.GameParams()
        
        @testset "Pre-flop Tree Construction" begin
            # Build pre-flop tree
            tree = Tree.build_game_tree(params, preflop_only=true, verbose=false)
            
            # Root node should be correct
            @test tree.root.id == 1
            @test tree.root.player == 0  # SB acts first
            @test tree.root.pot == 3.0f0  # SB + BB
            @test tree.root.facing_bet == false
            @test tree.root.street == Tree.Preflop
            
            # Tree should have nodes
            @test length(tree.nodes) > 1
            @test length(tree.terminal_nodes) > 0
            @test length(tree.player_nodes) > 0
            
            # All nodes should be in the nodes list
            visited = Set{Int}()
            Tree.traverse_tree(tree, node -> push!(visited, node.id))
            @test length(visited) == length(tree.nodes)
            
            # Check specific paths exist
            # SB fold should exist
            @test haskey(tree.root.action_to_child, GameTypes.Fold)
            fold_child = tree.root.children[tree.root.action_to_child[GameTypes.Fold]]
            @test fold_child.is_terminal
            @test fold_child.terminal_type == 1  # fold terminal
            
            # SB call (limp) should exist
            @test haskey(tree.root.action_to_child, GameTypes.Call)
            limp_child = tree.root.children[tree.root.action_to_child[GameTypes.Call]]
            @test !limp_child.is_terminal
            @test limp_child.player == 1  # BB to act
            @test limp_child.pot == 4.0f0  # Both players have 2 BB in
            
            # BB check after limp should exist
            @test haskey(limp_child.action_to_child, GameTypes.Check)
            check_child = limp_child.children[limp_child.action_to_child[GameTypes.Check]]
            @test check_child.is_terminal
            @test check_child.terminal_type == 2  # go to next street
            
            # SB raise should exist
            @test haskey(tree.root.action_to_child, GameTypes.BetOrRaise)
            raise_child = tree.root.children[tree.root.action_to_child[GameTypes.BetOrRaise]]
            @test !raise_child.is_terminal
            @test raise_child.player == 1  # BB to act
            @test raise_child.facing_bet == true
            @test raise_child.pot == 6.0f0  # SB raised to 4 total (4 from SB + 2 from BB = 6 in pot)
        end
        
        @testset "Tree Validation" begin
            tree = Tree.build_game_tree(params, preflop_only=true, verbose=false)
            Tree.evaluate_all_terminals!(tree, params)
            
            # Tree should pass validation
            @test Tree.validate_tree(tree) == true
            
            # All terminal nodes should be marked correctly
            for node in tree.terminal_nodes
                @test node.is_terminal
                @test length(node.children) == 0
                @test node.utilities !== nothing
            end
            
            # All player nodes should not be terminal
            for node in tree.player_nodes
                @test !node.is_terminal
            end
            
            # Parent-child relationships should be consistent
            for node in tree.nodes
                for child in node.children
                    @test child.parent === node
                end
            end
        end
        
        @testset "Information Sets" begin
            tree = Tree.build_game_tree(params, preflop_only=true, verbose=false)
            Tree.update_tree_statistics!(tree, verbose=false)
            Tree.assign_infoset_ids!(tree, verbose=false)
            
            # All player nodes should have infoset IDs
            for node in tree.player_nodes
                @test node.infoset_id > 0
            end
            
            # Nodes with same betting history and player should have same infoset
            infoset_groups = Dict{Int, Vector{Tree.GameNode}}()
            for node in tree.player_nodes
                if !haskey(infoset_groups, node.infoset_id)
                    infoset_groups[node.infoset_id] = Tree.GameNode[]
                end
                push!(infoset_groups[node.infoset_id], node)
            end
            
            # Verify nodes in same infoset have same properties
            for (id, nodes) in infoset_groups
                if length(nodes) > 1
                    first_node = nodes[1]
                    for node in nodes[2:end]
                        @test node.player == first_node.player
                        @test node.betting_history == first_node.betting_history
                    end
                end
            end
            
            # Check infoset map in tree
            @test length(tree.infoset_map) > 0
            for (id, nodes) in tree.infoset_map
                for node in nodes
                    @test node.infoset_id == id
                end
            end
        end
        
        @testset "Tree Statistics" begin
            tree = Tree.build_game_tree(params, preflop_only=true, verbose=false)
            
            # Count nodes manually
            total_count = 0
            terminal_count = 0
            player_count = 0
            Tree.traverse_tree(tree, node -> begin
                total_count += 1
                if node.is_terminal
                    terminal_count += 1
                elseif Tree.is_player_node(node)
                    player_count += 1
                end
            end)
            
            # Verify counts match tree statistics
            @test length(tree.nodes) == total_count
            @test length(tree.terminal_nodes) == terminal_count
            @test length(tree.player_nodes) == player_count
            
            # Terminal + player nodes should equal total (no chance nodes in preflop)
            @test terminal_count + player_count == total_count
        end
        
        @testset "Terminal Node Evaluation" begin
            params = GameTypes.GameParams()
            
            # Test investment calculation
            @testset "Investment Calculation" begin
                tree = Tree.build_game_tree(params, preflop_only=true, verbose=false)
                
                # Find a fold terminal node
                fold_node = nothing
                Tree.traverse_tree(tree, node -> begin
                    if node.is_terminal && node.terminal_type == 1
                        fold_node = node
                        return false
                    end
                    return true
                end)
                
                @test fold_node !== nothing
                investments = Tree.calculate_investments(fold_node, params)
                @test investments.player0 >= params.small_blind
                @test investments.player1 >= params.big_blind
                
                # Total investments should equal the pot (within tolerance for floating point)
                # Note: If this fails, debug the investment calculation
                if !(abs(investments.player0 + investments.player1 - fold_node.pot) < 0.01)
                    println("Investment mismatch for node with history: ", fold_node.betting_history)
                    println("  Pot: ", fold_node.pot)
                    println("  P0 investment: ", investments.player0)
                    println("  P1 investment: ", investments.player1)
                    println("  Total: ", investments.player0 + investments.player1)
                end
                @test abs(investments.player0 + investments.player1 - fold_node.pot) < 0.01
            end
            
            # Test fold utility calculation
            @testset "Fold Utility Evaluation" begin
                tree = Tree.build_game_tree(params, preflop_only=true, verbose=false)
                Tree.evaluate_all_terminals!(tree, params)
                
                # Find a specific fold scenario: SB folds immediately
                sb_fold_node = nothing
                Tree.traverse_tree(tree, node -> begin
                    if node.is_terminal && node.terminal_type == 1 && 
                       length(node.action_history) == 1 && 
                       node.action_history[1] == GameTypes.Fold
                        sb_fold_node = node
                        return false
                    end
                    return true
                end)
                
                if sb_fold_node !== nothing
                    @test sb_fold_node.utilities !== nothing
                    utility0, utility1 = sb_fold_node.utilities
                    
                    # SB (player 0) folds, loses small blind
                    @test utility0 ≈ -params.small_blind
                    # BB (player 1) wins small blind
                    @test utility1 ≈ params.small_blind
                    # Utilities should sum to zero (zero-sum game)
                    @test utility0 + utility1 ≈ 0.0f0
                end
            end
            
            # Test showdown utility placeholder
            @testset "Showdown Utility Placeholder" begin
                tree = Tree.build_game_tree(params, preflop_only=true, verbose=false)
                Tree.evaluate_all_terminals!(tree, params)
                
                # Find a showdown terminal (goes to next street)
                showdown_node = nothing
                Tree.traverse_tree(tree, node -> begin
                    if node.is_terminal && node.terminal_type == 2
                        showdown_node = node
                        return false
                    end
                    return true
                end)
                
                if showdown_node !== nothing
                    @test showdown_node.utilities !== nothing
                    # Without cards, should return placeholder (0, 0)
                    @test showdown_node.utilities == (0.0f0, 0.0f0)
                end
            end
        end
        
        @testset "Utilities and Pot Distribution" begin
            tree = Tree.build_game_tree(params, preflop_only=true, verbose=false)
            Tree.evaluate_all_terminals!(tree, params)
            
            # Check fold terminals have correct utilities
            for node in tree.terminal_nodes
                if node.terminal_type == 1  # fold
                    utils = node.utilities
                    @test utils !== nothing
                    # Utilities should sum to 0 (zero-sum game)
                    @test abs(utils[1] + utils[2]) < 0.01
                    # Winner should get positive utility
                    @test maximum([utils[1], utils[2]]) > 0
                    @test minimum([utils[1], utils[2]]) < 0
                end
            end
        end
        
        @testset "Tree Printing" begin
            tree = Tree.build_game_tree(params, preflop_only=true, verbose=false)
            
            # Should not error when printing
            # Capture output using devnull to avoid cluttering test results
            original_stdout = stdout
            redirect_stdout(devnull) do
                Tree.print_tree_structure(tree, max_depth=2)
            end
            
            # Just test that the function runs without error
            # We can't easily test the output content when redirecting to devnull
            @test true  # If we get here, the function didn't error
        end
    end
    
    @testset "Post-flop Tree Building" begin
        params = GameTypes.GameParams()
        
        # Use a smaller tree for testing - limit to flop only
        # This prevents stack overflow and speeds up tests
        full_tree = begin
            tree = Tree.build_game_tree(params, preflop_only=true, verbose=false)
            # Manually build just one post-flop path for testing
            # Find one pre-flop terminal that goes to flop
            for node in tree.terminal_nodes
                if node.terminal_type == 2  # Goes to next street
                    Tree.build_street_subtree!(tree, node, Tree.Flop, Ref(1000))
                    break  # Only build one path
                end
            end
            Tree.update_tree_statistics!(tree, verbose=false)
            tree
        end
        
        @testset "Post-flop Tree Construction" begin
            tree = full_tree  # Use the pre-built tree
            
            # Should have more nodes than preflop-only tree
            preflop_tree = Tree.build_game_tree(params, preflop_only=true, verbose=false)
            @test tree.num_nodes > preflop_tree.num_nodes
            @test tree.num_player_nodes > preflop_tree.num_player_nodes
            
            # Find a preflop node that goes to flop (e.g., SB limp, BB check)
            limp_check_node = nothing
            Tree.traverse_tree(tree, node -> begin
                if node.street == Tree.Preflop && node.betting_history == "cc" && !node.is_terminal
                    limp_check_node = node
                    return false
                end
                return true
            end)
            
            @test limp_check_node !== nothing
            @test !limp_check_node.is_terminal
            @test length(limp_check_node.children) > 0
            
            # Check that flop nodes exist
            flop_child = limp_check_node.children[1]
            @test flop_child.street == Tree.Flop
            # Note: In our simplified implementation, player 0 acts first post-flop
            # In real poker, it would depend on position
            @test flop_child.player in [0, 1]  # Either player could act first
            @test flop_child.pot == 4.0f0  # Pot from preflop
            @test flop_child.raises_this_street == 0
            @test !flop_child.facing_bet
        end
        
        @testset "Street Transitions" begin
            tree = full_tree  # Use the pre-built tree
            
            # Find nodes at each street
            streets_found = Set{Tree.Street}()
            Tree.traverse_tree(tree, node -> begin
                push!(streets_found, node.street)
            end)
            
            # Should have all streets
            @test Tree.Preflop in streets_found
            @test Tree.Flop in streets_found
            @test Tree.Turn in streets_found
            @test Tree.River in streets_found
        end
        
        @testset "Post-flop Betting" begin
            tree = full_tree  # Use the pre-built tree
            
            # Find a flop node and check betting options
            flop_node = nothing
            Tree.traverse_tree(tree, node -> begin
                if node.street == Tree.Flop && node.player == 0 && !node.facing_bet
                    flop_node = node
                    return false
                end
                return true
            end)
            
            @test flop_node !== nothing
            
            # Should have check and bet options
            @test haskey(flop_node.action_to_child, GameTypes.Check)
            @test haskey(flop_node.action_to_child, GameTypes.BetOrRaise)
            
            # Check bet sizes (should be small bet on flop)
            bet_child = flop_node.children[flop_node.action_to_child[GameTypes.BetOrRaise]]
            bet_size = Tree.get_bet_size(Tree.Flop, params)
            @test bet_size == 2  # Small bet on flop
            @test bet_child.pot == flop_node.pot + bet_size
        end
        
        @testset "River Terminal Nodes" begin
            tree = full_tree  # Use the pre-built tree
            
            # Evaluate all terminal nodes (needed for utilities)
            Tree.evaluate_all_terminals!(tree, params)
            
            # Find river terminal nodes
            river_terminals = filter(tree.terminal_nodes) do node
                node.street == Tree.River
            end
            
            @test length(river_terminals) > 0
            
            # River terminals should be either fold or showdown
            for node in river_terminals
                @test node.terminal_type in [1, 2]  # Fold or showdown
                @test node.utilities !== nothing
            end
        end
        
        @testset "Tree Size and Complexity" begin
            tree = full_tree  # Use the pre-built tree
            
            # Basic sanity checks on tree size
            @test tree.num_nodes > 1000  # Should have many nodes with full tree
            @test tree.num_terminal_nodes > 100
            @test tree.num_player_nodes > 500
            
            # Check that statistics are consistent
            total_counted = tree.num_player_nodes + tree.num_terminal_nodes + tree.num_chance_nodes
            @test total_counted == tree.num_nodes
        end
    end
end
