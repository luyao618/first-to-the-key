"""
Fog of War / Vision — per-agent visibility tracking.
Mirrors the GDD: design/gdd/fog-of-war.md
"""

from __future__ import annotations

from collections import deque
from enum import Enum

from maze import MazeData


class Visibility(Enum):
    UNKNOWN = "UNKNOWN"
    EXPLORED = "EXPLORED"
    VISIBLE = "VISIBLE"


class FogOfWar:
    """
    Per-agent fog of war. Tracks which cells are visible, explored, or unknown.
    Vision uses BFS along passable paths (not Euclidean distance).
    """

    def __init__(self, maze: MazeData, vision_radius: int):
        self.maze = maze
        self.vision_radius = vision_radius
        # Initialize all cells as UNKNOWN
        self.visibility: list[list[Visibility]] = [
            [Visibility.UNKNOWN for _ in range(maze.width)]
            for _ in range(maze.height)
        ]

    def get_cell_visibility(self, x: int, y: int) -> Visibility:
        if not self.maze.in_bounds(x, y):
            return Visibility.UNKNOWN
        return self.visibility[y][x]

    def get_visible_cells(self) -> list[tuple[int, int]]:
        result = []
        for y in range(self.maze.height):
            for x in range(self.maze.width):
                if self.visibility[y][x] == Visibility.VISIBLE:
                    result.append((x, y))
        return result

    def get_explored_cells(self) -> list[tuple[int, int]]:
        result = []
        for y in range(self.maze.height):
            for x in range(self.maze.width):
                if self.visibility[y][x] == Visibility.EXPLORED:
                    result.append((x, y))
        return result

    def update_vision(self, agent_x: int, agent_y: int) -> None:
        """
        Recalculate vision from agent position.
        1. Demote all VISIBLE to EXPLORED
        2. BFS from agent position up to vision_radius steps
        3. Mark reached cells as VISIBLE
        """
        # Step 1: Demote VISIBLE -> EXPLORED
        for y in range(self.maze.height):
            for x in range(self.maze.width):
                if self.visibility[y][x] == Visibility.VISIBLE:
                    self.visibility[y][x] = Visibility.EXPLORED

        # Step 2: BFS along passable paths
        visible = self._compute_visible(agent_x, agent_y)

        # Step 3: Mark as VISIBLE
        for vx, vy in visible:
            self.visibility[vy][vx] = Visibility.VISIBLE

    def _compute_visible(self, origin_x: int, origin_y: int) -> list[tuple[int, int]]:
        """BFS from origin, expanding along passable paths up to vision_radius."""
        result = [(origin_x, origin_y)]
        queue: deque[tuple[int, int, int]] = deque([(origin_x, origin_y, 0)])
        visited = {(origin_x, origin_y)}

        while queue:
            cx, cy, dist = queue.popleft()
            if dist >= self.vision_radius:
                continue
            for nx, ny in self.maze.get_neighbors(cx, cy):
                if (nx, ny) not in visited:
                    visited.add((nx, ny))
                    result.append((nx, ny))
                    queue.append((nx, ny, dist + 1))

        return result

    def reset(self) -> None:
        """Reset all cells to UNKNOWN."""
        for y in range(self.maze.height):
            for x in range(self.maze.width):
                self.visibility[y][x] = Visibility.UNKNOWN


# Quick test
if __name__ == "__main__":
    from maze import generate_maze, maze_to_ascii, MarkerType

    m = generate_maze(7, 7, seed=42)
    print(maze_to_ascii(m))

    fog = FogOfWar(m, vision_radius=3)
    spawn = m.get_marker_position(MarkerType.SPAWN_A)
    fog.update_vision(*spawn)

    print(f"\nVision from {spawn} (radius=3):")
    print(f"  Visible cells: {len(fog.get_visible_cells())}")
    print(f"  Explored cells: {len(fog.get_explored_cells())}")

    # Visual
    for y in range(m.height):
        row = ""
        for x in range(m.width):
            v = fog.get_cell_visibility(x, y)
            if (x, y) == spawn:
                row += " @ "
            elif v == Visibility.VISIBLE:
                row += " . "
            elif v == Visibility.EXPLORED:
                row += " ~ "
            else:
                row += " ? "
        print(row)
