"""
    Checkpoint

Module for saving and loading CFR solver state to enable pausing and resuming
long-running solves. Provides automatic checkpointing, manual save/restore,
and checkpoint management.
"""
module Checkpoint

using Serialization
using Dates
using Printf
using ..CFR
using ..CFRMetrics
using ..SolverConfig
using ..ProgressTracker
using ..Tree
using ..Tree.InfoSet
using ..Tree.InfoSetManager
using ..GameTypes

# Export main functionality
export CheckpointManager, CheckpointInfo, CheckpointOptions
export save_checkpoint, load_checkpoint, list_checkpoints
export delete_checkpoint, cleanup_old_checkpoints
export auto_checkpoint!, should_checkpoint
export create_checkpoint_manager, restore_from_checkpoint

"""
    CheckpointOptions

Options for checkpoint behavior.
"""
struct CheckpointOptions
    # Basic settings
    enabled::Bool
    checkpoint_dir::String
    
    # Frequency settings
    frequency_iterations::Int    # Checkpoint every N iterations
    frequency_seconds::Float64   # Checkpoint every N seconds
    frequency_exploitability::Float64  # Checkpoint when exploitability improves by N
    
    # Management settings
    max_checkpoints::Int         # Maximum number of checkpoints to keep
    keep_best::Bool              # Always keep checkpoint with best exploitability
    compress::Bool               # Compress checkpoint files
    
    # Content settings
    save_full_state::Bool        # Save complete state including tree
    save_strategies_only::Bool   # Only save converged strategies
    save_metrics::Bool           # Save training metrics history
    
    function CheckpointOptions(;
        enabled::Bool = true,
        checkpoint_dir::String = "checkpoints",
        frequency_iterations::Int = 1000,
        frequency_seconds::Float64 = 300.0,  # 5 minutes
        frequency_exploitability::Float64 = 0.0,  # Disabled by default
        max_checkpoints::Int = 5,
        keep_best::Bool = true,
        compress::Bool = true,
        save_full_state::Bool = true,
        save_strategies_only::Bool = false,
        save_metrics::Bool = true
    )
        # Create checkpoint directory if it doesn't exist
        if enabled && !isdir(checkpoint_dir)
            mkpath(checkpoint_dir)
        end
        
        new(
            enabled, checkpoint_dir,
            frequency_iterations, frequency_seconds, frequency_exploitability,
            max_checkpoints, keep_best, compress,
            save_full_state, save_strategies_only, save_metrics
        )
    end
end

"""
    CheckpointInfo

Metadata about a checkpoint file.
"""
struct CheckpointInfo
    filename::String
    filepath::String
    iteration::Int
    exploitability::Float64
    timestamp::DateTime
    file_size::Int64
    compressed::Bool
    is_best::Bool
    metadata::Dict{String, Any}
end

"""
    CheckpointManager

Manages checkpointing for a CFR solver.
"""
mutable struct CheckpointManager
    options::CheckpointOptions
    checkpoints::Vector{CheckpointInfo}
    last_checkpoint_iteration::Int
    last_checkpoint_time::Float64
    last_checkpoint_exploitability::Float64
    best_exploitability::Float64
    best_checkpoint_file::Union{String, Nothing}
end

"""
    create_checkpoint_manager(options::CheckpointOptions)

Create a new checkpoint manager with the given options.
"""
function create_checkpoint_manager(options::CheckpointOptions = CheckpointOptions())
    # List existing checkpoints
    existing = list_checkpoints(options.checkpoint_dir)
    
    # Find best checkpoint if any exist
    best_exploit = Inf
    best_file = nothing
    for info in existing
        if info.exploitability < best_exploit
            best_exploit = info.exploitability
            best_file = info.filepath
        end
    end
    
    return CheckpointManager(
        options,
        existing,
        0,
        time(),
        Inf,
        best_exploit,
        best_file
    )
end

