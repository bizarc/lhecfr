"""
    SolverConfig

Comprehensive configuration system for the LHE CFR solver, providing a unified
interface for all solver parameters including game setup, algorithm settings,
resource limits, and output options.
"""
module SolverConfig

using ..GameTypes
using ..CFR
using ..ThreadedCFR
using ..CFRMetrics
using ..Tree.InfoSetCache
using TOML
using JSON
using Dates

# Export configuration types and functions
export SolverConfiguration, GameConfig, AlgorithmConfig, ResourceConfig
export OutputConfig, CheckpointConfig, ValidationConfig
export load_config, save_config, validate_config, merge_configs
export create_default_config, create_minimal_config, create_performance_config
export print_config, config_to_dict, dict_to_config

"""
    GameConfig

Configuration for game-specific parameters.
"""
mutable struct GameConfig
    # Game structure
    stack_size::Int
    small_blind::Int
    big_blind::Int
    max_raises_per_street::Int
    rake_milli_bb::Int
    
    # Tree construction
    preflop_only::Bool
    use_suit_isomorphism::Bool
    use_card_abstraction::Bool
    abstraction_buckets::Int
    
    function GameConfig(;
        stack_size::Int = 200,
        small_blind::Int = 1,
        big_blind::Int = 2,
        max_raises_per_street::Int = 4,
        rake_milli_bb::Int = 0,
        preflop_only::Bool = false,
        use_suit_isomorphism::Bool = true,
        use_card_abstraction::Bool = false,
        abstraction_buckets::Int = 1000
    )
        config = new(
            stack_size, small_blind, big_blind, max_raises_per_street, rake_milli_bb,
            preflop_only, use_suit_isomorphism, use_card_abstraction, abstraction_buckets
        )
        validate_game_config(config)
        return config
    end
end

"""
    AlgorithmConfig

Configuration for CFR algorithm parameters.
"""
mutable struct AlgorithmConfig
    # CFR variant
    use_cfr_plus::Bool
    use_linear_weighting::Bool
    use_discounting::Bool
    discount_factor::Float64
    
    # Sampling
    use_sampling::Bool
    sampling_strategy::Symbol  # :none, :chance, :external, :outcome
    sampling_probability::Float64
    
    # Pruning
    prune_threshold::Float64
    prune_frequency::Int
    
    # Iterations
    max_iterations::Int
    min_iterations::Int
    
    # Convergence
    target_exploitability::Float64  # 1 milli-blind
    check_frequency::Int
    early_stopping::Bool
    
    function AlgorithmConfig(;
        use_cfr_plus::Bool = true,
        use_linear_weighting::Bool = false,
        use_discounting::Bool = false,
        discount_factor::Float64 = 1.0,
        use_sampling::Bool = false,
        sampling_strategy::Symbol = :none,
        sampling_probability::Float64 = 1.0,
        prune_threshold::Float64 = -1e9,
        prune_frequency::Int = 100,
        max_iterations::Int = 1000000,
        min_iterations::Int = 100,
        target_exploitability::Float64 = 0.001,
        check_frequency::Int = 100,
        early_stopping::Bool = true
    )
        config = new(
            use_cfr_plus, use_linear_weighting, use_discounting, discount_factor,
            use_sampling, sampling_strategy, sampling_probability,
            prune_threshold, prune_frequency,
            max_iterations, min_iterations,
            target_exploitability, check_frequency, early_stopping
        )
        validate_algorithm_config(config)
        return config
    end
end

