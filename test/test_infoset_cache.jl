"""
Tests for the InfoSetCache module that provides advanced caching with LRU eviction and statistics.
"""

using Test
using LHECFR
using LHECFR.Tree
using LHECFR.Tree.InfoSetCache
using LHECFR.Tree.InfoSetManager
using LHECFR.Tree.TreeIndexing
using LHECFR.GameTypes
using LHECFR.CFR

@testset "InfoSetCache Tests" begin
    
    @testset "Basic Cache Operations" begin
        # Create a small cache
        config = CacheConfig(max_size=10, enable_statistics=true)
        cache = LRUInfoSetCache(config)
        
        # Test putting and getting
        cfr_infoset = InfoSetManager.CFRInfoSet("test_id_1", 3, zeros(3), zeros(3), 0)
        put_cached!(cache, "test_id_1", cfr_infoset)
        
        # Test cache hit
        result, was_hit = get_cached!(cache, "test_id_1")
        @test was_hit == true
        @test result === cfr_infoset
        
        # Test cache miss
        result, was_hit = get_cached!(cache, "nonexistent")
        @test was_hit == false
        @test result === nothing
        
        # Test statistics
        stats = get_statistics(cache)
        @test stats["hits"] == 1
        @test stats["misses"] == 1
        @test stats["hit_rate"] ≈ 0.5
        @test stats["current_size"] == 1
    end
    
    @testset "LRU Eviction" begin
        # Create cache with size 3
        config = CacheConfig(max_size=3, enable_statistics=true)
        cache = LRUInfoSetCache(config)
        
        # Add 3 items
        for i in 1:3
            cfr_infoset = InfoSetManager.CFRInfoSet("id_$i", 2, zeros(2), zeros(2), 0)
            put_cached!(cache, "id_$i", cfr_infoset)
        end
        
        @test cache.stats.current_size == 3
        @test cache.stats.evictions == 0
        
        # Access id_1 to make it recently used
        get_cached!(cache, "id_1")
        
        # Add 4th item - should evict id_2 (least recently used)
        cfr_infoset4 = InfoSetManager.CFRInfoSet("id_4", 2, zeros(2), zeros(2), 0)
        put_cached!(cache, "id_4", cfr_infoset4)
        
        @test cache.stats.current_size == 3
        @test cache.stats.evictions == 1
        
        # id_2 should be evicted
        result, was_hit = get_cached!(cache, "id_2")
        @test was_hit == false
        
        # id_1, id_3, id_4 should still be there
        _, hit1 = get_cached!(cache, "id_1")
        _, hit3 = get_cached!(cache, "id_3")
        _, hit4 = get_cached!(cache, "id_4")
        @test hit1 == true
        @test hit3 == true
        @test hit4 == true
    end
    
    @testset "Batch Operations" begin
        config = CacheConfig(max_size=100, enable_statistics=true)
        cache = LRUInfoSetCache(config)
        
        # Batch put
        entries = Dict{String, InfoSetManager.CFRInfoSet}()
        for i in 1:10
            entries["batch_$i"] = InfoSetManager.CFRInfoSet("batch_$i", 2, zeros(2), zeros(2), 0)
        end
        batch_put!(cache, entries)
        
        @test cache.stats.current_size == 10
        
        # Batch get
        keys = ["batch_1", "batch_5", "batch_10", "missing_1", "missing_2"]
        batch_result = batch_get!(cache, keys)
        
        @test length(batch_result.found) == 3
        @test length(batch_result.missing) == 2
        @test batch_result.hit_rate ≈ 0.6
        @test "batch_1" in Base.keys(batch_result.found)
        @test "missing_1" in batch_result.missing
    end
    
    @testset "Cache with Creator Function" begin
        config = CacheConfig(max_size=50, enable_statistics=true)
        cache = LRUInfoSetCache(config)
        
        # Get with creator function
        created_count = 0
        creator = () -> begin
            created_count += 1
            InfoSetManager.CFRInfoSet("created_$created_count", 3, zeros(3), zeros(3), 0)
        end
        
        # First access creates
        result1, was_hit1 = get_cached!(cache, "test_create", creator)
        @test was_hit1 == false
        @test result1 !== nothing
        @test created_count == 1
        
        # Second access hits cache
        result2, was_hit2 = get_cached!(cache, "test_create", creator)
        @test was_hit2 == true
        @test result2 === result1
        @test created_count == 1  # Creator not called again
    end
    
    @testset "Integration with TreeIndexing" begin
        # Create a small tree
        params = GameTypes.GameParams(stack=10)
        tree = Tree.build_game_tree(params, preflop_only=true, verbose=false)
        
        # Create indexed storage with custom cache config
        cache_config = CacheConfig(
            max_size=100,
            enable_statistics=true,
            eviction_policy=:lru
        )
        indexed_storage = TreeIndexing.IndexedInfoSetStorage(tree, cache_config=cache_config)
        
        @test indexed_storage.cache !== nothing
        @test isa(indexed_storage.cache, LRUInfoSetCache)
        
        # Get some infosets
        nodes = TreeIndexing.collect_nodes_preorder(tree.root)
        player_nodes = filter(n -> !Tree.TreeNode.is_terminal_node(n) && !Tree.TreeNode.is_chance_node(n), nodes)
        
        # Access nodes multiple times
        for _ in 1:3
            for node in player_nodes[1:min(5, length(player_nodes))]
                TreeIndexing.get_or_create_indexed_infoset!(
                    indexed_storage,
                    node,
                    nothing,
                    nothing
                )
            end
        end
        
        # Check cache statistics
        cache_stats = TreeIndexing.get_cache_statistics(indexed_storage)
        @test cache_stats !== nothing
        @test cache_stats["hits"] > 0  # Should have hits on repeated access
        @test cache_stats["hit_rate"] > 0.0
    end
    
    @testset "Cache Clear Operation" begin
        config = CacheConfig(max_size=50, enable_statistics=true)
        cache = LRUInfoSetCache(config)
        
        # Add some items
        for i in 1:10
            cfr_infoset = InfoSetManager.CFRInfoSet("clear_$i", 2, zeros(2), zeros(2), 0)
            put_cached!(cache, "clear_$i", cfr_infoset)
        end
        
        @test cache.stats.current_size == 10
        
        # Clear cache
        clear_cache!(cache)
        
        @test cache.stats.current_size == 0
        
        # All items should be gone
        for i in 1:10
            _, was_hit = get_cached!(cache, "clear_$i")
            @test was_hit == false
        end
    end
    
    @testset "Statistics Tracking" begin
        config = CacheConfig(max_size=100, enable_statistics=true)
        cache = LRUInfoSetCache(config)
        
        # Perform various operations
        for i in 1:20
            cfr_infoset = InfoSetManager.CFRInfoSet("stat_$i", 2, zeros(2), zeros(2), 0)
            put_cached!(cache, "stat_$i", cfr_infoset)
        end
        
        # Some hits
        for i in 1:10
            get_cached!(cache, "stat_$i")
        end
        
        # Some misses
        for i in 21:30
            get_cached!(cache, "stat_$i")
        end
        
        stats = get_statistics(cache)
        @test stats["hits"] == 10
        @test stats["misses"] == 10
        @test stats["hit_rate"] ≈ 0.5
        @test stats["current_size"] == 20
        @test stats["peak_size"] == 20
        @test stats["avg_get_time_us"] > 0
        
        # Test print function doesn't error
        # Simply test that the function runs without error
        @test begin
            InfoSetCache.print_cache_statistics(cache)
            true  # If we get here, no error was thrown
        end
    end
    
    @testset "No Statistics Mode" begin
        # Create cache with statistics disabled
        config = CacheConfig(max_size=50, enable_statistics=false)
        cache = LRUInfoSetCache(config)
        
        # Add and get items
        cfr_infoset = InfoSetManager.CFRInfoSet("nostat_1", 2, zeros(2), zeros(2), 0)
        put_cached!(cache, "nostat_1", cfr_infoset)
        get_cached!(cache, "nostat_1")
        
        # Statistics should be nothing
        stats = get_statistics(cache)
        @test stats === nothing
    end
end
