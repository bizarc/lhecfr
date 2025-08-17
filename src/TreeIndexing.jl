"""
    TreeIndexing

Module for efficient indexing and mapping between game tree nodes and information sets.
Provides O(1) lookup and pre-allocated storage for CFR traversal optimization.
"""
module TreeIndexing

using ..GameTypes
using ..TreeNode
using ..InfoSet
using ..InfoSetManager
using ..TreeTraversal
using ..TreeBuilder
using ..InfoSetCache

"""
    TreeIndex

Efficient indexing structure for mapping between tree nodes and information sets.
"""
struct TreeIndex
    # Node ID to information set ID mapping
    node_to_infoset::Dict{Int, String}
    
    # Information set ID to node IDs mapping (multiple nodes can share an infoset)
    infoset_to_nodes::Dict{String, Vector{Int}}
    
    # Pre-computed information set IDs for all possible card combinations
    card_infosets::Dict{Tuple{Int, Vector{GameTypes.Card}}, String}
    
    # Statistics
    num_nodes::Int
    num_infosets::Int
    num_player_nodes::Int
    num_terminal_nodes::Int
    num_chance_nodes::Int
end

"""
    collect_nodes_preorder(root::GameNode)

Helper function to collect all nodes in pre-order traversal.
"""
function collect_nodes_preorder(root::TreeNode.GameNode)
    nodes = TreeNode.GameNode[]
    
    function visit(node::TreeNode.GameNode)
        push!(nodes, node)
        for child in node.children
            visit(child)
        end
    end
    
    visit(root)
    return nodes
end

"""
    build_tree_index(tree::GameTree)

Build an efficient index for the game tree, pre-computing all information set mappings.
"""
function build_tree_index(tree::TreeBuilder.GameTree)
    node_to_infoset = Dict{Int, String}()
    infoset_to_nodes = Dict{String, Vector{Int}}()
    card_infosets = Dict{Tuple{Int, Vector{GameTypes.Card}}, String}()
    
    num_player_nodes = 0
    num_terminal_nodes = 0
    num_chance_nodes = 0
    
    # First pass: collect all nodes and their types
    nodes = collect_nodes_preorder(tree.root)
    
    for (idx, node) in enumerate(nodes)
        if TreeNode.is_terminal_node(node)
            num_terminal_nodes += 1
        elseif TreeNode.is_chance_node(node)
            num_chance_nodes += 1
        else
            num_player_nodes += 1
            
            # For player nodes, pre-compute infoset ID without cards
            # This is the base infoset that will be combined with cards later
            base_infoset_id = InfoSet.create_infoset_id(
                node.player,
                node.street,
                node.betting_history,
                nothing,  # No cards yet
                nothing
            )
            
            node_to_infoset[idx] = base_infoset_id
            
            # Add to reverse mapping
            if !haskey(infoset_to_nodes, base_infoset_id)
                infoset_to_nodes[base_infoset_id] = Int[]
            end
            push!(infoset_to_nodes[base_infoset_id], idx)
        end
    end
    
    num_unique_infosets = length(infoset_to_nodes)
    
    return TreeIndex(
        node_to_infoset,
        infoset_to_nodes,
        card_infosets,
        length(nodes),
        num_unique_infosets,
        num_player_nodes,
        num_terminal_nodes,
        num_chance_nodes
    )
end

"""
    get_infoset_id_for_node(index::TreeIndex, node_id::Int, 
                           hole_cards::Union{Nothing, Vector{Card}},
                           board_cards::Union{Nothing, Vector{Card}})

Get the information set ID for a node with specific cards.
Uses pre-computed index for O(1) lookup.
"""
function get_infoset_id_for_node(index::TreeIndex, node::TreeNode.GameNode,
                                hole_cards::Union{Nothing, Vector{GameTypes.Card}},
                                board_cards::Union{Nothing, Vector{GameTypes.Card}})
    # For now, create the infoset ID dynamically
    # In a future optimization, we could cache these combinations
    return InfoSet.create_infoset_id(
        node.player,
        node.street,
        node.betting_history,
        hole_cards,
        board_cards
    )
end