"""
    ResourceConfig

Configuration for computational resource limits.
"""
mutable struct ResourceConfig
    # Threading
    num_threads::Int  # 0 = auto-detect
    thread_chunk_size::Int
    load_balancing::Symbol  # :static, :dynamic, :work_stealing
    thread_safe_cache::Bool
    
    # Memory limits
    max_memory_gb::Float64
    cache_size_mb::Int
    infoset_limit::Int
    enable_memory_pruning::Bool
    pruning_threshold_gb::Float64
    
    # Time limits
    max_time_seconds::Float64  # 1 hour default
    iteration_timeout_seconds::Float64
    
    # Performance
    use_indexing::Bool
    use_caching::Bool
    cache_eviction_policy::Symbol  # :lru, :lfu, :fifo
    
    function ResourceConfig(;
        num_threads::Int = 0,
        thread_chunk_size::Int = 100,
        load_balancing::Symbol = :dynamic,
        thread_safe_cache::Bool = true,
        max_memory_gb::Float64 = 8.0,
        cache_size_mb::Int = 1000,
        infoset_limit::Int = 10_000_000,
        enable_memory_pruning::Bool = true,
        pruning_threshold_gb::Float64 = 6.0,
        max_time_seconds::Float64 = 3600.0,
        iteration_timeout_seconds::Float64 = 60.0,
        use_indexing::Bool = true,
        use_caching::Bool = true,
        cache_eviction_policy::Symbol = :lru
    )
        config = new(
            num_threads, thread_chunk_size, load_balancing, thread_safe_cache,
            max_memory_gb, cache_size_mb, infoset_limit, enable_memory_pruning, pruning_threshold_gb,
            max_time_seconds, iteration_timeout_seconds,
            use_indexing, use_caching, cache_eviction_policy
        )
        validate_resource_config(config)
        return config
    end
end

"""
    OutputConfig

Configuration for output and logging.
"""
mutable struct OutputConfig
    # Console output
    verbose::Bool
    progress_frequency::Int
    show_iteration_details::Bool
    colored_output::Bool
    
    # File output
    log_to_file::Bool
    log_file_path::String
    metrics_file_path::String
    strategy_file_path::String
    
    # Metrics tracking
    track_metrics::Bool
    track_strategy_changes::Bool
    track_regret_evolution::Bool
    track_memory_usage::Bool
    
    # Strategy export
    export_format::Symbol  # :binary, :json, :csv
    export_frequency::Int
    compress_output::Bool
    
    function OutputConfig(;
        verbose::Bool = true,
        progress_frequency::Int = 100,
        show_iteration_details::Bool = false,
        colored_output::Bool = true,
        log_to_file::Bool = false,
        log_file_path::String = "cfr_solver.log",
        metrics_file_path::String = "cfr_metrics.csv",
        strategy_file_path::String = "strategy.dat",
        track_metrics::Bool = true,
        track_strategy_changes::Bool = true,
        track_regret_evolution::Bool = false,
        track_memory_usage::Bool = true,
        export_format::Symbol = :binary,
        export_frequency::Int = 1000,
        compress_output::Bool = true
    )
        config = new(
            verbose, progress_frequency, show_iteration_details, colored_output,
            log_to_file, log_file_path, metrics_file_path, strategy_file_path,
            track_metrics, track_strategy_changes, track_regret_evolution, track_memory_usage,
            export_format, export_frequency, compress_output
        )
        validate_output_config(config)
        return config
    end
end

"""
    CheckpointConfig

Configuration for checkpointing and recovery.
"""
mutable struct CheckpointConfig
    # Checkpointing
    enable_checkpoints::Bool
    checkpoint_frequency::Int
    checkpoint_dir::String
    max_checkpoints::Int
    
    # Recovery
    auto_resume::Bool
    resume_from_checkpoint::String
    
    # Checkpoint content
    save_full_state::Bool
    save_strategies_only::Bool
    compress_checkpoints::Bool
    
    function CheckpointConfig(;
        enable_checkpoints::Bool = false,
        checkpoint_frequency::Int = 1000,
        checkpoint_dir::String = "checkpoints",
        max_checkpoints::Int = 3,
        auto_resume::Bool = true,
        resume_from_checkpoint::String = "",
        save_full_state::Bool = true,
        save_strategies_only::Bool = false,
        compress_checkpoints::Bool = true
    )
        config = new(
            enable_checkpoints, checkpoint_frequency, checkpoint_dir, max_checkpoints,
            auto_resume, resume_from_checkpoint,
            save_full_state, save_strategies_only, compress_checkpoints
        )
        validate_checkpoint_config(config)
        return config
    end
end

