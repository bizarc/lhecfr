"""
    MemoryManager

Module for managing memory usage in large game trees, including pruning strategies,
compression techniques, and memory monitoring.
"""
module MemoryManager

using Printf
using ..Tree
using ..Tree.TreeNode
using ..Tree.TreeTraversal
using ..Tree.InfoSetManager
using ..CFR
using ..CFRTraversal

# Export main functionality
export MemoryConfig, MemoryStats, MemoryMonitor
export PruningStrategy, DepthPruning, ImportancePruning, FrequencyPruning, AdaptivePruning
export create_memory_monitor, monitor_memory!, get_memory_stats
export prune_tree!, estimate_memory_usage, optimize_memory!
export set_memory_limit!, check_memory_pressure

"""
    MemoryConfig

Configuration for memory management strategies.
"""
struct MemoryConfig
    # Memory limits
    max_memory_gb::Float64
    warning_threshold::Float64  # Percentage of max_memory to trigger warning
    critical_threshold::Float64  # Percentage of max_memory to trigger pruning
    
    # Pruning settings
    enable_pruning::Bool
    pruning_strategy::Symbol  # :depth, :importance, :frequency, :adaptive
    pruning_aggressiveness::Float64  # 0.0 to 1.0
    min_nodes_to_keep::Int
    
    # Monitoring settings
    monitor_interval::Int  # Check memory every N iterations
    log_memory_stats::Bool
    auto_gc::Bool  # Automatically trigger garbage collection
    
    function MemoryConfig(;
        max_memory_gb::Float64 = 8.0,
        warning_threshold::Float64 = 0.75,
        critical_threshold::Float64 = 0.9,
        enable_pruning::Bool = true,
        pruning_strategy::Symbol = :adaptive,
        pruning_aggressiveness::Float64 = 0.3,
        min_nodes_to_keep::Int = 10000,
        monitor_interval::Int = 100,
        log_memory_stats::Bool = true,
        auto_gc::Bool = true
    )
        @assert max_memory_gb > 0 "Max memory must be positive"
        @assert 0 <= warning_threshold <= 1 "Warning threshold must be between 0 and 1"
        @assert 0 <= critical_threshold <= 1 "Critical threshold must be between 0 and 1"
        @assert warning_threshold < critical_threshold "Warning threshold must be less than critical"
        @assert 0 <= pruning_aggressiveness <= 1 "Pruning aggressiveness must be between 0 and 1"
        @assert min_nodes_to_keep > 0 "Minimum nodes to keep must be positive"
        
        new(
            max_memory_gb, warning_threshold, critical_threshold,
            enable_pruning, pruning_strategy, pruning_aggressiveness, min_nodes_to_keep,
            monitor_interval, log_memory_stats, auto_gc
        )
    end
end

"""
    MemoryStats

Statistics about memory usage.
"""
mutable struct MemoryStats
    total_memory_mb::Float64
    used_memory_mb::Float64
    tree_memory_mb::Float64
    infoset_memory_mb::Float64
    
    node_count::Int
    infoset_count::Int
    pruned_nodes::Int
    
    last_check_time::Float64
    peak_memory_mb::Float64
    
    gc_count::Int
    gc_time::Float64
end

"""
    MemoryMonitor

Monitors and manages memory usage during solving.
"""
mutable struct MemoryMonitor
    config::MemoryConfig
    stats::MemoryStats
    memory_history::Vector{Float64}
    pruning_history::Vector{Int}
    
    warning_issued::Bool
    critical_issued::Bool
    auto_pruned::Bool
end

"""
    PruningStrategy

Abstract type for tree pruning strategies.
"""
abstract type PruningStrategy end

"""
    DepthPruning <: PruningStrategy

Prune nodes beyond a certain depth.
"""
struct DepthPruning <: PruningStrategy
    max_depth::Int
end

"""
    ImportancePruning <: PruningStrategy

Prune nodes with low importance scores.
"""
struct ImportancePruning <: PruningStrategy
    importance_threshold::Float64
end

"""
    FrequencyPruning <: PruningStrategy

Prune rarely visited nodes based on traversal frequency.
"""
struct FrequencyPruning <: PruningStrategy
    min_visit_count::Int
    visit_counts::Dict{Int, Int}  # Node ID -> visit count
