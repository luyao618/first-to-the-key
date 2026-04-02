"""
Test Runner — batch-run maze navigation tests and collect statistics.
Validates the three core hypotheses:
  1. Can LLM navigate a maze better than random?
  2. Which information format works best?
  3. Does prompt quality affect performance?
"""

from __future__ import annotations

import json
import sys
import time
from datetime import datetime
from pathlib import Path

from maze import generate_maze, maze_to_ascii, MarkerType
from agent import Agent, RandomAgent, AgentStats
from config import (
    MAZE_WIDTH,
    MAZE_HEIGHT,
    MAX_TICKS,
    NUM_TRIALS,
    RANDOM_SEED,
    VISION_RADIUS,
    OLLAMA_MODEL,
)


def run_single_trial(
    maze_width: int,
    maze_height: int,
    seed: int | None,
    player_prompt: str,
    model: str,
    max_ticks: int,
    use_random: bool = False,
    include_ascii_map: bool = False,
    verbose: bool = False,
) -> dict:
    """Run one agent through a maze. Returns stats dict."""
    maze = generate_maze(maze_width, maze_height, seed=seed)
    spawn = maze.get_marker_position(MarkerType.SPAWN_A)

    if use_random:
        agent = RandomAgent(0, maze, spawn)
    else:
        agent = Agent(0, maze, spawn, player_prompt, model=model)

    start_time = time.time()

    for tick in range(1, max_ticks + 1):
        if not agent.alive:
            break
        agent.tick(tick)

        if verbose and tick % 20 == 0:
            print(
                f"  tick {tick}: pos=({agent.x},{agent.y}) "
                f"keys={agent.keys_collected}/3 "
                f"visited={len(agent.visited)}/{maze_width * maze_height}"
            )

    elapsed = time.time() - start_time
    s = agent.stats

    # Compute optimal path length for reference
    brass_pos = maze.get_marker_position(MarkerType.KEY_BRASS)
    jade_pos = maze.get_marker_position(MarkerType.KEY_JADE)
    crystal_pos = maze.get_marker_position(MarkerType.KEY_CRYSTAL)
    chest_pos = maze.get_marker_position(MarkerType.CHEST)
    optimal = (
        len(maze.get_shortest_path(spawn, brass_pos))
        + len(maze.get_shortest_path(brass_pos, jade_pos))
        + len(maze.get_shortest_path(jade_pos, crystal_pos))
        + len(maze.get_shortest_path(crystal_pos, chest_pos))
        - 3  # subtract 3 because each path includes start which was prev end
    )

    return {
        "completed": s.chest_opened,
        "ticks_used": s.total_ticks,
        "total_moves": s.total_moves,
        "wall_bumps": s.wall_bumps,
        "idle_ticks": s.idle_ticks,
        "keys_collected": s.keys_collected,
        "key_ticks": s.key_ticks,
        "chest_tick": s.chest_tick,
        "cells_explored": len(agent.visited),
        "total_cells": maze_width * maze_height,
        "explore_rate": len(agent.visited) / (maze_width * maze_height),
        "api_calls": s.api_calls,
        "api_errors": s.api_errors,
        "avg_response_time": s.total_response_time / max(s.api_calls, 1),
        "wall_time_seconds": elapsed,
        "optimal_steps": optimal,
        "efficiency": optimal / max(s.total_moves, 1) if s.chest_opened else 0.0,
    }


