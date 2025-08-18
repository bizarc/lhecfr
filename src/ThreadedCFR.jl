"""
    ThreadedCFR

Module implementing parallel CFR traversal using multi-threading for improved performance.
"""
module ThreadedCFR

using ..GameTypes
using ..Tree
using ..Tree.TreeNode
using ..Tree.InfoSet
using ..Tree.InfoSetManager
using ..Tree.InfoSetCache
using ..Tree.TreeIndexing
using ..CFR
using ..CFRTraversal
using Base.Threads
using Random
using LinearAlgebra

# Export main functions
export ThreadConfig, ParallelCFRState
export parallel_train!, parallel_cfr_iteration!
export get_thread_stats, print_thread_performance

"""
    ThreadStats

Statistics for a single thread's performance.
"""
mutable struct ThreadStats
    nodes_processed::Int64
    infosets_updated::Int64
    time_computing::Float64
    time_waiting::Float64
    cache_hits::Int64
    cache_misses::Int64
    
    ThreadStats() = new(0, 0, 0.0, 0.0, 0, 0)
end

"""
    ThreadConfig

Configuration for multi-threaded CFR execution.
"""
struct ThreadConfig
    num_threads::Int              # Number of threads to use (0 = auto)
    chunk_size::Int               # Minimum nodes per thread chunk
    sync_frequency::Int           # How often to synchronize threads
    thread_safe_cache::Bool       # Enable thread-safe caching
    load_balancing::Symbol        # :static, :dynamic, :work_stealing
    
    function ThreadConfig(;
        num_threads::Int = 0,  # 0 = use all available
        chunk_size::Int = 100,
        sync_frequency::Int = 10,
        thread_safe_cache::Bool = true,
        load_balancing::Symbol = :dynamic
    )
        # Auto-detect thread count
        actual_threads = num_threads == 0 ? Threads.nthreads() : min(num_threads, Threads.nthreads())
        
        @assert load_balancing in [:static, :dynamic, :work_stealing] "Invalid load balancing strategy"
        @assert chunk_size > 0 "Chunk size must be positive"
        
        new(actual_threads, chunk_size, sync_frequency, thread_safe_cache, load_balancing)
    end
end

"""
    ParallelCFRState

Thread-safe CFR state for parallel execution.
"""
mutable struct ParallelCFRState
    base_state::CFR.CFRState      # Underlying CFR state
    thread_config::ThreadConfig    # Threading configuration
    thread_locks::Vector{ReentrantLock}  # Per-infoset locks for thread safety
    thread_stats::Vector{ThreadStats}    # Performance statistics per thread
    global_lock::ReentrantLock    # Global lock for state updates
end

"""
    ParallelCFRState(tree::GameTree, cfr_config::CFRConfig, thread_config::ThreadConfig)

Create a parallel CFR state with thread-safe components.
"""
function ParallelCFRState(tree::Tree.GameTree, cfr_config::CFR.CFRConfig = CFR.CFRConfig(), 
                         thread_config::ThreadConfig = ThreadConfig())
    # Create base state with thread-safe cache if requested
    cache_config = if thread_config.thread_safe_cache
        InfoSetCache.CacheConfig(
            max_size = 1000000,
            enable_statistics = true,
            thread_safe = true
        )
    else
        nothing
    end
    
    # Always use indexing for parallel execution
    base_state = if cache_config !== nothing
        # Create indexed storage with thread-safe cache
        indexed_storage = TreeIndexing.IndexedInfoSetStorage(tree, cache_config=cache_config)
        CFR.CFRState(
            InfoSetManager.InfoSetStorage(),
            indexed_storage,
            tree,
            cfr_config,
            0, 0, Inf, Float64[], 0.0, "", nothing
        )
    else
        CFR.CFRState(tree, cfr_config, true)
    end
    
    # Create per-infoset locks (simplified: use a pool of locks)
    num_locks = 1024  # Use a fixed pool to avoid too many locks
    thread_locks = [ReentrantLock() for _ in 1:num_locks]
    
    # Initialize thread stats
    thread_stats = [ThreadStats() for _ in 1:thread_config.num_threads]
    
    return ParallelCFRState(
        base_state,
        thread_config,
        thread_locks,
        thread_stats,
        ReentrantLock()
    )
