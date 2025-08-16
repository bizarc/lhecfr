module CFR
using ..GameTypes
using ..Tree

# Storage for regrets and strategy sums (CFR+)
struct CFRState
    # Arrays indexed by infoset id and action
    regrets::Vector{Float32}
    strategy_sum::Vector{Float32}
    num_actions::Int
end

function init_state(gt::Tree.GameTree; num_actions=3)
    # For a real implementation, size these arrays to (#infosets * #actions).
    CFRState(zeros(Float32, 10*num_actions), zeros(Float32, 10*num_actions), num_actions)
end

# Compute current strategy from regrets (CFR+)
function strategy_from_regrets!(out::Vector{Float32}, regrets::Vector{Float32}, num_actions::Int)
    # Toy: uniform policy
    fill!(out, 1/num_actions)
    return out
end

function train!(gt::Tree.GameTree, st::CFRState; iterations=1000, plus=true, verbose=true)
    tmp = zeros(Float32, st.num_actions)
    for it in 1:iterations
        # TODO: traverse game tree for both players, update regrets & strategy_sum
        # This is a stub loop to show structure.
        strategy_from_regrets!(tmp, st.regrets, st.num_actions)
        st.strategy_sum .+= tmp
        if verbose && (it % max(1, iterations ÷ 10) == 0)
            println("Iter ", it, "/", iterations)
        end
    end
    return st
end

end # module
