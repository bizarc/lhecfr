"""
Tests for the ProgressTracker module that provides progress tracking and ETA estimation.
"""

using Test
using LHECFR
using LHECFR.ProgressTracker
using LHECFR.CFR
using LHECFR.GameTypes
using LHECFR.Tree
using Dates

@testset "ProgressTracker Tests" begin
    
    @testset "ProgressConfig Creation" begin
        # Default configuration
        config = ProgressConfig()
        @test config.show_progress_bar == true
        @test config.bar_width == 50
        @test config.update_frequency == 100
        @test config.show_eta == true
        @test config.window_size == 100
        @test config.smoothing_factor == 0.9
        
        # Custom configuration
        config2 = ProgressConfig(
            show_progress_bar = false,
            bar_width = 30,
            update_frequency = 50,
            window_size = 50
        )
        @test config2.show_progress_bar == false
        @test config2.bar_width == 30
        @test config2.update_frequency == 50
        @test config2.window_size == 50
    end
    
    @testset "ETAEstimator" begin
        estimator = ETAEstimator(10, 0.9)
        
        @test estimator.window_size == 10
        @test estimator.smoothing_factor == 0.9
        @test isempty(estimator.iteration_times)
        @test estimator.smoothed_rate == 0.0
        
        # Update with some iteration times
        for i in 1:5
            ProgressTracker.update_eta!(estimator, 0.1)  # 0.1 seconds per iteration
        end
        
        @test length(estimator.iteration_times) == 5
        @test estimator.smoothed_rate > 0
        
        # Test window size limit
        for i in 1:10
            ProgressTracker.update_eta!(estimator, 0.2)
        end
        
        @test length(estimator.iteration_times) == 10  # Should not exceed window size
    end
    
    @testset "Progress State Initialization" begin
        # Create a simple CFR state for testing
        params = GameTypes.GameParams(stack=4)
        tree = Tree.build_game_tree(params, preflop_only=true, verbose=false)
        cfr_config = CFR.CFRConfig(max_iterations=1000, target_exploitability=0.01)
        cfr_state = CFR.CFRState(tree, cfr_config)
        
        # Initialize progress
        config = ProgressConfig(update_frequency=10)
        progress = initialize_progress!(cfr_state, config)
        
        @test progress.current_iteration == 0
        @test progress.total_iterations == 1000
        @test progress.target_exploitability == 0.01
        @test progress.current_exploitability == Inf
        @test progress.config === config
    end
    
    @testset "Progress Updates" begin
        # Create progress state
        params = GameTypes.GameParams(stack=4)
        tree = Tree.build_game_tree(params, preflop_only=true, verbose=false)
        cfr_config = CFR.CFRConfig(max_iterations=100)
        cfr_state = CFR.CFRState(tree, cfr_config)
        
        progress = initialize_progress!(cfr_state, ProgressConfig(update_frequency=10))
        
        # Simulate some iterations
        for i in 1:10
            sleep(0.001)  # Small delay to have measurable time
            update_progress!(progress, i, 1.0 / i)
        end
        
        @test progress.current_iteration == 10
        @test progress.iterations_per_second > 0
        @test progress.average_iteration_time > 0
        @test progress.current_exploitability == 0.1
        @test progress.convergence_rate < 0  # Should be negative (improving)
    end
    
    @testset "Time Estimation" begin
        estimator = ETAEstimator()
        
        # Add consistent iteration times
        for i in 1:10
            ProgressTracker.update_eta!(estimator, 0.1)
        end
        
        # Test time remaining estimation
        eta = estimate_time_remaining(estimator, 10, 100, Inf, 0.01, 0.0)
        
        # Should estimate based on iterations remaining
        @test eta > 0
        @test eta < Inf
        
        # Test with convergence information
        eta2 = estimate_time_remaining(estimator, 50, 100, 0.1, 0.01, -0.1)
        @test eta2 > 0
        @test eta2 < Inf
        
        # Test when already complete
        eta3 = estimate_time_remaining(estimator, 100, 100, 0.01, 0.01, -0.1)
        @test eta3 == 0.0
    end
    
    @testset "Duration Formatting" begin
        # Test various duration formats
        @test format_duration(30.0) == "30s"
        @test format_duration(90.0) == "1m 30s"
        @test format_duration(3661.0) == "1h 1m"
        @test format_duration(90000.0) == "1d 1h"
        
        # Test edge cases
        @test format_duration(0.0) == "0s"
        @test format_duration(59.9) == "60s"
        @test format_duration(3599.9) == "59m 60s"  # Due to rounding
    end
    
    @testset "Progress Display" begin
        # Test should_display logic
        config = ProgressConfig(update_frequency=10)
        progress = ProgressState(
            0, 100, time(), time(),
            0.0, 0.0,
            Inf, 0.01, 0.0,
            0.0, 0.0,
            ETAEstimator(), Inf, now(),
            0, config
        )
        
        # Should display first iteration
        @test ProgressTracker.should_display(progress, 1) == true
        
        # Should display last iteration
        @test ProgressTracker.should_display(progress, 100) == true
        
        # Should display at update frequency
        progress.last_display_iteration = 5
        @test ProgressTracker.should_display(progress, 15) == true
        @test ProgressTracker.should_display(progress, 10) == false
        @test ProgressTracker.should_display(progress, 14) == false
    end
    
    @testset "Progress Statistics" begin
        # Create a progress state with some data
        config = ProgressConfig()
        progress = ProgressState(
            50, 100, time() - 10.0, time(),
            5.0, 0.2,
            0.05, 0.01, -0.1,
            100.0, 150.0,
            ETAEstimator(), 10.0, now() + Second(10),
            40, config
        )
        
        stats = get_progress_stats(progress)
        
        @test stats["current_iteration"] == 50
        @test stats["total_iterations"] == 100
        @test stats["percentage_complete"] == 50.0
        @test stats["iterations_per_second"] == 5.0
        @test stats["current_exploitability"] == 0.05
        @test stats["convergence_rate"] == -0.1
        @test stats["estimated_time_remaining"] == 10.0
        @test stats["current_memory_mb"] == 100.0
        @test stats["peak_memory_mb"] == 150.0
    end
    
    @testset "Progress Bar Generation" begin
        config = ProgressConfig(bar_width=20, show_progress_bar=true)
        progress = ProgressState(
            25, 100, time(), time(),
            0.0, 0.0,
            Inf, 0.01, 0.0,
            0.0, 0.0,
            ETAEstimator(), Inf, now(),
            0, config
        )
        
        # Capture output
        io = IOBuffer()
        ProgressTracker.print_progress(progress, io=io)
        output = String(take!(io))
        
        # Check that output contains expected elements
        @test occursin("25/100", output)
        @test occursin("25.0%", output)
        @test occursin("[", output)  # Progress bar starts
        @test occursin("]", output)  # Progress bar ends
    end
    
    @testset "Memory Statistics" begin
        config = ProgressConfig()
        progress = ProgressState(
            0, 100, time(), time(),
            0.0, 0.0,
            Inf, 0.01, 0.0,
            0.0, 0.0,
            ETAEstimator(), Inf, now(),
            0, config
        )
        
        # Update memory stats
        ProgressTracker.update_memory_stats!(progress)
        
        # Should have some memory usage recorded
        @test progress.current_memory_mb > 0
        @test progress.peak_memory_mb >= progress.current_memory_mb
    end
    
    @testset "Final Summary" begin
        config = ProgressConfig()
        progress = ProgressState(
            100, 100, time() - 60.0, time(),
            1.67, 0.6,
            0.008, 0.01, -0.05,
            120.0, 150.0,
            ETAEstimator(), 0.0, now(),
            100, config
        )
        
        # Capture output
        io = IOBuffer()
        ProgressTracker.print_final_summary(progress, io=io)
        output = String(take!(io))
        
        # Check summary contains key information
        @test occursin("CFR Solver Complete!", output)
        @test occursin("Total iterations: 100", output)
        @test occursin("Final exploitability: 0.008", output)
        @test occursin("Target exploitability reached!", output)
        @test occursin("Peak memory usage: 150.0 MB", output)
    end
end