def run_experiment(
    name: str,
    prompt: str,
    model: str = OLLAMA_MODEL,
    maze_width: int = MAZE_WIDTH,
    maze_height: int = MAZE_HEIGHT,
    num_trials: int = NUM_TRIALS,
    max_ticks: int = MAX_TICKS,
    base_seed: int | None = RANDOM_SEED,
    use_random: bool = False,
    verbose: bool = True,
) -> dict:
    """Run multiple trials and aggregate results."""
    print(f"\n{'='*60}")
    print(f"Experiment: {name}")
    print(f"  Model: {'RANDOM' if use_random else model}")
    print(f"  Maze: {maze_width}x{maze_height}, Vision: {VISION_RADIUS}")
    print(f"  Max ticks: {max_ticks}, Trials: {num_trials}")
    if not use_random:
        prompt_preview = prompt[:80] + "..." if len(prompt) > 80 else prompt
        print(f"  Prompt: {prompt_preview}")
    print(f"{'='*60}")

    trials = []
    for i in range(num_trials):
        seed = (base_seed + i) if base_seed is not None else None
        print(f"\n--- Trial {i+1}/{num_trials} (seed={seed}) ---")

        result = run_single_trial(
            maze_width=maze_width,
            maze_height=maze_height,
            seed=seed,
            player_prompt=prompt,
            model=model,
            max_ticks=max_ticks,
            use_random=use_random,
            verbose=verbose,
        )
        trials.append(result)

        status = "COMPLETED" if result["completed"] else f"FAILED (keys={result['keys_collected']}/3)"
        print(
            f"  Result: {status} | "
            f"ticks={result['ticks_used']} | "
            f"moves={result['total_moves']} | "
            f"bumps={result['wall_bumps']} | "
            f"idle={result['idle_ticks']} | "
            f"explored={result['cells_explored']}/{result['total_cells']} | "
            f"optimal={result['optimal_steps']}"
        )
        if not use_random:
            print(
                f"  API: calls={result['api_calls']} errors={result['api_errors']} "
                f"avg_resp={result['avg_response_time']:.2f}s | "
                f"wall_time={result['wall_time_seconds']:.1f}s"
            )

    # Aggregate
    completed = sum(1 for t in trials if t["completed"])
    avg_ticks = sum(t["ticks_used"] for t in trials) / num_trials
    avg_moves = sum(t["total_moves"] for t in trials) / num_trials
    avg_bumps = sum(t["wall_bumps"] for t in trials) / num_trials
    avg_idle = sum(t["idle_ticks"] for t in trials) / num_trials
    avg_keys = sum(t["keys_collected"] for t in trials) / num_trials
    avg_explore = sum(t["explore_rate"] for t in trials) / num_trials
    completed_trials = [t for t in trials if t["completed"]]
    avg_efficiency = (
        sum(t["efficiency"] for t in completed_trials) / len(completed_trials)
        if completed_trials
        else 0.0
    )

    summary = {
        "experiment": name,
        "model": "RANDOM" if use_random else model,
        "maze_size": f"{maze_width}x{maze_height}",
        "vision_radius": VISION_RADIUS,
        "max_ticks": max_ticks,
        "num_trials": num_trials,
        "prompt": prompt if not use_random else "(random agent)",
        "completion_rate": completed / num_trials,
        "avg_ticks": avg_ticks,
        "avg_moves": avg_moves,
        "avg_wall_bumps": avg_bumps,
        "avg_idle_ticks": avg_idle,
        "avg_keys_collected": avg_keys,
        "avg_explore_rate": avg_explore,
        "avg_efficiency": avg_efficiency,
        "trials": trials,
        "timestamp": datetime.now().isoformat(),
    }

    print(f"\n{'='*60}")
    print(f"SUMMARY: {name}")
    print(f"  Completion: {completed}/{num_trials} ({100*completed/num_trials:.0f}%)")
    print(f"  Avg ticks: {avg_ticks:.1f}")
    print(f"  Avg moves: {avg_moves:.1f} (bumps: {avg_bumps:.1f}, idle: {avg_idle:.1f})")
    print(f"  Avg keys: {avg_keys:.1f}/3")
    print(f"  Avg explore: {100*avg_explore:.1f}%")
    if completed_trials:
        print(f"  Avg efficiency: {100*avg_efficiency:.1f}% of optimal")
    print(f"{'='*60}")

    return summary


def save_results(results: list[dict], filename: str) -> None:
    """Save experiment results to JSON."""
    path = Path(__file__).parent / "results" / filename
    path.parent.mkdir(exist_ok=True)
    with open(path, "w") as f:
        json.dump(results, f, indent=2)
    print(f"\nResults saved to {path}")


# --- Experiment Definitions ---

