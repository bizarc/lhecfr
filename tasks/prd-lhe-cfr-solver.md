# Product Requirements Document: Limit Hold'em CFR Solver

## Introduction/Overview

The Limit Hold'em CFR Solver is a comprehensive poker strategy optimization tool designed to identify and teach optimal play in Limit Hold'em poker. Using Counterfactual Regret Minimization (CFR+) algorithms, this solver will compute Nash equilibrium strategies for poker scenarios, starting with heads-up play and expanding to full-ring games. The primary focus is pre-flop strategy optimization, with progressive expansion to post-flop play (flop, turn, and river).

This tool addresses the need for professional and serious amateur poker players to study optimal strategies, identify exploitable tendencies in opponents, and improve their overall game theory understanding in a simplified, accessible manner.

## Goals

1. **Compute Nash Equilibrium Strategies**: Calculate game-theory optimal (GTO) strategies for Limit Hold'em scenarios with exploitability < 1 mbb/hand
2. **Educational Tool**: Provide clear, understandable strategy outputs for players of all expertise levels
3. **Scalable Architecture**: Support progression from 2-player to 10-player games
4. **Performance Optimization**: Leverage multi-threading, parallel processing, and GPU acceleration for faster solving
5. **Extensibility**: Build foundation for future support of No-Limit variants and other poker games
6. **API-First Design**: Enable integration with external tools and custom applications

## User Stories

1. **As a professional poker player**, I want to compute optimal pre-flop strategies for heads-up Limit Hold'em, so that I can identify and correct leaks in my game.

2. **As a serious amateur player**, I want to visualize hand ranges and decision trees, so that I can understand why certain plays are optimal.

3. **As a poker student**, I want to load and analyze hand histories, so that I can compare my actual play against GTO strategies.

4. **As a coach**, I want to create opponent models based on observed tendencies, so that I can develop exploitative counter-strategies.

5. **As a developer**, I want to access solver functionality through an API, so that I can build custom poker training applications.

6. **As a researcher**, I want to experiment with different abstraction levels and CFR variants, so that I can optimize solving efficiency.

## Functional Requirements

### Core Solver Engine
1. The system must implement CFR+ algorithm for computing Nash equilibrium strategies
2. The system must support heads-up (2-player) Limit Hold'em as the initial game variant
3. The system must calculate and store regret values and strategy sums for all information sets
4. The system must support perfect recall information set representation
5. The system must provide convergence metrics and exploitability calculations

### Game Representation
6. The system must accurately model Limit Hold'em rules including:
   - Blind structure (small blind, big blind)
   - Betting limits (fixed bet sizes per street)
   - Maximum raises per street (typically 4)
   - All four betting rounds (pre-flop, flop, turn, river)
7. The system must handle card evaluation for 5-card, 6-card, and 7-card scenarios
8. The system must implement suit isomorphism for equivalent hands
9. The system must support game trees with proper action sequences

### Strategy Output & Analysis
10. The system must export computed strategies in human-readable formats
11. The system must generate pre-flop charts showing optimal actions for all starting hands
12. The system must calculate best response strategies and exploitability metrics
13. The system must provide strategy comparison capabilities
14. The system must support saving and loading of computed strategies

### User Interface (CLI - Phase 1)
15. The system must provide a command-line interface for:
    - Initiating solving sessions with configurable parameters
    - Monitoring solving progress with iteration counts and convergence metrics
    - Querying specific hand strategies
    - Exporting results in various formats
16. The system must support batch processing of multiple solving tasks
17. The system must provide clear error messages and input validation

### Performance & Scalability
18. The system must utilize multi-threading for parallel tree traversal
19. The system must support incremental solving with checkpoint/resume capability
20. The system must optimize memory usage for large game trees
21. The system must provide performance profiling and bottleneck identification

### Hand History & Opponent Modeling
22. The system must import standard hand history formats
23. The system must build opponent models from observed actions
24. The system must calculate exploitation strategies against specific opponent tendencies
25. The system must support hand replay with GTO strategy overlay

### API & Integration
26. The system must expose RESTful API endpoints for:
    - Starting/stopping solving sessions
    - Querying strategy for specific game states
    - Retrieving exploitability metrics
    - Managing saved strategies
27. The system must provide API documentation with examples
28. The system must support authentication and rate limiting for API access

### Future Expansion Support
29. The system architecture must support extension to 3-10 player games
30. The system must allow pluggable CFR algorithm variants (Linear CFR, Monte Carlo CFR)
31. The system must support configurable abstraction levels
32. The system must prepare for No-Limit variant implementation

## Non-Goals (Out of Scope)

**Phase 1 (Current) Exclusions:**
- GUI implementation (planned for Phase 2)
- Real-time opponent exploitation during live play
- No-Limit Hold'em support
- Games other than Hold'em
- Multi-player games (3+ players)
- Integration with third-party poker platforms
- Cloud deployment infrastructure
- Advanced abstraction techniques (initially using minimal abstraction)

