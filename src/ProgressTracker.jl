"""
    ProgressTracker

Module for tracking CFR solver progress and estimating time to completion.
Provides real-time progress updates, ETA calculations, and performance metrics.
"""
module ProgressTracker

using Printf
using Dates
using Statistics
using ..CFR
using ..CFRMetrics
using ..SolverConfig

# Export main functionality
export ProgressState, ProgressConfig, ETAEstimator
export initialize_progress!, update_progress!, print_progress
export estimate_time_remaining, format_duration, get_progress_stats

"""
    ProgressConfig

Configuration for progress tracking and display.
"""
struct ProgressConfig
    # Display settings
    show_progress_bar::Bool
    bar_width::Int
    update_frequency::Int
    show_eta::Bool
    show_rate::Bool
    show_memory::Bool
    
    # ETA estimation
    window_size::Int          # Number of iterations for moving average
    smoothing_factor::Float64 # Exponential smoothing factor
    
    # Performance tracking
    track_iteration_times::Bool
    track_convergence_rate::Bool
    
    function ProgressConfig(;
        show_progress_bar::Bool = true,
        bar_width::Int = 50,
        update_frequency::Int = 100,
        show_eta::Bool = true,
        show_rate::Bool = true,
        show_memory::Bool = true,
        window_size::Int = 100,
        smoothing_factor::Float64 = 0.9,
        track_iteration_times::Bool = true,
        track_convergence_rate::Bool = true
    )
        new(
            show_progress_bar, bar_width, update_frequency,
            show_eta, show_rate, show_memory,
            window_size, smoothing_factor,
            track_iteration_times, track_convergence_rate
        )
    end
end

"""
    ETAEstimator

Estimates time remaining based on iteration history.
"""
mutable struct ETAEstimator
    iteration_times::Vector{Float64}
    window_size::Int
    smoothing_factor::Float64
    smoothed_rate::Float64
    last_update::Float64
    
    function ETAEstimator(window_size::Int = 100, smoothing_factor::Float64 = 0.9)
        new(Float64[], window_size, smoothing_factor, 0.0, time())
    end
end

"""
    ProgressState

Tracks the current state of solver progress.
"""
mutable struct ProgressState
    # Basic progress
    current_iteration::Int
    total_iterations::Int
    start_time::Float64
    last_update_time::Float64
    
    # Performance metrics
    iterations_per_second::Float64
    average_iteration_time::Float64
    
    # Convergence tracking
    current_exploitability::Float64
    target_exploitability::Float64
    convergence_rate::Float64
    
    # Memory usage
    current_memory_mb::Float64
    peak_memory_mb::Float64
    
    # ETA estimation
    eta_estimator::ETAEstimator
    estimated_time_remaining::Float64
    estimated_completion_time::DateTime
    
    # Display state
    last_display_iteration::Int
    config::ProgressConfig
end

"""
    initialize_progress!(state::CFR.CFRState, config::ProgressConfig = ProgressConfig())

Initialize progress tracking for a CFR solver state.
"""
function initialize_progress!(state::CFR.CFRState, config::ProgressConfig = ProgressConfig())
    progress = ProgressState(
        0,                              # current_iteration
        state.config.max_iterations,   # total_iterations
        time(),                         # start_time
        time(),                         # last_update_time
        0.0,                           # iterations_per_second
        0.0,                           # average_iteration_time
        Inf,                           # current_exploitability
        state.config.target_exploitability, # target_exploitability
        0.0,                           # convergence_rate
        0.0,                           # current_memory_mb
        0.0,                           # peak_memory_mb
        ETAEstimator(config.window_size, config.smoothing_factor),
        Inf,                           # estimated_time_remaining
        now() + Hour(999),             # estimated_completion_time
        0,                             # last_display_iteration
        config                         # config
    )
    
    # Store progress state in CFR metrics
    if state.metrics !== nothing
        state.metrics.progress = progress
    end
    
    return progress
end