"""
    ValidationConfig

Configuration for solution validation and testing.
"""
mutable struct ValidationConfig
    # Validation
    validate_strategies::Bool
    validate_zero_sum::Bool
    validate_reach_probabilities::Bool
    
    # Testing
    run_convergence_tests::Bool
    test_against_baseline::Bool
    baseline_strategy_path::String
    
    # Benchmarking
    benchmark_performance::Bool
    benchmark_iterations::Int
    
    function ValidationConfig(;
        validate_strategies::Bool = true,
        validate_zero_sum::Bool = true,
        validate_reach_probabilities::Bool = false,
        run_convergence_tests::Bool = false,
        test_against_baseline::Bool = false,
        baseline_strategy_path::String = "",
        benchmark_performance::Bool = false,
        benchmark_iterations::Int = 100
    )
        return new(
            validate_strategies, validate_zero_sum, validate_reach_probabilities,
            run_convergence_tests, test_against_baseline, baseline_strategy_path,
            benchmark_performance, benchmark_iterations
        )
    end
end

"""
    SolverConfiguration

Master configuration containing all solver settings.
"""
struct SolverConfiguration
    game::GameConfig
    algorithm::AlgorithmConfig
    resources::ResourceConfig
    output::OutputConfig
    checkpoint::CheckpointConfig
    validation::ValidationConfig
    metadata::Dict{String, Any}
    
    function SolverConfiguration(;
        game::GameConfig = GameConfig(),
        algorithm::AlgorithmConfig = AlgorithmConfig(),
        resources::ResourceConfig = ResourceConfig(),
        output::OutputConfig = OutputConfig(),
        checkpoint::CheckpointConfig = CheckpointConfig(),
        validation::ValidationConfig = ValidationConfig(),
        metadata::Dict{String, Any} = Dict{String, Any}()
    )
        # Add metadata
        if !haskey(metadata, "created_at")
            metadata["created_at"] = string(now())
        end
        if !haskey(metadata, "version")
            metadata["version"] = "0.1.0"
        end
        
        config = new(game, algorithm, resources, output, checkpoint, validation, metadata)
        validate_config(config)
        return config
    end
end

# Validation functions
function validate_game_config(config::GameConfig)
    @assert config.stack_size > 0 "Stack size must be positive"
    @assert config.small_blind > 0 "Small blind must be positive"
    @assert config.big_blind > config.small_blind "Big blind must be larger than small blind"
    @assert config.max_raises_per_street >= 1 "Must allow at least 1 raise per street"
    @assert config.rake_milli_bb >= 0 "Rake cannot be negative"
    @assert config.abstraction_buckets > 0 "Abstraction buckets must be positive"
end

function validate_algorithm_config(config::AlgorithmConfig)
    @assert config.discount_factor > 0 && config.discount_factor <= 1 "Discount factor must be in (0, 1]"
    @assert config.sampling_probability > 0 && config.sampling_probability <= 1 "Sampling probability must be in (0, 1]"
    @assert config.max_iterations > 0 "Maximum iterations must be positive"
    @assert config.min_iterations >= 0 "Minimum iterations cannot be negative"
    @assert config.target_exploitability >= 0 "Target exploitability cannot be negative"
    @assert config.check_frequency > 0 "Check frequency must be positive"
    @assert config.prune_frequency > 0 "Prune frequency must be positive"
    @assert config.sampling_strategy in [:none, :chance, :external, :outcome] "Invalid sampling strategy"
end

function validate_resource_config(config::ResourceConfig)
    @assert config.num_threads >= 0 "Number of threads cannot be negative"
    @assert config.thread_chunk_size > 0 "Thread chunk size must be positive"
    @assert config.max_memory_gb > 0 "Maximum memory must be positive"
    @assert config.cache_size_mb > 0 "Cache size must be positive"
    @assert config.infoset_limit > 0 "Information set limit must be positive"
    @assert config.pruning_threshold_gb > 0 && config.pruning_threshold_gb <= config.max_memory_gb "Invalid pruning threshold"
    @assert config.max_time_seconds > 0 "Maximum time must be positive"
    @assert config.iteration_timeout_seconds > 0 "Iteration timeout must be positive"
    @assert config.load_balancing in [:static, :dynamic, :work_stealing] "Invalid load balancing strategy"
    @assert config.cache_eviction_policy in [:lru, :lfu, :fifo] "Invalid cache eviction policy"
end

function validate_output_config(config::OutputConfig)
    @assert config.progress_frequency > 0 "Progress frequency must be positive"
    @assert config.export_frequency > 0 "Export frequency must be positive"
    @assert config.export_format in [:binary, :json, :csv] "Invalid export format"
    
    # Validate file paths are not empty if enabled
    if config.log_to_file
        @assert !isempty(config.log_file_path) "Log file path cannot be empty when logging is enabled"
    end
