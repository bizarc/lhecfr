module LHECFR

include("GameTypes.jl")
include("Deck.jl")
include("Evaluator.jl")
include("Tree.jl")
include("CFR.jl")
include("CFRMetrics.jl")
include("CFRTraversal.jl")
include("ThreadedCFR.jl")
include("SolverConfig.jl")
include("ProgressTracker.jl")
include("Checkpoint.jl")
include("PreflopSolver.jl")
include("BestResponse.jl")
include("Persist.jl")
include("CLI.jl")

using .GameTypes
using .Deck
using .Evaluator
using .Tree
using .CFR
using .CFRMetrics
using .CFRTraversal
using .ThreadedCFR
using .SolverConfig
using .ProgressTracker
using .Checkpoint
using .PreflopSolver
using .BestResponse
using .Persist
using .CLI
using Random

export run_demo

function run_demo(; iterations=1000, seed=42)
    println("LHE CFR demo starting… (iterations=$(iterations))")
    Random.seed!(seed)
    params = GameTypes.GameParams()  # default heads-up LHE
    gt = Tree.build_game_tree(params, preflop_only=true, verbose=false)
    
    # Create CFR configuration and state (with indexing for performance)
    config = CFR.CFRConfig(use_cfr_plus=true)
    cfr_state = CFR.CFRState(gt, config, true)  # Enable indexing for better performance
    
    # Train the solver
    CFRTraversal.train!(gt, cfr_state; iterations=iterations, verbose=true)
    
    # TODO: Calculate actual exploitability once BestResponse is implemented
    # br = BestResponse.exploitability(gt, cfr_state)
    # println("Estimated exploitability (bb/100 approximation): ", br)
    
    println("Training complete. Information sets: $(CFR.get_infoset_count(cfr_state))")
    
    return cfr_state
end

end # module
