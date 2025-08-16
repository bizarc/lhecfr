module Persist
using Serialization

function save_strategy(path::AbstractString, strategy::Vector{Float32})
    open(path, "w") do io
        serialize(io, strategy)
    end
end

function load_strategy(path::AbstractString)::Vector{Float32}
    open(path, "r") do io
        return deserialize(io)
    end
end

end # module