end

"""
    get_infoset_lock(state::ParallelCFRState, infoset_id::String)

Get the lock for a specific information set (using hash-based lock pool).
"""
function get_infoset_lock(state::ParallelCFRState, infoset_id::String)
    lock_idx = (hash(infoset_id) % length(state.thread_locks)) + 1
    return state.thread_locks[lock_idx]
end

"""
    parallel_cfr_iteration!(state::ParallelCFRState, tree::GameTree)

Run one CFR iteration in parallel across multiple threads.
"""
function parallel_cfr_iteration!(state::ParallelCFRState, tree::Tree.GameTree)
    # Reset thread stats for this iteration
    for stats in state.thread_stats
        stats.nodes_processed = 0
        stats.infosets_updated = 0
    end
    
    # Increment iteration counter
    lock(state.global_lock) do
        state.base_state.iteration += 1
    end
    
    # Get all player nodes for parallel processing
    all_nodes = Tree.TreeIndexing.collect_nodes_preorder(tree.root)
    player_nodes = filter(n -> Tree.TreeNode.is_player_node(n), all_nodes)
    
    if state.thread_config.load_balancing == :static
        parallel_static_traversal!(state, tree, player_nodes)
    elseif state.thread_config.load_balancing == :dynamic
        parallel_dynamic_traversal!(state, tree, player_nodes)
    else  # :work_stealing
        parallel_work_stealing_traversal!(state, tree, player_nodes)
    end
end

"""
    parallel_static_traversal!(state::ParallelCFRState, tree::GameTree, nodes::Vector)

Static load balancing: divide nodes evenly among threads.
"""
function parallel_static_traversal!(state::ParallelCFRState, tree::Tree.GameTree, 
                                   nodes::Vector{TreeNode.GameNode})
    n_threads = state.thread_config.num_threads
    n_nodes = length(nodes)
    chunk_size = ceil(Int, n_nodes / n_threads)
    
    @threads for tid in 1:n_threads
        # Use tid instead of threadid() to ensure we stay within bounds
        stats = state.thread_stats[tid]
        
        # Calculate this thread's range
        start_idx = (tid - 1) * chunk_size + 1
        end_idx = min(tid * chunk_size, n_nodes)
        
        if start_idx <= n_nodes
            for i in start_idx:end_idx
                node = nodes[i]
                process_node_parallel!(state, tree, node, stats)
            end
        end
    end
end

"""
    parallel_dynamic_traversal!(state::ParallelCFRState, tree::GameTree, nodes::Vector)

Dynamic load balancing: threads take work from a shared queue.
"""
function parallel_dynamic_traversal!(state::ParallelCFRState, tree::Tree.GameTree,
                                    nodes::Vector{TreeNode.GameNode})
    # Create atomic counter for work distribution
    next_idx = Threads.Atomic{Int}(1)
    n_nodes = length(nodes)
    
    @threads for tid in 1:state.thread_config.num_threads
        # Use tid instead of threadid() to ensure we stay within bounds
        stats = state.thread_stats[tid]
        
        while true
            # Get next work item
            idx = Threads.atomic_add!(next_idx, 1)
            if idx > n_nodes
                break
            end
            
            node = nodes[idx]
            process_node_parallel!(state, tree, node, stats)
        end
    end
end

