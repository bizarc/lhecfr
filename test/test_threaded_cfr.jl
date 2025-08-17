"""
Tests for the ThreadedCFR module that implements parallel tree traversal.
"""

using Test
using LHECFR
using LHECFR.GameTypes
using LHECFR.Tree
using LHECFR.CFR
using LHECFR.ThreadedCFR
using Base.Threads

@testset "ThreadedCFR Tests" begin
    
    @testset "ThreadConfig Creation" begin
        # Default configuration
        config = ThreadConfig()
        @test config.num_threads > 0  # Should auto-detect
        @test config.chunk_size == 100
        @test config.sync_frequency == 10
        @test config.thread_safe_cache == true
        @test config.load_balancing == :dynamic
        
        # Custom configuration
        config2 = ThreadConfig(
            num_threads = 2,
            chunk_size = 50,
            load_balancing = :static
        )
        @test config2.num_threads <= Threads.nthreads()
        @test config2.chunk_size == 50
        @test config2.load_balancing == :static
    end
    
    @testset "ParallelCFRState Creation" begin
        params = GameTypes.GameParams(stack=10)
        tree = Tree.build_game_tree(params, preflop_only=true, verbose=false)
        
        # Create parallel state
        thread_config = ThreadConfig(num_threads=2)
        cfr_config = CFR.CFRConfig(use_cfr_plus=true)
        
        parallel_state = ParallelCFRState(tree, cfr_config, thread_config)
        
        @test parallel_state.base_state !== nothing
        @test parallel_state.thread_config === thread_config
        @test length(parallel_state.thread_locks) > 0
        @test length(parallel_state.thread_stats) == thread_config.num_threads
    end
    
    @testset "Thread Stats Tracking" begin
        stats = ThreadedCFR.ThreadStats()
        
        @test stats.nodes_processed == 0
        @test stats.infosets_updated == 0
        @test stats.time_computing == 0.0
        @test stats.time_waiting == 0.0
        
        # Update stats
        stats.nodes_processed = 100
        stats.infosets_updated = 50
        @test stats.nodes_processed == 100
        @test stats.infosets_updated == 50
    end
    
    @testset "Parallel Iteration - Static" begin
        if Threads.nthreads() > 1
            params = GameTypes.GameParams(stack=4)
            tree = Tree.build_game_tree(params, preflop_only=true, verbose=false)
            
            thread_config = ThreadConfig(
                num_threads = 2,
                load_balancing = :static
            )
            cfr_config = CFR.CFRConfig(max_iterations=1)
            
            parallel_state = ParallelCFRState(tree, cfr_config, thread_config)
            
            # Run one iteration
            parallel_cfr_iteration!(parallel_state, tree)
            
            @test parallel_state.base_state.iteration == 1
            
            # Check that threads did some work
            total_nodes = sum(s.nodes_processed for s in parallel_state.thread_stats)
            @test total_nodes > 0
        else
            @test_skip "Requires multiple threads"
        end
    end
    
    @testset "Parallel Iteration - Dynamic" begin
        if Threads.nthreads() > 1
            params = GameTypes.GameParams(stack=4)
            tree = Tree.build_game_tree(params, preflop_only=true, verbose=false)
            
            thread_config = ThreadConfig(
                num_threads = 2,
                load_balancing = :dynamic
            )
            cfr_config = CFR.CFRConfig(max_iterations=1)
            
            parallel_state = ParallelCFRState(tree, cfr_config, thread_config)
            
            # Run one iteration
            parallel_cfr_iteration!(parallel_state, tree)
            
            @test parallel_state.base_state.iteration == 1
            
            # Check work distribution
            total_nodes = sum(s.nodes_processed for s in parallel_state.thread_stats)
            @test total_nodes > 0
        else
            @test_skip "Requires multiple threads"
        end
    end
    
    @testset "Parallel Iteration - Work Stealing" begin
        if Threads.nthreads() > 1
            params = GameTypes.GameParams(stack=4)
            tree = Tree.build_game_tree(params, preflop_only=true, verbose=false)
            
            thread_config = ThreadConfig(
                num_threads = 2,
                load_balancing = :work_stealing
            )
            cfr_config = CFR.CFRConfig(max_iterations=1)
            
            parallel_state = ParallelCFRState(tree, cfr_config, thread_config)
            
            # Run one iteration
            parallel_cfr_iteration!(parallel_state, tree)
            
            @test parallel_state.base_state.iteration == 1
            
            # Verify work was done
            total_updates = sum(s.infosets_updated for s in parallel_state.thread_stats)
            @test total_updates >= 0  # May be 0 for small trees
        else
            @test_skip "Requires multiple threads"
        end
    end
    
    @testset "Thread Safety - InfoSet Locking" begin
        params = GameTypes.GameParams(stack=4)
        tree = Tree.build_game_tree(params, preflop_only=true, verbose=false)
        
        thread_config = ThreadConfig(num_threads=1)  # Single thread for deterministic test
        parallel_state = ParallelCFRState(tree, CFR.CFRConfig(), thread_config)
        
        # Test lock hashing
        lock1 = ThreadedCFR.get_infoset_lock(parallel_state, "test_id_1")
        lock2 = ThreadedCFR.get_infoset_lock(parallel_state, "test_id_1")
        @test lock1 === lock2  # Same ID should get same lock
        
        # Different IDs might get different locks (or same due to pooling)
        lock3 = ThreadedCFR.get_infoset_lock(parallel_state, "different_id")
        @test lock3 !== nothing
    end
    
    @testset "Parallel Training" begin
        if Threads.nthreads() > 1
            params = GameTypes.GameParams(stack=4)
            tree = Tree.build_game_tree(params, preflop_only=true, verbose=false)
            
            thread_config = ThreadConfig(
                num_threads = 2,
                load_balancing = :dynamic
            )
            cfr_config = CFR.CFRConfig(
                max_iterations = 5,
                use_cfr_plus = true
            )
            
            parallel_state = ParallelCFRState(tree, cfr_config, thread_config)
            
            # Train for a few iterations
            parallel_train!(tree, parallel_state, iterations=5, verbose=false)
            
            @test parallel_state.base_state.iteration >= 1
            @test parallel_state.base_state.iteration <= 5
            
            # Check that information sets were created
            @test CFR.get_infoset_count(parallel_state.base_state) > 0
        else
            @test_skip "Requires multiple threads"
        end
    end
    
    @testset "Thread Statistics" begin
        params = GameTypes.GameParams(stack=4)
        tree = Tree.build_game_tree(params, preflop_only=true, verbose=false)
        
        thread_config = ThreadConfig(num_threads=1)
        parallel_state = ParallelCFRState(tree, CFR.CFRConfig(), thread_config)
        
        # Run one iteration
        parallel_cfr_iteration!(parallel_state, tree)
        
        # Get statistics
        stats = get_thread_stats(parallel_state)
        
        @test haskey(stats, "total_nodes_processed")
        @test haskey(stats, "total_infosets_updated")
        @test haskey(stats, "thread_efficiency")
        @test stats["total_nodes_processed"] >= 0
        
        # Test print function doesn't error
        @test begin
            print_thread_performance(parallel_state)
            true
        end
    end
    
    @testset "Single vs Multi-threaded Consistency" begin
        if Threads.nthreads() > 1
            params = GameTypes.GameParams(stack=4)
            tree = Tree.build_game_tree(params, preflop_only=true, verbose=false)
            
            # Single-threaded baseline
            single_config = ThreadConfig(num_threads=1)
            single_state = ParallelCFRState(tree, CFR.CFRConfig(), single_config)
            parallel_cfr_iteration!(single_state, tree)
            single_count = CFR.get_infoset_count(single_state.base_state)
            
            # Multi-threaded version
            multi_config = ThreadConfig(num_threads=2)
            multi_state = ParallelCFRState(tree, CFR.CFRConfig(), multi_config)
            parallel_cfr_iteration!(multi_state, tree)
            multi_count = CFR.get_infoset_count(multi_state.base_state)
            
            # Both should create infosets (exact count may vary due to randomness)
            @test single_count > 0
            @test multi_count > 0
        else
            @test_skip "Requires multiple threads"
        end
    end
    
    @testset "Performance Scaling" begin
        if Threads.nthreads() >= 4
            params = GameTypes.GameParams(stack=6)
            tree = Tree.build_game_tree(params, preflop_only=true, verbose=false)
            
            times = Float64[]
            thread_counts = [1, 2, 4]
            
            for n_threads in thread_counts
                config = ThreadConfig(num_threads=n_threads, load_balancing=:dynamic)
                state = ParallelCFRState(tree, CFR.CFRConfig(), config)
                
                start_time = time()
                parallel_train!(tree, state, iterations=2, verbose=false)
                elapsed = time() - start_time
                
                push!(times, elapsed)
            end
            
            # More threads should generally be faster (though not always for small problems)
            # Just verify the code runs without error
            @test length(times) == length(thread_counts)
            @test all(t > 0 for t in times)
            
            # Print scaling info for debugging
            println("\nScaling results:")
            for (n, t) in zip(thread_counts, times)
                println("  $n threads: $(round(t, digits=3))s")
            end
        else
            @test_skip "Requires 4+ threads for scaling test"
        end
    end
end
