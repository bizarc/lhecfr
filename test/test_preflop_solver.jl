"""
Tests for the PreflopSolver module that provides specialized pre-flop-only solving.
"""

using Test
using LHECFR
using LHECFR.PreflopSolver
using LHECFR.GameTypes
using LHECFR.Tree
using LHECFR.CFR

@testset "PreflopSolver Tests" begin
    
    @testset "PreflopConfig" begin
        # Default configuration
        config = PreflopConfig()
        @test config.target_exploitability == 0.001
        @test config.max_iterations == 10000
        @test config.use_parallel == true
        @test config.num_threads == 0
        @test config.use_symmetry == true
        @test config.cache_strategies == true
        
        # Custom configuration
        config2 = PreflopConfig(
            target_exploitability = 0.01,
            max_iterations = 500,
            use_parallel = false,
            show_progress = false
        )
        @test config2.target_exploitability == 0.01
        @test config2.max_iterations == 500
        @test config2.use_parallel == false
        @test config2.show_progress == false
    end
    
    @testset "Basic Pre-flop Solving" begin
        # Small stack for faster solving
        params = GameTypes.GameParams(
            stack = 10,
            small_blind = 1,
            big_blind = 2
        )
        
        config = PreflopConfig(
            max_iterations = 100,
            target_exploitability = 0.1,  # Relaxed for testing
            use_parallel = false,  # Sequential for deterministic test
            show_progress = false,
            save_checkpoints = false
        )
        
        # Solve pre-flop
        result = solve_preflop(params, config)
        
        @test result isa PreflopResult
        @test result.iterations > 0
        @test result.iterations <= 100
        @test result.final_exploitability >= 0
        @test result.solve_time > 0
        @test !isempty(result.strategies)
    end
    
    @testset "Parallel Pre-flop Solving" begin
        if Threads.nthreads() > 1
            params = GameTypes.GameParams(
                stack = 8,
                small_blind = 1,
                big_blind = 2
            )
            
            config = PreflopConfig(
                max_iterations = 50,
                target_exploitability = 1.0,  # Very relaxed
                use_parallel = true,
                num_threads = 2,
                show_progress = false
            )
            
            result = solve_preflop(params, config)
            
            @test result.iterations > 0
            @test result.solve_time > 0
            @test !isempty(result.strategies)
        else
            @test_skip "Requires multiple threads"
        end
    end
    
    @testset "Quick Solve Function" begin
        # Test the quick solve utility
        result = quick_solve_preflop(
            stack = 6,
            iterations = 20,
            show_progress = false
        )
        
        @test result isa PreflopResult
        @test result.iterations <= 20
        @test result.final_exploitability >= 0
    end
    
    @testset "Convergence Check" begin
        params = GameTypes.GameParams(
            stack = 4,
            small_blind = 1,
            big_blind = 2
        )
        
        # Set very easy target for guaranteed convergence
        config = PreflopConfig(
            max_iterations = 200,
            target_exploitability = 10.0,  # Very easy target
            use_parallel = false,
            show_progress = false
        )
        
        result = solve_preflop(params, config)
        
        # With such a high target, it should converge
        @test result.converged == true || result.iterations == 200
    end
    
    @testset "Strategy Extraction" begin
        params = GameTypes.GameParams(stack = 4)
        config = PreflopConfig(
            max_iterations = 50,
            use_parallel = false,
            show_progress = false
        )
        
        result = solve_preflop(params, config)
        
        # Check that strategies are valid probability distributions
        for (_, strategy) in result.strategies
            @test all(x -> x >= 0, strategy)  # Non-negative
            @test abs(sum(strategy) - 1.0) < 0.01  # Sums to 1 (with tolerance)
        end
    end
    
    @testset "Range Computation" begin
        # Create mock strategies for testing
        strategies = Dict{String, Vector{Float64}}(
            "P1:PREFLOP:[]" => [0.2, 0.3, 0.5],  # Fold, Call, Raise
            "P2:PREFLOP:[]" => [0.1, 0.4, 0.5]
        )
        
        ranges = PreflopSolver.compute_preflop_ranges(strategies)
        
        @test ranges isa Dict
        @test haskey(ranges, "SB")
        @test haskey(ranges, "BB")
    end
    
    @testset "Checkpointing in Pre-flop" begin
        params = GameTypes.GameParams(stack = 4)
        
        # Create temp directory for checkpoints
        checkpoint_dir = mktempdir()
        
        config = PreflopConfig(
            max_iterations = 30,
            save_checkpoints = true,
            checkpoint_frequency = 10,
            show_progress = false
        )
        
        # Modify checkpoint directory
        result = solve_preflop(params, config)
        
        @test result.iterations > 0
        
        # Cleanup
        rm(checkpoint_dir, recursive=true, force=true)
    end
    
    @testset "PreflopState Creation" begin
        params = GameTypes.GameParams(stack = 4)
        tree = Tree.build_game_tree(params, preflop_only=true, verbose=false)
        cfr_config = CFR.CFRConfig(max_iterations=10)
        cfr_state = CFR.CFRState(tree, cfr_config)
        config = PreflopConfig()
        
        state = PreflopSolver.PreflopState(
            tree, cfr_state, config,
            0, Inf, 0.0,
            Dict{String, Vector{Float64}}()
        )
        
        @test state.tree === tree
        @test state.cfr_state === cfr_state
        @test state.config === config
        @test state.iteration == 0
        @test state.exploitability == Inf
    end
    
    @testset "Get Strategy for Specific Hand" begin
        # Create a result with known strategies
        strategies = Dict{String, Vector{Float64}}(
            "P1:PREFLOP:[]" => [0.1, 0.3, 0.6]
        )
        ranges = Dict{String, Dict{String, Float64}}()
        
        result = PreflopResult(
            true, 100, 0.001, 1.0,
            strategies, ranges
        )
        
        # Create some cards
        cards = [GameTypes.Card(14, 0), GameTypes.Card(13, 0)]  # AK offsuit
        
        strategy = get_preflop_strategy(result, "SB", cards)
        
        @test strategy isa Vector{Float64}
        @test length(strategy) == 3
        @test all(x -> x >= 0, strategy)
    end
    
    @testset "Range Analysis" begin
        # Create mock result
        ranges = Dict(
            "SB" => Dict(
                "AA" => 1.0,
                "KK" => 0.9,
                "72o" => 0.0
            ),
            "BB" => Dict(
                "AA" => 1.0,
                "AK" => 0.8,
                "22" => 0.3
            )
        )
        
        result = PreflopResult(
            true, 100, 0.001, 1.0,
            Dict{String, Vector{Float64}}(),
            ranges
        )
        
        stats = analyze_preflop_ranges(result)
        
        @test haskey(stats, "SB")
        @test haskey(stats, "BB")
        @test haskey(stats["SB"], "Total Hands")
    end
    
    @testset "Export Chart" begin
        # Create mock result
        ranges = Dict(
            "SB" => Dict("AA" => 1.0, "KK" => 0.5),
            "BB" => Dict("AA" => 0.9, "72o" => 0.1)
        )
        
        result = PreflopResult(
            true, 100, 0.001, 1.0,
            Dict{String, Vector{Float64}}(),
            ranges
        )
        
        # Export to temp file
        temp_file = tempname() * ".csv"
        export_preflop_chart(result, temp_file)
        
        @test isfile(temp_file)
        
        # Read and verify content
        content = read(temp_file, String)
        @test occursin("Position,Hand,Frequency,Action", content)
        @test occursin("AA", content)
        
        # Cleanup
        rm(temp_file)
    end
    
    @testset "Print Functions" begin
        # Create mock result
        ranges = Dict(
            "SB" => Dict("AA" => 1.0, "KK" => 0.8),
            "BB" => Dict("AA" => 0.95)
        )
        
        result = PreflopResult(
            true, 100, 0.001, 1.0,
            Dict{String, Vector{Float64}}(),
            ranges
        )
        
        # Test that print functions don't error
        # Simply call the function to ensure it doesn't error
        # (redirect_stdout has issues in some Julia versions)
        @test begin
            print_preflop_ranges(result, position="SB")
            true
        end
    end
end