"""
    parallel_work_stealing_traversal!(state::ParallelCFRState, tree::GameTree, nodes::Vector)

Work-stealing load balancing for better load distribution.
"""
function parallel_work_stealing_traversal!(state::ParallelCFRState, tree::Tree.GameTree,
                                         nodes::Vector{TreeNode.GameNode})
    n_threads = state.thread_config.num_threads
    n_nodes = length(nodes)
    
    # Create work queues for each thread
    work_queues = [Vector{TreeNode.GameNode}() for _ in 1:n_threads]
    queue_locks = [ReentrantLock() for _ in 1:n_threads]
    
    # Initial distribution
    for (i, node) in enumerate(nodes)
        queue_idx = ((i - 1) % n_threads) + 1
        push!(work_queues[queue_idx], node)
    end
    
    @threads for tid in 1:n_threads
        # Use tid instead of threadid() to ensure we stay within bounds
        stats = state.thread_stats[tid]
        my_queue = work_queues[tid]
        my_lock = queue_locks[tid]
        
        while true
            # Try to get work from own queue
            node = lock(my_lock) do
                isempty(my_queue) ? nothing : pop!(my_queue)
            end
            
            if node === nothing
                # Try to steal from other queues
                stolen = false
                for steal_tid in 1:n_threads
                    if steal_tid != tid
                        node = lock(queue_locks[steal_tid]) do
                            other_queue = work_queues[steal_tid]
                            if length(other_queue) > 1
                                # Steal half of remaining work
                                num_steal = div(length(other_queue), 2)
                                if num_steal > 0
                                    stolen_nodes = other_queue[1:num_steal]
                                    deleteat!(other_queue, 1:num_steal)
                                    # Add to own queue
                                    lock(my_lock) do
                                        append!(my_queue, stolen_nodes[2:end])
                                    end
                                    return stolen_nodes[1]
                                end
                            end
                            return nothing
                        end
                        
                        if node !== nothing
                            stolen = true
                            break
                        end
                    end
                end
                
                if !stolen
                    break  # No more work available
                end
            end
            
            if node !== nothing
                process_node_parallel!(state, tree, node, stats)
            end
        end
    end
end

"""
    process_node_parallel!(state::ParallelCFRState, tree::GameTree, node::GameNode, stats::ThreadStats)

Process a single node in parallel, with thread-safe updates.
"""
function process_node_parallel!(state::ParallelCFRState, tree::Tree.GameTree, 
                               node::TreeNode.GameNode, stats::ThreadStats)
    start_time = time()
    
    # Skip if terminal or chance node
    if TreeNode.is_terminal_node(node) || TreeNode.is_chance_node(node)
        return
    end
    
    # Generate random cards for this iteration
    # Each thread needs its own RNG for thread safety
    thread_rng = Random.MersenneTwister(rand(UInt32))
    
    # Sample random hole cards (simplified)
    p1_cards = [GameTypes.Card(rand(thread_rng, 2:14), rand(thread_rng, 0:3)),
                GameTypes.Card(rand(thread_rng, 2:14), rand(thread_rng, 0:3))]
    p2_cards = [GameTypes.Card(rand(thread_rng, 2:14), rand(thread_rng, 0:3)),
                GameTypes.Card(rand(thread_rng, 2:14), rand(thread_rng, 0:3))]
    
    # Get or create information set with thread safety
    hole_cards = node.player == 1 ? p1_cards : p2_cards
    
    # Get infoset with locking
    infoset_id = InfoSet.create_infoset_id(
        node.player,
        node.street,
        node.betting_history,
        hole_cards,
        GameTypes.Card[]
    )
    
    infoset_lock = get_infoset_lock(state, infoset_id)
    
    cfr_infoset = lock(infoset_lock) do
        CFR.get_or_create_infoset_for_node(state.base_state, node, hole_cards, GameTypes.Card[])
    end
    
    # Compute strategy (thread-safe read)
    strategy = CFR.compute_strategy_from_regrets(cfr_infoset, state.base_state.config)
    
    # Simplified regret update (would need full traversal in production)
    # This is a placeholder for demonstration
    if length(node.children) > 0
        action_utilities = randn(thread_rng, length(node.children))
        node_utility = dot(strategy, action_utilities)
        
        # Update regrets with locking
        lock(infoset_lock) do
            CFR.update_regrets!(state.base_state, cfr_infoset, action_utilities, node_utility)
            CFR.update_strategy_sum!(state.base_state, cfr_infoset, strategy, 1.0)
        end
        
        stats.infosets_updated += 1
    end
    
    stats.nodes_processed += 1
    stats.time_computing += time() - start_time
