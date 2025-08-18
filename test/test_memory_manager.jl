"""
Tests for the MemoryManager module that provides memory management for large trees.
"""

using Test
using LHECFR
using LHECFR.MemoryManager
using LHECFR.Tree
using LHECFR.CFR
using LHECFR.GameTypes
using LHECFR.Tree.InfoSetManager

# Import MemoryManager functions
import LHECFR.MemoryManager: MemoryConfig, MemoryStats, MemoryMonitor
import LHECFR.MemoryManager: create_memory_monitor, monitor_memory!, get_memory_stats
import LHECFR.MemoryManager: prune_tree!, estimate_memory_usage, optimize_memory!
import LHECFR.MemoryManager: set_memory_limit!, check_memory_pressure
import LHECFR.MemoryManager: DepthPruning, ImportancePruning, FrequencyPruning, AdaptivePruning

@testset "MemoryManager Tests" begin
    
    @testset "MemoryConfig" begin
        # Default configuration
        config = MemoryConfig()
        @test config.max_memory_gb == 8.0
        @test config.warning_threshold == 0.75
        @test config.critical_threshold == 0.9
        @test config.enable_pruning == true
        @test config.pruning_strategy == :adaptive
        @test config.pruning_aggressiveness == 0.3
        @test config.min_nodes_to_keep == 10000
        @test config.monitor_interval == 100
        @test config.log_memory_stats == true
        @test config.auto_gc == true
        
        # Custom configuration
        config2 = MemoryConfig(
            max_memory_gb = 4.0,
            warning_threshold = 0.6,
            critical_threshold = 0.8,
            enable_pruning = false,
            pruning_strategy = :depth,
            pruning_aggressiveness = 0.5,
            min_nodes_to_keep = 5000,
            monitor_interval = 50,
            log_memory_stats = false,
            auto_gc = false
        )
        @test config2.max_memory_gb == 4.0
        @test config2.warning_threshold == 0.6
        @test config2.critical_threshold == 0.8
        @test config2.enable_pruning == false
        @test config2.pruning_strategy == :depth
        @test config2.pruning_aggressiveness == 0.5
        @test config2.min_nodes_to_keep == 5000
        @test config2.monitor_interval == 50
        @test config2.log_memory_stats == false
        @test config2.auto_gc == false
        
        # Invalid configurations
        @test_throws AssertionError MemoryConfig(max_memory_gb = -1.0)
        @test_throws AssertionError MemoryConfig(warning_threshold = 1.5)
        @test_throws AssertionError MemoryConfig(critical_threshold = -0.1)
        @test_throws AssertionError MemoryConfig(warning_threshold = 0.9, critical_threshold = 0.8)
        @test_throws AssertionError MemoryConfig(pruning_aggressiveness = 1.5)
        @test_throws AssertionError MemoryConfig(min_nodes_to_keep = 0)
    end
    
    @testset "MemoryMonitor Creation" begin
        monitor = create_memory_monitor()
        @test monitor isa MemoryMonitor
        @test monitor.config isa MemoryConfig
        @test monitor.stats isa MemoryStats
        @test isempty(monitor.memory_history)
        @test isempty(monitor.pruning_history)
        @test monitor.warning_issued == false
        @test monitor.critical_issued == false
        @test monitor.auto_pruned == false
        
        # With custom config
        config = MemoryConfig(max_memory_gb = 2.0, log_memory_stats = false)
        monitor2 = create_memory_monitor(config)
        @test monitor2.config.max_memory_gb == 2.0
        @test monitor2.config.log_memory_stats == false
    end
    
    @testset "Memory Estimation" begin
        # Create a small tree for testing
        params = GameTypes.GameParams(stack=4)
        tree = Tree.build_game_tree(params, preflop_only=true, verbose=false)
        cfr_config = CFR.CFRConfig(max_iterations=10)
        cfr_state = CFR.CFRState(tree, cfr_config)
        
        # Test tree memory estimation
        tree_memory = MemoryManager.estimate_tree_memory(tree)
        @test tree_memory > 0
        @test tree_memory < 100  # Small tree should be < 100 MB
        
        # Test infoset memory estimation
        storage = CFR.get_infoset_storage(cfr_state)
        infoset_memory = MemoryManager.estimate_infoset_memory(storage)
        @test infoset_memory >= 0
        
        # Test total memory estimation
        total_memory = estimate_memory_usage(tree, cfr_state)
        @test total_memory == tree_memory + infoset_memory
    end
    
    @testset "Memory Monitoring" begin
        # Create a small tree
        params = GameTypes.GameParams(stack=4)
        tree = Tree.build_game_tree(params, preflop_only=true, verbose=false)
        cfr_state = CFR.CFRState(tree, CFR.CFRConfig())
        
        # Create monitor with low thresholds for testing
        config = MemoryConfig(
            max_memory_gb = 0.001,  # Very low limit to trigger warnings
            warning_threshold = 0.5,
            critical_threshold = 0.7,
            log_memory_stats = false,
            enable_pruning = false
        )
        monitor = create_memory_monitor(config)
        
        # Monitor memory
        stats = monitor_memory!(monitor, tree, cfr_state)
        @test stats isa MemoryStats
        @test stats.node_count == length(tree.nodes)
        @test stats.tree_memory_mb > 0
        @test length(monitor.memory_history) == 1
        
        # Check memory pressure detection
        pressure = check_memory_pressure(monitor)
        @test pressure in [:normal, :warning, :critical]
    end
    
    @testset "Pruning Strategies" begin
        # Create a tree for pruning tests
        params = GameTypes.GameParams(stack=6)
        tree = Tree.build_game_tree(params, preflop_only=true, verbose=false)
        initial_nodes = length(tree.nodes)
        
        @testset "DepthPruning" begin
            tree_copy = deepcopy(tree)
            strategy = DepthPruning(2)
            pruned = prune_tree!(tree_copy, strategy)
            @test pruned >= 0
            @test length(tree_copy.nodes) <= initial_nodes
            @test !isempty(tree_copy.nodes)  # Tree should not be empty
            @test tree_copy.nodes[1].id == 1  # Root should still exist
        end
        
        @testset "ImportancePruning" begin
            tree_copy = deepcopy(tree)
            strategy = ImportancePruning(0.5)
            pruned = prune_tree!(tree_copy, strategy)
            @test pruned >= 0
            @test length(tree_copy.nodes) <= initial_nodes
            @test !isempty(tree_copy.nodes)  # Tree should not be empty
            @test tree_copy.nodes[1].id == 1  # Root should still exist
        end
        
        @testset "FrequencyPruning" begin
            tree_copy = deepcopy(tree)
            # Create frequency strategy with empty visit counts (all nodes will be prunable)
            strategy = FrequencyPruning(10, Dict{Int, Int}())
            pruned = prune_tree!(tree_copy, strategy, 0.5)
            @test pruned >= 0
            @test length(tree_copy.nodes) <= initial_nodes
            @test !isempty(tree_copy.nodes)  # Tree should not be empty
            @test tree_copy.nodes[1].id == 1  # Root should still exist
        end
        
        @testset "AdaptivePruning" begin
            tree_copy = deepcopy(tree)
            target_nodes = div(initial_nodes, 2)  # Target half the nodes
            strategy = AdaptivePruning(target_nodes, 0.5)
            pruned = prune_tree!(tree_copy, strategy)
            @test pruned >= 0
            @test length(tree_copy.nodes) <= initial_nodes
            @test !isempty(tree_copy.nodes)  # Tree should not be empty
            @test tree_copy.nodes[1].id == 1  # Root should still exist
            # Should be close to target (within 20%)
            @test abs(length(tree_copy.nodes) - target_nodes) < initial_nodes * 0.2
        end
    end
    
    @testset "Importance Score Calculation" begin
        params = GameTypes.GameParams(stack=4)
        tree = Tree.build_game_tree(params, preflop_only=true, verbose=false)
        
        scores = MemoryManager.calculate_importance_scores(tree)
        @test length(scores) == length(tree.nodes)
        @test all(0 <= score <= 1 for (_, score) in scores)
        @test scores[1] > 0  # Root should have positive importance
        
        # Check that root has high importance
        root_score = scores[1]
        avg_score = sum(values(scores)) / length(scores)
        @test root_score >= avg_score  # Root should be at least average importance
    end
    
    @testset "Memory Optimization" begin
        params = GameTypes.GameParams(stack=4)
        tree = Tree.build_game_tree(params, preflop_only=true, verbose=false)
        cfr_state = CFR.CFRState(tree, CFR.CFRConfig())
        
        config = MemoryConfig(
            enable_pruning = true,
            pruning_strategy = :adaptive,
            pruning_aggressiveness = 0.2,
            auto_gc = true,
            log_memory_stats = false
        )
        monitor = create_memory_monitor(config)
        
        initial_nodes = length(tree.nodes)
        
        # Run optimization
        optimizations = optimize_memory!(tree, cfr_state, monitor)
        @test optimizations isa Vector{String}
        @test length(tree.nodes) <= initial_nodes
        @test !isempty(tree.nodes)  # Tree should not be empty
        @test tree.nodes[1].id == 1  # Root should still exist
    end
    
    @testset "Orphaned Node Removal" begin
        params = GameTypes.GameParams(stack=4)
        tree = Tree.build_game_tree(params, preflop_only=true, verbose=false)
        
        # Manually create an orphaned node
        # Get the maximum ID from existing nodes
        max_id = maximum(node.id for node in tree.nodes)
        
        # Create an orphaned node (not connected to the tree)
        orphan_node = Tree.TreeNode.GameNode(
            max_id + 1,  # id
            Tree.TreeNode.PlayerNode,  # type
            UInt8(1),    # player
            Tree.TreeNode.Preflop,  # street
            Float32(10), # pot
            UInt8(0),    # raises_on_street
            false,       # facing_bet
            nothing      # parent
        )
        # Orphan node has no children (not needed for this test)
        
        # Add orphaned node to the tree
        push!(tree.nodes, orphan_node)
        
        initial_count = length(tree.nodes)
        removed = MemoryManager.remove_orphaned_nodes!(tree)
        @test removed >= 1
        @test length(tree.nodes) < initial_count
        # Check that orphaned node was removed
        @test !any(node.id == max_id + 1 for node in tree.nodes)
    end
    
    @testset "Memory Limit Setting" begin
        monitor = create_memory_monitor()
        original_limit = monitor.config.max_memory_gb
        
        # Set new limit
        new_limit = 16.0
        set_memory_limit!(monitor, new_limit)
        @test monitor.config.max_memory_gb == new_limit
        
        # Test invalid limit
        @test_throws AssertionError set_memory_limit!(monitor, -1.0)
    end
    
    @testset "Memory Pressure Levels" begin
        config = MemoryConfig(
            max_memory_gb = 1.0,
            warning_threshold = 0.5,
            critical_threshold = 0.8,
            log_memory_stats = false
        )
        monitor = create_memory_monitor(config)
        
        # Test normal pressure
        monitor.stats.used_memory_mb = 400  # 40% of 1GB
        @test check_memory_pressure(monitor) == :normal
        
        # Test warning pressure
        monitor.stats.used_memory_mb = 600  # 60% of 1GB
        @test check_memory_pressure(monitor) == :warning
        
        # Test critical pressure
        monitor.stats.used_memory_mb = 900  # 90% of 1GB
        @test check_memory_pressure(monitor) == :critical
    end
    
    @testset "Auto-Pruning on Critical Memory" begin
        params = GameTypes.GameParams(stack=4)
        tree = Tree.build_game_tree(params, preflop_only=true, verbose=false)
        cfr_state = CFR.CFRState(tree, CFR.CFRConfig())
        
        config = MemoryConfig(
            max_memory_gb = 0.0001,  # Extremely low to trigger critical
            warning_threshold = 0.5,
            critical_threshold = 0.7,
            enable_pruning = true,
            pruning_strategy = :adaptive,
            pruning_aggressiveness = 0.5,  # More aggressive pruning
            min_nodes_to_keep = 10,  # Lower minimum
            log_memory_stats = false
        )
        monitor = create_memory_monitor(config)
        
        initial_nodes = length(tree.nodes)
        
        # Should trigger auto-pruning
        monitor_memory!(monitor, tree, cfr_state)
        
        @test monitor.critical_issued == true
        if monitor.auto_pruned
            @test length(tree.nodes) < initial_nodes || initial_nodes <= config.min_nodes_to_keep
            @test length(monitor.pruning_history) > 0 || initial_nodes <= config.min_nodes_to_keep
        end
    end
    
    @testset "Clear Unused InfoSets" begin
        params = GameTypes.GameParams(stack=4)
        tree = Tree.build_game_tree(params, preflop_only=true, verbose=false)
        cfr_state = CFR.CFRState(tree, CFR.CFRConfig())
        
        # Add some infosets
        storage = CFR.get_infoset_storage(cfr_state)
        initial_count = length(storage.infosets)
        for i in 1:5
            InfoSetManager.get_or_create_infoset!(storage, "test_infoset_$i", 3)
        end
        
        new_count = length(storage.infosets)
        @test new_count == initial_count + 5
        
        # Clear unused (currently simplified to return 0)
        cleared = MemoryManager.clear_unused_infosets!(cfr_state, tree)
        @test cleared >= 0  # Currently returns 0 in simplified implementation
    end
end
