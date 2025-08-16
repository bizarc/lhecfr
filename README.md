# Limit Hold'em CFR Solver (Julia) — Skeleton

This is a starter scaffold for a **Heads-Up Limit Hold'em** solver in Julia using **CFR+**.
It lays out modules, data structures, and a minimal driver to help you implement and iterate quickly.

> Status: Skeleton with stubs. You will need to implement the evaluator and game tree generation details to run full solves.

## Features (planned)
- Heads-up Limit Hold'em, fixed bet sizes
- Information-set abstraction via **suit isomorphisms** and **action symmetry**
- CFR+ with dictionary-free, array-backed storage for speed
- Best-response exploitability evaluation
- Multi-threading for traversals

## Project Layout
```
src/
  LHECFR.jl                # Top-level module
  GameTypes.jl             # Core types: cards, hands, infosets
  Deck.jl                  # Deck, shuffling, suit-isomorphisms
  Evaluator.jl             # Hand strength evaluator
  Tree.jl                  # Game tree builder for LHE
  CFR.jl                   # CFR / CFR+ implementation
  BestResponse.jl          # Exploitability and BR computation
  Persist.jl               # Save/load strategies & EV tables
  CLI.jl                   # Simple CLI entrypoints
test/
  runtests.jl
  test_basic.jl            # Basic unit tests for deck, eval stubs, and small trees
```

## Quick Start
1. Install Julia 1.10+
2. `] activate .` then `] instantiate`
3. `julia --project -e 'using LHECFR; LHECFR.run_demo()'` (after implementing missing stubs)

## Implementation Notes
- CFR+ stores **regrets** and **strategy sums** per information set and action. Use dense arrays keyed by integer ids for speed.
- Use **perfect recall** to define information sets: (position, street, betting history (capped), private cards, public cards bucket). In LHE, the betting history space is small.
- Start with **no board abstraction** for HU-LHE; the state space is still manageable. You can later add board-bucketing to accelerate.
- For hand evaluation, either:
  - Implement a fast evaluator (e.g., 7-card evaluator with hash-based ranking), or
  - Bind to a C/Rust evaluator via `ccall` for speed.

## Milestones
- M1: Cards/deck + evaluator returns correct ordering on toy cases
- M2: Build HU-LHE game tree and validate node counts vs expectations
- M3: CFR+ traversals converge on small subgames
- M4: Full-game HU-LHE to sub-mBB exploitability
- M5: Add Best-Response calc to measure exploitability
- M6: Persist/Load strategies; export preflop charts

## License
MIT (change if you prefer)