"""
    should_checkpoint(manager::CheckpointManager, iteration::Int, 
                     exploitability::Float64 = Inf)

Determine if a checkpoint should be saved based on current state.
"""
function should_checkpoint(manager::CheckpointManager, iteration::Int, 
                          exploitability::Float64 = Inf)
    if !manager.options.enabled
        return false
    end
    
    # Check iteration frequency
    if manager.options.frequency_iterations > 0
        if iteration - manager.last_checkpoint_iteration >= manager.options.frequency_iterations
            return true
        end
    end
    
    # Check time frequency
    if manager.options.frequency_seconds > 0
        if time() - manager.last_checkpoint_time >= manager.options.frequency_seconds
            return true
        end
    end
    
    # Check exploitability improvement
    if manager.options.frequency_exploitability > 0 && exploitability < Inf
        improvement = manager.last_checkpoint_exploitability - exploitability
        if improvement >= manager.options.frequency_exploitability
            return true
        end
    end
    
    return false
end

"""
    save_checkpoint(state::CFR.CFRState, manager::CheckpointManager, 
                   tree::Union{Tree.GameTree, Nothing} = nothing;
                   iteration::Union{Int, Nothing} = nothing,
                   exploitability::Union{Float64, Nothing} = nothing,
                   metadata::Dict{String, Any} = Dict{String, Any}())

Save a checkpoint of the current solver state.
"""
function save_checkpoint(state::CFR.CFRState, manager::CheckpointManager, 
                        tree::Union{Tree.GameTree, Nothing} = nothing;
                        iteration::Union{Int, Nothing} = nothing,
                        exploitability::Union{Float64, Nothing} = nothing,
                        metadata::Dict{String, Any} = Dict{String, Any}())
    
    # Use provided values or fall back to state values
    iteration = iteration !== nothing ? iteration : state.iteration
    exploitability = exploitability !== nothing ? exploitability : state.exploitability
    
    options = manager.options
    
    # Generate checkpoint filename
    timestamp = now()
    timestamp_str = Dates.format(timestamp, "yyyymmdd_HHMMSS")
    filename = "checkpoint_iter$(iteration)_$(timestamp_str).jls"
    if options.compress
        filename *= ".gz"
    end
    filepath = joinpath(options.checkpoint_dir, filename)
    
    # Prepare checkpoint data
    checkpoint_data = Dict{String, Any}()
    
    # Basic information
    checkpoint_data["version"] = "1.0.0"
    checkpoint_data["iteration"] = iteration
    checkpoint_data["exploitability"] = exploitability
    checkpoint_data["timestamp"] = timestamp
    checkpoint_data["metadata"] = metadata
    
    # CFR state
    if options.save_full_state || !options.save_strategies_only
        checkpoint_data["cfr_state"] = serialize_cfr_state(state)
    end
    
    # Strategies only (more compact)
    if options.save_strategies_only
        checkpoint_data["strategies"] = extract_strategies(state)
    end
    
    # Game tree (if provided and requested)
    if tree !== nothing && options.save_full_state
        checkpoint_data["tree"] = serialize_tree(tree)
    end
    
    # Metrics history
    if options.save_metrics && state.metrics !== nothing
        checkpoint_data["metrics"] = serialize_metrics(state.metrics)
    end
    
    # Progress information
    if hasfield(typeof(state), :progress) && state.progress !== nothing
        checkpoint_data["progress"] = serialize_progress(state.progress)
    end
    
    # Save checkpoint
    if options.compress
        save_compressed(filepath, checkpoint_data)
    else
        open(filepath, "w") do io
            serialize(io, checkpoint_data)
        end
    end
    
    # Get file size
    file_size = filesize(filepath)
    
    # Check if this is the best checkpoint
    is_best = exploitability < manager.best_exploitability
    if is_best
        manager.best_exploitability = exploitability
        manager.best_checkpoint_file = filepath
    end
    
    # Create checkpoint info
    info = CheckpointInfo(
        filename,
        filepath,
        iteration,
        exploitability,
        timestamp,
        file_size,
        options.compress,
        is_best,
        metadata
    )
    
    # Add to checkpoint list
    push!(manager.checkpoints, info)
    
    # Update manager state
    manager.last_checkpoint_iteration = iteration
    manager.last_checkpoint_time = time()
    manager.last_checkpoint_exploitability = exploitability
    
    # Cleanup old checkpoints if needed
    cleanup_old_checkpoints(manager)
    
    println("✓ Checkpoint saved: $(filename) ($(format_file_size(file_size)))")
    
    return info
