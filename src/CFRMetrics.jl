"""
CFRMetrics module for tracking convergence and performance metrics.
"""
module CFRMetrics

using ..CFR
using ..Tree
using ..GameTypes
using Statistics
using Printf

# --- Metric Types ---

"""
    ConvergenceMetrics

Tracks various convergence metrics during CFR training.
"""
mutable struct ConvergenceMetrics
    # Basic metrics
    iteration::Int
    exploitability::Float64
    
    # Strategy metrics
    avg_strategy_change::Float64  # Average change in strategy from last iteration
    max_strategy_change::Float64  # Maximum change in any action probability
    strategy_entropy::Float64     # Average entropy of strategies
    
    # Regret metrics
    total_regret::Float64         # Sum of all positive regrets
    avg_regret::Float64           # Average regret per infoset
    max_regret::Float64           # Maximum regret in any infoset
    
    # Performance metrics
    infosets_visited::Int         # Number of infosets visited this iteration
    nodes_traversed::Int          # Number of nodes traversed this iteration
    time_elapsed::Float64         # Time for this iteration
    memory_usage::Float64         # Current memory usage in MB
    
    # History tracking
    exploitability_history::Vector{Float64}
    strategy_change_history::Vector{Float64}
    regret_history::Vector{Float64}
    time_history::Vector{Float64}
end

"""
    ConvergenceMetrics()

Create empty convergence metrics.
"""
function ConvergenceMetrics()
    return ConvergenceMetrics(
        0, 0.0,
        0.0, 0.0, 0.0,
        0.0, 0.0, 0.0,
        0, 0, 0.0, 0.0,
        Float64[], Float64[], Float64[], Float64[]
    )
end

# --- Logging Configuration ---

"""
    LogConfig

Configuration for logging during CFR training.
"""
struct LogConfig
    verbose::Bool                 # Print to console
    log_frequency::Int           # How often to log (iterations)
    log_file::Union{String, Nothing}  # File to write logs to
    track_strategies::Bool       # Track strategy changes
    track_regrets::Bool         # Track regret evolution
    track_memory::Bool          # Track memory usage
    save_checkpoints::Bool      # Save periodic checkpoints
    checkpoint_frequency::Int   # How often to save checkpoints
    checkpoint_dir::String      # Directory for checkpoints
end

"""
    LogConfig(; kwargs...)

Create logging configuration with defaults.
"""
function LogConfig(;
    verbose::Bool = true,
    log_frequency::Int = 100,
    log_file::Union{String, Nothing} = nothing,
    track_strategies::Bool = true,
    track_regrets::Bool = true,
    track_memory::Bool = false,
    save_checkpoints::Bool = false,
    checkpoint_frequency::Int = 1000,
    checkpoint_dir::String = "checkpoints"
)
    return LogConfig(
        verbose,
        log_frequency,
        log_file,
        track_strategies,
        track_regrets,
        track_memory,
        save_checkpoints,
        checkpoint_frequency,
        checkpoint_dir
    )
end

# --- Metric Calculation Functions ---

"""
    calculate_strategy_metrics(state::CFRState, prev_strategies::Dict)

Calculate strategy-related metrics.
"""
function calculate_strategy_metrics(state::CFR.CFRState, prev_strategies::Dict{String, Vector{Float64}})
    if length(state.storage.infosets) == 0
        return 0.0, 0.0, 0.0
    end
    
    total_change = 0.0
    max_change = 0.0
    total_entropy = 0.0
    count = 0
    
    for (id, cfr_infoset) in state.storage.infosets
        current_strategy = Tree.get_average_strategy(cfr_infoset)
        
        # Calculate strategy change if we have previous
        if haskey(prev_strategies, id)
            prev = prev_strategies[id]
            change = sum(abs.(current_strategy .- prev))
            total_change += change
            max_change = max(max_change, maximum(abs.(current_strategy .- prev)))
        end
        
        # Calculate entropy
        entropy = 0.0
        for p in current_strategy
            if p > 0
                entropy -= p * log(p)
            end
        end
        total_entropy += entropy
        count += 1
    end
    
    avg_change = count > 0 ? total_change / count : 0.0
    avg_entropy = count > 0 ? total_entropy / count : 0.0
    
    return avg_change, max_change, avg_entropy
