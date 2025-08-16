"""
    TreeNode

Module containing node structures and basic operations for the game tree.
"""
module TreeNode

using ..GameTypes

# --- Node Types ---
@enum NodeType::UInt8 begin
    ChanceNode = 0    # Dealing cards
    PlayerNode = 1    # Player decision point
    TerminalNode = 2  # Game end (showdown or fold)
end

@enum Street::UInt8 begin
    Preflop = 0
    Flop = 1
    Turn = 2
    River = 3
end

# --- Game Node Structure ---
"""
    GameNode
    
Represents a single node in the game tree for Limit Hold'em.
Supports both player decision nodes and chance/terminal nodes.
"""
mutable struct GameNode
    # Node identification
    id::GameTypes.NodeId              # Unique node identifier
    node_type::NodeType               # Type of node (chance/player/terminal)
    
    # Game state
    player::UInt8                     # Player to act (0=SB/BTN, 1=BB, 255=chance/terminal)
    street::Street                    # Current betting round
    pot::Float32                      # Current pot size in big blinds
    
    # Betting state
    raises_this_street::UInt8        # Number of raises on current street
    facing_bet::Bool                  # Is the player facing a bet?
    last_aggressor::UInt8             # Player who made last aggressive action
    
    # Tree structure
    parent::Union{GameNode, Nothing}  # Parent node
    children::Vector{GameNode}        # Child nodes
    action_to_child::Dict{GameTypes.Action, Int}  # Map action to child index
    
    # History
    action_history::Vector{GameTypes.Action}  # Actions taken to reach this node
    betting_history::String           # Compact betting history representation
    
    # Information set
    infoset_id::GameTypes.ISId       # Information set identifier (0 if not assigned)
    
    # Terminal node data
    is_terminal::Bool                 # Is this a terminal node?
    utilities::Union{Nothing, Tuple{Float32, Float32}}  # Utilities for (P1, P2) if terminal
    terminal_type::UInt8             # 0=not terminal, 1=fold, 2=showdown
    
    # CFR-related (will be populated during solving)
    reach_probability::Float32       # Product of probabilities to reach this node
    
    # Constructor for non-terminal nodes
    function GameNode(
        id::Int,
        node_type::NodeType,
        player::UInt8,
        street::Street,
        pot::Float32,
        raises_this_street::UInt8,
        facing_bet::Bool,
        parent::Union{GameNode, Nothing} = nothing
    )
        node = new(
            id,
            node_type,
            player,
            street,
            pot,
            raises_this_street,
            facing_bet,
            player,  # last_aggressor defaults to current player
            parent,
            GameNode[],  # empty children
            Dict{GameTypes.Action, Int}(),
            GameTypes.Action[],
            "",  # betting history will be computed
            0,   # infoset_id will be assigned later
            false,  # not terminal
            nothing,  # no utilities
            0,  # not terminal
            1.0f0  # initial reach probability
        )
        return node
    end
    
    # Constructor for terminal nodes
    function GameNode(
        id::Int,
        street::Street,
        pot::Float32,
        utilities::Tuple{Float32, Float32},
        terminal_type::UInt8,
        parent::Union{GameNode, Nothing} = nothing
    )
        node = new(
            id,
            TerminalNode,
            255,  # no player to act
            street,
            pot,
            0,  # raises_this_street
            false,  # facing_bet
            255,  # no last aggressor
            parent,
            GameNode[],  # no children
            Dict{GameTypes.Action, Int}(),
            GameTypes.Action[],
            "",  # betting history
            0,   # infoset_id
            true,  # is terminal
            utilities,
            terminal_type,
            1.0f0
        )
        return node
    end
end

# Custom show method to prevent stack overflow when printing
Base.show(io::IO, node::GameNode) = print(io, "GameNode(id=$(node.id), player=$(node.player), pot=$(node.pot), terminal=$(node.is_terminal))")

# --- Helper Functions ---

"""
    add_child!(parent::GameNode, child::GameNode, action::GameTypes.Action)
    
Add a child node to a parent node with the associated action.
"""
function add_child!(parent::GameNode, child::GameNode, action::GameTypes.Action)
    push!(parent.children, child)
    parent.action_to_child[action] = length(parent.children)
    child.parent = parent
    
    # Update child's action history
    child.action_history = copy(parent.action_history)
    push!(child.action_history, action)
    
    # Update betting history string
    child.betting_history = update_betting_history(parent.betting_history, action)
    
    return child
