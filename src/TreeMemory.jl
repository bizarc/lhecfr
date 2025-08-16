"""
    TreeMemory

Module for memory-efficient tree storage and manipulation.
Provides compact representations, lazy evaluation, and tree pruning.
"""
module TreeMemory

using ..GameTypes
using ..TreeNode
using ..TreeBuilder
using ..TreeTraversal
using ..BettingSequence

# --- Compact Node Representation ---

"""
    CompactNode

A memory-efficient representation of a game node.
Uses smaller data types and bit packing where possible.
"""
struct CompactNode
    # Core fields (16 bytes)
    id::UInt32              # 4 bytes (supports up to 4 billion nodes)
    parent_id::UInt32       # 4 bytes
    pot::Float32            # 4 bytes
    infoset_id::UInt32      # 4 bytes
    
    # Packed fields (8 bytes)
    packed_info::UInt64     # Contains: player(2 bits), street(2 bits), 
                           # terminal_type(2 bits), facing_bet(1 bit), 
                           # is_terminal(1 bit), num_children(8 bits)
                           # betting_history_idx(32 bits), utilities_idx(16 bits)
    
    # Children stored separately in a pool
    first_child_idx::UInt32  # 4 bytes - index into children pool
end

"""
    CompactTree

A memory-efficient tree representation using compact nodes and pooled storage.
"""
mutable struct CompactTree
    nodes::Vector{CompactNode}
    children_pool::Vector{UInt32}  # Pool of child node IDs
    betting_histories::Vector{String}  # Unique betting histories
    utilities_pool::Vector{Tuple{Float32, Float32}}  # Terminal utilities
    
    # Metadata
    num_nodes::Int
    num_player_nodes::Int
    num_terminal_nodes::Int
    num_infosets::Int
    
    # Memory tracking
    memory_used::Int  # Bytes
end

# --- Bit Packing/Unpacking Functions ---

"""
Pack node information into a UInt64 for compact storage.
"""
function pack_node_info(player::UInt8, street::TreeNode.Street, terminal_type::Int,
                       facing_bet::Bool, is_terminal::Bool, num_children::Int,
                       betting_history_idx::UInt32, utilities_idx::UInt16)
    packed = UInt64(0)
    
    # Pack fields (LSB to MSB)
    packed |= UInt64(player) & 0x3                    # Bits 0-1 (2 bits)
    packed |= (UInt64(street) & 0x3) << 2            # Bits 2-3 (2 bits)
    packed |= (UInt64(terminal_type) & 0x3) << 4     # Bits 4-5 (2 bits)
    packed |= (UInt64(facing_bet) & 0x1) << 6        # Bit 6 (1 bit)
    packed |= (UInt64(is_terminal) & 0x1) << 7       # Bit 7 (1 bit)
    packed |= (UInt64(num_children) & 0xFF) << 8     # Bits 8-15 (8 bits)
    packed |= (UInt64(betting_history_idx) & 0xFFFFFFFF) << 16  # Bits 16-47 (32 bits)
    packed |= UInt64(utilities_idx) << 48            # Bits 48-63 (16 bits)
    
    return packed
end

"""
Unpack node information from a UInt64.
"""
function unpack_node_info(packed::UInt64)
    player = UInt8(packed & 0x3)
    street = TreeNode.Street((packed >> 2) & 0x3)
    terminal_type = Int((packed >> 4) & 0x3)
    facing_bet = Bool((packed >> 6) & 0x1)
    is_terminal = Bool((packed >> 7) & 0x1)
    num_children = Int((packed >> 8) & 0xFF)
    betting_history_idx = UInt32((packed >> 16) & 0xFFFFFFFF)
    utilities_idx = UInt16((packed >> 48) & 0xFFFF)
    
    return (player, street, terminal_type, facing_bet, is_terminal, 
            num_children, betting_history_idx, utilities_idx)
end