end

"""
    AdaptivePruning <: PruningStrategy

Adaptively prune to maintain a target tree size.
"""
struct AdaptivePruning <: PruningStrategy
    target_node_count::Int
    preserve_ratio::Float64
end

# Memory monitoring functions

"""
    create_memory_monitor(config::MemoryConfig)

Create a new memory monitor with the given configuration.
"""
function create_memory_monitor(config::MemoryConfig = MemoryConfig())
    stats = MemoryStats(
        0.0, 0.0, 0.0, 0.0,
        0, 0, 0,
        time(), 0.0,
        0, 0.0
    )
    
    return MemoryMonitor(
        config,
        stats,
        Float64[],
        Int[],
        false, false, false
    )
end

"""
    monitor_memory!(monitor::MemoryMonitor, tree::Tree.GameTree, state::CFR.CFRState)

Monitor current memory usage and trigger actions if needed.
"""
function monitor_memory!(monitor::MemoryMonitor, tree::Tree.GameTree, state::CFR.CFRState)
    stats = monitor.stats
    config = monitor.config
    
    # Update memory statistics
    update_memory_stats!(stats, tree, state)
    
    # Check memory pressure
    memory_pressure = stats.used_memory_mb / (config.max_memory_gb * 1024)
    
    # Log memory stats if enabled
    if config.log_memory_stats
        log_memory_status(stats, memory_pressure)
    end
    
    # Handle warning threshold
    if memory_pressure >= config.warning_threshold && !monitor.warning_issued
        println("⚠️  Memory Warning: Using $(round(memory_pressure * 100, digits=1))% of max memory")
        monitor.warning_issued = true
    end
    
    # Handle critical threshold
    if memory_pressure >= config.critical_threshold
        if !monitor.critical_issued
            println("🚨 Memory Critical: Using $(round(memory_pressure * 100, digits=1))% of max memory")
            monitor.critical_issued = true
        end
        
        # Trigger automatic pruning if enabled
        if config.enable_pruning && !monitor.auto_pruned
            println("   Triggering automatic tree pruning...")
            strategy = create_pruning_strategy(config.pruning_strategy, tree, config)
            nodes_pruned = prune_tree!(tree, strategy, config.pruning_aggressiveness)
            monitor.auto_pruned = true
            push!(monitor.pruning_history, nodes_pruned)
            println("   Pruned $nodes_pruned nodes")
        end
        
        # Force garbage collection if enabled
        if config.auto_gc
            GC.gc()
        end
    end
    
    # Update history
    push!(monitor.memory_history, stats.used_memory_mb)
    
    return stats
end

"""
    update_memory_stats!(stats::MemoryStats, tree::Tree.GameTree, state::CFR.CFRState)

Update memory statistics with current usage.
"""
function update_memory_stats!(stats::MemoryStats, tree::Tree.GameTree, state::CFR.CFRState)
    # Get Julia memory stats
    stats.total_memory_mb = Sys.total_memory() / 1024^2
    
    # Estimate used memory
    gc_stats = Base.gc_num()
    stats.used_memory_mb = gc_stats.allocd / 1024^2
    
    # Count nodes and infosets
    stats.node_count = length(tree.nodes)
    storage = CFR.get_infoset_storage(state)
    stats.infoset_count = length(storage.infosets)
    
    # Estimate tree and infoset memory
    stats.tree_memory_mb = estimate_tree_memory(tree)
    stats.infoset_memory_mb = estimate_infoset_memory(storage)
    
    # Update peak memory
    stats.peak_memory_mb = max(stats.peak_memory_mb, stats.used_memory_mb)
    
    # Update GC stats
    stats.gc_count = gc_stats.full_sweep
    stats.gc_time = gc_stats.total_time / 1e9  # Convert to seconds
    
    stats.last_check_time = time()
end

"""
    estimate_tree_memory(tree::Tree.GameTree)

Estimate memory usage of the game tree in MB.
"""
function estimate_tree_memory(tree::Tree.GameTree)
    # Estimate bytes per node
    # Node struct has: id, parent, children vector, player, pot, street, actions, etc.
    bytes_per_node = 200  # Conservative estimate
    
    # Add memory for children vectors
    total_children = 0
    for node in tree.nodes
        total_children += length(node.children)
    end
    bytes_for_children = total_children * 8  # 8 bytes per Int reference
    
    node_count = length(tree.nodes)
    total_bytes = node_count * bytes_per_node + bytes_for_children
    
    return total_bytes / 1024^2  # Convert to MB
