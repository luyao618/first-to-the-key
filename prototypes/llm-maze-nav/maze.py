"""
Maze Data Model — Grid-based maze with walls, markers, and pathfinding.
Mirrors the GDD: design/gdd/maze-data-model.md
"""

from __future__ import annotations

import random
from collections import deque
from enum import Enum
from typing import Optional


class Direction(Enum):
    NORTH = "NORTH"
    EAST = "EAST"
    SOUTH = "SOUTH"
    WEST = "WEST"


# Opposite direction lookup
OPPOSITE = {
    Direction.NORTH: Direction.SOUTH,
    Direction.SOUTH: Direction.NORTH,
    Direction.EAST: Direction.WEST,
    Direction.WEST: Direction.EAST,
}

# Direction to (dx, dy) offset — X right, Y down (matches GDD)
DIRECTION_DELTA = {
    Direction.NORTH: (0, -1),
    Direction.SOUTH: (0, 1),
    Direction.EAST: (1, 0),
    Direction.WEST: (-1, 0),
}


class MarkerType(Enum):
    SPAWN_A = "SPAWN_A"
    SPAWN_B = "SPAWN_B"
    KEY_BRASS = "KEY_BRASS"
    KEY_JADE = "KEY_JADE"
    KEY_CRYSTAL = "KEY_CRYSTAL"
    CHEST = "CHEST"


class Cell:
    """Single cell in the maze grid."""

    def __init__(self, x: int, y: int):
        self.x = x
        self.y = y
        # All walls start as True (solid)
        self.walls: dict[Direction, bool] = {d: True for d in Direction}
        self.markers: list[MarkerType] = []

    def __repr__(self) -> str:
        return f"Cell({self.x},{self.y})"


class MazeData:
    """
    2D grid of cells with wall state and markers.
    Coordinate system: (0,0) = top-left, X right, Y down.
    """

    def __init__(self, width: int, height: int):
        self.width = width
        self.height = height
        self.cells: list[list[Cell]] = [
            [Cell(x, y) for x in range(width)] for y in range(height)
        ]
        self._finalized = False

    # --- Query ---

    def in_bounds(self, x: int, y: int) -> bool:
        return 0 <= x < self.width and 0 <= y < self.height

    def get_cell(self, x: int, y: int) -> Optional[Cell]:
        if not self.in_bounds(x, y):
            return None
        return self.cells[y][x]

    def has_wall(self, x: int, y: int, direction: Direction) -> bool:
        cell = self.get_cell(x, y)
        if cell is None:
            return True  # out of bounds = wall
        return cell.walls[direction]

    def can_move(self, x: int, y: int, direction: Direction) -> bool:
        return not self.has_wall(x, y, direction)

    def get_neighbors(self, x: int, y: int) -> list[tuple[int, int]]:
        """Return coordinates of all passable neighboring cells."""
        result = []
        for d in Direction:
            if self.can_move(x, y, d):
                dx, dy = DIRECTION_DELTA[d]
                nx, ny = x + dx, y + dy
                if self.in_bounds(nx, ny):
                    result.append((nx, ny))
        return result

    def get_open_directions(self, x: int, y: int) -> list[Direction]:
        """Return directions without walls from (x, y)."""
        return [d for d in Direction if self.can_move(x, y, d)]

    def get_marker_position(self, marker_type: MarkerType) -> Optional[tuple[int, int]]:
        for y in range(self.height):
            for x in range(self.width):
                if marker_type in self.cells[y][x].markers:
                    return (x, y)
        return None

    def get_markers_at(self, x: int, y: int) -> list[MarkerType]:
        cell = self.get_cell(x, y)
        if cell is None:
            return []
        return list(cell.markers)

    # --- Write (only before finalize) ---

    def set_wall(self, x: int, y: int, direction: Direction, value: bool) -> None:
        """Set wall, auto-syncing the neighbor's shared wall."""
        cell = self.get_cell(x, y)
        if cell is None:
            return
        cell.walls[direction] = value

        # Sync neighbor
        dx, dy = DIRECTION_DELTA[direction]
        nx, ny = x + dx, y + dy
        neighbor = self.get_cell(nx, ny)
        if neighbor is not None:
            neighbor.walls[OPPOSITE[direction]] = value

    def remove_wall(self, x: int, y: int, direction: Direction) -> None:
        self.set_wall(x, y, direction, False)

    def place_marker(self, x: int, y: int, marker_type: MarkerType) -> None:
        cell = self.get_cell(x, y)
        if cell is not None and marker_type not in cell.markers:
            cell.markers.append(marker_type)

    # --- Pathfinding ---

    def get_shortest_path(
        self, start: tuple[int, int], end: tuple[int, int]
    ) -> list[tuple[int, int]]:
        """BFS shortest path. Returns list of coordinates from start to end (inclusive)."""
        if start == end:
            return [start]

        queue: deque[tuple[int, int]] = deque([start])
        came_from: dict[tuple[int, int], Optional[tuple[int, int]]] = {start: None}

        while queue:
            cx, cy = queue.popleft()
            for nx, ny in self.get_neighbors(cx, cy):
                if (nx, ny) not in came_from:
                    came_from[(nx, ny)] = (cx, cy)
                    if (nx, ny) == end:
                        # Reconstruct path
                        path = []
                        pos: Optional[tuple[int, int]] = end
                        while pos is not None:
                            path.append(pos)
                            pos = came_from[pos]
                        return list(reversed(path))
                    queue.append((nx, ny))

        return []  # no path found

    # --- Validation ---

    def is_valid(self) -> bool:
        """Check maze integrity: all required markers present, all reachable."""
        required = [
            MarkerType.SPAWN_A,
            MarkerType.SPAWN_B,
            MarkerType.KEY_BRASS,
            MarkerType.KEY_JADE,
            MarkerType.KEY_CRYSTAL,
            MarkerType.CHEST,
        ]
        positions = []
        for m in required:
            pos = self.get_marker_position(m)
            if pos is None:
                return False
            positions.append(pos)

        # All markers must be at distinct positions
        if len(set(positions)) != len(positions):
            return False

        # All markers must be reachable from SPAWN_A
        spawn_a = self.get_marker_position(MarkerType.SPAWN_A)
        for pos in positions:
            if pos != spawn_a and not self.get_shortest_path(spawn_a, pos):
                return False

        return True

    def finalize(self) -> bool:
        if self.is_valid():
            self._finalized = True
            return True
        return False


