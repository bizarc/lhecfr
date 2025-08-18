"""
Tests for the Checkpoint module that provides save/restore functionality for long-running solves.
"""

using Test
using LHECFR
using LHECFR.Checkpoint
using LHECFR.CFR
using LHECFR.GameTypes
using LHECFR.Tree
using LHECFR.Tree.InfoSetManager
using Dates
using Serialization

@testset "Checkpoint Tests" begin
    
    # Create temporary directory for test checkpoints
    test_dir = mktempdir()
    
    @testset "CheckpointOptions" begin
        # Default options
        opts = CheckpointOptions(checkpoint_dir=test_dir)
        @test opts.enabled == true
        @test opts.checkpoint_dir == test_dir
        @test opts.frequency_iterations == 1000
        @test opts.frequency_seconds == 300.0
        @test opts.max_checkpoints == 5
        @test opts.compress == true
        @test opts.save_full_state == true
        
        # Custom options
        opts2 = CheckpointOptions(
            enabled = false,
            checkpoint_dir = test_dir,
            frequency_iterations = 500,
            max_checkpoints = 3,
            compress = false
        )
        @test opts2.enabled == false
        @test opts2.frequency_iterations == 500
        @test opts2.max_checkpoints == 3
        @test opts2.compress == false
        
        # Directory creation
        subdir = joinpath(test_dir, "subdir")
        opts3 = CheckpointOptions(checkpoint_dir=subdir)
        @test isdir(subdir)
    end
    
    @testset "CheckpointManager" begin
        opts = CheckpointOptions(checkpoint_dir=test_dir)
        manager = create_checkpoint_manager(opts)
        
        @test manager.options === opts
        @test manager.last_checkpoint_iteration == 0
        @test manager.last_checkpoint_exploitability == Inf
        @test manager.best_exploitability == Inf
        @test manager.best_checkpoint_file === nothing
    end
    
    @testset "Should Checkpoint Logic" begin
        opts = CheckpointOptions(
            checkpoint_dir = test_dir,
            frequency_iterations = 100,
            frequency_seconds = 10.0,
            frequency_exploitability = 0.01
        )
        manager = create_checkpoint_manager(opts)
        
        # Test iteration frequency
        @test should_checkpoint(manager, 100) == true
        @test should_checkpoint(manager, 50) == false
        
        # Update last checkpoint
        manager.last_checkpoint_iteration = 100
        @test should_checkpoint(manager, 150) == false
        @test should_checkpoint(manager, 200) == true
        
        # Test time frequency
        manager.last_checkpoint_time = time() - 11.0  # 11 seconds ago
        @test should_checkpoint(manager, 150) == true
        
        # Test exploitability improvement
        manager.last_checkpoint_exploitability = 0.1
        manager.last_checkpoint_time = time() - 1.0  # Reset time to avoid time-based trigger
        @test should_checkpoint(manager, 150, 0.08) == true  # Improved by 0.02
        @test should_checkpoint(manager, 150, 0.095) == false  # Only improved by 0.005
        
        # Test disabled checkpointing
        opts2 = CheckpointOptions(enabled=false, checkpoint_dir=test_dir)
        manager2 = create_checkpoint_manager(opts2)
        @test should_checkpoint(manager2, 1000) == false
    end
    
    @testset "Save and Load Checkpoint" begin
        # Create a simple CFR state
        params = GameTypes.GameParams(stack=4)
        tree = Tree.build_game_tree(params, preflop_only=true, verbose=false)
        cfr_config = CFR.CFRConfig(max_iterations=1000)
        cfr_state = CFR.CFRState(tree, cfr_config)
        
        # Add some data to the state
        cfr_state.iteration = 100
        cfr_state.exploitability = 0.05
        
        # Create checkpoint manager
        opts = CheckpointOptions(
            checkpoint_dir = test_dir,
            compress = false  # Easier to debug
        )
        manager = create_checkpoint_manager(opts)
        
        # Save checkpoint
        info = save_checkpoint(cfr_state, manager, tree, 
                             iteration=100, 
                             exploitability=0.05,
                             metadata=Dict{String, Any}("test" => "value"))
        
        @test info.iteration == 100
        @test info.exploitability == 0.05
        @test info.compressed == false
        @test isfile(info.filepath)
        @test info.metadata["test"] == "value"
        
        # Load checkpoint
        checkpoint_data = load_checkpoint(info.filepath)
        @test checkpoint_data["iteration"] == 100
        @test checkpoint_data["exploitability"] == 0.05
        @test checkpoint_data["metadata"]["test"] == "value"
        @test haskey(checkpoint_data, "cfr_state")
    end
    
    @testset "Restore from Checkpoint" begin
        # Create and train a CFR state
        params = GameTypes.GameParams(stack=4)
        tree = Tree.build_game_tree(params, preflop_only=true, verbose=false)
        cfr_config = CFR.CFRConfig(max_iterations=1000)
        cfr_state = CFR.CFRState(tree, cfr_config)
        
        # Simulate some training
        cfr_state.iteration = 250
        cfr_state.exploitability = 0.03
        cfr_state.convergence_history = [0.1, 0.08, 0.05, 0.03]
        
        # Save checkpoint
        opts = CheckpointOptions(checkpoint_dir=test_dir)
        manager = create_checkpoint_manager(opts)
        info = save_checkpoint(cfr_state, manager, tree)
        
        # Create a new state and restore
        new_tree = Tree.build_game_tree(params, preflop_only=true, verbose=false)
        restored_state, checkpoint_data = restore_from_checkpoint(info.filepath, new_tree)
        
        @test restored_state.iteration == 250
        @test restored_state.exploitability == 0.03
        @test length(restored_state.convergence_history) == 4
        @test restored_state.convergence_history[end] == 0.03
    end
    
    @testset "Checkpoint List and Management" begin
        opts = CheckpointOptions(
            checkpoint_dir = test_dir,
            max_checkpoints = 3,
            keep_best = true
        )
        manager = create_checkpoint_manager(opts)
        
        # Create multiple checkpoints
        params = GameTypes.GameParams(stack=4)
        tree = Tree.build_game_tree(params, preflop_only=true, verbose=false)
        cfr_state = CFR.CFRState(tree, CFR.CFRConfig())
        
        # Save several checkpoints
        for i in 1:5
            cfr_state.iteration = i * 100
            cfr_state.exploitability = 0.1 / i  # Improving
            sleep(0.01)  # Ensure different timestamps
            save_checkpoint(cfr_state, manager, tree)
        end
        
        # Should only keep 3 checkpoints
        @test length(manager.checkpoints) <= 3
        
        # Best checkpoint should be kept
        @test manager.best_exploitability ≈ 0.02  # 0.1/5
        @test manager.best_checkpoint_file !== nothing
        
        # List checkpoints
        checkpoints = list_checkpoints(test_dir)
        @test length(checkpoints) > 0
        @test all(info -> info.iteration > 0, checkpoints)
    end
    
    @testset "Auto Checkpoint" begin
        params = GameTypes.GameParams(stack=4)
        tree = Tree.build_game_tree(params, preflop_only=true, verbose=false)
        cfr_state = CFR.CFRState(tree, CFR.CFRConfig())
        
        opts = CheckpointOptions(
            checkpoint_dir = test_dir,
            frequency_iterations = 50
        )
        manager = create_checkpoint_manager(opts)
        
        # Should not checkpoint at iteration 25
        cfr_state.iteration = 25
        auto_checkpoint!(cfr_state, manager, tree)
        initial_count = length(manager.checkpoints)
        
        # Should checkpoint at iteration 50
        cfr_state.iteration = 50
        auto_checkpoint!(cfr_state, manager, tree)
        @test length(manager.checkpoints) == initial_count + 1
    end
    
    @testset "Compressed Checkpoints" begin
        params = GameTypes.GameParams(stack=4)
        tree = Tree.build_game_tree(params, preflop_only=true, verbose=false)
        cfr_state = CFR.CFRState(tree, CFR.CFRConfig())
        
        # Save compressed checkpoint
        opts = CheckpointOptions(
            checkpoint_dir = test_dir,
            compress = true
        )
        manager = create_checkpoint_manager(opts)
        
        cfr_state.iteration = 300
        info = save_checkpoint(cfr_state, manager, tree)
        
        @test info.compressed == true
        @test endswith(info.filename, ".gz")
        @test isfile(info.filepath)
        
        # Load compressed checkpoint
        restored_state, _ = restore_from_checkpoint(info.filepath, tree)
        @test restored_state.iteration == 300
    end
    
    @testset "Strategies Only Mode" begin
        params = GameTypes.GameParams(stack=4)
        tree = Tree.build_game_tree(params, preflop_only=true, verbose=false)
        cfr_state = CFR.CFRState(tree, CFR.CFRConfig())
        
        # Create some infosets with strategies
        storage = CFR.get_infoset_storage(cfr_state)
        infoset1 = InfoSetManager.CFRInfoSet("test1", 2, zeros(2), zeros(2), 0)
        infoset1.strategy_sum = [10.0, 20.0]
        storage.infosets["test1"] = infoset1
        
        # Save strategies only
        opts = CheckpointOptions(
            checkpoint_dir = test_dir,
            save_strategies_only = true,
            save_full_state = false
        )
        manager = create_checkpoint_manager(opts)
        
        info = save_checkpoint(cfr_state, manager, tree)
        
        # Load and verify
        checkpoint_data = load_checkpoint(info.filepath)
        @test haskey(checkpoint_data, "strategies")
        @test !haskey(checkpoint_data, "cfr_state")  # Should not have full state
        
        strategies = checkpoint_data["strategies"]
        @test haskey(strategies, "test1")
        @test strategies["test1"] ≈ [1/3, 2/3]  # Normalized strategy
    end
    
    @testset "Delete Checkpoint" begin
        # Create a test checkpoint file
        test_file = joinpath(test_dir, "test_checkpoint.jls")
        open(test_file, "w") do io
            serialize(io, Dict("test" => "data"))
        end
        
        @test isfile(test_file)
        @test delete_checkpoint(test_file) == true
        @test !isfile(test_file)
        @test delete_checkpoint(test_file) == false  # Already deleted
    end
    
    @testset "File Size Formatting" begin
        @test Checkpoint.format_file_size(500) == "500 B"
        @test Checkpoint.format_file_size(1536) == "1.5 KB"
        @test Checkpoint.format_file_size(1048576) == "1.0 MB"
        @test Checkpoint.format_file_size(2147483648) == "2.0 GB"
    end
    
    @testset "Print Checkpoint List" begin
        # Create some test checkpoint info
        checkpoints = [
            CheckpointInfo(
                "checkpoint_iter100_20250101_120000.jls",
                "/path/to/checkpoint1.jls",
                100, 0.05, now(), 1024000, false, false,
                Dict{String, Any}()
            ),
            CheckpointInfo(
                "checkpoint_iter200_20250101_130000.jls",
                "/path/to/checkpoint2.jls",
                200, 0.02, now(), 2048000, true, true,
                Dict{String, Any}()
            )
        ]
        
        # Capture output
        io = IOBuffer()
        Checkpoint.print_checkpoint_list(checkpoints, io=io)
        output = String(take!(io))
        
        @test occursin("Available Checkpoints", output)
        @test occursin("100", output)
        @test occursin("200", output)
        @test occursin("*", output)  # Best checkpoint marker
    end
    
    # Cleanup
    rm(test_dir, recursive=true, force=true)
end