end

"""
    estimate_infoset_memory(storage::InfoSetManager.InfoSetStorage)

Estimate memory usage of information sets in MB.
"""
function estimate_infoset_memory(storage::InfoSetManager.InfoSetStorage)
    # Estimate bytes per infoset
    bytes_per_infoset = 100  # Base struct size
    bytes_per_action = 16  # Two Float64s for regret and strategy
    
    total_bytes = 0
    for (_, infoset) in storage.infosets
        total_bytes += bytes_per_infoset + infoset.num_actions * bytes_per_action * 2
    end
    
    return total_bytes / 1024^2  # Convert to MB
end

# Tree pruning functions

"""
    create_pruning_strategy(strategy::Symbol, tree::Tree.GameTree, config::MemoryConfig)

Create a pruning strategy based on the configuration.
"""
function create_pruning_strategy(strategy::Symbol, tree::Tree.GameTree, config::MemoryConfig)
    if strategy == :depth
        max_depth = round(Int, 10 * (1 - config.pruning_aggressiveness))
        return DepthPruning(max_depth)
    elseif strategy == :importance
        threshold = config.pruning_aggressiveness
        return ImportancePruning(threshold)
    elseif strategy == :frequency
        min_visits = round(Int, 100 * (1 - config.pruning_aggressiveness))
        return FrequencyPruning(min_visits, Dict{Int, Int}())
    elseif strategy == :adaptive
        target_count = max(config.min_nodes_to_keep, 
                          round(Int, length(tree.nodes) * (1 - config.pruning_aggressiveness)))
        return AdaptivePruning(target_count, 1 - config.pruning_aggressiveness)
    else
        error("Unknown pruning strategy: $strategy")
    end
end

"""
    prune_tree!(tree::Tree.GameTree, strategy::PruningStrategy, aggressiveness::Float64 = 0.3)

Prune the game tree using the specified strategy.
"""
function prune_tree!(tree::Tree.GameTree, strategy::DepthPruning, aggressiveness::Float64 = 0.3)
    nodes_pruned = 0
    nodes_to_keep = TreeNode.GameNode[]
    
    for node in tree.nodes
        if TreeNode.get_node_depth(node) <= strategy.max_depth
            push!(nodes_to_keep, node)
        else
            nodes_pruned += 1
        end
    end
    
    # Replace nodes with filtered list
    tree.nodes = nodes_to_keep
    
    # Update counts
    tree.num_nodes = length(tree.nodes)
    
    return nodes_pruned
end

function prune_tree!(tree::Tree.GameTree, strategy::ImportancePruning, aggressiveness::Float64 = 0.3)
    nodes_pruned = 0
    nodes_to_keep = TreeNode.GameNode[]
    
    # Calculate importance scores
    importance_scores = calculate_importance_scores(tree)
    
    # Keep nodes with high enough importance
    for node in tree.nodes
        score = get(importance_scores, node.id, 0.0)
        if score >= strategy.importance_threshold || node.id == 1  # Always keep root
            push!(nodes_to_keep, node)
        else
            nodes_pruned += 1
        end
    end
    
    # Replace nodes with filtered list
    tree.nodes = nodes_to_keep
    tree.num_nodes = length(tree.nodes)
    
    return nodes_pruned
end

function prune_tree!(tree::Tree.GameTree, strategy::FrequencyPruning, aggressiveness::Float64 = 0.3)
    nodes_pruned = 0
    nodes_to_keep = TreeNode.GameNode[]
    
    # Keep frequently visited nodes
    for node in tree.nodes
        visit_count = get(strategy.visit_counts, node.id, 0)
        if visit_count >= strategy.min_visit_count || node.id == 1  # Always keep root
            push!(nodes_to_keep, node)
        else
            nodes_pruned += 1
        end
    end
    
    # Replace nodes with filtered list
    tree.nodes = nodes_to_keep
    tree.num_nodes = length(tree.nodes)
    
    return nodes_pruned
end

