"""
    PreflopSolver

Module for specialized pre-flop-only solving mode, providing faster iteration
and optimized solving for the pre-flop portion of Limit Hold'em.
"""
module PreflopSolver

using Printf
using Statistics
using ..GameTypes
using ..Tree
using ..Tree.InfoSet
using ..Tree.InfoSetManager
using ..CFR
using ..CFRTraversal
using ..ThreadedCFR
using ..SolverConfig
using ..ProgressTracker
using ..Checkpoint

# Export main functionality
export PreflopConfig, PreflopState, PreflopResult
export solve_preflop, solve_preflop_parallel
export get_preflop_strategy, print_preflop_ranges
export analyze_preflop_ranges, export_preflop_chart
export quick_solve_preflop

"""
    PreflopConfig

Configuration specific to pre-flop solving.
"""
struct PreflopConfig
    # Solving parameters
    target_exploitability::Float64
    max_iterations::Int
    use_parallel::Bool
    num_threads::Int
    
    # Strategy refinement
    use_card_abstraction::Bool
    abstraction_buckets::Int
    
    # Output options
    show_progress::Bool
    save_checkpoints::Bool
    checkpoint_frequency::Int
    
    # Optimization settings
    cache_strategies::Bool
    use_symmetry::Bool  # Exploit suit symmetries
    
    function PreflopConfig(;
        target_exploitability::Float64 = 0.001,
        max_iterations::Int = 10000,
        use_parallel::Bool = true,
        num_threads::Int = 0,  # 0 = auto
        use_card_abstraction::Bool = false,
        abstraction_buckets::Int = 169,  # Number of unique starting hands
        show_progress::Bool = true,
        save_checkpoints::Bool = false,
        checkpoint_frequency::Int = 1000,
        cache_strategies::Bool = true,
        use_symmetry::Bool = true
    )
        new(
            target_exploitability, max_iterations, use_parallel, num_threads,
            use_card_abstraction, abstraction_buckets,
            show_progress, save_checkpoints, checkpoint_frequency,
            cache_strategies, use_symmetry
        )
    end
end

"""
    PreflopState

State for pre-flop solving, optimized for the smaller pre-flop tree.
"""
mutable struct PreflopState
    tree::Tree.GameTree
    cfr_state::CFR.CFRState
    config::PreflopConfig
    iteration::Int
    exploitability::Float64
    solve_time::Float64
    strategy_cache::Dict{String, Vector{Float64}}
end

"""
    PreflopResult

Results from pre-flop solving.
"""
struct PreflopResult
    converged::Bool
    iterations::Int
    final_exploitability::Float64
    solve_time::Float64
    strategies::Dict{String, Vector{Float64}}
    ranges::Dict{String, Dict{String, Float64}}  # Position -> Hand -> Frequency
end