end

"""
    update_betting_history(history::String, action::GameTypes.Action)
    
Update betting history string with compact notation.
Uses standard poker notation: f=fold, c=call/check, r=raise/bet
"""
function update_betting_history(history::String, action::GameTypes.Action)
    action_char = if action == GameTypes.Fold
        "f"
    elseif action == GameTypes.Call || action == GameTypes.Check
        "c"
    elseif action == GameTypes.BetOrRaise
        "r"
    else
        "?"
    end
    return history * action_char
end

"""
    get_valid_actions(node::GameNode, params::GameTypes.GameParams)
    
Return valid actions at a given node based on game rules.
"""
function get_valid_actions(node::GameNode, params::GameTypes.GameParams)
    if node.is_terminal || node.node_type == ChanceNode
        return GameTypes.Action[]
    end
    
    actions = GameTypes.Action[]
    
    if node.facing_bet
        # Can fold or call
        push!(actions, GameTypes.Fold)
        push!(actions, GameTypes.Call)
        
        # Can raise if not at cap
        if node.raises_this_street < params.max_raises_per_street
            push!(actions, GameTypes.BetOrRaise)
        end
    else
        # Can check
        push!(actions, GameTypes.Check)
        
        # Can bet if not at cap
        if node.raises_this_street < params.max_raises_per_street
            push!(actions, GameTypes.BetOrRaise)
        end
    end
    
    return actions
end

"""
    is_player_node(node::GameNode)
    
Check if a node is a player decision node.
"""
is_player_node(node::GameNode) = node.node_type == PlayerNode && !node.is_terminal

"""
    is_chance_node(node::GameNode)
    
Check if a node is a chance node (card dealing).
"""
is_chance_node(node::GameNode) = node.node_type == ChanceNode

"""
    is_terminal_node(node::GameNode)
    
Check if a node is a terminal node.
"""
is_terminal_node(node::GameNode) = node.is_terminal

"""
    get_current_player(node::GameNode)
    
Get the player to act at this node (0=SB/BTN, 1=BB).
"""
get_current_player(node::GameNode) = node.player

"""
    calculate_pot_after_action(node::GameNode, action::GameTypes.Action, params::GameTypes.GameParams)
    
Calculate the pot size after an action is taken.
"""
function calculate_pot_after_action(node::GameNode, action::GameTypes.Action, params::GameTypes.GameParams)
    pot = node.pot
    
    if action == GameTypes.Call
        # In LHE, call amount depends on street and current bet
        bet_size = get_bet_size(node.street, params)
        if node.facing_bet
            pot += bet_size
        end
    elseif action == GameTypes.BetOrRaise
        # Add bet/raise amount
        bet_size = get_bet_size(node.street, params)
        pot += bet_size * (node.facing_bet ? 2 : 1)  # Raise is 2x bet, bet is 1x
    end
    # Fold and Check don't change pot
    
    return pot
end

"""
    get_bet_size(street::Street, params::GameTypes.GameParams)
    
Get the bet size for a given street in Limit Hold'em.
Pre-flop and flop use small bets (1 BB), turn and river use big bets (2 BB).
"""
function get_bet_size(street::Street, params::GameTypes.GameParams)
    if street == Preflop || street == Flop
        return Float32(params.big_blind)  # Small bet = 1 BB
    else
        return Float32(2 * params.big_blind)  # Big bet = 2 BB
    end
end

"""
    get_node_depth(node::GameNode)
    
Get the depth of a node in the tree (root has depth 0).
"""
function get_node_depth(node::GameNode)
    depth = 0
    current = node
    while current.parent !== nothing
        depth += 1
        current = current.parent
    end
    return depth
end

# Export all types and functions
export NodeType, ChanceNode, PlayerNode, TerminalNode
export Street, Preflop, Flop, Turn, River
export GameNode
export add_child!, update_betting_history, get_valid_actions
export is_player_node, is_chance_node, is_terminal_node
export get_current_player, calculate_pot_after_action, get_bet_size
export get_node_depth

end # module