## Design Considerations

### User Interface Evolution
- **Phase 1**: Command-line interface with text-based output
- **Phase 2**: Web-based GUI with canvas rendering similar to GTO Wizard
- Consider using Julia's web frameworks (Genie.jl) or separate frontend (React/Vue)
- Visualizations should include:
  - Interactive decision trees
  - Hand range matrices
  - Strategy heatmaps
  - EV distributions

### Data Storage
- Strategies stored in efficient binary format with compression
- Support for strategy versioning and metadata
- Consider using HDF5 or similar for large dataset management

## Technical Considerations

### Architecture
- **Modular Design**: Separate solver engine, game logic, UI, and API layers
- **Language**: Julia for performance-critical solver components
- **Parallelization**: Use Julia's native threading and distributed computing capabilities
- **GPU Acceleration**: Leverage CUDA.jl for GPU computing when available

### Dependencies & Libraries
- **Required**: Random, Serialization (already included)
- **Recommended**: 
  - DataStructures.jl for efficient tree representation
  - ProgressMeter.jl for solving progress display
  - JSON3.jl for API data exchange
  - CUDA.jl for GPU acceleration (optional)
  - Plots.jl for strategy visualization

### Performance Targets
- **Initial**: Solve heads-up Limit Hold'em pre-flop to < 10 mbb/hand exploitability in < 1 hour on consumer hardware
- **Optimized**: Achieve < 1 mbb/hand exploitability in < 10 minutes with multi-threading
- **Memory**: Fit full heads-up LHE solution in < 16GB RAM

### Cloud Migration Path
- Design with containerization in mind (Docker)
- Separate compute-intensive operations for distributed processing
- Use cloud-agnostic storage abstractions
- Prepare for horizontal scaling of solving tasks

## Success Metrics

1. **Accuracy**: Achieve exploitability < 1 mbb/hand for heads-up Limit Hold'em
2. **Performance**: Solve pre-flop strategies 10x faster than naive implementation
3. **Usability**: Users can generate and understand strategies without poker theory expertise
4. **Reliability**: 99.9% solving session completion rate without errors
5. **Adoption**: Successfully used by at least 10 professional players for strategy improvement
6. **Extensibility**: Add support for 3-player games without major architecture changes

## Open Questions

1. **Abstraction Strategy**: What level of card and action abstraction provides the best accuracy/performance tradeoff?
2. **Memory Management**: Should we implement out-of-core solving for very large game trees?
3. **CFR Variants**: Which specific CFR variants (CFR+, Linear CFR, DCFR) should be prioritized?
4. **Opponent Modeling**: What statistical methods should be used for opponent profiling?
5. **API Design**: Should the API be synchronous or support async/webhook patterns for long-running solves?
6. **Visualization Library**: What technology stack for the future GUI (native Julia, web-based, or hybrid)?
7. **Strategy Format**: What standard format should be used for strategy export/import?
8. **Distributed Computing**: Should we support cluster computing or focus on single-machine optimization?
9. **Licensing Model**: Open source, commercial, or hybrid licensing approach?
10. **Benchmarking**: What existing solvers should we benchmark against for validation?

## Implementation Milestones

Following the README milestones with expanded scope:

**M1: Cards/Deck + Evaluator** ✅ (Completed)
- Hand evaluation for 5-7 card combinations
- Correct ranking of all poker hands

**M2: Game Tree Construction**
- Build complete HU-LHE game tree
- Validate node counts against theoretical expectations
- Implement information set identification

**M3: CFR+ Implementation**
- Basic CFR+ traversal and regret updates
- Convergence on toy games (Kuhn poker)
- Strategy extraction from regrets

**M4: Full HU-LHE Solving**
- Complete heads-up Limit Hold'em solver
- Achieve < 1 mbb/hand exploitability
- Performance optimization with multi-threading

**M5: Best Response & Exploitability**
- Implement best response calculation
- Add exploitability metrics
- Create strategy analysis tools

**M6: Persistence & Export**
- Save/load strategy files
- Generate pre-flop charts
- API implementation

**Future Phases:**
- M7: Multi-player support (3-6 players)
- M8: GUI development
- M9: No-Limit variant
- M10: Cloud deployment

## Appendix: Technical Definitions

- **CFR (Counterfactual Regret Minimization)**: Algorithm for finding Nash equilibrium in imperfect information games
- **Information Set**: Game states that are indistinguishable to a player
- **Exploitability**: How much a perfect opponent could win against a strategy
- **mbb/hand**: Milli-big-blinds per hand, a measure of win rate
- **Nash Equilibrium**: Strategy profile where no player can unilaterally improve
- **Suit Isomorphism**: Treating equivalent hands with different suits as identical