"""
    solve_preflop(params::GameTypes.GameParams, config::PreflopConfig)

Solve pre-flop with optimized settings.
"""
function solve_preflop(params::GameTypes.GameParams, config::PreflopConfig = PreflopConfig())
    # Build pre-flop-only tree
    if config.show_progress
        println("Building pre-flop tree...")
    end
    tree = Tree.build_game_tree(params, preflop_only=true, verbose=false)
    
    if config.show_progress
        println("Pre-flop tree built: $(length(tree.nodes)) nodes")
    end
    
    # Create CFR configuration optimized for pre-flop
    cfr_config = CFR.CFRConfig(
        use_cfr_plus = true,
        use_linear_weighting = true,
        max_iterations = config.max_iterations,
        target_exploitability = config.target_exploitability,
        check_frequency = min(100, config.max_iterations ÷ 10)
    )
    
    # Initialize CFR state with indexing for efficiency
    cfr_state = CFR.CFRState(tree, cfr_config, true)
    
    # Create pre-flop state
    preflop_state = PreflopState(
        tree, cfr_state, config,
        0, Inf, 0.0,
        Dict{String, Vector{Float64}}()
    )
    
    # Setup progress tracking if requested
    if config.show_progress
        progress_config = ProgressTracker.ProgressConfig(
            show_progress_bar = true,
            update_frequency = min(100, config.max_iterations ÷ 20),
            show_eta = true
        )
        ProgressTracker.initialize_progress!(cfr_state, progress_config)
    end
    
    # Setup checkpointing if requested
    checkpoint_manager = nothing
    if config.save_checkpoints
        checkpoint_opts = Checkpoint.CheckpointOptions(
            enabled = true,
            checkpoint_dir = "preflop_checkpoints",
            frequency_iterations = config.checkpoint_frequency,
            compress = true,
            save_strategies_only = true  # Only need strategies for pre-flop
        )
        checkpoint_manager = Checkpoint.create_checkpoint_manager(checkpoint_opts)
    end
    
    # Solve
    start_time = time()
    
    if config.use_parallel && config.num_threads != 1
        # Use parallel solving
        solve_preflop_parallel!(preflop_state, checkpoint_manager)
    else
        # Use sequential solving
        solve_preflop_sequential!(preflop_state, checkpoint_manager)
    end
    
    preflop_state.solve_time = time() - start_time
    
    # Extract results
    converged = preflop_state.exploitability <= config.target_exploitability
    
    if config.show_progress
        println("\nPre-flop solving complete!")
        println("  Iterations: $(preflop_state.iteration)")
        println("  Final exploitability: $(round(preflop_state.exploitability, digits=6))")
        println("  Time: $(round(preflop_state.solve_time, digits=2))s")
        println("  Converged: $(converged ? "Yes ✓" : "No")")
    end
    
    # Build result
    strategies = extract_preflop_strategies(preflop_state)
    ranges = compute_preflop_ranges(strategies)
    
    return PreflopResult(
        converged,
        preflop_state.iteration,
        preflop_state.exploitability,
        preflop_state.solve_time,
        strategies,
        ranges
    )
end

"""
    solve_preflop_sequential!(state::PreflopState, checkpoint_manager)

Sequential pre-flop solving.
"""
function solve_preflop_sequential!(state::PreflopState, checkpoint_manager)
    config = state.config
    
    for iter in 1:config.max_iterations
        # Run CFR traversal for one iteration
        exploitability = CFRTraversal.train!(state.tree, state.cfr_state, iterations=1, verbose=false)
        
        state.iteration = iter
        state.cfr_state.iteration = iter
        
        # Update progress if available
        # Note: metrics structure may vary, so we skip progress tracking for now
        
        # Check convergence
        if iter % state.cfr_state.config.check_frequency == 0
            state.exploitability = state.cfr_state.exploitability
            
            if state.exploitability <= config.target_exploitability
                if config.show_progress
                    println("\nConverged at iteration $iter!")
                end
                break
            end
        end
        
        # Auto-checkpoint
        if checkpoint_manager !== nothing
            Checkpoint.auto_checkpoint!(state.cfr_state, checkpoint_manager, state.tree)
        end
        
        # Check stopping conditions
        should_stop, reason = CFR.should_stop(state.cfr_state)
        if should_stop
            if config.show_progress
                println("\nStopping: $reason")
            end
            break
        end
    end
    
    state.exploitability = state.cfr_state.exploitability
end

"""
    solve_preflop_parallel!(state::PreflopState, checkpoint_manager)

Parallel pre-flop solving using multiple threads.
"""
function solve_preflop_parallel!(state::PreflopState, checkpoint_manager)
    config = state.config
    
    # Create thread configuration
    thread_config = ThreadedCFR.ThreadConfig(
        num_threads = config.num_threads,
        chunk_size = 50,  # Smaller chunks for pre-flop
        load_balancing = :dynamic,
        thread_safe_cache = true
    )
    
    # Create parallel state
    parallel_state = ThreadedCFR.ParallelCFRState(
        state.tree,
        state.cfr_state.config,
        thread_config
    )
    
    # Train with parallel execution
    ThreadedCFR.parallel_train!(
        state.tree,
        parallel_state,
        iterations = config.max_iterations,
        verbose = config.show_progress
    )
    
    # Update state from parallel results
    state.cfr_state = parallel_state.base_state
    state.iteration = parallel_state.base_state.iteration
    state.exploitability = parallel_state.base_state.exploitability