end

"""
    load_checkpoint(filepath::String)

Load a checkpoint from file and return the checkpoint data.
"""
function load_checkpoint(filepath::String)
    if !isfile(filepath)
        error("Checkpoint file not found: $filepath")
    end
    
    # Load checkpoint data
    if endswith(filepath, ".gz")
        checkpoint_data = load_compressed(filepath)
    else
        checkpoint_data = open(deserialize, filepath)
    end
    
    # Validate version
    version = get(checkpoint_data, "version", "unknown")
    if version != "1.0.0"
        @warn "Checkpoint version mismatch: expected 1.0.0, got $version"
    end
    
    return checkpoint_data
end

"""
    restore_from_checkpoint(filepath::String, tree::Union{Tree.GameTree, Nothing} = nothing)

Restore solver state from a checkpoint file.
"""
function restore_from_checkpoint(filepath::String, tree::Union{Tree.GameTree, Nothing} = nothing)
    checkpoint_data = load_checkpoint(filepath)
    
    # Restore CFR state
    cfr_state = nothing
    if haskey(checkpoint_data, "cfr_state")
        cfr_state = deserialize_cfr_state(checkpoint_data["cfr_state"], tree)
    elseif haskey(checkpoint_data, "strategies")
        # Create minimal state with just strategies
        cfr_state = create_state_from_strategies(checkpoint_data["strategies"], tree)
    else
        error("Checkpoint does not contain CFR state or strategies")
    end
    
    # Restore metrics if available
    if haskey(checkpoint_data, "metrics")
        metrics = deserialize_metrics(checkpoint_data["metrics"])
        cfr_state.metrics = metrics
    end
    
    # Restore progress if available
    if haskey(checkpoint_data, "progress")
        progress = deserialize_progress(checkpoint_data["progress"])
        if cfr_state.metrics !== nothing
            cfr_state.metrics.progress = progress
        end
    end
    
    # Update state with checkpoint info
    cfr_state.iteration = checkpoint_data["iteration"]
    if haskey(checkpoint_data, "exploitability")
        cfr_state.exploitability = checkpoint_data["exploitability"]
    end
    
    println("✓ Restored from checkpoint: iteration $(cfr_state.iteration)")
    
    return cfr_state, checkpoint_data
end

"""
    auto_checkpoint!(state::CFR.CFRState, manager::CheckpointManager,
                    tree::Union{Tree.GameTree, Nothing} = nothing)

Automatically save a checkpoint if conditions are met.
"""
function auto_checkpoint!(state::CFR.CFRState, manager::CheckpointManager,
                         tree::Union{Tree.GameTree, Nothing} = nothing)
    if should_checkpoint(manager, state.iteration, state.exploitability)
        save_checkpoint(state, manager, tree)
    end
end

"""
    list_checkpoints(checkpoint_dir::String)

List all checkpoints in the given directory.
"""
function list_checkpoints(checkpoint_dir::String)
    if !isdir(checkpoint_dir)
        return CheckpointInfo[]
    end
    
    checkpoints = CheckpointInfo[]
    
    for file in readdir(checkpoint_dir)
        if startswith(file, "checkpoint_") && (endswith(file, ".jls") || endswith(file, ".jls.gz"))
            filepath = joinpath(checkpoint_dir, file)
            
            # Try to extract info from filename
            m = match(r"checkpoint_iter(\d+)_(\d{8}_\d{6})", file)
            if m !== nothing
                iteration = parse(Int, m[1])
                
                # Try to load for more info
                try
                    data = load_checkpoint(filepath)
                    exploitability = get(data, "exploitability", Inf)
                    timestamp = get(data, "timestamp", now())
                    metadata = get(data, "metadata", Dict{String, Any}())
                catch e
                    # If loading fails, use defaults
                    exploitability = Inf
                    timestamp = unix2datetime(mtime(filepath))
                    metadata = Dict{String, Any}()
                end
                
                info = CheckpointInfo(
                    file,
                    filepath,
                    iteration,
                    exploitability,
                    timestamp,
                    filesize(filepath),
                    endswith(file, ".gz"),
                    false,  # is_best will be determined later
                    metadata
                )
                push!(checkpoints, info)
            end
        end
    end
    
    # Sort by iteration
    sort!(checkpoints, by = info -> info.iteration)
    
    return checkpoints
