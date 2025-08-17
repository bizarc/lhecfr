"""
    InfoSetCache

Advanced caching system for information sets with LRU eviction, statistics tracking,
and thread-safe operations support.
"""
module InfoSetCache

using ..GameTypes
using ..TreeNode
using ..InfoSet
using ..InfoSetManager
using DataStructures  # For LRU cache

# Export main types and functions
export CacheConfig, CacheStatistics, LRUInfoSetCache
export get_cached!, put_cached!, clear_cache!, get_statistics
export BatchLookup, batch_get!, batch_put!

"""
    CacheConfig

Configuration for the information set cache.
"""
struct CacheConfig
    max_size::Int                    # Maximum number of entries
    enable_statistics::Bool          # Track cache statistics
    eviction_policy::Symbol          # :lru, :lfu, :fifo
    batch_size::Int                  # Size for batch operations
    thread_safe::Bool                # Enable thread-safe operations
    
    function CacheConfig(;
        max_size::Int = 1000000,
        enable_statistics::Bool = true,
        eviction_policy::Symbol = :lru,
        batch_size::Int = 100,
        thread_safe::Bool = false
    )
        @assert eviction_policy in [:lru, :lfu, :fifo] "Invalid eviction policy"
        @assert max_size > 0 "Cache size must be positive"
        new(max_size, enable_statistics, eviction_policy, batch_size, thread_safe)
    end
end

"""
    CacheStatistics

Statistics tracking for cache performance.
"""
mutable struct CacheStatistics
    hits::Int64                      # Number of cache hits
    misses::Int64                    # Number of cache misses
    evictions::Int64                 # Number of evictions
    total_lookups::Int64             # Total lookup attempts
    total_put_time_ns::Int64         # Total time spent in put operations
    total_get_time_ns::Int64         # Total time spent in get operations
    current_size::Int                # Current cache size
    peak_size::Int                   # Peak cache size reached
    
    CacheStatistics() = new(0, 0, 0, 0, 0, 0, 0, 0)
end

"""
    LRUInfoSetCache

Least Recently Used cache for information sets.
"""
mutable struct LRUInfoSetCache
    cache::OrderedDict{String, InfoSetManager.CFRInfoSet}  # Ordered for LRU
    config::CacheConfig
    stats::CacheStatistics
    lock::ReentrantLock              # For thread safety
    
    function LRUInfoSetCache(config::CacheConfig = CacheConfig())
        new(
            OrderedDict{String, InfoSetManager.CFRInfoSet}(),
            config,
            CacheStatistics(),
            ReentrantLock()
        )
    end
end

"""
    get_cached!(cache::LRUInfoSetCache, key::String, 
                creator::Union{Nothing, Function} = nothing)

Get an item from cache, creating it if necessary.
Returns (value, was_hit) tuple.
"""
function get_cached!(cache::LRUInfoSetCache, key::String, creator::Union{Nothing, Function} = nothing)
    start_time = time_ns()
    
    # Thread safety if enabled
    if cache.config.thread_safe
        lock(cache.lock)
    end
    
    try
        # Update statistics
        if cache.config.enable_statistics
            cache.stats.total_lookups += 1
        end
        
        # Check if key exists
        if haskey(cache.cache, key)
            # Move to end (most recently used)
            value = cache.cache[key]
            delete!(cache.cache, key)
            cache.cache[key] = value
            
            # Update statistics
            if cache.config.enable_statistics
                cache.stats.hits += 1
                cache.stats.total_get_time_ns += time_ns() - start_time
            end
            
            return value, true
        else
            # Cache miss
            if cache.config.enable_statistics
                cache.stats.misses += 1
            end
            
            # Create new value if creator provided
            if creator !== nothing
                value = creator()
                put_cached!(cache, key, value)
                
                if cache.config.enable_statistics
                    cache.stats.total_get_time_ns += time_ns() - start_time
                end
                
                return value, false
            else
                if cache.config.enable_statistics
                    cache.stats.total_get_time_ns += time_ns() - start_time
                end
                
                return nothing, false
            end
        end
    finally
        if cache.config.thread_safe
            unlock(cache.lock)
        end
    end
end

"""
    put_cached!(cache::LRUInfoSetCache, key::String, value::InfoSetManager.CFRInfoSet)

Put an item into the cache, evicting if necessary.
"""
function put_cached!(cache::LRUInfoSetCache, key::String, value::InfoSetManager.CFRInfoSet)
    start_time = time_ns()
    
    if cache.config.thread_safe
        lock(cache.lock)
    end
    
    try
        # Check if we need to evict
        if length(cache.cache) >= cache.config.max_size && !haskey(cache.cache, key)
            # Evict based on policy (LRU = first item in OrderedDict)
            if cache.config.eviction_policy == :lru
                # Remove first (least recently used) item
                first_key = first(keys(cache.cache))
                delete!(cache.cache, first_key)
                
                if cache.config.enable_statistics
                    cache.stats.evictions += 1
                end
            end
        end
        
        # Add or update the item
        if haskey(cache.cache, key)
            # Update existing - move to end
            delete!(cache.cache, key)
        end
        cache.cache[key] = value
        
        # Update statistics
        if cache.config.enable_statistics
            cache.stats.current_size = length(cache.cache)
            cache.stats.peak_size = max(cache.stats.peak_size, cache.stats.current_size)
            cache.stats.total_put_time_ns += time_ns() - start_time
        end
    finally
        if cache.config.thread_safe
            unlock(cache.lock)
        end
    end
