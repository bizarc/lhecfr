"""
    InfoSetManager

Module for managing information sets with their associated regret and strategy storage
for the CFR+ algorithm. This module works in conjunction with InfoSet.jl for identification.
"""
module InfoSetManager

using ..TreeNode
using ..InfoSet

"""
    CFRInfoSet

Stores CFR-specific data for a single information set.
"""
mutable struct CFRInfoSet
    id::String                    # Information set identifier
    num_actions::Int             # Number of available actions
    regrets::Vector{Float64}     # Regret values for each action
    strategy_sum::Vector{Float64} # Strategy sum for averaging
    last_iteration::Int          # Last iteration this was updated (for pruning)
end

"""
    InfoSetStorage

Manages all information sets and their CFR data.
"""
struct InfoSetStorage
    infosets::Dict{String, CFRInfoSet}  # Map from infoset ID to CFR data
    action_lookup::Dict{String, Vector{String}}  # Map from infoset ID to action labels
    lock::ReentrantLock  # Thread safety lock
end

"""
    InfoSetStorage()

Create an empty information set storage.
"""
function InfoSetStorage()
    return InfoSetStorage(
        Dict{String, CFRInfoSet}(),
        Dict{String, Vector{String}}(),
        ReentrantLock()
    )
end

"""
    get_or_create_infoset!(storage::InfoSetStorage, infoset_id::String, num_actions::Int)

Get an existing CFR information set or create a new one if it doesn't exist.
"""
function get_or_create_infoset!(storage::InfoSetStorage, infoset_id::String, num_actions::Int)
    lock(storage.lock) do
        if !haskey(storage.infosets, infoset_id)
            storage.infosets[infoset_id] = CFRInfoSet(
                infoset_id,
                num_actions,
                zeros(Float64, num_actions),     # Initialize regrets to 0
                zeros(Float64, num_actions),     # Initialize strategy sum to 0
                0                                 # No iterations yet
            )
        end
        return storage.infosets[infoset_id]
    end
end

"""
    get_infoset(storage::InfoSetStorage, infoset_id::String)

Get an existing CFR information set, returns nothing if not found.
"""
function get_infoset(storage::InfoSetStorage, infoset_id::String)
    return get(storage.infosets, infoset_id, nothing)
end

"""
    set_action_labels!(storage::InfoSetStorage, infoset_id::String, actions::Vector{String})

Store the action labels for an information set (for debugging and analysis).
"""
function set_action_labels!(storage::InfoSetStorage, infoset_id::String, actions::Vector{String})
    lock(storage.lock) do
        storage.action_lookup[infoset_id] = actions
    end
end

"""
    get_action_labels(storage::InfoSetStorage, infoset_id::String)

Get the action labels for an information set.
"""
function get_action_labels(storage::InfoSetStorage, infoset_id::String)
    return get(storage.action_lookup, infoset_id, String[])
end

"""
    update_regrets!(cfr_infoset::CFRInfoSet, action_regrets::Vector{Float64}, iteration::Int)

Update regrets for an information set using CFR+ rules (floor negative regrets at 0).
"""
function update_regrets!(cfr_infoset::CFRInfoSet, action_regrets::Vector{Float64}, iteration::Int)
    @assert length(action_regrets) == cfr_infoset.num_actions "Regret vector size mismatch"
    
    for i in 1:cfr_infoset.num_actions
        # CFR+ modification: floor negative regrets at 0
        cfr_infoset.regrets[i] = max(0.0, cfr_infoset.regrets[i] + action_regrets[i])
    end
    
    cfr_infoset.last_iteration = iteration
end

"""
    update_strategy_sum!(cfr_infoset::CFRInfoSet, strategy::Vector{Float64}, reach_prob::Float64)

Update the strategy sum for averaging, weighted by the reach probability.
"""
function update_strategy_sum!(cfr_infoset::CFRInfoSet, strategy::Vector{Float64}, reach_prob::Float64)
    @assert length(strategy) == cfr_infoset.num_actions "Strategy vector size mismatch"
    
    for i in 1:cfr_infoset.num_actions
        cfr_infoset.strategy_sum[i] += reach_prob * strategy[i]
    end