"""
    update_progress!(progress::ProgressState, iteration::Int, exploitability::Float64 = Inf)

Update progress state with new iteration data.
"""
function update_progress!(progress::ProgressState, iteration::Int, exploitability::Float64 = Inf)
    current_time = time()
    
    # Update basic progress
    progress.current_iteration = iteration
    
    # Calculate iteration time
    iteration_time = current_time - progress.last_update_time
    progress.last_update_time = current_time
    
    # Update ETA estimator
    update_eta!(progress.eta_estimator, iteration_time)
    
    # Calculate performance metrics
    elapsed = current_time - progress.start_time
    progress.iterations_per_second = iteration / elapsed
    progress.average_iteration_time = elapsed / iteration
    
    # Update convergence tracking
    if exploitability < Inf
        old_exploitability = progress.current_exploitability
        progress.current_exploitability = exploitability
        
        if old_exploitability < Inf && old_exploitability > 0
            # Calculate convergence rate (exponential decay rate)
            progress.convergence_rate = log(exploitability / old_exploitability)
        end
    end
    
    # Update memory usage
    update_memory_stats!(progress)
    
    # Estimate time remaining
    progress.estimated_time_remaining = estimate_time_remaining(
        progress.eta_estimator,
        progress.current_iteration,
        progress.total_iterations,
        progress.current_exploitability,
        progress.target_exploitability,
        progress.convergence_rate
    )
    
    # Calculate estimated completion time
    if progress.estimated_time_remaining < Inf
        progress.estimated_completion_time = now() + Second(round(Int, progress.estimated_time_remaining))
    end
    
    # Display progress if needed
    if should_display(progress, iteration)
        print_progress(progress)
        progress.last_display_iteration = iteration
    end
end

"""
    update_eta!(estimator::ETAEstimator, iteration_time::Float64)

Update the ETA estimator with a new iteration time.
"""
function update_eta!(estimator::ETAEstimator, iteration_time::Float64)
    # Add to window
    push!(estimator.iteration_times, iteration_time)
    
    # Maintain window size
    if length(estimator.iteration_times) > estimator.window_size
        popfirst!(estimator.iteration_times)
    end
    
    # Calculate moving average
    if !isempty(estimator.iteration_times)
        avg_time = mean(estimator.iteration_times)
        
        # Apply exponential smoothing
        if estimator.smoothed_rate == 0.0
            estimator.smoothed_rate = avg_time
        else
            α = estimator.smoothing_factor
            estimator.smoothed_rate = α * estimator.smoothed_rate + (1 - α) * avg_time
        end
    end
    
    estimator.last_update = time()
end

"""
    estimate_time_remaining(estimator::ETAEstimator, current::Int, total::Int,
                           current_exploit::Float64, target_exploit::Float64,
                           convergence_rate::Float64)

Estimate time remaining based on multiple factors.
"""
function estimate_time_remaining(estimator::ETAEstimator, current::Int, total::Int,
                                current_exploit::Float64, target_exploit::Float64,
                                convergence_rate::Float64)
    if current >= total
        return 0.0
    end
    
    # Method 1: Linear projection based on iterations
    remaining_iterations = total - current
    if estimator.smoothed_rate > 0
        eta_linear = remaining_iterations * estimator.smoothed_rate
    else
        eta_linear = Inf
    end
    
    # Method 2: Exponential projection based on convergence
    eta_convergence = Inf
    if current_exploit < Inf && target_exploit > 0 && convergence_rate < 0
        # Estimate iterations needed based on convergence rate
        iterations_needed = log(target_exploit / current_exploit) / convergence_rate
        if iterations_needed > 0 && estimator.smoothed_rate > 0
            eta_convergence = iterations_needed * estimator.smoothed_rate
        end
    end
    
    # Use the more conservative (smaller) estimate
    return min(eta_linear, eta_convergence)
end

"""
    update_memory_stats!(progress::ProgressState)

Update memory usage statistics.
"""
function update_memory_stats!(progress::ProgressState)
    # Get current memory usage (this is a simplified version)
    # In practice, you might want to use more sophisticated memory tracking
    gc_stats = Base.gc_num()
    memory_bytes = gc_stats.total_allocd
    progress.current_memory_mb = memory_bytes / (1024 * 1024)
    progress.peak_memory_mb = max(progress.peak_memory_mb, progress.current_memory_mb)
end

"""
    should_display(progress::ProgressState, iteration::Int)

Determine if progress should be displayed for this iteration.
"""
function should_display(progress::ProgressState, iteration::Int)
    if iteration == 1
        return true
    end
    
    if iteration == progress.total_iterations
        return true
    end
    
    if iteration - progress.last_display_iteration >= progress.config.update_frequency
        return true
    end
    
    return false
end