PROMPTS = {
    "empty": "",
    "basic": "Explore the maze efficiently. Avoid going back the way you came.",
    "detailed": """Navigate the maze systematically:
1. Always prefer moving to unvisited cells over visited ones.
2. When at a fork, choose directions you haven't explored yet.
3. If you reach a dead end, backtrack to the nearest unexplored fork.
4. Keep track of your path to avoid loops.
5. When you see a key in your visible cells, move toward it.
6. After collecting all keys, search for the treasure chest.""",
    "spatial": """You are navigating a grid maze. Key strategy:
- Look at the VISITED list to know where you've been. NEVER revisit a cell if there's an unvisited option.
- Look at OPEN DIRECTIONS to know where you CAN move.
- Look at VISIBLE CELLS for keys marked with [KEY:xxx].
- If you see a key, navigate toward it using the coordinates.
- Use a depth-first exploration: go as far as you can in one direction before trying others.
- When backtracking, use the EXPLORED CELLS to find paths you haven't fully explored.""",
}


def main():
    all_results = []

    # --- Hypothesis 1: LLM vs Random ---
    print("\n" + "#" * 60)
    print("# HYPOTHESIS 1: Can LLM navigate better than random?")
    print("#" * 60)

    # Random baseline
    result = run_experiment(
        name="random_baseline",
        prompt="",
        use_random=True,
        num_trials=NUM_TRIALS,
    )
    all_results.append(result)

    # LLM with basic prompt
    result = run_experiment(
        name="llm_basic",
        prompt=PROMPTS["basic"],
        num_trials=NUM_TRIALS,
    )
    all_results.append(result)

    # --- Hypothesis 3: Does prompt quality matter? ---
    print("\n" + "#" * 60)
    print("# HYPOTHESIS 3: Does prompt quality affect performance?")
    print("#" * 60)

    # Empty prompt
    result = run_experiment(
        name="llm_empty_prompt",
        prompt=PROMPTS["empty"],
        num_trials=NUM_TRIALS,
    )
    all_results.append(result)

    # Detailed prompt
    result = run_experiment(
        name="llm_detailed_prompt",
        prompt=PROMPTS["detailed"],
        num_trials=NUM_TRIALS,
    )
    all_results.append(result)

    # Spatial prompt
    result = run_experiment(
        name="llm_spatial_prompt",
        prompt=PROMPTS["spatial"],
        num_trials=NUM_TRIALS,
    )
    all_results.append(result)

    # --- Save ---
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    save_results(all_results, f"experiment_{timestamp}.json")

    # --- Final Comparison ---
    print("\n" + "=" * 70)
    print("FINAL COMPARISON")
    print("=" * 70)
    print(
        f"{'Experiment':<25} {'Complete':>10} {'Avg Ticks':>10} "
        f"{'Avg Keys':>10} {'Explore%':>10} {'Efficiency':>10}"
    )
    print("-" * 70)
    for r in all_results:
        eff_str = f"{100*r['avg_efficiency']:.0f}%" if r['avg_efficiency'] > 0 else "N/A"
        print(
            f"{r['experiment']:<25} "
            f"{100*r['completion_rate']:>9.0f}% "
            f"{r['avg_ticks']:>10.1f} "
            f"{r['avg_keys_collected']:>10.1f} "
            f"{100*r['avg_explore_rate']:>9.1f}% "
            f"{eff_str:>10}"
        )
    print("=" * 70)

    # --- Verdict ---
    print("\n--- CORE HYPOTHESIS VERDICT ---")
    random_result = all_results[0]
    llm_basic = all_results[1]

    if llm_basic["completion_rate"] > random_result["completion_rate"]:
        print("H1: SUPPORTED — LLM completes maze more often than random")
    elif llm_basic["avg_keys_collected"] > random_result["avg_keys_collected"]:
        print("H1: PARTIALLY SUPPORTED — LLM collects more keys but completion rate similar")
    else:
        print("H1: NOT SUPPORTED — LLM does not outperform random baseline")

    prompt_results = {r["experiment"]: r for r in all_results if r["experiment"].startswith("llm_")}
    if len(prompt_results) >= 2:
        rates = [(n, r["completion_rate"], r["avg_keys_collected"]) for n, r in prompt_results.items()]
        best = max(rates, key=lambda x: (x[1], x[2]))
        worst = min(rates, key=lambda x: (x[1], x[2]))
        if best[1] > worst[1] or best[2] > worst[2]:
            print(f"H3: SUPPORTED — prompt quality matters (best={best[0]}, worst={worst[0]})")
        else:
            print("H3: NOT SUPPORTED — all prompts perform similarly")


if __name__ == "__main__":
    main()
