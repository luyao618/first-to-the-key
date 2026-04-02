"""
LLM Information Format — serialize maze state to text, parse LLM responses.
Mirrors the GDD: design/gdd/llm-information-format.md
"""

from __future__ import annotations

import json
import re

from maze import MazeData, Direction, MarkerType, DIRECTION_DELTA
from fog import FogOfWar, Visibility
from config import (
    INCLUDE_ASCII_MAP,
    INCLUDE_EXPLORED,
    MAX_VISITED_COUNT,
    MAX_EXPLORED_COUNT,
    KEY_ORDER,
)


# Map key progress index to MarkerType
KEY_MARKERS = [MarkerType.KEY_BRASS, MarkerType.KEY_JADE, MarkerType.KEY_CRYSTAL]
KEY_NAMES = ["Brass", "Jade", "Crystal"]


def build_system_message(player_prompt: str, vision_radius: int) -> str:
    """Build the fixed system message for the LLM session."""
    return f"""You are an AI agent navigating a maze. Your goal is to collect three keys in order (Brass → Jade → Crystal) and then reach the treasure chest to win.

RULES:
- You move one cell per turn in a cardinal direction: NORTH, EAST, SOUTH, or WEST.
- You can only move in directions without walls. Moving into a wall wastes your turn.
- You have limited vision: you can see cells within {vision_radius} steps along open paths from your position.
- "Visible" cells show walls AND items (keys, chest). "Explored" cells show walls only (you visited before but can't currently see items there).
- Keys must be collected in order. You can only pick up the key matching your current progress.
- You share the maze with an opponent agent. First to open the chest wins.

COORDINATE SYSTEM:
- (x, y) where x increases rightward, y increases downward.
- (0, 0) is the top-left corner.
- NORTH = y-1, SOUTH = y+1, EAST = x+1, WEST = x-1.

OUTPUT FORMAT:
- Respond with ONLY a JSON object: {{"direction": "NORTH|EAST|SOUTH|WEST"}}
- Do NOT include any explanation, reasoning, or extra text.

PLAYER STRATEGY:
{player_prompt if player_prompt else "(no strategy provided)"}"""


def build_state_message(
    maze: MazeData,
    fog: FogOfWar,
    agent_x: int,
    agent_y: int,
    visited_cells: list[tuple[int, int]],
    keys_collected: int,
    tick: int,
    last_action: str | None = None,
    last_result: str | None = None,
    include_ascii_map: bool = INCLUDE_ASCII_MAP,
    include_explored: bool = INCLUDE_EXPLORED,
) -> str:
    """Build the per-tick state message for the LLM."""
    parts = []

    # Last action feedback
    if last_action and last_result:
        parts.append(f"LAST ACTION: moved {last_action} — {last_result}")
        parts.append("")

    # Header
    open_dirs = maze.get_open_directions(agent_x, agent_y)
    open_str = ", ".join(d.value for d in open_dirs) if open_dirs else "NONE"
    parts.append(f"TURN {tick}")
    parts.append(f"Position: ({agent_x}, {agent_y})")

    # Annotate each open direction with visited/unvisited
    visited_set = set(visited_cells)
    dir_annotations = []
    for d in open_dirs:
        dx, dy = DIRECTION_DELTA[d]
        nx, ny = agent_x + dx, agent_y + dy
        tag = "visited" if (nx, ny) in visited_set else "NEW"
        dir_annotations.append(f"{d.value}→({nx},{ny}) [{tag}]")
    parts.append(f"Open directions: {', '.join(dir_annotations) if dir_annotations else 'NONE'}")
    if any("[NEW]" in a for a in dir_annotations):
        parts.append("HINT: Prefer [NEW] directions to explore more of the maze!")
    parts.append("")

    # ASCII map (optional)
    if include_ascii_map:
        map_str = _build_ascii_map(maze, fog, agent_x, agent_y, keys_collected)
        parts.append(map_str)
        parts.append("")

    # Visible cells
    visible = fog.get_visible_cells()
    parts.append("VISIBLE CELLS:")
    for vx, vy in visible:
        line = _format_cell(maze, vx, vy, agent_x, agent_y, keys_collected, show_markers=True)
        parts.append(line)
    parts.append("")

    # Explored cells (optional)
    if include_explored:
        explored = fog.get_explored_cells()
        if explored:
            # Sort by Manhattan distance to agent (approximation of path distance)
            explored.sort(key=lambda c: abs(c[0] - agent_x) + abs(c[1] - agent_y))
            total = len(explored)
            if total > MAX_EXPLORED_COUNT:
                explored = explored[:MAX_EXPLORED_COUNT]
                parts.append(
                    f"EXPLORED CELLS (walls only, showing nearest {MAX_EXPLORED_COUNT} of {total}):"
                )
            else:
                parts.append("EXPLORED CELLS (walls only, items may have changed):")
            for ex, ey in explored:
                line = _format_cell(maze, ex, ey, agent_x, agent_y, keys_collected, show_markers=False)
                parts.append(line)
            parts.append("")

    # Visited cells
    total_visited = len(visited_cells)
    shown = visited_cells[-MAX_VISITED_COUNT:] if total_visited > MAX_VISITED_COUNT else visited_cells
    if total_visited > MAX_VISITED_COUNT:
        parts.append(
            f"VISITED (showing last {MAX_VISITED_COUNT} of {total_visited}):"
        )
    else:
        parts.append("VISITED (cells you have been to):")
    visited_str = " ".join(f"({x},{y})" for x, y in reversed(shown))
    parts.append(visited_str)
    parts.append("")

    # Objective
    if keys_collected < 3:
        key_name = KEY_NAMES[keys_collected]
        parts.append(f"OBJECTIVE: Find {key_name} key")
    else:
        parts.append("OBJECTIVE: Find and open the treasure chest")
    parts.append(f"Keys collected: {keys_collected}/3")

    return "\n".join(parts)