end

function validate_checkpoint_config(config::CheckpointConfig)
    @assert config.checkpoint_frequency > 0 "Checkpoint frequency must be positive"
    @assert config.max_checkpoints > 0 "Maximum checkpoints must be positive"
    @assert !isempty(config.checkpoint_dir) "Checkpoint directory cannot be empty"
end

"""
    validate_config(config::SolverConfiguration)

Validate the entire solver configuration.
"""
function validate_config(config::SolverConfiguration)
    # Cross-validation between configs
    if config.algorithm.use_sampling && config.resources.num_threads > 1
        @warn "Sampling with multiple threads may affect reproducibility"
    end
    
    if config.resources.max_memory_gb < config.resources.cache_size_mb / 1000
        @warn "Cache size exceeds total memory limit"
    end
    
    if config.checkpoint.enable_checkpoints && config.output.compress_output
        @info "Both checkpointing and output compression enabled - may impact performance"
    end
    
    return true
end

"""
    create_default_config()

Create a default solver configuration suitable for most use cases.
"""
function create_default_config()
    return SolverConfiguration()
end

"""
    create_minimal_config()

Create a minimal configuration for testing and small problems.
"""
function create_minimal_config()
    return SolverConfiguration(
        game = GameConfig(stack_size=10, preflop_only=true),
        algorithm = AlgorithmConfig(max_iterations=1000, check_frequency=100),
        resources = ResourceConfig(max_memory_gb=1.0, cache_size_mb=100, pruning_threshold_gb=0.8),
        output = OutputConfig(verbose=false, track_metrics=false),
        checkpoint = CheckpointConfig(enable_checkpoints=false)
    )
end

"""
    create_performance_config()

Create a high-performance configuration for production solving.
"""
function create_performance_config()
    return SolverConfiguration(
        game = GameConfig(use_suit_isomorphism=true, use_card_abstraction=true),
        algorithm = AlgorithmConfig(
            use_cfr_plus=true,
            use_linear_weighting=true,
            use_sampling=true,
            sampling_strategy=:external
        ),
        resources = ResourceConfig(
            num_threads=0,  # Use all available
            load_balancing=:work_stealing,
            max_memory_gb=32.0,
            cache_size_mb=8000,
            use_indexing=true,
            use_caching=true
        ),
        output = OutputConfig(
            verbose=true,
            log_to_file=true,
            track_metrics=true,
            export_format=:binary,
            compress_output=true
        ),
        checkpoint = CheckpointConfig(
            enable_checkpoints=true,
            checkpoint_frequency=10000,
            compress_checkpoints=true
        )
    )
end

"""
    load_config(filepath::String)

Load a solver configuration from a TOML or JSON file.
"""
function load_config(filepath::String)
    if endswith(filepath, ".toml")
        dict = TOML.parsefile(filepath)
    elseif endswith(filepath, ".json")
        dict = JSON.parsefile(filepath)
    else
        error("Unsupported config file format. Use .toml or .json")
    end
    
    return dict_to_config(dict)
end

"""
    save_config(config::SolverConfiguration, filepath::String)

Save a solver configuration to a TOML or JSON file.
"""
function save_config(config::SolverConfiguration, filepath::String)
    dict = config_to_dict(config)
    
    if endswith(filepath, ".toml")
        open(filepath, "w") do io
            TOML.print(io, dict)
        end
    elseif endswith(filepath, ".json")
        open(filepath, "w") do io
            JSON.print(io, dict, 4)
        end
    else
        error("Unsupported config file format. Use .toml or .json")
    end
end

"""
    config_to_dict(config::SolverConfiguration)

Convert a solver configuration to a dictionary.
"""
function config_to_dict(config::SolverConfiguration)
    return Dict(
        "game" => struct_to_dict(config.game),
        "algorithm" => struct_to_dict(config.algorithm),
        "resources" => struct_to_dict(config.resources),
        "output" => struct_to_dict(config.output),
        "checkpoint" => struct_to_dict(config.checkpoint),
        "validation" => struct_to_dict(config.validation),
        "metadata" => config.metadata
    )
end

