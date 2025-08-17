"""
    CFR

Module implementing the Counterfactual Regret Minimization (CFR) algorithm
and its variants (CFR+, Linear CFR, etc.) for solving extensive-form games.
"""
module CFR

using ..GameTypes
using ..Tree
using ..Tree.TreeNode
using ..Tree.InfoSet
using ..Tree.InfoSetManager

# Forward declare the traversal module that will be included later
# This avoids circular dependencies

"""
    CFRConfig

Configuration for the CFR algorithm.
"""
struct CFRConfig
    use_cfr_plus::Bool           # Use CFR+ (floor negative regrets)
    use_linear_weighting::Bool   # Use Linear CFR weighting
    use_sampling::Bool           # Use Monte Carlo sampling
    sampling_strategy::Symbol     # :none, :chance, :external, :outcome
    sampling_probability::Float64 # Probability for chance sampling
    prune_threshold::Float64     # Threshold for pruning low-regret actions
    discount_factor::Float64     # Discount factor for regret updates
    
    # Stopping criteria
    max_iterations::Int          # Maximum number of iterations
    target_exploitability::Float64 # Stop when exploitability falls below this
    max_time_seconds::Float64    # Maximum training time in seconds
    min_iterations::Int          # Minimum iterations before checking stopping criteria
    check_frequency::Int         # How often to check stopping criteria
end

"""
    CFRConfig(; kwargs...)

Create a CFR configuration with default values.
"""
function CFRConfig(;
    use_cfr_plus::Bool = true,
    use_linear_weighting::Bool = false,
    use_sampling::Bool = false,
    sampling_strategy::Symbol = :none,  # :none, :chance, :external, :outcome
    sampling_probability::Float64 = 1.0,
    prune_threshold::Float64 = -1e9,  # Effectively no pruning by default
    discount_factor::Float64 = 1.0,
    # Stopping criteria defaults
    max_iterations::Int = 1000000,
    target_exploitability::Float64 = 0.001,  # 1 milli-blind
    max_time_seconds::Float64 = Inf,
    min_iterations::Int = 100,
    check_frequency::Int = 100
)
    # Auto-enable sampling if a strategy is specified
    if sampling_strategy != :none && !use_sampling
        use_sampling = true
    end
    
    return CFRConfig(
        use_cfr_plus,
        use_linear_weighting,
        use_sampling,
        sampling_strategy,
        sampling_probability,
        prune_threshold,
        discount_factor,
        max_iterations,
        target_exploitability,
        max_time_seconds,
        min_iterations,
        check_frequency
    )
end

"""
    CFRState

Main state container for the CFR algorithm.
"""
mutable struct CFRState
    storage::InfoSetManager.InfoSetStorage  # Information set storage
    config::CFRConfig                        # Algorithm configuration
    iteration::Int                           # Current iteration number
    total_iterations::Int                    # Total iterations to run
    exploitability::Float64                  # Current exploitability
    convergence_history::Vector{Float64}     # History of exploitability
    training_start_time::Float64             # Start time of training (seconds since epoch)
    stopping_reason::String                  # Reason for stopping training
    metrics::Any                             # Convergence metrics (CFRMetrics.ConvergenceMetrics)
end

"""
    CFRState(tree::GameTree, config::CFRConfig)

Initialize CFR state for a game tree.
"""
function CFRState(tree::Tree.GameTree, config::CFRConfig = CFRConfig())
    storage = InfoSetManager.InfoSetStorage()
    
    return CFRState(
        storage,
        config,
        0,  # iteration
        0,  # total_iterations
        Inf,  # exploitability (unknown initially)
        Float64[],  # convergence_history
        0.0,  # training_start_time (set when training starts)
        "",  # stopping_reason
        nothing  # metrics (initialized during training)
    )
end

"""
    get_or_create_infoset_for_node(state::CFRState, node::GameNode, 
                                   hole_cards::Union{Nothing, Vector{Card}} = nothing,
                                   board_cards::Union{Nothing, Vector{Card}} = nothing)

Get or create the information set for a game node.
"""
function get_or_create_infoset_for_node(state::CFRState, node::TreeNode.GameNode,
                                       hole_cards::Union{Nothing, Vector{GameTypes.Card}} = nothing,
                                       board_cards::Union{Nothing, Vector{GameTypes.Card}} = nothing)
    # Create information set ID
    infoset_id = InfoSet.create_infoset_id(
        node.player,
        node.street,
        node.betting_history,
        hole_cards,
        board_cards
    )
    
    # Count available actions for this node
    num_actions = length(node.children)
    
    # Get or create the CFR information set
    cfr_infoset = InfoSetManager.get_or_create_infoset!(
        state.storage,
        infoset_id,
        num_actions
    )
    
    # Store action labels for debugging
    if num_actions > 0 && length(InfoSetManager.get_action_labels(state.storage, infoset_id)) == 0
        action_labels = String[]
        for child in node.children
            # Extract action from betting history difference
            action = length(child.betting_history) > length(node.betting_history) ?
                     string(child.betting_history[end]) : "?"
            push!(action_labels, action)
        end
        InfoSetManager.set_action_labels!(state.storage, infoset_id, action_labels)
    end
    
    return cfr_infoset
