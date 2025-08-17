using Test
using LHECFR.Tree

@testset "InfoSetManager Tests" begin
    
    @testset "CFRInfoSet Creation and Initialization" begin
        # Create a CFR information set
        cfr_is = Tree.CFRInfoSet(
            "P1|PRE|AKs|c",
            3,  # 3 actions (fold, call, raise)
            zeros(Float64, 3),
            zeros(Float64, 3),
            0
        )
        
        @test cfr_is.id == "P1|PRE|AKs|c"
        @test cfr_is.num_actions == 3
        @test all(cfr_is.regrets .== 0.0)
        @test all(cfr_is.strategy_sum .== 0.0)
        @test cfr_is.last_iteration == 0
    end
    
    @testset "InfoSetStorage Creation and Management" begin
        storage = Tree.InfoSetStorage()
        
        @test length(storage.infosets) == 0
        @test length(storage.action_lookup) == 0
        
        # Get or create a new infoset
        cfr_is = Tree.get_or_create_infoset!(storage, "P1|PRE|AKs|c", 3)
        @test cfr_is.id == "P1|PRE|AKs|c"
        @test cfr_is.num_actions == 3
        @test length(storage.infosets) == 1
        
        # Get the same infoset again
        cfr_is2 = Tree.get_or_create_infoset!(storage, "P1|PRE|AKs|c", 3)
        @test cfr_is === cfr_is2  # Should be the same object
        @test length(storage.infosets) == 1  # Should not create duplicate
        
        # Get non-existent infoset
        cfr_is3 = Tree.get_infoset(storage, "P2|PRE|QQ|r")
        @test cfr_is3 === nothing
        
        # Create another infoset
        cfr_is4 = Tree.get_or_create_infoset!(storage, "P2|PRE|QQ|r", 2)
        @test cfr_is4.num_actions == 2
        @test length(storage.infosets) == 2
    end
    
    @testset "Action Labels" begin
        storage = Tree.InfoSetStorage()
        cfr_is = Tree.get_or_create_infoset!(storage, "P1|PRE|AKs|c", 3)
        
        # Set action labels
        actions = ["fold", "call", "raise"]
        Tree.set_action_labels!(storage, "P1|PRE|AKs|c", actions)
        
        # Get action labels
        retrieved = Tree.get_action_labels(storage, "P1|PRE|AKs|c")
        @test retrieved == actions
        
        # Get labels for non-existent infoset
        empty = Tree.get_action_labels(storage, "nonexistent")
        @test empty == String[]
    end
    
    @testset "Regret Updates with CFR+" begin
        storage = Tree.InfoSetStorage()
        cfr_is = Tree.get_or_create_infoset!(storage, "P1|PRE|AKs|c", 3)
        
        # Initial regrets should be zero
        @test all(cfr_is.regrets .== 0.0)
        
        # Update with positive regrets
        action_regrets = [2.5, -1.0, 3.0]
        Tree.update_regrets!(cfr_is, action_regrets, 1)
        
        # CFR+ should floor negative regrets at 0
        @test cfr_is.regrets[1] ≈ 2.5
        @test cfr_is.regrets[2] ≈ 0.0  # -1.0 floored to 0
        @test cfr_is.regrets[3] ≈ 3.0
        @test cfr_is.last_iteration == 1
        
        # Update again with more regrets
        action_regrets2 = [1.0, 2.0, -4.0]
        Tree.update_regrets!(cfr_is, action_regrets2, 2)
        
        @test cfr_is.regrets[1] ≈ 3.5  # 2.5 + 1.0
        @test cfr_is.regrets[2] ≈ 2.0  # 0.0 + 2.0
        @test cfr_is.regrets[3] ≈ 0.0  # 3.0 + (-4.0) = -1.0 floored to 0
        @test cfr_is.last_iteration == 2
    end
    
    @testset "Strategy Computation with Regret Matching" begin
        storage = Tree.InfoSetStorage()
        cfr_is = Tree.get_or_create_infoset!(storage, "P1|PRE|AKs|c", 3)
        
        # When all regrets are zero, should return uniform strategy
        strategy = Tree.get_current_strategy(cfr_is)
        @test all(strategy .≈ 1/3)
        @test sum(strategy) ≈ 1.0
        
        # Set some positive regrets
        cfr_is.regrets = [4.0, 0.0, 2.0]
        strategy = Tree.get_current_strategy(cfr_is)
        
        # Strategy should be proportional to positive regrets
        @test strategy[1] ≈ 4.0/6.0  # 4/(4+0+2)
        @test strategy[2] ≈ 0.0/6.0
        @test strategy[3] ≈ 2.0/6.0
        @test sum(strategy) ≈ 1.0
        
        # With negative regrets (treated as 0)
        cfr_is.regrets = [3.0, -2.0, 1.0]
        strategy = Tree.get_current_strategy(cfr_is)
        
        @test strategy[1] ≈ 3.0/4.0  # 3/(3+0+1)
        @test strategy[2] ≈ 0.0/4.0  # negative treated as 0
        @test strategy[3] ≈ 1.0/4.0
        @test sum(strategy) ≈ 1.0
    end
    
    @testset "Strategy Sum Updates and Averaging" begin
        storage = Tree.InfoSetStorage()
        cfr_is = Tree.get_or_create_infoset!(storage, "P1|PRE|AKs|c", 3)
        
        # Update strategy sum with reach probability
        strategy1 = [0.5, 0.3, 0.2]
        reach_prob1 = 0.1
        Tree.update_strategy_sum!(cfr_is, strategy1, reach_prob1)
        
        @test cfr_is.strategy_sum[1] ≈ 0.05  # 0.5 * 0.1
        @test cfr_is.strategy_sum[2] ≈ 0.03  # 0.3 * 0.1
        @test cfr_is.strategy_sum[3] ≈ 0.02  # 0.2 * 0.1
        
        # Update again
        strategy2 = [0.2, 0.4, 0.4]
        reach_prob2 = 0.2
        Tree.update_strategy_sum!(cfr_is, strategy2, reach_prob2)
        
        @test cfr_is.strategy_sum[1] ≈ 0.09  # 0.05 + 0.2*0.2
        @test cfr_is.strategy_sum[2] ≈ 0.11  # 0.03 + 0.4*0.2
        @test cfr_is.strategy_sum[3] ≈ 0.10  # 0.02 + 0.4*0.2
        
        # Get average strategy
        avg_strategy = Tree.get_average_strategy(cfr_is)
        total = sum(cfr_is.strategy_sum)
        
        @test avg_strategy[1] ≈ 0.09/total
        @test avg_strategy[2] ≈ 0.11/total
        @test avg_strategy[3] ≈ 0.10/total
        @test sum(avg_strategy) ≈ 1.0
    end
    
    @testset "Reset Functions" begin
        storage = Tree.InfoSetStorage()
        cfr_is = Tree.get_or_create_infoset!(storage, "P1|PRE|AKs|c", 3)
        
        # Set some values
        cfr_is.regrets = [1.0, 2.0, 3.0]
        cfr_is.strategy_sum = [0.1, 0.2, 0.3]
        
        # Reset regrets
        Tree.reset_regrets!(cfr_is)
        @test all(cfr_is.regrets .== 0.0)
        @test cfr_is.strategy_sum == [0.1, 0.2, 0.3]  # Should not change
        
        # Reset strategy sum
        Tree.reset_strategy_sum!(cfr_is)
        @test all(cfr_is.strategy_sum .== 0.0)
    end
    
    @testset "Storage Statistics" begin
        storage = Tree.InfoSetStorage()
        
        # Create multiple infosets
        Tree.get_or_create_infoset!(storage, "P1|PRE|AKs|c", 3)
        Tree.get_or_create_infoset!(storage, "P2|PRE|QQ|r", 2)
        Tree.get_or_create_infoset!(storage, "P1|FLOP|AKs|cc", 4)
        
        stats = Tree.get_storage_statistics(storage)
        
        @test stats.num_infosets == 3
        @test stats.total_actions == 9  # 3 + 2 + 4
        @test stats.estimated_memory_mb > 0
    end
    
    @testset "Pruning Unused Information Sets" begin
        storage = Tree.InfoSetStorage()
        
        # Create infosets with different last iterations
        is1 = Tree.get_or_create_infoset!(storage, "P1|PRE|AKs|c", 3)
        is1.last_iteration = 100
        
        is2 = Tree.get_or_create_infoset!(storage, "P2|PRE|QQ|r", 2)
        is2.last_iteration = 50
        
        is3 = Tree.get_or_create_infoset!(storage, "P1|FLOP|AKs|cc", 4)
        is3.last_iteration = 95
        
        # Prune infosets not visited in last 20 iterations
        pruned = Tree.prune_unused!(storage, 100, 20)
        
        @test pruned == 1  # Only is2 should be pruned (50 < 100-20)
        @test length(storage.infosets) == 2
        @test haskey(storage.infosets, "P1|PRE|AKs|c")
        @test !haskey(storage.infosets, "P2|PRE|QQ|r")  # Pruned
        @test haskey(storage.infosets, "P1|FLOP|AKs|cc")
    end
    
    @testset "Edge Cases" begin
        storage = Tree.InfoSetStorage()
        
        # Test with single action
        cfr_is = Tree.get_or_create_infoset!(storage, "terminal", 1)
        strategy = Tree.get_current_strategy(cfr_is)
        @test strategy == [1.0]  # Only one action gets probability 1
        
        # Test average strategy with zero sum
        cfr_is2 = Tree.get_or_create_infoset!(storage, "never_visited", 3)
        avg_strategy = Tree.get_average_strategy(cfr_is2)
        @test all(avg_strategy .≈ 1/3)  # Should be uniform when never visited
        
        # Test regret update with wrong size
        @test_throws AssertionError Tree.update_regrets!(cfr_is2, [1.0, 2.0], 1)  # Wrong size
        
        # Test strategy sum update with wrong size  
        @test_throws AssertionError Tree.update_strategy_sum!(cfr_is2, [0.5, 0.5], 1.0)  # Wrong size
    end
    
    @testset "Integration with InfoSet Module" begin
        # Test that InfoSetManager works well with InfoSet identifiers
        storage = Tree.InfoSetStorage()
        
        # Create an infoset ID using InfoSet module
        infoset_id = Tree.create_infoset_id(
            UInt8(1), 
            Tree.Preflop, 
            "c",
            nothing,  # No cards for this test
            nothing
        )
        
        # Use it with InfoSetManager
        cfr_is = Tree.get_or_create_infoset!(storage, infoset_id, 3)
        @test cfr_is.id == infoset_id
        @test cfr_is.id == "P1|PRE|c"
        
        # Test with cards
        using LHECFR.GameTypes
        hole_cards = [GameTypes.Card(14, 1), GameTypes.Card(13, 1)]  # AK suited
        infoset_id2 = Tree.create_infoset_id(
            UInt8(2),
            Tree.Flop,
            "cr",
            hole_cards,
            nothing
        )
        
        cfr_is2 = Tree.get_or_create_infoset!(storage, infoset_id2, 2)
        @test cfr_is2.id == infoset_id2
        @test occursin("AKs", cfr_is2.id)  # Should contain canonicalized cards
    end
end
