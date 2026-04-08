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

enum GlobalKeyPhase { BRASS_ACTIVE, JADE_ACTIVE, CRYSTAL_ACTIVE, ALL_COLLECTED }

enum RenderMode { GOD_VIEW, AGENT_VIEW }

enum AgentKeyState { NEED_BRASS, NEED_JADE, NEED_CRYSTAL, KEYS_COMPLETE }

enum ChestState { INACTIVE, ACTIVE }

enum AgentEligibility { INELIGIBLE, ELIGIBLE }

enum RequestState { IDLE, IN_FLIGHT }

## Key sequence: the fixed order of key collection.
const KEY_SEQUENCE: Array = [
	MarkerType.KEY_BRASS,
	MarkerType.KEY_JADE,
	MarkerType.KEY_CRYSTAL,
]

## MoveDirection -> opposite mapping.
const OPPOSITE_MOVE_DIRECTION: Dictionary = {
	MoveDirection.NORTH: MoveDirection.SOUTH,
	MoveDirection.SOUTH: MoveDirection.NORTH,
	MoveDirection.EAST: MoveDirection.WEST,
	MoveDirection.WEST: MoveDirection.EAST,
}


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