function prune_tree!(tree::Tree.GameTree, strategy::AdaptivePruning, aggressiveness::Float64 = 0.3)
    current_nodes = length(tree.nodes)
    nodes_to_prune = max(0, current_nodes - strategy.target_node_count)
    
    if nodes_to_prune <= 0
        return 0
    end
    
    # Use importance-based pruning to reach target
    importance_scores = calculate_importance_scores(tree)
    
    # Sort nodes by importance
    node_scores = [(node, get(importance_scores, node.id, 0.0)) for node in tree.nodes]
    sort!(node_scores, by = x -> x[2])  # Sort by score (ascending)
    
    # Separate root from other nodes
    root_node = nothing
    other_nodes = TreeNode.GameNode[]
    nodes_pruned = 0
    
    for (i, (node, score)) in enumerate(node_scores)
        if node.id == 1
            root_node = node  # Always keep root
        elseif i > nodes_to_prune
            push!(other_nodes, node)  # Keep high-importance nodes
        else
            nodes_pruned += 1  # Prune low-importance nodes
        end
    end
    
    # Rebuild nodes list with root first
    nodes_to_keep = TreeNode.GameNode[]
    if root_node !== nothing
        push!(nodes_to_keep, root_node)
    end
    append!(nodes_to_keep, other_nodes)
    
    # Replace nodes with filtered list
    tree.nodes = nodes_to_keep
    tree.num_nodes = length(tree.nodes)
    
    return nodes_pruned
end

"""
    calculate_importance_scores(tree::Tree.GameTree)

Calculate importance scores for all nodes in the tree.
"""
function calculate_importance_scores(tree::Tree.GameTree)
    scores = Dict{Int, Float64}()
    
    for node in tree.nodes
        # Simple importance based on depth, children, and terminal status
        depth = TreeNode.get_node_depth(node)
        depth_factor = 1.0 / (1.0 + depth)
        children_factor = length(node.children) > 0 ? 1.0 : 0.5
        terminal_factor = TreeNode.is_terminal_node(node) ? 0.3 : 1.0
        
        # Prefer keeping nodes closer to root and with more children
        scores[node.id] = depth_factor * children_factor * terminal_factor
    end
    
    return scores
end

# Memory optimization functions

"""
    optimize_memory!(tree::Tree.GameTree, state::CFR.CFRState, monitor::MemoryMonitor)

Optimize memory usage using various techniques.
"""
function optimize_memory!(tree::Tree.GameTree, state::CFR.CFRState, monitor::MemoryMonitor)
    optimizations_applied = String[]
    
    # Update stats first to get current counts
    update_memory_stats!(monitor.stats, tree, state)
    initial_memory = monitor.stats.used_memory_mb
    
    # 1. Remove orphaned nodes
    orphaned = remove_orphaned_nodes!(tree)
    if orphaned > 0
        push!(optimizations_applied, "Removed $orphaned orphaned nodes")
    end
    
    # 2. Prune deep subtrees if needed
    if monitor.config.enable_pruning && monitor.stats.node_count > monitor.config.min_nodes_to_keep * 2
        strategy = create_pruning_strategy(monitor.config.pruning_strategy, tree, monitor.config)
        pruned = prune_tree!(tree, strategy, monitor.config.pruning_aggressiveness * 0.5)  # Less aggressive
        if pruned > 0
            push!(optimizations_applied, "Pruned $pruned low-importance nodes")
        end
    end
    
    # 3. Clear unused infosets
    cleared = clear_unused_infosets!(state, tree)
    if cleared > 0
        push!(optimizations_applied, "Cleared $cleared unused infosets")
    end
    
    # 4. Force garbage collection
    if monitor.config.auto_gc
        GC.gc()
        push!(optimizations_applied, "Triggered garbage collection")
    end
    
    # Update stats
    update_memory_stats!(monitor.stats, tree, state)
    memory_saved = initial_memory - monitor.stats.used_memory_mb
    
    if memory_saved > 0
        println("Memory optimized: saved $(round(memory_saved, digits=1)) MB")
    end
    
    return optimizations_applied
end

