# LLM Maze Navigation Prototype

Validates the core hypothesis of *First to the Key*:

> Can LLM agents meaningfully navigate procedurally generated mazes using
> natural language prompts, and does prompt quality measurably affect performance?

## What This Tests

| # | Hypothesis | Method |
|---|-----------|--------|
| H1 | LLM can navigate a maze better than random | Compare LLM agent vs random-walk baseline |
| H2 | Information format affects navigation quality | (future) Compare coordinate-list vs ASCII map |
| H3 | Prompt quality significantly affects performance | Compare empty / basic / detailed / spatial prompts |

## Setup

Requires:
- Python 3.10+
- [Ollama](https://ollama.ai) running locally with a model pulled

```bash
# Check Ollama is running
curl http://localhost:11434/api/tags

# Pull a model (if needed)
ollama pull qwen2.5:14b
```

## Usage

```bash
# Run full experiment suite
python3 runner.py

# Quick single-agent test
python3 agent.py

# Test maze generation
python3 maze.py
```

## Files

| File | Purpose |
|------|---------|
| `config.py` | All tuning parameters |
| `maze.py` | Maze data model + recursive backtracker generator |
| `fog.py` | Per-agent fog of war (BFS vision) |
| `formatter.py` | Serialize maze state to LLM prompt, parse responses |
| `agent.py` | LLM agent (Ollama) + random baseline agent |
| `runner.py` | Batch test runner with statistics |
| `results/` | JSON experiment outputs |

## Key Metrics

- **Completion rate**: % of trials where agent collected all 3 keys + opened chest
- **Avg ticks**: average ticks used (lower = faster)
- **Avg keys**: average keys collected (3 = all)
- **Explore rate**: % of maze cells visited
- **Efficiency**: optimal path length / actual moves (higher = better, 100% = perfect)

## Results

**Status**: In progress — Round 1 complete, further optimization needed.

**Date**: 2026-04-02
**Model**: qwen2.5:14b (14.8B, Q4_K_M) via Ollama local
**Maze**: 7x7, vision_radius=3, max_ticks=80

### Round 1: Baseline Comparison

| Experiment | Complete | Ticks | Keys | Explore% | Bumps | Idle |
|------------|----------|-------|------|----------|-------|------|
| Random (3 trials) | 0% | 80 | 0/3 | 25.2% | 0 | 0 |
| LLM basic (1 trial) | 0% | 80 | 0/3 | **44.9%** | 3 | 0 |
| LLM detailed (1 trial) | 0% | 80 | 0/3 | **44.9%** | 3 | 0 |

- LLM basic prompt: `"Explore unvisited directions. Avoid backtracking."`
- LLM detailed prompt: 6-step systematic navigation instructions

### Key Findings

**H1 — LLM vs Random: PARTIALLY SUPPORTED**
- LLM explores 45% of the maze vs Random's 25% in the same number of ticks
- LLM demonstrates genuine spatial understanding: in the first 20 ticks it explored 21/49 cells (43%) by consistently choosing `[NEW]` directions
- However, neither agent collected any keys in 80 ticks — the maze's optimal path requires 49 steps, so 80 ticks is tight but should be enough for at least 1 key
- LLM's main weakness: after exhausting immediately visible new cells (~tick 20), it falls into loops in already-explored areas instead of systematically pushing into unknown territory

**H2 — Information Format: NOT YET TESTED**
- Only tested coordinate-list format (GDD default, `include_ascii_map=False`)
- ASCII map comparison deferred to Round 2

**H3 — Prompt Quality: NOT CONFIRMED**
- Basic and detailed prompts produced identical results (44.9% exploration)
- 80 ticks may be insufficient to differentiate — both hit the same exploration ceiling
- Need longer runs or more trials to see divergence

### Critical Bug Found & Fixed

Initial prototype had LLM agents stuck in 2-cell loops (oscillating between two adjacent cells). Root cause: without action feedback or visited-cell annotations in direction choices, the LLM made the same decision every tick.

**Fix applied**: Added two enhancements to the state message:
1. Direction annotations: `SOUTH→(0,1) [NEW]` vs `NORTH→(0,0) [visited]`
2. Last action feedback: `LAST ACTION: moved SOUTH — moved from (0,0) to (0,1)`

This improved exploration from 4 cells/100 ticks to 21 cells/20 ticks.

### Performance Notes

- Average API response time: ~10 seconds/tick (qwen2.5:14b local)
- A single 80-tick trial takes ~13-14 minutes wall time
- State message size: ~200-400 characters/tick (~50-100 tokens)
- No API errors observed (0/80 in each trial)

### Implications for Game Design

1. **Core concept is viable** — LLM agents can meaningfully interpret maze state from text and make navigation decisions that outperform random walk
2. **Tick budget needs increase** — 80 ticks on a 7x7 maze is not enough. GDD default of 200 ticks (config `max_match_duration=300s` at `tick_interval=0.5s` = 600 ticks) should be sufficient
3. **Exploration plateau is a design opportunity** — the point where LLM stops efficiently exploring (~tick 20-30) is exactly where prompt quality *should* matter. Better prompts should teach the agent to push past this plateau
4. **Local 14B models are playable but slow** — 10s/tick means a match would take ~30-100 minutes. Cloud APIs (GPT-4o, Claude) would be ~1-2s/tick, matching the GDD's 0.5-1.0s tick_interval target
5. **Information format enhancements are critical** — the `[NEW]`/`[visited]` direction annotations and action feedback were essential for basic functionality. These should be incorporated into the LLM Information Format GDD

### Next Steps

- [ ] Run with higher tick budget (200+) to see if LLM can complete the full key→chest loop
- [ ] Test with ASCII map enabled (`include_ascii_map=True`) — may help spatial reasoning
- [ ] Test with a larger model (magidonia-24b) to see if model size improves exploration plateau
- [ ] Add "unexplored region hint" to state message (e.g., "27 cells unexplored, mostly SOUTH and EAST")
- [ ] Test with cloud API (faster response, stronger model) for realistic gameplay speed validation