end

"""
    parallel_train!(tree::GameTree, state::ParallelCFRState; 
                   iterations::Int = 1000, verbose::Bool = true)

Train CFR solver using parallel execution.
"""
function parallel_train!(tree::Tree.GameTree, state::ParallelCFRState;
                        iterations::Int = 1000, verbose::Bool = true)
    if verbose
        println("Starting parallel CFR training with $(state.thread_config.num_threads) threads")
        println("Load balancing: $(state.thread_config.load_balancing)")
    end
    
    start_time = time()
    
    for iter in 1:iterations
        iter_start = time()
        
        # Run parallel iteration
        parallel_cfr_iteration!(state, tree)
        
        iter_time = time() - iter_start
        
        # Print progress
        if verbose && (iter % 100 == 0 || iter == 1)
            total_nodes = sum(s.nodes_processed for s in state.thread_stats)
            total_updates = sum(s.infosets_updated for s in state.thread_stats)
            
            println("Iteration $iter: $(round(iter_time, digits=3))s, " *
                   "$total_nodes nodes, $total_updates updates")
        end
        
        # Check stopping criteria
        should_stop, reason = CFR.should_stop(state.base_state)
        if should_stop
            if verbose
                println("Stopping: $reason")
            end
            break
        end
    end
    
    total_time = time() - start_time
    
    if verbose
        print_thread_performance(state)
        println("\nTotal training time: $(round(total_time, digits=2))s")
        println("Average iteration time: $(round(total_time / state.base_state.iteration, digits=3))s")
    end
end

"""
    get_thread_stats(state::ParallelCFRState)

Get aggregated statistics for all threads.
"""
function get_thread_stats(state::ParallelCFRState)
    total_nodes = sum(s.nodes_processed for s in state.thread_stats)
    total_updates = sum(s.infosets_updated for s in state.thread_stats)
    total_compute_time = sum(s.time_computing for s in state.thread_stats)
    total_wait_time = sum(s.time_waiting for s in state.thread_stats)
    
    return Dict(
        "total_nodes_processed" => total_nodes,
        "total_infosets_updated" => total_updates,
        "avg_compute_time" => total_compute_time / state.thread_config.num_threads,
        "avg_wait_time" => total_wait_time / state.thread_config.num_threads,
        "thread_efficiency" => total_compute_time / (total_compute_time + total_wait_time),
        "nodes_per_thread" => total_nodes / state.thread_config.num_threads
    )
end

"""
    print_thread_performance(state::ParallelCFRState)

Print detailed thread performance statistics.
"""
function print_thread_performance(state::ParallelCFRState)
    println("\nThread Performance Statistics:")
    println("="^50)
    
    for (tid, stats) in enumerate(state.thread_stats)
        efficiency = stats.time_computing / max(0.001, stats.time_computing + stats.time_waiting)
        println("Thread $tid:")
        println("  Nodes processed: $(stats.nodes_processed)")
        println("  Infosets updated: $(stats.infosets_updated)")
        println("  Compute time: $(round(stats.time_computing, digits=3))s")
        println("  Wait time: $(round(stats.time_waiting, digits=3))s")
        println("  Efficiency: $(round(efficiency * 100, digits=1))%")
    end
    
    # Print aggregate stats
    agg_stats = get_thread_stats(state)
    println("\nAggregate Performance:")
    println("  Total nodes: $(agg_stats["total_nodes_processed"])")
    println("  Total updates: $(agg_stats["total_infosets_updated"])")
    println("  Thread efficiency: $(round(agg_stats["thread_efficiency"] * 100, digits=1))%")
end

end # module ThreadedCFR
