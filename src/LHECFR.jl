module LHECFR

include("GameTypes.jl")
include("Deck.jl")
include("Evaluator.jl")
include("Tree.jl")
include("CFR.jl")
include("BestResponse.jl")
include("Persist.jl")
include("CLI.jl")

using .GameTypes
using .Deck
using .Evaluator
using .Tree
using .CFR
using .BestResponse
using .Persist
using .CLI

export run_demo

function run_demo(; iterations=1000, seed=42)
    println("LHE CFR demo starting… (iterations=$(iterations))")
    Random.seed!(seed)
    params = GameTypes.GameParams()  # default heads-up LHE
    gt = Tree.build_game_tree(params)
    cfr_state = CFR.init_state(gt)
    CFR.train!(gt, cfr_state; iterations=iterations, plus=true, verbose=true)
    br = BestResponse.exploitability(gt, cfr_state.avg_strategy)
    println("Estimated exploitability (bb/100 approximation): ", br)
    return br
end

end # module