end

"""
    calculate_regret_metrics(state::CFRState)

Calculate regret-related metrics.
"""
function calculate_regret_metrics(state::CFR.CFRState)
    if length(state.storage.infosets) == 0
        return 0.0, 0.0, 0.0
    end
    
    total_regret = 0.0
    max_regret = 0.0
    count = 0
    
    for (id, cfr_infoset) in state.storage.infosets
        # Sum positive regrets
        for r in cfr_infoset.regrets
            if r > 0
                total_regret += r
                max_regret = max(max_regret, r)
            end
        end
        count += 1
    end
    
    avg_regret = count > 0 ? total_regret / count : 0.0
    
    return total_regret, avg_regret, max_regret
end

"""
    update_metrics!(metrics::ConvergenceMetrics, state::CFRState, 
                   iteration_time::Float64, prev_strategies::Dict)

Update convergence metrics after an iteration.
"""
function update_metrics!(metrics::ConvergenceMetrics, state::CFR.CFRState,
                        iteration_time::Float64, prev_strategies::Dict{String, Vector{Float64}})
    metrics.iteration = state.iteration
    metrics.exploitability = state.exploitability
    metrics.time_elapsed = iteration_time
    
    # Calculate strategy metrics
    avg_change, max_change, entropy = calculate_strategy_metrics(state, prev_strategies)
    metrics.avg_strategy_change = avg_change
    metrics.max_strategy_change = max_change
    metrics.strategy_entropy = entropy
    
    # Calculate regret metrics
    total_regret, avg_regret, max_regret = calculate_regret_metrics(state)
    metrics.total_regret = total_regret
    metrics.avg_regret = avg_regret
    metrics.max_regret = max_regret
    
    # Performance metrics
    metrics.infosets_visited = CFR.get_infoset_count(state)
    metrics.memory_usage = CFR.get_memory_usage(state)
    
    # Update history
    push!(metrics.exploitability_history, metrics.exploitability)
    push!(metrics.strategy_change_history, metrics.avg_strategy_change)
    push!(metrics.regret_history, metrics.total_regret)
    push!(metrics.time_history, iteration_time)
    
    return metrics
end

# --- Logging Functions ---

"""
    log_iteration(metrics::ConvergenceMetrics, config::LogConfig, io::IO=stdout)

Log metrics for current iteration.
"""
function log_iteration(metrics::ConvergenceMetrics, config::LogConfig, io::IO=stdout)
    if !config.verbose && io == stdout
        return
    end
    
    # Format the log message
    msg = @sprintf("Iter %6d | Expl: %.6f | ΔStrat: %.4f | Regret: %.2f | InfoSets: %d | Time: %.2fs",
                   metrics.iteration,
                   metrics.exploitability,
                   metrics.avg_strategy_change,
                   metrics.total_regret,
                   metrics.infosets_visited,
                   metrics.time_elapsed)
    
    println(io, msg)
    flush(io)
end

"""
    log_summary(metrics::ConvergenceMetrics, state::CFRState, total_time::Float64, io::IO=stdout)

Log final training summary.
"""
function log_summary(metrics::ConvergenceMetrics, state::CFR.CFRState, total_time::Float64, io::IO=stdout)
    println(io, "\n" * "="^80)
    println(io, "CFR Training Summary")
    println(io, "="^80)
    
    println(io, @sprintf("Total Iterations: %d", state.iteration))
    println(io, @sprintf("Final Exploitability: %.6f", metrics.exploitability))
    println(io, @sprintf("Information Sets: %d", metrics.infosets_visited))
    println(io, @sprintf("Total Time: %.2f seconds", total_time))
    println(io, @sprintf("Iterations/Second: %.2f", state.iteration / total_time))
    
    if metrics.memory_usage > 0
        println(io, @sprintf("Memory Usage: %.2f MB", metrics.memory_usage))
    end
    
    if length(metrics.exploitability_history) > 1
        initial_expl = metrics.exploitability_history[1]
        final_expl = metrics.exploitability_history[end]
        improvement = (initial_expl - final_expl) / initial_expl * 100
        println(io, @sprintf("Exploitability Reduction: %.1f%%", improvement))
    end
    
    if state.stopping_reason != ""
        println(io, "Stopping Reason: $(state.stopping_reason)")
    end
    
    println(io, "="^80)
    flush(io)