end

"""
    clear_cache!(cache::LRUInfoSetCache)

Clear all entries from the cache.
"""
function clear_cache!(cache::LRUInfoSetCache)
    if cache.config.thread_safe
        lock(cache.lock)
    end
    
    try
        empty!(cache.cache)
        
        if cache.config.enable_statistics
            cache.stats.current_size = 0
        end
    finally
        if cache.config.thread_safe
            unlock(cache.lock)
        end
    end
end

"""
    get_statistics(cache::LRUInfoSetCache)

Get cache performance statistics.
"""
function get_statistics(cache::LRUInfoSetCache)
    if !cache.config.enable_statistics
        return nothing
    end
    
    hit_rate = cache.stats.total_lookups > 0 ? 
               cache.stats.hits / cache.stats.total_lookups : 0.0
    
    avg_get_time_us = cache.stats.total_lookups > 0 ?
                      cache.stats.total_get_time_ns / (1000.0 * cache.stats.total_lookups) : 0.0
    
    avg_put_time_us = (cache.stats.hits + cache.stats.misses) > 0 ?
                      cache.stats.total_put_time_ns / (1000.0 * (cache.stats.hits + cache.stats.misses)) : 0.0
    
    return Dict(
        "hits" => cache.stats.hits,
        "misses" => cache.stats.misses,
        "hit_rate" => hit_rate,
        "evictions" => cache.stats.evictions,
        "current_size" => cache.stats.current_size,
        "peak_size" => cache.stats.peak_size,
        "avg_get_time_us" => avg_get_time_us,
        "avg_put_time_us" => avg_put_time_us
    )
end

"""
    BatchLookup

Result of a batch lookup operation.
"""
struct BatchLookup
    found::Dict{String, InfoSetManager.CFRInfoSet}  # Found entries
    missing::Vector{String}                          # Missing keys
    hit_rate::Float64                                # Hit rate for this batch
end

"""
    batch_get!(cache::LRUInfoSetCache, keys::Vector{String})

Perform batch lookup of multiple keys.
"""
function batch_get!(cache::LRUInfoSetCache, keys::Vector{String})
    found = Dict{String, InfoSetManager.CFRInfoSet}()
    missing = String[]
    
    if cache.config.thread_safe
        lock(cache.lock)
    end
    
    try
        for key in keys
            if haskey(cache.cache, key)
                found[key] = cache.cache[key]
                # Move to end for LRU
                value = cache.cache[key]
                delete!(cache.cache, key)
                cache.cache[key] = value
            else
                push!(missing, key)
            end
        end
        
        if cache.config.enable_statistics
            cache.stats.hits += length(found)
            cache.stats.misses += length(missing)
            cache.stats.total_lookups += length(keys)
        end
    finally
        if cache.config.thread_safe
            unlock(cache.lock)
        end
    end
    
    hit_rate = length(keys) > 0 ? length(found) / length(keys) : 0.0
    return BatchLookup(found, missing, hit_rate)
end

"""
    batch_put!(cache::LRUInfoSetCache, entries::Dict{String, InfoSetManager.CFRInfoSet})

Perform batch insertion of multiple entries.
"""
function batch_put!(cache::LRUInfoSetCache, entries::Dict{String, InfoSetManager.CFRInfoSet})
    if cache.config.thread_safe
        lock(cache.lock)
    end
    
    try
        for (key, value) in entries
            # Check if we need to evict
            if length(cache.cache) >= cache.config.max_size && !haskey(cache.cache, key)
                if cache.config.eviction_policy == :lru
                    first_key = first(keys(cache.cache))
                    delete!(cache.cache, first_key)
                    
                    if cache.config.enable_statistics
                        cache.stats.evictions += 1
                    end
                end
            end
            
            # Add or update
            if haskey(cache.cache, key)
                delete!(cache.cache, key)
            end
            cache.cache[key] = value
        end
        
        # Update statistics once after all insertions
        if cache.config.enable_statistics
            cache.stats.current_size = length(cache.cache)
            cache.stats.peak_size = max(cache.stats.peak_size, cache.stats.current_size)
        end
    finally
        if cache.config.thread_safe
            unlock(cache.lock)
        end
    end
end

"""
    print_cache_statistics(cache::LRUInfoSetCache)

Print formatted cache statistics.
"""
function print_cache_statistics(cache::LRUInfoSetCache)
    stats = get_statistics(cache)
    if stats === nothing
        println("Cache statistics not enabled")
        return
    end
    
    println("Cache Statistics:")
    println("  Hits: $(stats["hits"]) ($(round(stats["hit_rate"] * 100, digits=2))%)")
    println("  Misses: $(stats["misses"])")
    println("  Evictions: $(stats["evictions"])")
    println("  Current size: $(stats["current_size"]) / $(cache.config.max_size)")
    println("  Peak size: $(stats["peak_size"])")
    println("  Avg get time: $(round(stats["avg_get_time_us"], digits=2)) μs")
    println("  Avg put time: $(round(stats["avg_put_time_us"], digits=2)) μs")
end

end # module InfoSetCache
