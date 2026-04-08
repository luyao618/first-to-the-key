## Shared enums used across all game systems.
## Registered as Autoload "Enums" for global access.
extends Node

enum Direction { NORTH, EAST, SOUTH, WEST }

enum MarkerType { SPAWN_A, SPAWN_B, KEY_BRASS, KEY_JADE, KEY_CRYSTAL, CHEST }

enum MatchState { SETUP, COUNTDOWN, PLAYING, FINISHED }

enum GameMode { AGENT_VS_AGENT, PLAYER_VS_AGENT, PLAYER_VS_PLAYER }

enum MatchResult { NONE, PLAYER_A_WIN, PLAYER_B_WIN, DRAW }

enum VisionStrategy { PATH_REACH, LINE_OF_SIGHT }

enum MoveDirection { NORTH, EAST, SOUTH, WEST, NONE }

enum CellVisibility { UNKNOWN, VISIBLE, EXPLORED }


## Direction -> Vector2i offset mapping.
const DIRECTION_OFFSETS: Dictionary = {
	Direction.NORTH: Vector2i(0, -1),
	Direction.EAST: Vector2i(1, 0),
	Direction.SOUTH: Vector2i(0, 1),
	Direction.WEST: Vector2i(-1, 0),
}

## Direction -> opposite direction mapping.
const OPPOSITE_DIRECTION: Dictionary = {
	Direction.NORTH: Direction.SOUTH,
	Direction.SOUTH: Direction.NORTH,
	Direction.EAST: Direction.WEST,
	Direction.WEST: Direction.EAST,
}