end

"""
    cleanup_old_checkpoints(manager::CheckpointManager)

Remove old checkpoints based on manager settings.
"""
function cleanup_old_checkpoints(manager::CheckpointManager)
    options = manager.options
    
    if options.max_checkpoints <= 0
        return  # No limit
    end
    
    # Sort checkpoints by iteration (newest first)
    sort!(manager.checkpoints, by = info -> info.iteration, rev = true)
    
    # Identify checkpoints to keep
    to_keep = CheckpointInfo[]
    to_delete = CheckpointInfo[]
    
    # Always keep the best checkpoint if requested
    best_checkpoint = nothing
    if options.keep_best && manager.best_checkpoint_file !== nothing
        for info in manager.checkpoints
            if info.filepath == manager.best_checkpoint_file
                best_checkpoint = info
                push!(to_keep, info)
                break
            end
        end
    end
    
    # Keep the most recent checkpoints
    for info in manager.checkpoints
        if info !== best_checkpoint
            if length(to_keep) < options.max_checkpoints
                push!(to_keep, info)
            else
                push!(to_delete, info)
            end
        end
    end
    
    # Delete old checkpoints
    for info in to_delete
        try
            rm(info.filepath)
            println("  Deleted old checkpoint: $(info.filename)")
        catch e
            @warn "Failed to delete checkpoint: $(info.filename)" exception=e
        end
    end
    
    # Update checkpoint list
    manager.checkpoints = to_keep
end

"""
    delete_checkpoint(filepath::String)

Delete a specific checkpoint file.
"""
function delete_checkpoint(filepath::String)
    if isfile(filepath)
        rm(filepath)
        return true
    end
    return false
end

# Serialization helper functions

function serialize_cfr_state(state::CFR.CFRState)
    return Dict(
        "storage" => serialize_infoset_storage(CFR.get_infoset_storage(state)),
        "config" => state.config,
        "iteration" => state.iteration,
        "total_iterations" => state.total_iterations,
        "exploitability" => state.exploitability,
        "convergence_history" => state.convergence_history,
        "training_start_time" => state.training_start_time,
        "stopping_reason" => state.stopping_reason
    )
end

function deserialize_cfr_state(data::Dict, tree::Union{Tree.GameTree, Nothing})
    # Create new CFR state
    config = data["config"]
    state = CFR.CFRState(tree, config)
    
    # Restore storage
    deserialize_infoset_storage!(CFR.get_infoset_storage(state), data["storage"])
    
    # Restore other fields
    state.iteration = data["iteration"]
    state.total_iterations = data["total_iterations"]
    state.exploitability = data["exploitability"]
    state.convergence_history = data["convergence_history"]
    state.training_start_time = data["training_start_time"]
    state.stopping_reason = data["stopping_reason"]
    
    return state
end

function serialize_infoset_storage(storage::InfoSetManager.InfoSetStorage)
    infosets_data = Dict{String, Any}()
    for (id, infoset) in storage.infosets
        infosets_data[id] = Dict(
            "id" => infoset.id,
            "num_actions" => infoset.num_actions,
            "regrets" => infoset.regrets,
            "strategy_sum" => infoset.strategy_sum,
            "iteration" => infoset.iteration
        )
    end
    return infosets_data