def _format_cell(
    maze: MazeData,
    x: int,
    y: int,
    agent_x: int,
    agent_y: int,
    keys_collected: int,
    show_markers: bool,
) -> str:
    """Format a single cell line: (x,y) open:N,E [annotations]."""
    open_dirs = maze.get_open_directions(x, y)
    dir_str = ",".join(d.value[0] for d in open_dirs)  # N,E,S,W abbreviations
    annotations = []

    if x == agent_x and y == agent_y:
        annotations.append("[YOU]")

    if show_markers:
        markers = maze.get_markers_at(x, y)
        # Show current target key
        if keys_collected < 3:
            target_marker = KEY_MARKERS[keys_collected]
            if target_marker in markers:
                annotations.append(f"[KEY:{KEY_ORDER[keys_collected]}]")
        # Show chest if all keys collected
        if keys_collected >= 3 and MarkerType.CHEST in markers:
            annotations.append("[CHEST]")

    if len(open_dirs) == 1:
        annotations.append("(dead end)")

    ann_str = " " + " ".join(annotations) if annotations else ""
    return f"({x},{y}) open:{dir_str}{ann_str}"


def _build_ascii_map(
    maze: MazeData,
    fog: FogOfWar,
    agent_x: int,
    agent_y: int,
    keys_collected: int,
) -> str:
    """Build a simple ASCII map centered on the agent's vision."""
    from config import VISION_RADIUS

    r = VISION_RADIUS
    size = 2 * r + 1

    lines = [f"MAP ({size}x{size} around you):"]
    for dy in range(-r, r + 1):
        row = ""
        for dx in range(-r, r + 1):
            mx, my = agent_x + dx, agent_y + dy
            if mx == agent_x and my == agent_y:
                row += "@"
            elif not maze.in_bounds(mx, my):
                row += "#"
            else:
                vis = fog.get_cell_visibility(mx, my)
                if vis == Visibility.UNKNOWN:
                    row += "?"
                elif vis == Visibility.EXPLORED:
                    row += "~"
                else:
                    # Visible — check for markers
                    markers = maze.get_markers_at(mx, my)
                    if keys_collected < 3 and KEY_MARKERS[keys_collected] in markers:
                        row += "K"
                    elif keys_collected >= 3 and MarkerType.CHEST in markers:
                        row += "C"
                    else:
                        row += "."
        lines.append(row)

    return "\n".join(lines)


# --- Response Parsing ---


def parse_response(text: str) -> str | None:
    """
    Parse LLM response to extract a direction.
    Returns direction string (NORTH/EAST/SOUTH/WEST) or None.
    """
    if not text or not text.strip():
        return None

    # Try to extract JSON block
    json_match = re.search(r"\{[^}]*\}", text)
    if json_match:
        try:
            data = json.loads(json_match.group())
            dir_str = data.get("direction", "")
            if isinstance(dir_str, str):
                return _normalize_direction(dir_str)
        except json.JSONDecodeError:
            pass

    # Fallback: try to find a bare direction word
    text_upper = text.upper().strip()
    for candidate in ["NORTH", "SOUTH", "EAST", "WEST"]:
        if candidate in text_upper:
            return candidate

    return None


def _normalize_direction(s: str) -> str | None:
    """Normalize direction string to NORTH/EAST/SOUTH/WEST or None."""
    s = s.upper().strip()
    mapping = {
        "NORTH": "NORTH",
        "N": "NORTH",
        "UP": "NORTH",
        "SOUTH": "SOUTH",
        "S": "SOUTH",
        "DOWN": "SOUTH",
        "EAST": "EAST",
        "E": "EAST",
        "RIGHT": "EAST",
        "WEST": "WEST",
        "W": "WEST",
        "LEFT": "WEST",
    }
    return mapping.get(s)


# Quick test
if __name__ == "__main__":
    # Test parse_response
    tests = [
        ('{"direction": "NORTH"}', "NORTH"),
        ('{"direction": "n"}', "NORTH"),
        ('{"direction": "UP"}', "NORTH"),
        ('I think north. {"direction": "NORTH"}', "NORTH"),
        ("", None),
        ('{"direction": "NORTHEAST"}', None),
        ('{"foo": "bar"}', None),
        ("not json at all", None),
        ("Go SOUTH now", "SOUTH"),
    ]
    print("=== parse_response tests ===")
    for text, expected in tests:
        result = parse_response(text)
        status = "PASS" if result == expected else "FAIL"
        print(f"  {status}: parse({text!r}) = {result!r} (expected {expected!r})")