function struct_to_dict(obj)
    dict = Dict{String, Any}()
    for field in fieldnames(typeof(obj))
        value = getfield(obj, field)
        # Convert Symbols to strings for TOML serialization
        if isa(value, Symbol)
            value = string(value)
        end
        dict[string(field)] = value
    end
    return dict
end

"""
    dict_to_config(dict::Dict)

Create a solver configuration from a dictionary.
"""
function dict_to_config(dict::Dict)
    game = dict_to_struct(get(dict, "game", Dict()), GameConfig)
    algorithm = dict_to_struct(get(dict, "algorithm", Dict()), AlgorithmConfig)
    resources = dict_to_struct(get(dict, "resources", Dict()), ResourceConfig)
    output = dict_to_struct(get(dict, "output", Dict()), OutputConfig)
    checkpoint = dict_to_struct(get(dict, "checkpoint", Dict()), CheckpointConfig)
    validation = dict_to_struct(get(dict, "validation", Dict()), ValidationConfig)
    metadata = get(dict, "metadata", Dict{String, Any}())
    
    return SolverConfiguration(
        game=game,
        algorithm=algorithm,
        resources=resources,
        output=output,
        checkpoint=checkpoint,
        validation=validation,
        metadata=metadata
    )
end

function dict_to_struct(dict::Dict, T::Type)
    # Create a list of field names for the type
    field_names = fieldnames(T)
    
    # Build kwargs with only the fields that exist in the struct
    kwargs = Dict{Symbol, Any}()
    for field in field_names
        field_str = string(field)
        if haskey(dict, field_str)
            value = dict[field_str]
            # Convert strings back to Symbols for specific fields
            if field in [:sampling_strategy, :load_balancing, :cache_eviction_policy, :export_format] && isa(value, String)
                value = Symbol(value)
            end
            kwargs[field] = value
        end
    end
    
    return T(; kwargs...)
end

"""
    merge_configs(base::SolverConfiguration, override::Dict)

Merge a configuration with override values from a dictionary.
"""
function merge_configs(base::SolverConfiguration, override::Dict)
    base_dict = config_to_dict(base)
    merged_dict = recursive_merge(base_dict, override)
    return dict_to_config(merged_dict)
end

function recursive_merge(base::Dict, override::Dict)
    result = copy(base)
    for (k, v) in override
        if haskey(result, k) && isa(result[k], Dict) && isa(v, Dict)
            result[k] = recursive_merge(result[k], v)
        else
            result[k] = v
        end
    end
    return result
end

"""
    print_config(config::SolverConfiguration; io::IO = stdout)

Print a human-readable summary of the configuration.
"""
function print_config(config::SolverConfiguration; io::IO = stdout)
    println(io, "╔══════════════════════════════════════════════╗")
    println(io, "║        LHE CFR Solver Configuration          ║")
    println(io, "╚══════════════════════════════════════════════╝")
    
    println(io, "\n📎 Game Configuration:")
    println(io, "  • Stack size: $(config.game.stack_size) BB")
    println(io, "  • Blinds: $(config.game.small_blind)/$(config.game.big_blind)")
    println(io, "  • Max raises: $(config.game.max_raises_per_street) per street")
    println(io, "  • Preflop only: $(config.game.preflop_only)")
    println(io, "  • Suit isomorphism: $(config.game.use_suit_isomorphism)")
    
    println(io, "\n⚙️  Algorithm Configuration:")
    println(io, "  • Variant: $(config.algorithm.use_cfr_plus ? "CFR+" : "Vanilla CFR")")
    println(io, "  • Linear weighting: $(config.algorithm.use_linear_weighting)")
    println(io, "  • Sampling: $(config.algorithm.use_sampling ? config.algorithm.sampling_strategy : "None")")
    println(io, "  • Max iterations: $(config.algorithm.max_iterations)")
    println(io, "  • Target exploitability: $(config.algorithm.target_exploitability)")
    
    println(io, "\n💻 Resource Configuration:")
    println(io, "  • Threads: $(config.resources.num_threads == 0 ? "Auto" : config.resources.num_threads)")
    println(io, "  • Load balancing: $(config.resources.load_balancing)")
    println(io, "  • Max memory: $(config.resources.max_memory_gb) GB")
    println(io, "  • Cache size: $(config.resources.cache_size_mb) MB")
    println(io, "  • Max time: $(config.resources.max_time_seconds / 3600) hours")
    
    println(io, "\n📊 Output Configuration:")
    println(io, "  • Verbose: $(config.output.verbose)")
    println(io, "  • Log to file: $(config.output.log_to_file)")
    println(io, "  • Track metrics: $(config.output.track_metrics)")
    println(io, "  • Export format: $(config.output.export_format)")
    
    println(io, "\n💾 Checkpoint Configuration:")
    println(io, "  • Enabled: $(config.checkpoint.enable_checkpoints)")
    if config.checkpoint.enable_checkpoints
        println(io, "  • Frequency: Every $(config.checkpoint.checkpoint_frequency) iterations")
        println(io, "  • Directory: $(config.checkpoint.checkpoint_dir)")
    end
    
    println(io, "\n✅ Validation Configuration:")
    println(io, "  • Validate strategies: $(config.validation.validate_strategies)")
    println(io, "  • Validate zero-sum: $(config.validation.validate_zero_sum)")
    println(io, "  • Run tests: $(config.validation.run_convergence_tests)")
    
    if !isempty(config.metadata)
        println(io, "\n📝 Metadata:")
        for (k, v) in config.metadata
            println(io, "  • $k: $v")
        end
    end