# --- Conversion Functions ---

"""
    compress_tree(tree::GameTree) -> CompactTree

Convert a regular GameTree to a memory-efficient CompactTree.
"""
function compress_tree(tree::TreeBuilder.GameTree)
    # Initialize pools
    nodes = CompactNode[]
    children_pool = UInt32[]
    betting_histories = String[]
    betting_history_map = Dict{String, UInt32}()
    utilities_pool = Tuple{Float32, Float32}[]
    
    # Reserve space
    sizehint!(nodes, tree.num_nodes)
    sizehint!(children_pool, tree.num_nodes * 2)  # Estimate
    
    # Process nodes in BFS order for better cache locality
    queue = [(tree.root, UInt32(0))]
    node_to_compact_id = Dict{TreeNode.GameNode, UInt32}()
    next_id = UInt32(1)
    
    while !isempty(queue)
        node, parent_id = popfirst!(queue)
        
        # Assign compact ID
        compact_id = next_id
        next_id += 1
        node_to_compact_id[node] = compact_id
        
        # Handle betting history
        if !haskey(betting_history_map, node.betting_history)
            push!(betting_histories, node.betting_history)
            betting_history_map[node.betting_history] = UInt32(length(betting_histories))
        end
        betting_history_idx = betting_history_map[node.betting_history]
        
        # Handle utilities for terminal nodes
        utilities_idx = UInt16(0)
        if node.is_terminal && node.utilities !== nothing
            push!(utilities_pool, node.utilities)
            utilities_idx = UInt16(length(utilities_pool))
        end
        
        # Store children indices
        first_child_idx = UInt32(length(children_pool) + 1)
        num_children = length(node.children)
        
        if num_children > 0
            # Reserve space for children (will be filled later)
            for _ in 1:num_children
                push!(children_pool, UInt32(0))
            end
            
            # Queue children for processing
            for child in node.children
                push!(queue, (child, compact_id))
            end
        else
            first_child_idx = UInt32(0)  # No children
        end
        
        # Pack node info
        packed_info = pack_node_info(
            node.player, node.street, Int(node.terminal_type),
            node.facing_bet, node.is_terminal, num_children,
            betting_history_idx, utilities_idx
        )
        
        # Create compact node
        compact_node = CompactNode(
            compact_id,
            parent_id,
            node.pot,
            UInt32(node.infoset_id),
            packed_info,
            first_child_idx
        )
        
        push!(nodes, compact_node)
    end
    
    # Second pass: fill in children IDs
    for node in tree.nodes
        if !isempty(node.children)
            compact_id = node_to_compact_id[node]
            compact_node = nodes[compact_id]
            
            for (i, child) in enumerate(node.children)
                child_compact_id = node_to_compact_id[child]
                children_pool[compact_node.first_child_idx + i - 1] = child_compact_id
            end
        end
    end
    
    # Calculate memory usage
    memory_used = sizeof(nodes) + sizeof(children_pool) + 
                 sum(sizeof, betting_histories) + sizeof(utilities_pool)
    
    return CompactTree(
        nodes, children_pool, betting_histories, utilities_pool,
        tree.num_nodes, tree.num_player_nodes, tree.num_terminal_nodes,
        tree.num_infosets, memory_used
    )
end