"""
    print_progress(progress::ProgressState; io::IO = stdout)

Print a formatted progress update.
"""
function print_progress(progress::ProgressState; io::IO = stdout)
    config = progress.config
    
    # Calculate percentage
    percentage = 100.0 * progress.current_iteration / progress.total_iterations
    
    # Build progress bar if enabled
    if config.show_progress_bar
        filled = round(Int, config.bar_width * percentage / 100)
        empty = config.bar_width - filled
        bar = "[" * "=" ^ filled * ">" * " " ^ empty * "]"
    else
        bar = ""
    end
    
    # Format the progress line
    line_parts = String[]
    
    # Basic progress
    push!(line_parts, @sprintf("Iter %d/%d (%.1f%%)", 
                               progress.current_iteration,
                               progress.total_iterations,
                               percentage))
    
    # Progress bar
    if config.show_progress_bar
        push!(line_parts, bar)
    end
    
    # Iteration rate
    if config.show_rate && progress.iterations_per_second > 0
        push!(line_parts, @sprintf("%.1f it/s", progress.iterations_per_second))
    end
    
    # Exploitability
    if progress.current_exploitability < Inf
        push!(line_parts, @sprintf("Exploit: %.4f", progress.current_exploitability))
    end
    
    # ETA
    if config.show_eta && progress.estimated_time_remaining < Inf
        eta_str = format_duration(progress.estimated_time_remaining)
        push!(line_parts, "ETA: " * eta_str)
        
        # Show completion time if reasonable
        if progress.estimated_time_remaining < 86400  # Less than 24 hours
            completion_str = Dates.format(progress.estimated_completion_time, "HH:MM:SS")
            push!(line_parts, "Complete: " * completion_str)
        end
    end
    
    # Memory usage
    if config.show_memory && progress.current_memory_mb > 0
        push!(line_parts, @sprintf("Mem: %.1f MB", progress.current_memory_mb))
    end
    
    # Print the line
    line = join(line_parts, " | ")
    print(io, "\r" * line * "  ")  # Extra spaces to clear previous line
    
    # Flush to ensure immediate display
    flush(io)
end

"""
    format_duration(seconds::Float64)

Format a duration in seconds as a human-readable string.
"""
function format_duration(seconds::Float64)
    if seconds < 60
        return @sprintf("%.0fs", seconds)
    elseif seconds < 3600
        minutes = floor(Int, seconds / 60)
        secs = round(Int, seconds % 60)
        return @sprintf("%dm %ds", minutes, secs)
    elseif seconds < 86400
        hours = floor(Int, seconds / 3600)
        minutes = floor(Int, (seconds % 3600) / 60)
        return @sprintf("%dh %dm", hours, minutes)
    else
        days = floor(Int, seconds / 86400)
        hours = floor(Int, (seconds % 86400) / 3600)
        return @sprintf("%dd %dh", days, hours)
    end
end

"""
    get_progress_stats(progress::ProgressState)

Get a dictionary of progress statistics.
"""
function get_progress_stats(progress::ProgressState)
    elapsed = progress.last_update_time - progress.start_time
    
    return Dict(
        "current_iteration" => progress.current_iteration,
        "total_iterations" => progress.total_iterations,
        "percentage_complete" => 100.0 * progress.current_iteration / progress.total_iterations,
        "elapsed_time" => elapsed,
        "iterations_per_second" => progress.iterations_per_second,
        "average_iteration_time" => progress.average_iteration_time,
        "current_exploitability" => progress.current_exploitability,
        "convergence_rate" => progress.convergence_rate,
        "estimated_time_remaining" => progress.estimated_time_remaining,
        "current_memory_mb" => progress.current_memory_mb,
        "peak_memory_mb" => progress.peak_memory_mb
    )
end

"""
    print_final_summary(progress::ProgressState; io::IO = stdout)

Print a final summary when solving is complete.
"""
function print_final_summary(progress::ProgressState; io::IO = stdout)
    println(io, "\n" * "="^60)
    println(io, "CFR Solver Complete!")
    println(io, "="^60)
    
    elapsed = progress.last_update_time - progress.start_time
    println(io, @sprintf("Total iterations: %d", progress.current_iteration))
    println(io, @sprintf("Total time: %s", format_duration(elapsed)))
    println(io, @sprintf("Average speed: %.2f iterations/second", progress.iterations_per_second))
    
    if progress.current_exploitability < Inf
        println(io, @sprintf("Final exploitability: %.6f", progress.current_exploitability))
        
        if progress.current_exploitability <= progress.target_exploitability
            println(io, "✓ Target exploitability reached!")
        else
            println(io, @sprintf("Target exploitability: %.6f (not reached)", 
                               progress.target_exploitability))
        end
    end
    
    println(io, @sprintf("Peak memory usage: %.1f MB", progress.peak_memory_mb))
    println(io, "="^60)
end

end # module ProgressTracker