"""
    remove_orphaned_nodes!(tree::Tree.GameTree)

Remove nodes that are not connected to the root.
"""
function remove_orphaned_nodes!(tree::Tree.GameTree)
    # Find all reachable nodes from root
    reachable = Set{Int}()
    
    # Start from root
    if !isempty(tree.nodes) && tree.nodes[1].id == 1
        queue = Int[1]
        
        # Build set of all node IDs for quick lookup
        node_id_to_index = Dict{Int, Int}()
        for (i, node) in enumerate(tree.nodes)
            node_id_to_index[node.id] = i
        end
        
        while !isempty(queue)
            node_id = popfirst!(queue)
            if node_id in reachable
                continue
            end
            push!(reachable, node_id)
            
            # Find node and add its children IDs
            if haskey(node_id_to_index, node_id)
                node = tree.nodes[node_id_to_index[node_id]]
                # Add children IDs to queue
                for child in node.children
                    push!(queue, child.id)
                end
            end
        end
    end
    
    # Keep only reachable nodes
    nodes_to_keep = TreeNode.GameNode[]
    orphaned = 0
    
    for node in tree.nodes
        if node.id in reachable
            push!(nodes_to_keep, node)
        else
            orphaned += 1
        end
    end
    
    tree.nodes = nodes_to_keep
    tree.num_nodes = length(tree.nodes)
    
    return orphaned
end

"""
    clear_unused_infosets!(state::CFR.CFRState, tree::Tree.GameTree)

Clear information sets that are no longer referenced by any tree node.
"""
function clear_unused_infosets!(state::CFR.CFRState, tree::Tree.GameTree)
    storage = CFR.get_infoset_storage(state)
    
    # For now, we can't easily correlate integer IDs with string-based infoset keys
    # So we'll just count how many infosets we have
    # In a real implementation, we'd need to track the mapping between node IDs and infoset strings
    
    # This is a simplified version that just returns 0
    # A proper implementation would need to maintain a mapping between nodes and their infoset strings
    cleared = 0
    
    return cleared
end

# Utility functions

"""
    get_memory_stats(monitor::MemoryMonitor)

Get current memory statistics.
"""
function get_memory_stats(monitor::MemoryMonitor)
    return monitor.stats
end

"""
    estimate_memory_usage(tree::Tree.GameTree, state::CFR.CFRState)

Estimate total memory usage for the tree and CFR state.
"""
function estimate_memory_usage(tree::Tree.GameTree, state::CFR.CFRState)
    tree_memory = estimate_tree_memory(tree)
    storage = CFR.get_infoset_storage(state)
    infoset_memory = estimate_infoset_memory(storage)
    
    return tree_memory + infoset_memory
end

"""
    set_memory_limit!(monitor::MemoryMonitor, limit_gb::Float64)

Set a new memory limit.
"""
function set_memory_limit!(monitor::MemoryMonitor, limit_gb::Float64)
    @assert limit_gb > 0 "Memory limit must be positive"
    monitor.config = MemoryConfig(
        max_memory_gb = limit_gb,
        warning_threshold = monitor.config.warning_threshold,
        critical_threshold = monitor.config.critical_threshold,
        enable_pruning = monitor.config.enable_pruning,
        pruning_strategy = monitor.config.pruning_strategy,
        pruning_aggressiveness = monitor.config.pruning_aggressiveness,
        min_nodes_to_keep = monitor.config.min_nodes_to_keep,
        monitor_interval = monitor.config.monitor_interval,
        log_memory_stats = monitor.config.log_memory_stats,
        auto_gc = monitor.config.auto_gc
    )
end

"""
    check_memory_pressure(monitor::MemoryMonitor)

Check current memory pressure level.
"""
function check_memory_pressure(monitor::MemoryMonitor)
    pressure = monitor.stats.used_memory_mb / (monitor.config.max_memory_gb * 1024)
    
    if pressure >= monitor.config.critical_threshold
        return :critical
    elseif pressure >= monitor.config.warning_threshold
        return :warning
    else
        return :normal
    end
end

"""
    log_memory_status(stats::MemoryStats, pressure::Float64)

Log current memory status.
"""
function log_memory_status(stats::MemoryStats, pressure::Float64)
    @printf("Memory: %.1f MB used (%.1f%%) | Tree: %.1f MB (%d nodes) | InfoSets: %d | GC: %d\n",
            stats.used_memory_mb,
            pressure * 100,
            stats.tree_memory_mb,
            stats.node_count,
            stats.infoset_count,
            stats.gc_count)
end

end # module MemoryManager