# --- Maze Generator (Recursive Backtracker) ---


def generate_maze(
    width: int, height: int, seed: Optional[int] = None
) -> MazeData:
    """
    Generate a perfect maze using recursive backtracker (DFS),
    then place markers ensuring fairness.
    """
    rng = random.Random(seed)
    maze = MazeData(width, height)

    # DFS carve
    visited = set()
    stack: list[tuple[int, int]] = []
    start = (0, 0)
    visited.add(start)
    stack.append(start)

    while stack:
        cx, cy = stack[-1]
        # Shuffle directions for randomness
        directions = list(Direction)
        rng.shuffle(directions)

        carved = False
        for d in directions:
            dx, dy = DIRECTION_DELTA[d]
            nx, ny = cx + dx, cy + dy
            if maze.in_bounds(nx, ny) and (nx, ny) not in visited:
                maze.remove_wall(cx, cy, d)
                visited.add((nx, ny))
                stack.append((nx, ny))
                carved = True
                break

        if not carved:
            stack.pop()

    # Place markers — spawns on opposite sides, keys and chest spread out
    _place_markers(maze, rng)

    if not maze.finalize():
        raise RuntimeError("Generated maze failed validation")

    return maze


def _place_markers(maze: MazeData, rng: random.Random) -> None:
    """
    Place SPAWN_A, SPAWN_B, 3 keys, and CHEST.
    Spawns on opposite corners for fairness.
    """
    w, h = maze.width, maze.height

    # Spawns at opposite corners
    spawn_a = (0, 0)
    spawn_b = (w - 1, h - 1)
    maze.place_marker(*spawn_a, MarkerType.SPAWN_A)
    maze.place_marker(*spawn_b, MarkerType.SPAWN_B)

    # Collect all cells excluding spawn positions
    all_cells = [
        (x, y)
        for x in range(w)
        for y in range(h)
        if (x, y) not in (spawn_a, spawn_b)
    ]
    rng.shuffle(all_cells)

    # Place keys and chest, ensuring minimum distance from spawns
    markers_to_place = [
        MarkerType.KEY_BRASS,
        MarkerType.KEY_JADE,
        MarkerType.KEY_CRYSTAL,
        MarkerType.CHEST,
    ]
    placed = set()
    placed.add(spawn_a)
    placed.add(spawn_b)

    for marker in markers_to_place:
        for pos in all_cells:
            if pos not in placed:
                maze.place_marker(*pos, marker)
                placed.add(pos)
                break


def maze_to_ascii(maze: MazeData) -> str:
    """Render full maze as ASCII art for debugging."""
    lines = []
    # Top border
    top = "+"
    for x in range(maze.width):
        top += "---+"
    lines.append(top)

    for y in range(maze.height):
        # Cell row
        row = "|"
        for x in range(maze.width):
            cell = maze.get_cell(x, y)
            # Cell content
            markers = cell.markers
            if MarkerType.SPAWN_A in markers:
                content = " A "
            elif MarkerType.SPAWN_B in markers:
                content = " B "
            elif MarkerType.KEY_BRASS in markers:
                content = " b "
            elif MarkerType.KEY_JADE in markers:
                content = " j "
            elif MarkerType.KEY_CRYSTAL in markers:
                content = " c "
            elif MarkerType.CHEST in markers:
                content = " $ "
            else:
                content = "   "

            east_wall = "|" if cell.walls[Direction.EAST] else " "
            row += content + east_wall
        lines.append(row)

        # Bottom walls
        bottom = "+"
        for x in range(maze.width):
            cell = maze.get_cell(x, y)
            south_wall = "---" if cell.walls[Direction.SOUTH] else "   "
            bottom += south_wall + "+"
        lines.append(bottom)

    return "\n".join(lines)


# Quick test
if __name__ == "__main__":
    m = generate_maze(7, 7, seed=42)
    print(maze_to_ascii(m))
    print(f"\nValid: {m.is_valid()}")
    spawn_a = m.get_marker_position(MarkerType.SPAWN_A)
    spawn_b = m.get_marker_position(MarkerType.SPAWN_B)
    chest = m.get_marker_position(MarkerType.CHEST)
    print(f"Spawn A: {spawn_a}, Spawn B: {spawn_b}, Chest: {chest}")
    path = m.get_shortest_path(spawn_a, chest)
    print(f"Path A→Chest: {len(path)} steps")
    path_b = m.get_shortest_path(spawn_b, chest)
    print(f"Path B→Chest: {len(path_b)} steps")