end

"""
    extract_preflop_strategies(state::PreflopState)

Extract converged strategies from pre-flop state.
"""
function extract_preflop_strategies(state::PreflopState)
    strategies = Dict{String, Vector{Float64}}()
    storage = CFR.get_infoset_storage(state.cfr_state)
    
    for (id, infoset) in storage.infosets
        # Get average strategy
        if sum(infoset.strategy_sum) > 0
            strategy = infoset.strategy_sum / sum(infoset.strategy_sum)
        else
            strategy = fill(1.0 / infoset.num_actions, infoset.num_actions)
        end
        strategies[id] = strategy
    end
    
    return strategies
end

"""
    compute_preflop_ranges(strategies::Dict{String, Vector{Float64}})

Compute opening/calling/raising ranges from strategies.
"""
function compute_preflop_ranges(strategies::Dict{String, Vector{Float64}})
    ranges = Dict{String, Dict{String, Float64}}()
    
    # Initialize position ranges
    positions = ["SB", "BB"]
    for pos in positions
        ranges[pos] = Dict{String, Float64}()
    end
    
    # Process each strategy
    for (infoset_id, strategy) in strategies
        # Parse the infoset ID to extract position and cards
        parts = split(infoset_id, ":")
        if length(parts) >= 3
            position = parts[1] == "P1" ? "SB" : "BB"
            
            # Extract hole cards if present
            if occursin("cards=", infoset_id)
                cards_match = match(r"cards=\[([^\]]+)\]", infoset_id)
                if cards_match !== nothing
                    cards_str = cards_match[1]
                    # Parse cards and compute hand strength
                    hand_str = parse_hand_string(cards_str)
                    
                    if hand_str !== nothing
                        # Get the action frequencies
                        if !haskey(ranges[position], hand_str)
                            ranges[position][hand_str] = 0.0
                        end
                        
                        # Use the maximum action probability as the playing frequency
                        # (This is simplified - in practice you'd track specific actions)
                        ranges[position][hand_str] = max(ranges[position][hand_str], maximum(strategy))
                    end
                end
            end
        end
    end
    
    return ranges
end

"""
    parse_hand_string(cards_str::String)

Parse a hand string from card representation.
"""
function parse_hand_string(cards_str::String)
    # This is a simplified parser - in practice you'd have more sophisticated parsing
    # Example: "14s,13s" -> "AKs"
    
    # For now, return a placeholder
    return nothing
end

"""
    print_preflop_ranges(result::PreflopResult; position::String = "SB")

Print pre-flop ranges in a readable format.
"""
function print_preflop_ranges(result::PreflopResult; position::String = "SB")
    println("\n$(position) Pre-flop Ranges:")
    println("="^40)
    
    if !haskey(result.ranges, position)
        println("No ranges available for position: $position")
        return
    end
    
    # Get and sort hands by frequency
    hands = result.ranges[position]
    sorted_hands = sort(collect(hands), by = x -> x[2], rev = true)
    
    # Print opening ranges
    println("\nOpening/Playing Frequencies:")
    println("-"^40)
    
    for (hand, freq) in sorted_hands
        if freq > 0.01  # Only show hands played > 1% of the time
            bar_length = round(Int, freq * 20)
            bar = "█" ^ bar_length * "░" ^ (20 - bar_length)
            @printf("%-10s [%s] %.1f%%\n", hand, bar, freq * 100)
        end
    end
end