end

# Integration helper functions

"""
    to_cfr_config(config::SolverConfiguration)

Convert solver configuration to CFR.CFRConfig.
"""
function to_cfr_config(config::SolverConfiguration)
    return CFR.CFRConfig(
        use_cfr_plus = config.algorithm.use_cfr_plus,
        use_linear_weighting = config.algorithm.use_linear_weighting,
        use_sampling = config.algorithm.use_sampling,
        sampling_strategy = config.algorithm.sampling_strategy,
        sampling_probability = config.algorithm.sampling_probability,
        prune_threshold = config.algorithm.prune_threshold,
        discount_factor = config.algorithm.discount_factor,
        max_iterations = config.algorithm.max_iterations,
        target_exploitability = config.algorithm.target_exploitability,
        max_time_seconds = config.resources.max_time_seconds,
        min_iterations = config.algorithm.min_iterations,
        check_frequency = config.algorithm.check_frequency
    )
end

"""
    to_thread_config(config::SolverConfiguration)

Convert solver configuration to ThreadedCFR.ThreadConfig.
"""
function to_thread_config(config::SolverConfiguration)
    return ThreadedCFR.ThreadConfig(
        num_threads = config.resources.num_threads,
        chunk_size = config.resources.thread_chunk_size,
        thread_safe_cache = config.resources.thread_safe_cache,
        load_balancing = config.resources.load_balancing
    )
end

"""
    to_cache_config(config::SolverConfiguration)

Convert solver configuration to InfoSetCache.CacheConfig.
"""
function to_cache_config(config::SolverConfiguration)
    return InfoSetCache.CacheConfig(
        max_size = config.resources.cache_size_mb * 1000,  # Convert MB to approximate entries
        enable_statistics = config.output.track_metrics,
        eviction_policy = config.resources.cache_eviction_policy,
        thread_safe = config.resources.thread_safe_cache
    )
end

"""
    to_log_config(config::SolverConfiguration)

Convert solver configuration to CFRMetrics.LogConfig.
"""
function to_log_config(config::SolverConfiguration)
    return CFRMetrics.LogConfig(
        verbose = config.output.verbose,
        log_frequency = config.output.progress_frequency,
        log_file = config.output.log_to_file ? config.output.log_file_path : nothing,
        track_strategies = config.output.track_strategy_changes,
        track_regrets = config.output.track_regret_evolution,
        track_memory = config.output.track_memory_usage,
        save_checkpoints = config.checkpoint.enable_checkpoints,
        checkpoint_frequency = config.checkpoint.checkpoint_frequency,
        checkpoint_dir = config.checkpoint.checkpoint_dir
    )
end

"""
    to_game_params(config::SolverConfiguration)

Convert solver configuration to GameTypes.GameParams.
"""
function to_game_params(config::SolverConfiguration)
    return GameTypes.GameParams(
        small_blind = config.game.small_blind,
        big_blind = config.game.big_blind,
        stack = config.game.stack_size,
        max_raises_per_street = config.game.max_raises_per_street,
        rake_milli_bb = config.game.rake_milli_bb
    )
end

end # module SolverConfig
