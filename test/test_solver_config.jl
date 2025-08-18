"""
Tests for the SolverConfig module that provides comprehensive configuration management.
"""

using Test
using LHECFR
using LHECFR.SolverConfig
using LHECFR.GameTypes
using LHECFR.CFR
using LHECFR.ThreadedCFR
using LHECFR.CFRMetrics
using LHECFR.Tree.InfoSetCache

@testset "SolverConfig Tests" begin
    
    @testset "GameConfig" begin
        # Default configuration
        game = GameConfig()
        @test game.stack_size == 200
        @test game.small_blind == 1
        @test game.big_blind == 2
        @test game.max_raises_per_street == 4
        @test game.preflop_only == false
        @test game.use_suit_isomorphism == true
        
        # Custom configuration
        game2 = GameConfig(
            stack_size = 100,
            preflop_only = true,
            use_card_abstraction = true,
            abstraction_buckets = 500
        )
        @test game2.stack_size == 100
        @test game2.preflop_only == true
        @test game2.use_card_abstraction == true
        @test game2.abstraction_buckets == 500
        
        # Validation
        @test_throws AssertionError GameConfig(stack_size = -1)
        @test_throws AssertionError GameConfig(small_blind = 0)
        @test_throws AssertionError GameConfig(big_blind = 1, small_blind = 2)
    end
    
    @testset "AlgorithmConfig" begin
        # Default configuration
        algo = AlgorithmConfig()
        @test algo.use_cfr_plus == true
        @test algo.use_linear_weighting == false
        @test algo.max_iterations == 1000000
        @test algo.target_exploitability == 0.001
        @test algo.sampling_strategy == :none
        
        # Custom configuration
        algo2 = AlgorithmConfig(
            use_cfr_plus = false,
            use_linear_weighting = true,
            max_iterations = 5000,
            use_sampling = true,
            sampling_strategy = :external
        )
        @test algo2.use_cfr_plus == false
        @test algo2.use_linear_weighting == true
        @test algo2.max_iterations == 5000
        @test algo2.sampling_strategy == :external
        
        # Validation
        @test_throws AssertionError AlgorithmConfig(discount_factor = 1.5)
        @test_throws AssertionError AlgorithmConfig(sampling_probability = -0.1)
        @test_throws AssertionError AlgorithmConfig(max_iterations = 0)
    end
    
    @testset "ResourceConfig" begin
        # Default configuration
        resources = ResourceConfig()
        @test resources.num_threads == 0  # Auto-detect
        @test resources.max_memory_gb == 8.0
        @test resources.cache_size_mb == 1000
        @test resources.load_balancing == :dynamic
        @test resources.use_indexing == true
        
        # Custom configuration
        resources2 = ResourceConfig(
            num_threads = 4,
            max_memory_gb = 16.0,
            load_balancing = :work_stealing,
            cache_eviction_policy = :lfu
        )
        @test resources2.num_threads == 4
        @test resources2.max_memory_gb == 16.0
        @test resources2.load_balancing == :work_stealing
        @test resources2.cache_eviction_policy == :lfu
        
        # Validation
        @test_throws AssertionError ResourceConfig(thread_chunk_size = 0)
        @test_throws AssertionError ResourceConfig(max_memory_gb = -1.0)
        @test_throws AssertionError ResourceConfig(pruning_threshold_gb = 10.0, max_memory_gb = 8.0)
    end
    
    @testset "OutputConfig" begin
        # Default configuration
        output = OutputConfig()
        @test output.verbose == true
        @test output.log_to_file == false
        @test output.track_metrics == true
        @test output.export_format == :binary
        
        # Custom configuration
        output2 = OutputConfig(
            verbose = false,
            log_to_file = true,
            log_file_path = "test.log",
            export_format = :json,
            compress_output = false
        )
        @test output2.verbose == false
        @test output2.log_to_file == true
        @test output2.log_file_path == "test.log"
        @test output2.export_format == :json
        @test output2.compress_output == false
        
        # Validation
        @test_throws AssertionError OutputConfig(progress_frequency = 0)
        @test_throws AssertionError OutputConfig(export_frequency = -1)
    end
    
    @testset "CheckpointConfig" begin
        # Default configuration
        checkpoint = CheckpointConfig()
        @test checkpoint.enable_checkpoints == false
        @test checkpoint.checkpoint_frequency == 1000
        @test checkpoint.checkpoint_dir == "checkpoints"
        @test checkpoint.auto_resume == true
        
        # Custom configuration
        checkpoint2 = CheckpointConfig(
            enable_checkpoints = true,
            checkpoint_frequency = 5000,
            checkpoint_dir = "/tmp/cfr_checkpoints",
            max_checkpoints = 5
        )
        @test checkpoint2.enable_checkpoints == true
        @test checkpoint2.checkpoint_frequency == 5000
        @test checkpoint2.checkpoint_dir == "/tmp/cfr_checkpoints"
        @test checkpoint2.max_checkpoints == 5
        
        # Validation
        @test_throws AssertionError CheckpointConfig(checkpoint_frequency = 0)
        @test_throws AssertionError CheckpointConfig(max_checkpoints = 0)
    end
    
    @testset "ValidationConfig" begin
        # Default configuration
        validation = ValidationConfig()
        @test validation.validate_strategies == true
        @test validation.validate_zero_sum == true
        @test validation.run_convergence_tests == false
        @test validation.benchmark_performance == false
        
        # Custom configuration
        validation2 = ValidationConfig(
            validate_strategies = false,
            run_convergence_tests = true,
            benchmark_iterations = 50
        )
        @test validation2.validate_strategies == false
        @test validation2.run_convergence_tests == true
        @test validation2.benchmark_iterations == 50
    end
    
    @testset "SolverConfiguration" begin
        # Default configuration
        config = SolverConfiguration()
        @test config.game isa GameConfig
        @test config.algorithm isa AlgorithmConfig
        @test config.resources isa ResourceConfig
        @test config.output isa OutputConfig
        @test config.checkpoint isa CheckpointConfig
        @test config.validation isa ValidationConfig
        @test haskey(config.metadata, "version")
        @test haskey(config.metadata, "created_at")
        
        # Custom configuration
        config2 = SolverConfiguration(
            game = GameConfig(stack_size = 50),
            algorithm = AlgorithmConfig(max_iterations = 100),
            metadata = Dict{String, Any}("name" => "test_config")
        )
        @test config2.game.stack_size == 50
        @test config2.algorithm.max_iterations == 100
        @test config2.metadata["name"] == "test_config"
    end
    
    @testset "Preset Configurations" begin
        # Default config
        default = create_default_config()
        @test default isa SolverConfiguration
        @test default.game.stack_size == 200
        
        # Minimal config
        minimal = create_minimal_config()
        @test minimal.game.stack_size == 10
        @test minimal.game.preflop_only == true
        @test minimal.algorithm.max_iterations == 1000
        @test minimal.resources.max_memory_gb == 1.0
        
        # Performance config
        perf = create_performance_config()
        @test perf.algorithm.use_cfr_plus == true
        @test perf.algorithm.use_linear_weighting == true
        @test perf.algorithm.use_sampling == true
        @test perf.resources.load_balancing == :work_stealing
        @test perf.checkpoint.enable_checkpoints == true
    end
    
    @testset "Configuration Serialization" begin
        config = create_minimal_config()
        
        # Convert to dictionary
        dict = config_to_dict(config)
        @test haskey(dict, "game")
        @test haskey(dict, "algorithm")
        @test haskey(dict, "resources")
        @test dict["game"]["stack_size"] == 10
        
        # Convert back from dictionary
        config2 = dict_to_config(dict)
        @test config2.game.stack_size == 10
        @test config2.algorithm.max_iterations == 1000
    end
    
    @testset "Configuration Merging" begin
        base_config = create_minimal_config()
        
        # Override some values
        override = Dict(
            "game" => Dict("stack_size" => 20),
            "algorithm" => Dict("max_iterations" => 2000)
        )
        
        merged = merge_configs(base_config, override)
        @test merged.game.stack_size == 20  # Overridden
        @test merged.algorithm.max_iterations == 2000  # Overridden
        @test merged.game.preflop_only == true  # Unchanged from base
    end
    
    @testset "Integration Converters" begin
        config = create_default_config()
        
        # Convert to CFRConfig
        cfr_config = SolverConfig.to_cfr_config(config)
        @test cfr_config isa CFR.CFRConfig
        @test cfr_config.use_cfr_plus == config.algorithm.use_cfr_plus
        @test cfr_config.max_iterations == config.algorithm.max_iterations
        
        # Convert to ThreadConfig
        thread_config = SolverConfig.to_thread_config(config)
        @test thread_config isa ThreadedCFR.ThreadConfig
        # Note: ThreadConfig auto-detects threads when num_threads is 0
        @test thread_config.num_threads > 0  # Should have detected threads
        @test thread_config.load_balancing == config.resources.load_balancing
        
        # Convert to CacheConfig
        cache_config = SolverConfig.to_cache_config(config)
        @test cache_config isa InfoSetCache.CacheConfig
        @test cache_config.eviction_policy == config.resources.cache_eviction_policy
        
        # Convert to LogConfig
        log_config = SolverConfig.to_log_config(config)
        @test log_config isa CFRMetrics.LogConfig
        @test log_config.verbose == config.output.verbose
        # LogConfig uses log_file (String or nothing) instead of log_to_file boolean
        @test (log_config.log_file !== nothing) == config.output.log_to_file
        
        # Convert to GameParams
        game_params = SolverConfig.to_game_params(config)
        @test game_params isa GameTypes.GameParams
        @test game_params.stack == config.game.stack_size
        @test game_params.small_blind == config.game.small_blind
    end
    
    @testset "Configuration Validation" begin
        # Valid configuration should pass
        config = create_default_config()
        @test validate_config(config) == true
        
        # Test cross-validation warnings (these should warn but not error)
        config2 = SolverConfiguration(
            algorithm = AlgorithmConfig(use_sampling = true),
            resources = ResourceConfig(
                num_threads = 4,
                max_memory_gb = 2.0,
                cache_size_mb = 2000,  # At memory limit
                pruning_threshold_gb = 1.5  # Below max_memory_gb
            )
        )
        @test validate_config(config2) == true  # Should pass with warnings
    end
    
    @testset "Print Configuration" begin
        config = create_minimal_config()
        
        # Test that print_config doesn't error
        io = IOBuffer()
        print_config(config, io=io)
        output = String(take!(io))
        
        @test occursin("LHE CFR Solver Configuration", output)
        @test occursin("Game Configuration", output)
        @test occursin("Algorithm Configuration", output)
        @test occursin("Resource Configuration", output)
        @test occursin("Stack size: 10", output)
    end
    
    @testset "File I/O" begin
        config = create_minimal_config()
        
        # Test TOML save/load
        toml_file = tempname() * ".toml"
        save_config(config, toml_file)
        @test isfile(toml_file)
        
        loaded_config = load_config(toml_file)
        @test loaded_config.game.stack_size == config.game.stack_size
        @test loaded_config.algorithm.max_iterations == config.algorithm.max_iterations
        
        rm(toml_file)
        
        # Test JSON save/load
        json_file = tempname() * ".json"
        save_config(config, json_file)
        @test isfile(json_file)
        
        loaded_config2 = load_config(json_file)
        @test loaded_config2.game.stack_size == config.game.stack_size
        @test loaded_config2.algorithm.max_iterations == config.algorithm.max_iterations
        
        rm(json_file)
        
        # Test unsupported format
        @test_throws ErrorException save_config(config, "config.txt")
        @test_throws ErrorException load_config("config.txt")
    end
end