end

function deserialize_infoset_storage!(storage::InfoSetManager.InfoSetStorage, data::Dict)
    empty!(storage.infosets)
    for (id, infoset_data) in data
        infoset = InfoSetManager.CFRInfoSet(
            infoset_data["id"],
            infoset_data["num_actions"],
            infoset_data["regrets"],
            infoset_data["strategy_sum"],
            infoset_data["iteration"]
        )
        storage.infosets[id] = infoset
    end
end

function extract_strategies(state::CFR.CFRState)
    strategies = Dict{String, Vector{Float64}}()
    storage = CFR.get_infoset_storage(state)
    
    for (id, infoset) in storage.infosets
        if sum(infoset.strategy_sum) > 0
            strategy = infoset.strategy_sum / sum(infoset.strategy_sum)
        else
            strategy = fill(1.0 / infoset.num_actions, infoset.num_actions)
        end
        strategies[id] = strategy
    end
    
    return strategies
end

function serialize_tree(tree::Tree.GameTree)
    # For now, we don't serialize the full tree structure
    # as it can be rebuilt. Just save essential info.
    return Dict(
        "num_nodes" => length(tree.nodes),
        "root_id" => tree.root.id
    )
end

function serialize_metrics(metrics)
    # Simplified metrics serialization
    return Dict(
        "iterations_completed" => metrics.iterations_completed,
        "total_time_seconds" => metrics.total_time_seconds
    )
end

function deserialize_metrics(data::Dict)
    # Create basic metrics object
    metrics = CFRMetrics.Metrics()
    metrics.iterations_completed = get(data, "iterations_completed", 0)
    metrics.total_time_seconds = get(data, "total_time_seconds", 0.0)
    return metrics
end

function serialize_progress(progress)
    return Dict(
        "current_iteration" => progress.current_iteration,
        "total_iterations" => progress.total_iterations
    )
end

function deserialize_progress(data::Dict)
    # Create basic progress object
    # This is simplified - in practice you'd restore more state
    return data
end

# Compression helpers

function save_compressed(filepath::String, data)
    # For now, use Julia's built-in serialization
    # In production, you might use a compression library
    open(filepath, "w") do io
        serialize(io, data)
    end
end

function load_compressed(filepath::String)
    return open(deserialize, filepath)
end

# Utility functions

function format_file_size(bytes::Int64)
    if bytes < 1024
        return @sprintf("%d B", bytes)
    elseif bytes < 1024^2
        return @sprintf("%.1f KB", bytes / 1024)
    elseif bytes < 1024^3
        return @sprintf("%.1f MB", bytes / 1024^2)
    else
        return @sprintf("%.1f GB", bytes / 1024^3)
    end
end

"""
    print_checkpoint_list(checkpoints::Vector{CheckpointInfo}; io::IO = stdout)

Print a formatted list of checkpoints.
"""
function print_checkpoint_list(checkpoints::Vector{CheckpointInfo}; io::IO = stdout)
    if isempty(checkpoints)
        println(io, "No checkpoints found.")
        return
    end
    
    println(io, "\nAvailable Checkpoints:")
    println(io, "="^80)
    println(io, @sprintf("%-30s %10s %12s %10s %10s", 
                        "Filename", "Iteration", "Exploitability", "Size", "Date"))
    println(io, "-"^80)
    
    for info in checkpoints
        date_str = Dates.format(info.timestamp, "yyyy-mm-dd")
        exploit_str = info.exploitability < Inf ? @sprintf("%.6f", info.exploitability) : "N/A"
        best_marker = info.is_best ? " *" : ""
        
        println(io, @sprintf("%-30s %10d %12s %10s %10s%s",
                            info.filename[1:min(30, length(info.filename))],
                            info.iteration,
                            exploit_str,
                            format_file_size(info.file_size),
                            date_str,
                            best_marker))
    end
    
    println(io, "="^80)
    println(io, "* = Best checkpoint (lowest exploitability)")
end

end # module Checkpoint