"""
    decompress_tree(compact_tree::CompactTree, params::GameParams) -> GameTree

Convert a CompactTree back to a regular GameTree.
"""
function decompress_tree(compact_tree::CompactTree, params::GameTypes.GameParams)
    # Create mapping from compact ID to GameNode
    id_to_node = Dict{UInt32, TreeNode.GameNode}()
    
    # First pass: create all nodes
    for compact_node in compact_tree.nodes
        # Unpack node info
        (player, street, terminal_type, facing_bet, is_terminal, 
         num_children, betting_history_idx, utilities_idx) = unpack_node_info(compact_node.packed_info)
        
        # Get betting history
        betting_history = compact_tree.betting_histories[betting_history_idx]
        
        # Get utilities if terminal
        utilities = utilities_idx > 0 ? compact_tree.utilities_pool[utilities_idx] : nothing
        
        # Create GameNode
        node = TreeNode.GameNode(
            GameTypes.NodeId(compact_node.id),
            TreeNode.PlayerNode,  # Will be corrected based on is_terminal
            player,
            street,
            compact_node.pot,
            UInt8(terminal_type),
            facing_bet,
            utilities
        )
        
        node.betting_history = betting_history
        node.is_terminal = is_terminal
        node.infoset_id = GameTypes.ISId(compact_node.infoset_id)
        
        id_to_node[compact_node.id] = node
    end
    
    # Second pass: establish parent-child relationships
    for compact_node in compact_tree.nodes
        node = id_to_node[compact_node.id]
        
        # Set parent
        if compact_node.parent_id > 0
            parent = id_to_node[compact_node.parent_id]
            node.parent = parent
        end
        
        # Add children
        (_, _, _, _, _, num_children, _, _) = unpack_node_info(compact_node.packed_info)
        
        if num_children > 0 && compact_node.first_child_idx > 0
            for i in 1:num_children
                child_id = compact_tree.children_pool[compact_node.first_child_idx + i - 1]
                child = id_to_node[child_id]
                push!(node.children, child)
            end
        end
    end
    
    # Create GameTree
    tree = TreeBuilder.GameTree(params)
    tree.root = id_to_node[UInt32(1)]
    tree.num_nodes = compact_tree.num_nodes
    tree.num_player_nodes = compact_tree.num_player_nodes
    tree.num_terminal_nodes = compact_tree.num_terminal_nodes
    tree.num_infosets = compact_tree.num_infosets
    
    # Rebuild node lists
    for node in values(id_to_node)
        push!(tree.nodes, node)
        if !node.is_terminal && TreeNode.is_player_node(node)
            push!(tree.player_nodes, node)
        elseif node.is_terminal
            push!(tree.terminal_nodes, node)
        end
    end
    
    return tree
end

# --- Memory Pool Management ---

"""
    NodePool

A memory pool for efficient node allocation and deallocation.
"""
mutable struct NodePool
    nodes::Vector{TreeNode.GameNode}
    free_indices::Vector{Int}
    allocated::Int
    max_size::Int
end

"""
Create a new node pool with specified maximum size.
"""
function NodePool(max_size::Int = 1_000_000)
    NodePool(TreeNode.GameNode[], Int[], 0, max_size)
end

"""
Allocate a node from the pool.
"""
function allocate_node!(pool::NodePool, args...)
    if !isempty(pool.free_indices)
        # Reuse a freed node
        idx = pop!(pool.free_indices)
        node = TreeNode.GameNode(args...)
        pool.nodes[idx] = node
        return node
    elseif pool.allocated < pool.max_size
        # Allocate new node
        node = TreeNode.GameNode(args...)
        push!(pool.nodes, node)
        pool.allocated += 1
        return node
    else
        error("Node pool exhausted (max size: $(pool.max_size))")
    end
end

"""
Free a node back to the pool.
"""
function free_node!(pool::NodePool, node::TreeNode.GameNode)
    idx = findfirst(n -> n === node, pool.nodes)
    if idx !== nothing
        push!(pool.free_indices, idx)
    end
end

# --- Lazy Tree Construction ---

"""
    LazyTree

A tree that constructs nodes on-demand rather than all at once.
"""
mutable struct LazyTree
    params::GameTypes.GameParams
    root::TreeNode.GameNode
    expansion_depth::Int  # How deep to expand immediately
    max_depth::Int        # Maximum depth to ever expand
    nodes_created::Int
    node_pool::NodePool
end

