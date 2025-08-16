# Limit Hold'em CFR Solver (Julia)

A high-performance **Heads-Up Limit Hold'em** solver implementation in Julia using **CFR+** (Counterfactual Regret Minimization Plus).

> Status: Active development with core functionality implemented. Memory-efficient tree storage and advanced card isomorphism features are operational.

## Features

### Implemented
- ✅ Heads-up Limit Hold'em with fixed bet sizes
- ✅ Full game tree generation and validation
- ✅ Memory-efficient tree storage with compressed representations
- ✅ Advanced card isomorphism for state-space reduction
- ✅ Information set abstraction via suit isomorphisms and action symmetry
- ✅ Tree traversal with memory optimization
- ✅ Terminal node evaluation
- ✅ Betting sequence tracking
- ✅ Comprehensive test suite

### In Development
- 🚧 CFR+ algorithm implementation
- 🚧 Best-response exploitability evaluation
- 🚧 Multi-threading for traversals
- 🚧 Strategy persistence and loading
- 🚧 CLI interface for solving and analysis

## Project Structure

```
src/
  LHECFR.jl                # Top-level module
  GameTypes.jl             # Core types: cards, hands, information sets
  Deck.jl                  # Deck operations and shuffling
  AdvancedIsomorphism.jl   # Advanced card isomorphism for state reduction
  Evaluator.jl             # Hand strength evaluation
  Tree.jl                  # Main tree module
  TreeBuilder.jl           # Game tree construction
  TreeMemory.jl            # Memory-efficient tree storage
  TreeNode.jl              # Node representations
  TreeTraversal.jl         # Tree traversal algorithms
  TreeValidation.jl        # Tree validation utilities
  TreeSizeValidation.jl    # Tree size calculations
  BettingSequence.jl       # Betting history tracking
  TerminalEvaluation.jl    # Terminal node evaluation
  InfoSet.jl               # Information set management
  CFR.jl                   # CFR/CFR+ implementation
  BestResponse.jl          # Exploitability computation
  Persist.jl               # Strategy persistence
  CLI.jl                   # Command-line interface

test/
  runtests.jl              # Test runner
  test_basic.jl            # Basic unit tests
  test_eval.jl             # Evaluator tests
  test_infoset.jl          # Information set tests
  test_tree.jl             # Tree construction tests
  test_tree_memory.jl      # Memory optimization tests
  test_tree_traversal.jl   # Traversal tests
  test_tree_validation.jl  # Validation tests
  test_advanced_isomorphism.jl  # Isomorphism tests
```

## Quick Start

### Prerequisites
- Julia 1.10 or later
- 8GB+ RAM recommended for full game solving

### Installation
```bash
# Clone the repository
git clone https://github.com/yourusername/lhe_cfr.git
cd lhe_cfr

# Activate the project environment
julia --project -e 'using Pkg; Pkg.instantiate()'
```

### Running Tests
```bash
julia --project test/runtests.jl
```

### Basic Usage
```julia
using LHECFR

# Build game tree (example - actual implementation may vary)
tree = build_tree()

# Run CFR+ iterations (when implemented)
# strategy = solve_cfr(tree, iterations=1000000)

# Evaluate exploitability (when implemented)
# exploitability = compute_exploitability(tree, strategy)
```

## Implementation Details

### Memory Optimization
The solver uses several techniques to reduce memory usage:
- **Compressed tree storage**: Nodes are stored in memory-efficient formats
- **Integer-based indexing**: Uses dense arrays keyed by integer IDs instead of dictionaries
- **Card isomorphism**: Reduces state space by treating isomorphic card combinations as equivalent
- **Lazy evaluation**: Computes values on-demand where possible

### Card Isomorphism
Advanced card isomorphism is implemented to significantly reduce the state space:
- Suit symmetries are exploited to treat equivalent card combinations as identical
- Canonical representations ensure consistent mapping of isomorphic states
- Supports both preflop and postflop isomorphisms

### Information Sets
Information sets use perfect recall and include:
- Player position
- Current street (preflop, flop, turn, river)
- Betting history (compressed representation)
- Private cards (with isomorphic reduction)
- Public cards (bucketed when applicable)

## Development Roadmap

### Completed Milestones
- ✅ M1: Core data structures and types
- ✅ M2: Game tree construction and validation
- ✅ M3: Memory-efficient storage implementation
- ✅ M4: Advanced card isomorphism

### Upcoming Milestones
- M5: Complete CFR+ implementation with convergence testing
- M6: Best-response calculation and exploitability metrics
- M7: Multi-threaded tree traversal
- M8: Strategy persistence and analysis tools
- M9: Preflop chart generation and export
- M10: Performance optimizations for sub-mBB exploitability

## Performance Targets
- Tree generation: < 30 seconds for full HU-LHE
- Memory usage: < 4GB for complete game tree
- Convergence: < 0.1 mBB/hand exploitability within 1B iterations
- Throughput: > 1M iterations per minute (single-threaded)

## Contributing
Contributions are welcome! Please ensure:
- All tests pass before submitting PRs
- New features include appropriate tests
- Code follows Julia style guidelines
- Documentation is updated for API changes

## License
MIT License - see LICENSE file for details

## Acknowledgments
- Based on CFR+ algorithm by Tammelin et al.
- Inspired by various open-source poker solver implementations
- Uses techniques from academic poker AI research

## Contact
For questions, issues, or collaboration opportunities, please open an issue on GitHub.