end

"""
    compute_strategy_from_regrets(cfr_infoset::CFRInfoSet, config::CFRConfig)

Compute current strategy from regrets using regret matching.
This is a wrapper around InfoSetManager.get_current_strategy with potential modifications.
"""
function compute_strategy_from_regrets(cfr_infoset::InfoSetManager.CFRInfoSet, config::CFRConfig)
    # Get base strategy from regret matching
    strategy = InfoSetManager.get_current_strategy(cfr_infoset)
    
    # Apply any modifications based on configuration
    if config.prune_threshold > -1e9
        # Prune actions with very negative regrets
        for i in 1:length(strategy)
            if cfr_infoset.regrets[i] < config.prune_threshold
                strategy[i] = 0.0
            end
        end
        
        # Renormalize
        sum_strategy = sum(strategy)
        if sum_strategy > 0
            strategy ./= sum_strategy
        else
            # If all actions pruned, use uniform
            fill!(strategy, 1.0 / length(strategy))
        end
    end
    
    return strategy
end

"""
    update_regrets!(state::CFRState, cfr_infoset::CFRInfoSet, 
                   action_utilities::Vector{Float64}, node_utility::Float64)

Update regrets for an information set based on counterfactual utilities.
"""
function update_regrets!(state::CFRState, cfr_infoset::InfoSetManager.CFRInfoSet,
                        action_utilities::Vector{Float64}, node_utility::Float64)
    # Compute regrets for each action (utility of action - utility of current strategy)
    action_regrets = similar(action_utilities)
    for i in 1:length(action_utilities)
        action_regrets[i] = action_utilities[i] - node_utility
    end
    
    # Apply weighting if using Linear CFR
    weight = 1.0
    if state.config.use_linear_weighting
        weight = Float64(state.iteration)
    end
    
    # Apply discount factor
    weight *= state.config.discount_factor
    
    # Scale regrets by weight
    action_regrets .*= weight
    
    # Update regrets (CFR+ will floor at 0 internally if enabled)
    if state.config.use_cfr_plus
        InfoSetManager.update_regrets!(cfr_infoset, action_regrets, state.iteration)
    else
        # Standard CFR: don't floor negative regrets
        for i in 1:cfr_infoset.num_actions
            cfr_infoset.regrets[i] += action_regrets[i]
        end
        cfr_infoset.last_iteration = state.iteration
    end
end

"""
    update_strategy_sum!(state::CFRState, cfr_infoset::CFRInfoSet, 
                        strategy::Vector{Float64}, reach_probability::Float64)

Update strategy sum for averaging, with proper weighting.
"""
function update_strategy_sum!(state::CFRState, cfr_infoset::InfoSetManager.CFRInfoSet,
                             strategy::Vector{Float64}, reach_probability::Float64)
    # Apply weighting if using Linear CFR
    weight = reach_probability
    if state.config.use_linear_weighting
        weight *= Float64(state.iteration)
    end
    
    # Update strategy sum
    InfoSetManager.update_strategy_sum!(cfr_infoset, strategy, weight)
end

"""
    get_strategy(state::CFRState, node::GameNode, 
                hole_cards::Union{Nothing, Vector{Card}} = nothing,
                board_cards::Union{Nothing, Vector{Card}} = nothing)

Get the current strategy for a game node.
"""
function get_strategy(state::CFRState, node::TreeNode.GameNode,
                     hole_cards::Union{Nothing, Vector{GameTypes.Card}} = nothing,
                     board_cards::Union{Nothing, Vector{GameTypes.Card}} = nothing)
    # Terminal nodes have no strategy
    if TreeNode.is_terminal_node(node)
        return Float64[]
    end
    
    # Get or create information set
    cfr_infoset = get_or_create_infoset_for_node(state, node, hole_cards, board_cards)
    
    # Compute and return strategy
    return compute_strategy_from_regrets(cfr_infoset, state.config)
end