"""
    IndexedInfoSetStorage

Enhanced information set storage with pre-allocated space and efficient indexing.
"""
struct IndexedInfoSetStorage
    storage::InfoSetManager.InfoSetStorage  # Underlying storage
    index::TreeIndex                        # Tree index
    cache::InfoSetCache.LRUInfoSetCache     # Advanced LRU cache with statistics
end

"""
    IndexedInfoSetStorage(tree::GameTree)

Create indexed storage for a game tree with pre-allocation.
"""
function IndexedInfoSetStorage(tree::TreeBuilder.GameTree; cache_config::Union{Nothing, InfoSetCache.CacheConfig} = nothing)
    storage = InfoSetManager.InfoSetStorage()
    index = build_tree_index(tree)
    
    # Create cache with appropriate configuration
    if cache_config === nothing
        # Default cache size based on tree size
        max_cache_size = min(1000000, index.num_player_nodes * 10)  # Allow for card variations
        cache_config = InfoSetCache.CacheConfig(
            max_size = max_cache_size,
            enable_statistics = true,
            eviction_policy = :lru,
            thread_safe = false  # Will be enabled in Task 3.3
        )
    end
    cache = InfoSetCache.LRUInfoSetCache(cache_config)
    
    # Pre-allocate information sets for all player nodes
    # This reduces allocation overhead during training
    nodes = collect_nodes_preorder(tree.root)
    for (base_infoset_id, node_ids) in index.infoset_to_nodes
        # Get a representative node to count actions
        representative_node = nodes[node_ids[1]]
        num_actions = length(representative_node.children)
        
        if num_actions > 0
            # Pre-create the information set
            cfr_infoset = InfoSetManager.get_or_create_infoset!(
                storage,
                base_infoset_id,
                num_actions
            )
            # Add to cache
            InfoSetCache.put_cached!(cache, base_infoset_id, cfr_infoset)
        end
    end
    
    return IndexedInfoSetStorage(storage, index, cache)
end

"""
    get_or_create_indexed_infoset!(indexed_storage::IndexedInfoSetStorage,
                                  node::GameNode,
                                  hole_cards::Union{Nothing, Vector{Card}},
                                  board_cards::Union{Nothing, Vector{Card}})

Get or create an information set using the indexed storage for O(1) lookup.
"""
function get_or_create_indexed_infoset!(indexed_storage::IndexedInfoSetStorage,
                                       node::TreeNode.GameNode,
                                       hole_cards::Union{Nothing, Vector{GameTypes.Card}},
                                       board_cards::Union{Nothing, Vector{GameTypes.Card}})
    # Get the full infoset ID including cards
    infoset_id = get_infoset_id_for_node(indexed_storage.index, node, hole_cards, board_cards)
    
    # Try to get from cache first
    cfr_infoset, was_hit = InfoSetCache.get_cached!(
        indexed_storage.cache,
        infoset_id,
        # Creator function if not in cache
        () -> begin
            num_actions = length(node.children)
            InfoSetManager.get_or_create_infoset!(
                indexed_storage.storage,
                infoset_id,
                num_actions
            )
        end
    )
    
    return cfr_infoset
end

"""
    print_index_statistics(index::TreeIndex)

Print statistics about the tree index.
"""
function print_index_statistics(index::TreeIndex)
    println("Tree Index Statistics:")
    println("  Total nodes: $(index.num_nodes)")
    println("  Player nodes: $(index.num_player_nodes)")
    println("  Terminal nodes: $(index.num_terminal_nodes)")
    println("  Chance nodes: $(index.num_chance_nodes)")
    println("  Unique information sets (without cards): $(index.num_infosets)")
    println("  Average nodes per infoset: $(round(index.num_player_nodes / max(1, index.num_infosets), digits=2))")
end

"""
    print_cache_statistics(indexed_storage::IndexedInfoSetStorage)

Print cache performance statistics.
"""
function print_cache_statistics(indexed_storage::IndexedInfoSetStorage)
    InfoSetCache.print_cache_statistics(indexed_storage.cache)
end

"""
    get_cache_statistics(indexed_storage::IndexedInfoSetStorage)

Get cache performance statistics as a dictionary.
"""
function get_cache_statistics(indexed_storage::IndexedInfoSetStorage)
    return InfoSetCache.get_statistics(indexed_storage.cache)
end

end # module TreeIndexing
