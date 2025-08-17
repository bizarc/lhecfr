using Test
using LHECFR
using LHECFR.CFR
using LHECFR.CFRTraversal
using LHECFR.CFRMetrics
using LHECFR.Tree
using LHECFR.GameTypes

@testset "CFR Metrics Tests" begin
    
    @testset "ConvergenceMetrics Creation" begin
        metrics = CFRMetrics.ConvergenceMetrics()
        @test metrics.iteration == 0
        @test metrics.exploitability == 0.0
        @test metrics.avg_strategy_change == 0.0
        @test metrics.total_regret == 0.0
        @test isempty(metrics.exploitability_history)
        @test isempty(metrics.strategy_change_history)
    end
    
    @testset "LogConfig Creation" begin
        # Test default config
        config = CFRMetrics.LogConfig()
        @test config.verbose == true
        @test config.log_frequency == 100
        @test config.log_file === nothing
        @test config.track_strategies == true
        @test config.track_regrets == true
        
        # Test custom config
        config = CFRMetrics.LogConfig(
            verbose=false,
            log_frequency=50,
            log_file="test.log",
            track_strategies=false
        )
        @test config.verbose == false
        @test config.log_frequency == 50
        @test config.log_file == "test.log"
        @test config.track_strategies == false
    end
    
    @testset "Strategy Metrics Calculation" begin
        params = GameTypes.GameParams(stack=4, big_blind=2, small_blind=1)
        tree = Tree.build_game_tree(params, preflop_only=true, verbose=false)
        
        config = CFR.CFRConfig(max_iterations=10)
        state = CFR.CFRState(tree, config)
        
        # Run a few iterations to populate infosets
        CFRTraversal.train!(tree, state, iterations=10, verbose=false)
        
        # Calculate strategy metrics
        prev_strategies = Dict{String, Vector{Float64}}()
        for (id, cfr_infoset) in state.storage.infosets
            prev_strategies[id] = copy(Tree.get_average_strategy(cfr_infoset))
        end
        
        avg_change, max_change, entropy = CFRMetrics.calculate_strategy_metrics(state, prev_strategies)
        
        # Strategies should be mostly unchanged (same vs same)
        @test avg_change >= 0.0
        @test max_change >= 0.0
        @test entropy >= 0.0  # Entropy should be non-negative
    end
    
    @testset "Regret Metrics Calculation" begin
        params = GameTypes.GameParams(stack=4, big_blind=2, small_blind=1)
        tree = Tree.build_game_tree(params, preflop_only=true, verbose=false)
        
        config = CFR.CFRConfig(max_iterations=10)
        state = CFR.CFRState(tree, config)
        
        # Run iterations to accumulate regrets
        CFRTraversal.train!(tree, state, iterations=10, verbose=false)
        
        total_regret, avg_regret, max_regret = CFRMetrics.calculate_regret_metrics(state)
        
        @test total_regret >= 0.0
        @test avg_regret >= 0.0
        @test max_regret >= 0.0
        @test max_regret >= avg_regret  # Max should be at least average
    end
    
    @testset "Metrics Update" begin
        params = GameTypes.GameParams(stack=4, big_blind=2, small_blind=1)
        tree = Tree.build_game_tree(params, preflop_only=true, verbose=false)
        
        config = CFR.CFRConfig(max_iterations=5)
        state = CFR.CFRState(tree, config)
        
        metrics = CFRMetrics.ConvergenceMetrics()
        prev_strategies = Dict{String, Vector{Float64}}()
        
        # Run one iteration
        CFRTraversal.train!(tree, state, iterations=1, verbose=false)
        
        # Update metrics
        CFRMetrics.update_metrics!(metrics, state, 0.1, prev_strategies)
        
        @test metrics.iteration == state.iteration
        @test metrics.time_elapsed == 0.1
        @test length(metrics.exploitability_history) == 1
        @test metrics.infosets_visited > 0
    end
    
    @testset "Convergence Rate Calculation" begin
        metrics = CFRMetrics.ConvergenceMetrics()
        
        # Add some exploitability history (simulated decreasing)
        for i in 1:10
            push!(metrics.exploitability_history, 10.0 / i)
        end
        
        rate = CFRMetrics.get_convergence_rate(metrics)
        @test rate > 0  # Should be positive for decreasing exploitability
    end
    
    @testset "Strategy Stability Calculation" begin
        metrics = CFRMetrics.ConvergenceMetrics()
        
        # Add strategy change history
        for i in 1:20
            push!(metrics.strategy_change_history, 0.1 / i)  # Decreasing changes
        end
        
        stability = CFRMetrics.get_strategy_stability(metrics, 5)
        @test stability >= 0.0 && stability <= 1.0
        
        # Later iterations should be more stable
        stability_early = CFRMetrics.get_strategy_stability(metrics, 20)
        stability_late = CFRMetrics.get_strategy_stability(metrics, 5)
        @test stability_late >= stability_early
    end
    
    @testset "Training with Metrics Logging" begin
        params = GameTypes.GameParams(stack=4, big_blind=2, small_blind=1)
        tree = Tree.build_game_tree(params, preflop_only=true, verbose=false)
        
        # Create temp log file
        log_file = tempname() * ".log"
        
        log_config = CFRMetrics.LogConfig(
            verbose=false,
            log_frequency=5,
            log_file=log_file,
            track_strategies=true,
            track_regrets=true
        )
        
        config = CFR.CFRConfig(max_iterations=20, check_frequency=5)
        state = CFR.CFRState(tree, config)
        
        # Train with metrics
        CFRTraversal.train!(tree, state, verbose=false, log_config=log_config)
        
        # Check that metrics were tracked
        @test state.metrics !== nothing
        @test state.metrics isa CFRMetrics.ConvergenceMetrics
        @test state.metrics.iteration == 20
        @test length(state.metrics.exploitability_history) > 0
        
        # Check that log file was created
        @test isfile(log_file)
        
        # Check that metrics CSV was created
        metrics_file = replace(log_file, ".log" => "_metrics.csv")
        @test isfile(metrics_file)
        
        # Clean up temp files
        rm(log_file, force=true)
        rm(metrics_file, force=true)
    end
    
    @testset "Metrics Export" begin
        metrics = CFRMetrics.ConvergenceMetrics()
        
        # Add some data
        for i in 1:5
            push!(metrics.exploitability_history, 10.0 / i)
            push!(metrics.strategy_change_history, 0.1 / i)
            push!(metrics.regret_history, 100.0 / i)
            push!(metrics.time_history, 0.1 * i)
        end
        
        # Export to temp file
        export_file = tempname() * ".csv"
        CFRMetrics.export_metrics(metrics, export_file)
        
        # Check file was created
        @test isfile(export_file)
        
        # Read and verify content
        lines = readlines(export_file)
        @test length(lines) == 6  # Header + 5 data lines
        @test occursin("iteration,exploitability,strategy_change", lines[1])
        
        # Clean up
        rm(export_file, force=true)
    end
end

# Run the tests
println("\n=== Running CFR Metrics Tests ===")