"""
    get_average_strategy(state::CFRState, node::GameNode,
                        hole_cards::Union{Nothing, Vector{Card}} = nothing,
                        board_cards::Union{Nothing, Vector{Card}} = nothing)

Get the average (final) strategy for a game node.
"""
function get_average_strategy(state::CFRState, node::TreeNode.GameNode,
                             hole_cards::Union{Nothing, Vector{GameTypes.Card}} = nothing,
                             board_cards::Union{Nothing, Vector{GameTypes.Card}} = nothing)
    # Terminal nodes have no strategy
    if TreeNode.is_terminal_node(node)
        return Float64[]
    end
    
    # Get information set
    infoset_id = InfoSet.create_infoset_id(
        node.player,
        node.street,
        node.betting_history,
        hole_cards,
        board_cards
    )
    
    cfr_infoset = InfoSetManager.get_infoset(state.storage, infoset_id)
    if cfr_infoset === nothing
        # Never visited - return uniform
        num_actions = length(node.children)
        return fill(1.0 / num_actions, num_actions)
    end
    
    return InfoSetManager.get_average_strategy(cfr_infoset)
end

"""
    reset_regrets!(state::CFRState)

Reset all regrets to zero (useful for CFR+ restart).
"""
function reset_regrets!(state::CFRState)
    for cfr_infoset in values(state.storage.infosets)
        InfoSetManager.reset_regrets!(cfr_infoset)
    end
end

"""
    reset_strategy_sum!(state::CFRState)

Reset all strategy sums to zero (useful for restarting averaging).
"""
function reset_strategy_sum!(state::CFRState)
    for cfr_infoset in values(state.storage.infosets)
        InfoSetManager.reset_strategy_sum!(cfr_infoset)
    end
end

"""
    get_infoset_count(state::CFRState)

Get the number of information sets discovered so far.
"""
function get_infoset_count(state::CFRState)
    return length(state.storage.infosets)
end

"""
    get_memory_usage(state::CFRState)

Get estimated memory usage in MB.
"""
function get_memory_usage(state::CFRState)
    stats = InfoSetManager.get_storage_statistics(state.storage)
    return stats.estimated_memory_mb
end

"""
    print_progress(state::CFRState; force::Bool = false)

Print progress information during training.
"""
function print_progress(state::CFRState; force::Bool = false)
    if !force && state.iteration % max(1, state.total_iterations ÷ 20) != 0
        return
    end
    
    pct = state.total_iterations > 0 ? 100 * state.iteration / state.total_iterations : 0
    
    println("Iteration: $(state.iteration)/$(state.total_iterations) ($(round(pct, digits=1))%)")
    println("  Information sets: $(get_infoset_count(state))")
    println("  Memory usage: $(round(get_memory_usage(state), digits=2)) MB")
    
    if !isinf(state.exploitability)
        println("  Exploitability: $(round(state.exploitability, digits=4)) mbb/hand")
    end
end

# Note: The actual train! function is implemented in CFRTraversal module
# to avoid circular dependencies and keep the traversal logic separate

# Export all public functions and types
"""
    should_stop(state::CFRState)

Check if any stopping criteria have been met.
Returns (should_stop::Bool, reason::String)
"""
function should_stop(state::CFRState)
    # Check minimum iterations requirement
    if state.iteration < state.config.min_iterations
        return false, ""
    end
    
    # Check maximum iterations
    if state.iteration >= state.config.max_iterations
        return true, "Maximum iterations reached ($(state.iteration))"
    end
    
    # Check exploitability (if available)
    if state.exploitability <= state.config.target_exploitability
        return true, "Target exploitability reached ($(state.exploitability) <= $(state.config.target_exploitability))"
    end
    
    # Check time limit
    if state.training_start_time > 0
        elapsed_time = time() - state.training_start_time
        if elapsed_time >= state.config.max_time_seconds
            return true, "Time limit reached ($(round(elapsed_time, digits=1))s >= $(state.config.max_time_seconds)s)"
        end
    end
    
    return false, ""
end

"""
    get_training_stats(state::CFRState)

Get a summary of training statistics.
"""
function get_training_stats(state::CFRState)
    elapsed_time = state.training_start_time > 0 ? time() - state.training_start_time : 0.0
    
    return Dict(
        "iterations" => state.iteration,
        "infosets" => get_infoset_count(state),
        "exploitability" => state.exploitability,
        "elapsed_time" => elapsed_time,
        "iterations_per_second" => state.iteration > 0 ? state.iteration / elapsed_time : 0.0,
        "stopping_reason" => state.stopping_reason,
        "convergence_history" => state.convergence_history
    )
end

export CFRConfig, CFRState
export get_or_create_infoset_for_node, compute_strategy_from_regrets
export update_regrets!, update_strategy_sum!
export get_strategy, get_average_strategy
export reset_regrets!, reset_strategy_sum!
export get_infoset_count, get_memory_usage
export print_progress
export should_stop, get_training_stats

end # module