end

"""
    get_current_strategy(cfr_infoset::CFRInfoSet)

Compute the current strategy using regret matching.
Returns uniform strategy if all regrets are non-positive.
"""
function get_current_strategy(cfr_infoset::CFRInfoSet)
    strategy = zeros(Float64, cfr_infoset.num_actions)
    
    # Sum of positive regrets
    regret_sum = sum(max(0.0, r) for r in cfr_infoset.regrets)
    
    if regret_sum > 0
        # Proportional to positive regrets
        for i in 1:cfr_infoset.num_actions
            strategy[i] = max(0.0, cfr_infoset.regrets[i]) / regret_sum
        end
    else
        # Uniform strategy when no positive regrets
        fill!(strategy, 1.0 / cfr_infoset.num_actions)
    end
    
    return strategy
end

"""
    get_average_strategy(cfr_infoset::CFRInfoSet)

Compute the average strategy from the strategy sum.
This is the final exploitable strategy after training.
"""
function get_average_strategy(cfr_infoset::CFRInfoSet)
    strategy = zeros(Float64, cfr_infoset.num_actions)
    
    strategy_sum_total = sum(cfr_infoset.strategy_sum)
    
    if strategy_sum_total > 0
        for i in 1:cfr_infoset.num_actions
            strategy[i] = cfr_infoset.strategy_sum[i] / strategy_sum_total
        end
    else
        # Uniform if never visited (shouldn't happen in proper CFR)
        fill!(strategy, 1.0 / cfr_infoset.num_actions)
    end
    
    return strategy
end

"""
    reset_regrets!(cfr_infoset::CFRInfoSet)

Reset all regrets to zero (useful for CFR+ variant).
"""
function reset_regrets!(cfr_infoset::CFRInfoSet)
    fill!(cfr_infoset.regrets, 0.0)
end

"""
    reset_strategy_sum!(cfr_infoset::CFRInfoSet)

Reset strategy sum to zero (useful for restarting averaging).
"""
function reset_strategy_sum!(cfr_infoset::CFRInfoSet)
    fill!(cfr_infoset.strategy_sum, 0.0)
end

"""
    get_storage_statistics(storage::InfoSetStorage)

Get statistics about the information set storage.
"""
function get_storage_statistics(storage::InfoSetStorage)
    num_infosets = length(storage.infosets)
    
    # Handle empty storage case
    if num_infosets == 0
        return (
            num_infosets = 0,
            total_actions = 0,
            estimated_memory_mb = 0.0
        )
    end
    
    total_actions = sum(is.num_actions for is in values(storage.infosets))
    
    # Memory usage estimation (rough)
    memory_bytes = num_infosets * 64  # Overhead per infoset
    for is in values(storage.infosets)
        memory_bytes += length(is.id) # String storage
        memory_bytes += is.num_actions * 8 * 2  # Two Float64 arrays
        memory_bytes += 8  # Integer field
    end
    
    return (
        num_infosets = num_infosets,
        total_actions = total_actions,
        estimated_memory_mb = memory_bytes / 1024 / 1024
    )
end

"""
    prune_unused!(storage::InfoSetStorage, current_iteration::Int, max_iterations_inactive::Int)

Remove information sets that haven't been visited recently.
This can help with memory management in large games.
"""
function prune_unused!(storage::InfoSetStorage, current_iteration::Int, max_iterations_inactive::Int)
    to_remove = String[]
    
    for (id, infoset) in storage.infosets
        if current_iteration - infoset.last_iteration > max_iterations_inactive
            push!(to_remove, id)
        end
    end
    
    for id in to_remove
        delete!(storage.infosets, id)
        delete!(storage.action_lookup, id)
    end
    
    return length(to_remove)
end

# Export all public types and functions
export CFRInfoSet, InfoSetStorage
export get_or_create_infoset!, get_infoset, set_action_labels!, get_action_labels
export update_regrets!, update_strategy_sum!
export get_current_strategy, get_average_strategy
export reset_regrets!, reset_strategy_sum!
export get_storage_statistics, prune_unused!

end # module