"""
    analyze_preflop_ranges(result::PreflopResult)

Analyze pre-flop ranges and provide statistics.
"""
function analyze_preflop_ranges(result::PreflopResult)
    stats = Dict{String, Any}()
    
    for (position, hands) in result.ranges
        pos_stats = Dict{String, Any}()
        
        # Calculate VPIP (Voluntarily Put money In Pot)
        vpip = sum(values(hands)) / length(hands)
        pos_stats["VPIP"] = vpip
        
        # Count different hand types
        premium_hands = count(h -> h[2] > 0.9, hands)  # Hands played >90%
        playable_hands = count(h -> h[2] > 0.1, hands)  # Hands played >10%
        
        pos_stats["Premium Hands"] = premium_hands
        pos_stats["Playable Hands"] = playable_hands
        pos_stats["Total Hands"] = length(hands)
        
        stats[position] = pos_stats
    end
    
    return stats
end

"""
    export_preflop_chart(result::PreflopResult, filepath::String)

Export pre-flop ranges to a file (CSV format).
"""
function export_preflop_chart(result::PreflopResult, filepath::String)
    open(filepath, "w") do io
        println(io, "Position,Hand,Frequency,Action")
        
        for (position, hands) in result.ranges
            for (hand, freq) in hands
                # Determine action based on frequency
                action = if freq > 0.9
                    "RAISE"
                elseif freq > 0.5
                    "CALL/RAISE"
                elseif freq > 0.1
                    "CALL"
                else
                    "FOLD"
                end
                
                println(io, "$position,$hand,$freq,$action")
            end
        end
    end
    
    println("Pre-flop chart exported to: $filepath")
end

"""
    quick_solve_preflop(; stack::Int = 200, iterations::Int = 1000)

Quick pre-flop solve with default settings for testing.
"""
function quick_solve_preflop(; 
    stack::Int = 200, 
    iterations::Int = 1000,
    show_progress::Bool = true)
    
    # Create game parameters
    params = GameTypes.GameParams(
        stack = stack,
        small_blind = 1,
        big_blind = 2
    )
    
    # Create config for quick solving
    config = PreflopConfig(
        max_iterations = iterations,
        target_exploitability = 0.01,  # Less strict for quick solve
        use_parallel = true,
        show_progress = show_progress,
        save_checkpoints = false
    )
    
    # Solve
    result = solve_preflop(params, config)
    
    # Print summary
    if show_progress
        println("\n" * "="^50)
        println("Quick Pre-flop Solve Summary:")
        println("="^50)
        println("Stack: $(stack)BB")
        println("Iterations: $(result.iterations)")
        println("Exploitability: $(round(result.final_exploitability, digits=4))")
        println("Time: $(round(result.solve_time, digits=2))s")
        println("Converged: $(result.converged ? "Yes ✓" : "No ✗")")
        
        # Print sample ranges
        if !isempty(result.ranges)
            for position in ["SB", "BB"]
                if haskey(result.ranges, position)
                    hands = result.ranges[position]
                    playing_count = count(h -> h[2] > 0.1, hands)
                    println("\n$position: Playing $playing_count hands")
                end
            end
        end
    end
    
    return result
end

"""
    get_preflop_strategy(result::PreflopResult, position::String, cards::Vector{GameTypes.Card})

Get the strategy for specific cards in a position.
"""
function get_preflop_strategy(result::PreflopResult, position::String, cards::Vector{GameTypes.Card})
    # Build the information set ID for these cards
    player = position == "SB" ? 1 : 2
    infoset_id = InfoSet.create_infoset_id(
        player,
        UInt8(0),  # 0 = preflop
        Int[],  # Empty betting history for opening position
        cards,
        GameTypes.Card[]  # No board cards pre-flop
    )
    
    # Look up strategy
    if haskey(result.strategies, infoset_id)
        return result.strategies[infoset_id]
    else
        # Return default strategy if not found
        return [1/3, 1/3, 1/3]  # Equal probability fold/call/raise
    end
end

end # module PreflopSolver
