"""
LLM Agent — Ollama API integration + maze navigation logic.
"""

from __future__ import annotations

import json
import time
import urllib.request
import urllib.error

from maze import MazeData, Direction, MarkerType, DIRECTION_DELTA
from fog import FogOfWar
from formatter import build_system_message, build_state_message, parse_response, KEY_MARKERS
from config import (
    OLLAMA_BASE_URL,
    OLLAMA_MODEL,
    OLLAMA_TEMPERATURE,
    OLLAMA_NUM_CTX,
    VISION_RADIUS,
    KEY_ORDER,
)


class AgentStats:
    """Track agent performance metrics."""

    def __init__(self):
        self.total_ticks = 0
        self.total_moves = 0  # successful moves
        self.wall_bumps = 0  # tried to move into wall
        self.idle_ticks = 0  # no response or parse failure
        self.api_calls = 0
        self.api_errors = 0
        self.total_response_time = 0.0  # seconds
        self.keys_collected = 0
        self.chest_opened = False
        self.key_ticks: dict[str, int] = {}  # key_name -> tick when collected
        self.chest_tick: int | None = None


class Agent:
    """
    LLM-powered maze navigation agent.
    Manages position, fog, visited cells, key progress, and LLM communication.
    """

    def __init__(
        self,
        agent_id: int,
        maze: MazeData,
        spawn: tuple[int, int],
        player_prompt: str,
        model: str = OLLAMA_MODEL,
    ):
        self.agent_id = agent_id
        self.maze = maze
        self.x, self.y = spawn
        self.player_prompt = player_prompt
        self.model = model

        # Fog of war
        self.fog = FogOfWar(maze, VISION_RADIUS)
        self.fog.update_vision(self.x, self.y)

        # State
        self.visited: list[tuple[int, int]] = [(self.x, self.y)]
        self.keys_collected = 0  # 0=need brass, 1=need jade, 2=need crystal, 3=all done
        self.alive = True  # set to False when finished
        self.last_action: str | None = None
        self.last_result: str | None = None

        # Stats
        self.stats = AgentStats()

        # Build system message once
        self.system_message = build_system_message(player_prompt, VISION_RADIUS)

        # Conversation history (for context)
        self.messages: list[dict] = []

    def tick(self, tick_number: int) -> str | None:
        """
        Execute one tick: build prompt, call LLM, parse response, move.
        Returns the direction moved (or None if idle).
        """
        if not self.alive:
            return None

        self.stats.total_ticks += 1

        # Build state message
        state_msg = build_state_message(
            self.maze,
            self.fog,
            self.x,
            self.y,
            self.visited,
            self.keys_collected,
            tick_number,
            last_action=self.last_action,
            last_result=self.last_result,
        )

        # Call LLM
        direction_str = self._call_llm(state_msg)

        if direction_str is None:
            self.stats.idle_ticks += 1
            self.last_action = None
            self.last_result = "no valid response, stayed in place"
            return None

        # Try to move
        direction = Direction(direction_str)
        if self.maze.can_move(self.x, self.y, direction):
            dx, dy = DIRECTION_DELTA[direction]
            old_x, old_y = self.x, self.y
            self.x += dx
            self.y += dy
            self.stats.total_moves += 1

            # Update fog
            self.fog.update_vision(self.x, self.y)

            # Track visited (only first visit)
            pos = (self.x, self.y)
            if pos not in self.visited:
                self.visited.append(pos)

            # Check key collection
            self._check_key_pickup(tick_number)

            # Check chest
            self._check_chest(tick_number)

            self.last_action = direction_str
            self.last_result = f"moved from ({old_x},{old_y}) to ({self.x},{self.y})"
            return direction_str
        else:
            self.stats.wall_bumps += 1
            self.last_action = direction_str
            self.last_result = "BLOCKED by wall, stayed in place"
            return None

    def _call_llm(self, state_message: str) -> str | None:
        """Call Ollama API and parse direction from response."""
        self.stats.api_calls += 1

        # Build messages for chat API
        messages = [
            {"role": "system", "content": self.system_message},
        ]
        # Add recent conversation context (last 4 exchanges to save tokens)
        recent = self.messages[-8:] if len(self.messages) > 8 else self.messages
        messages.extend(recent)
        messages.append({"role": "user", "content": state_message})

        payload = {
            "model": self.model,
            "messages": messages,
            "stream": False,
            "options": {
                "temperature": OLLAMA_TEMPERATURE,
                "num_ctx": OLLAMA_NUM_CTX,
            },
        }

        try:
            start = time.time()
            req = urllib.request.Request(
                f"{OLLAMA_BASE_URL}/api/chat",
                data=json.dumps(payload).encode("utf-8"),
                headers={"Content-Type": "application/json"},
                method="POST",
            )
            with urllib.request.urlopen(req, timeout=30) as resp:
                result = json.loads(resp.read().decode("utf-8"))

            elapsed = time.time() - start
            self.stats.total_response_time += elapsed

            response_text = result.get("message", {}).get("content", "")

            # Save to conversation history
            self.messages.append({"role": "user", "content": state_message})
            self.messages.append({"role": "assistant", "content": response_text})

            return parse_response(response_text)

        except (urllib.error.URLError, json.JSONDecodeError, TimeoutError) as e:
            self.stats.api_errors += 1
            return None

    def _check_key_pickup(self, tick: int) -> None:
        """Check if agent is standing on the current target key."""
        if self.keys_collected >= 3:
            return
        target = KEY_MARKERS[self.keys_collected]
        markers = self.maze.get_markers_at(self.x, self.y)
        if target in markers:
            key_name = KEY_ORDER[self.keys_collected]
            self.stats.key_ticks[key_name] = tick
            self.keys_collected += 1
            self.stats.keys_collected = self.keys_collected

    def _check_chest(self, tick: int) -> None:
        """Check if agent (with all keys) is on the chest."""
        if self.keys_collected < 3:
            return
        markers = self.maze.get_markers_at(self.x, self.y)
        if MarkerType.CHEST in markers:
            self.stats.chest_opened = True
            self.stats.chest_tick = tick
            self.alive = False