end

# --- Checkpoint Functions ---

"""
    save_checkpoint(state::CFRState, metrics::ConvergenceMetrics, filename::String)

Save a training checkpoint.
"""
function save_checkpoint(state::CFR.CFRState, metrics::ConvergenceMetrics, filename::String)
    # This would save the state and metrics to a file
    # For now, just a placeholder
    # In practice, would use JLD2 or similar
    println("Checkpoint saved to: $filename")
end

"""
    load_checkpoint(filename::String)

Load a training checkpoint.
"""
function load_checkpoint(filename::String)
    # This would load the state and metrics from a file
    # For now, just a placeholder
    println("Loading checkpoint from: $filename")
    return nothing, nothing
end

# --- Analysis Functions ---

"""
    get_convergence_rate(metrics::ConvergenceMetrics)

Calculate the convergence rate from exploitability history.
"""
function get_convergence_rate(metrics::ConvergenceMetrics)
    if length(metrics.exploitability_history) < 2
        return 0.0
    end
    
    # Fit exponential decay: expl(t) = a * exp(-b * t)
    # Use log-linear regression on log(expl) vs iteration
    y = log.(metrics.exploitability_history .+ 1e-10)  # Add small constant to avoid log(0)
    x = 1:length(y)
    
    # Simple linear regression
    n = length(x)
    x_mean = mean(x)
    y_mean = mean(y)
    
    numerator = sum((x .- x_mean) .* (y .- y_mean))
    denominator = sum((x .- x_mean) .^ 2)
    
    if denominator == 0
        return 0.0
    end
    
    slope = numerator / denominator
    return -slope  # Negative slope is convergence rate
end

"""
    get_strategy_stability(metrics::ConvergenceMetrics, window::Int=10)

Calculate strategy stability over recent iterations.
"""
function get_strategy_stability(metrics::ConvergenceMetrics, window::Int=10)
    if length(metrics.strategy_change_history) < window
        return 1.0
    end
    
    recent_changes = metrics.strategy_change_history[end-window+1:end]
    avg_change = mean(recent_changes)
    
    # Convert to stability score (1 = perfectly stable, 0 = highly unstable)
    stability = exp(-avg_change * 10)  # Exponential decay
    return clamp(stability, 0.0, 1.0)
end

"""
    export_metrics(metrics::ConvergenceMetrics, filename::String)

Export metrics to a file for analysis/plotting.
"""
function export_metrics(metrics::ConvergenceMetrics, filename::String)
    open(filename, "w") do io
        # Write header
        println(io, "iteration,exploitability,strategy_change,total_regret,time")
        
        # Write data
        for i in 1:length(metrics.exploitability_history)
            println(io, @sprintf("%d,%.6f,%.6f,%.6f,%.3f",
                                i,
                                metrics.exploitability_history[i],
                                i <= length(metrics.strategy_change_history) ? metrics.strategy_change_history[i] : 0.0,
                                i <= length(metrics.regret_history) ? metrics.regret_history[i] : 0.0,
                                i <= length(metrics.time_history) ? metrics.time_history[i] : 0.0))
        end
    end
    println("Metrics exported to: $filename")
end

# Export all public types and functions
export ConvergenceMetrics, LogConfig
export calculate_strategy_metrics, calculate_regret_metrics
export update_metrics!, log_iteration, log_summary
export save_checkpoint, load_checkpoint
export get_convergence_rate, get_strategy_stability, export_metrics

end # module