"""
Create a lazy tree that expands on demand.
"""
function LazyTree(params::GameTypes.GameParams; 
                 expansion_depth::Int = 2, 
                 max_depth::Int = 10)
    pool = NodePool()
    root = allocate_node!(pool,
        GameTypes.NodeId(1),
        TreeNode.PlayerNode,
        UInt8(0),  # SB acts first pre-flop
        TreeNode.Preflop,
        Float32(params.small_blind + params.big_blind),
        0,
        false,
        nothing
    )
    
    tree = LazyTree(params, root, expansion_depth, max_depth, 1, pool)
    
    # Expand initial levels
    expand_to_depth!(tree, root, 0)
    
    return tree
end

"""
Expand a node's children if not already expanded.
"""
function expand_node!(tree::LazyTree, node::TreeNode.GameNode)
    if !isempty(node.children) || node.is_terminal
        return  # Already expanded or terminal
    end
    
    depth = TreeNode.get_node_depth(node)
    if depth >= tree.max_depth
        # Force terminal at max depth
        node.is_terminal = true
        node.terminal_type = 2  # Showdown
        return
    end
    
    # Generate children based on current game state
    if node.street == TreeNode.Preflop
        expand_preflop_node!(tree, node)
    else
        expand_postflop_node!(tree, node)
    end
end

"""
Expand a pre-flop node.
"""
function expand_preflop_node!(tree::LazyTree, node::TreeNode.GameNode)
    # Generate valid actions
    # This is a simplified version - full implementation would use BettingSequence
    
    if node.facing_bet
        # Can fold, call, or raise
        actions = [GameTypes.Fold, GameTypes.Call, GameTypes.BetOrRaise]
    else
        # Can check or bet
        actions = [GameTypes.Check, GameTypes.BetOrRaise]
    end
    
    for action in actions
        child = create_child_node!(tree, node, action)
        TreeNode.add_child!(node, child, action)
    end
end

"""
Expand a post-flop node.
"""
function expand_postflop_node!(tree::LazyTree, node::TreeNode.GameNode)
    # Similar to pre-flop but with different logic
    expand_preflop_node!(tree, node)  # Simplified for now
end

"""
Create a child node based on parent and action.
"""
function create_child_node!(tree::LazyTree, parent::TreeNode.GameNode, action::GameTypes.Action)
    tree.nodes_created += 1
    child_id = GameTypes.NodeId(tree.nodes_created)
    
    # Calculate new game state
    new_pot = TreeNode.calculate_pot_after_action(parent, action, tree.params)
    new_player = parent.player == 0 ? UInt8(1) : UInt8(0)
    new_facing_bet = action == GameTypes.BetOrRaise
    
    # Check if terminal
    is_terminal = action == GameTypes.Fold
    terminal_type = is_terminal ? 1 : 0
    
    child = allocate_node!(tree.node_pool,
        child_id,
        TreeNode.PlayerNode,
        new_player,
        parent.street,
        new_pot,
        terminal_type,
        new_facing_bet,
        nothing
    )
    
    child.parent = parent
    child.is_terminal = is_terminal
    child.betting_history = TreeNode.update_betting_history(parent.betting_history, action)
    
    return child
end

"""
Expand tree to a certain depth from a node.
"""
function expand_to_depth!(tree::LazyTree, node::TreeNode.GameNode, current_depth::Int)
    if current_depth >= tree.expansion_depth || node.is_terminal
        return
    end
    
    expand_node!(tree, node)
    
    for child in node.children
        expand_to_depth!(tree, child, current_depth + 1)
    end
end

# --- Tree Pruning ---