class RandomAgent:
    """Baseline: picks a random valid direction each tick."""

    def __init__(
        self,
        agent_id: int,
        maze: MazeData,
        spawn: tuple[int, int],
    ):
        import random as _random

        self.agent_id = agent_id
        self.maze = maze
        self.x, self.y = spawn
        self.rng = _random.Random()

        self.fog = FogOfWar(maze, VISION_RADIUS)
        self.fog.update_vision(self.x, self.y)

        self.visited: list[tuple[int, int]] = [(self.x, self.y)]
        self.keys_collected = 0
        self.alive = True
        self.stats = AgentStats()

    def tick(self, tick_number: int) -> str | None:
        if not self.alive:
            return None

        self.stats.total_ticks += 1

        open_dirs = self.maze.get_open_directions(self.x, self.y)
        if not open_dirs:
            self.stats.idle_ticks += 1
            return None

        direction = self.rng.choice(open_dirs)
        dx, dy = DIRECTION_DELTA[direction]
        self.x += dx
        self.y += dy
        self.stats.total_moves += 1

        self.fog.update_vision(self.x, self.y)
        pos = (self.x, self.y)
        if pos not in self.visited:
            self.visited.append(pos)

        self._check_key_pickup(tick_number)
        self._check_chest(tick_number)

        return direction.value

    def _check_key_pickup(self, tick: int) -> None:
        if self.keys_collected >= 3:
            return
        target = KEY_MARKERS[self.keys_collected]
        if target in self.maze.get_markers_at(self.x, self.y):
            self.stats.key_ticks[KEY_ORDER[self.keys_collected]] = tick
            self.keys_collected += 1
            self.stats.keys_collected = self.keys_collected

    def _check_chest(self, tick: int) -> None:
        if self.keys_collected < 3:
            return
        if MarkerType.CHEST in self.maze.get_markers_at(self.x, self.y):
            self.stats.chest_opened = True
            self.stats.chest_tick = tick
            self.alive = False


# Quick test
if __name__ == "__main__":
    from maze import generate_maze, maze_to_ascii

    m = generate_maze(7, 7, seed=42)
    print(maze_to_ascii(m))

    spawn = m.get_marker_position(MarkerType.SPAWN_A)
    agent = Agent(0, m, spawn, "Explore unvisited directions first. Avoid backtracking.")

    print(f"\nAgent at {spawn}, testing 1 tick...")
    result = agent.tick(1)
    print(f"Tick 1 result: moved={result}, pos=({agent.x},{agent.y})")
    print(f"Stats: api_calls={agent.stats.api_calls}, response_time={agent.stats.total_response_time:.2f}s")
