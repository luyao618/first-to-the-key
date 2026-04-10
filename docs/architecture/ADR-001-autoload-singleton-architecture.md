# ADR-001: Autoload Singleton Architecture

> **Status**: Accepted
> **Date**: 2026-04-07 (recorded 2026-04-10)
> **Deciders**: Project lead
> **Relates to**: All 14 MVP systems

---

## Context

First to the Key has 14 MVP systems that need to communicate across scenes.
Key systems (state management, scene transitions, key collection tracking,
LLM agent control) must persist across scene changes and be globally accessible.
Godot offers several patterns for cross-scene communication: Autoload singletons,
dependency injection via scene tree, and explicit node references.

## Decision

Use **Godot Autoload singletons** as the primary inter-system communication backbone.

Five Autoloads are registered in `project.godot`:

| Autoload Name | Script | Purpose |
|---------------|--------|---------|
| `Enums` | `src/shared/enums.gd` | Shared enum definitions (Direction, MatchState, MarkerType, etc.) |
| `MatchStateManager` | `src/core/match_state_manager.gd` | FSM driving match lifecycle (SETUP→COUNTDOWN→PLAYING→FINISHED) |
| `SceneManagerGlobal` | `src/core/scene_manager.gd` | Scene transitions via registry lookup |
| `KeyCollection` | `src/gameplay/key_collection.gd` | Sequential key tracking per agent |
| `LLMAgentManager` | `src/ai/llm_agent_manager.gd` | Per-agent LLM brain management and API calls |

Non-Autoload systems (GridMovement, FogOfWar, MazeGenerator, MazeData,
WinCondition, all UI systems) are instantiated per-scene and receive
dependencies via explicit `initialize()` calls.

## Alternatives Considered

### A. Pure dependency injection (no Autoloads)

- **Pro**: Maximum testability, no global state
- **Con**: Match state and key collection must survive scene transitions
  (match → result → match). Without Autoloads, state must be serialized
  and passed through scene change arguments — adds complexity for a game
  with only 2 scenes.
- **Rejected**: Over-engineered for the project's scale.

### B. Single God-Autoload

- **Pro**: One entry point for everything
- **Con**: Becomes a monolithic blob; violates single responsibility
- **Rejected**: Contradicts the 4-layer separation.

### C. Event bus Autoload

- **Pro**: Fully decoupled communication
- **Con**: Hard to trace signal flow; debugging "who emitted what" becomes
  opaque. Godot's native signal system already provides typed, traceable
  event dispatch.
- **Rejected**: Godot signals on the Autoload nodes achieve the same goal
  with better traceability.

## Consequences

### Positive

- Systems that need persistence across scenes (MatchStateManager, KeyCollection)
  naturally survive `SceneTree.change_scene_to_packed()`
- Any node can access shared state via `MatchStateManager.current_state` without
  explicit wiring
- Signal connections to Autoloads (`MatchStateManager.state_changed`) provide a
  clean event mechanism
- `Enums` Autoload eliminates magic numbers across the entire codebase

### Negative

- Autoloads are harder to mock in unit tests than injected dependencies.
  Mitigation: non-Autoload systems use `initialize()` with injected
  dependencies, keeping them unit-testable. Autoloads themselves are
  integration-tested.
- Implicit coupling: any script can reach `MatchStateManager` without declaring
  the dependency. Mitigation: doc comments on each system list explicit
  dependencies, and the systems index tracks the dependency graph.
- Load order matters: Autoloads initialize in `project.godot` declaration order.
  Current order (Enums → MatchStateManager → SceneManager → KeyCollection →
  LLMAgentManager) respects the dependency chain.

## Compliance

- Per coding standards, all non-Autoload systems use dependency injection
  via `initialize()` to remain unit-testable
- Each Autoload has a corresponding GDD in `design/gdd/`