"""
    prune_tree!(tree::GameTree; max_nodes::Int, strategy::Symbol)

Prune a tree to reduce memory usage.
Strategy can be :depth, :random, or :importance.
"""
function prune_tree!(tree::TreeBuilder.GameTree; 
                    max_nodes::Int = 10000,
                    strategy::Symbol = :depth)
    
    if tree.num_nodes <= max_nodes
        return tree  # No pruning needed
    end
    
    if strategy == :depth
        prune_by_depth!(tree, max_nodes)
    elseif strategy == :random
        prune_randomly!(tree, max_nodes)
    elseif strategy == :importance
        prune_by_importance!(tree, max_nodes)
    else
        error("Unknown pruning strategy: $strategy")
    end
    
    # Update tree statistics
    TreeTraversal.update_tree_statistics!(tree, verbose=false)
    
    return tree
end

"""
Prune tree by limiting depth.
"""
function prune_by_depth!(tree::TreeBuilder.GameTree, max_nodes::Int)
    # Binary search for the right depth
    max_depth = TreeNode.get_node_depth(tree.root) + 10  # Reasonable upper bound
    
    for depth in 1:max_depth
        nodes_at_depth = count_nodes_to_depth(tree.root, depth)
        if nodes_at_depth > max_nodes
            # Prune at this depth
            prune_below_depth!(tree.root, depth - 1)
            break
        end
    end
end

"""
Count nodes up to a certain depth.
"""
function count_nodes_to_depth(node::TreeNode.GameNode, max_depth::Int, current_depth::Int = 0)
    if current_depth > max_depth
        return 0
    end
    
    count = 1
    for child in node.children
        count += count_nodes_to_depth(child, max_depth, current_depth + 1)
    end
    
    return count
end

"""
Remove all nodes below a certain depth.
"""
function prune_below_depth!(node::TreeNode.GameNode, max_depth::Int, current_depth::Int = 0)
    if current_depth >= max_depth
        # Make this node terminal
        empty!(node.children)
        if !node.is_terminal
            node.is_terminal = true
            node.terminal_type = 2  # Showdown
        end
        return
    end
    
    for child in node.children
        prune_below_depth!(child, max_depth, current_depth + 1)
    end
end

"""
Prune random nodes to reach target size.
"""
function prune_randomly!(tree::TreeBuilder.GameTree, max_nodes::Int)
    # Not implemented in detail - would randomly remove subtrees
    @warn "Random pruning not fully implemented"
end

"""
Prune based on node importance (e.g., visit frequency).
"""
function prune_by_importance!(tree::TreeBuilder.GameTree, max_nodes::Int)
    # Not implemented in detail - would use CFR visit counts
    @warn "Importance-based pruning not fully implemented"
end

# --- Memory Statistics ---

"""
    memory_stats(tree::GameTree)

Calculate memory usage statistics for a tree.
"""
function memory_stats(tree::TreeBuilder.GameTree)
    # Calculate memory usage
    node_memory = tree.num_nodes * sizeof(TreeNode.GameNode)
    
    # Estimate string memory (betting histories)
    history_memory = 0
    unique_histories = Set{String}()
    for node in tree.nodes
        push!(unique_histories, node.betting_history)
    end
    history_memory = sum(sizeof, unique_histories)
    
    # Children arrays
    children_memory = sum(node -> length(node.children) * sizeof(TreeNode.GameNode), tree.nodes)
    
    total_memory = node_memory + history_memory + children_memory
    
    # Compare with compact representation
    compact = compress_tree(tree)
    compact_memory = compact.memory_used
    
    savings = 1.0 - (compact_memory / total_memory)
    
    return Dict(
        :regular_memory => total_memory,
        :compact_memory => compact_memory,
        :savings_percent => savings * 100,
        :nodes => tree.num_nodes,
        :bytes_per_node => total_memory / tree.num_nodes,
        :compact_bytes_per_node => compact_memory / tree.num_nodes
    )
end

# Export functions
export CompactNode, CompactTree, compress_tree, decompress_tree
export NodePool, allocate_node!, free_node!
export LazyTree, expand_node!, expand_to_depth!
export prune_tree!, prune_by_depth!, prune_randomly!, prune_by_importance!
export memory_stats

end # module
