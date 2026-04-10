# ADR-002: Four-Layer System Architecture

> **Status**: Accepted
> **Date**: 2026-04-07 (recorded 2026-04-10)
> **Deciders**: Project lead
> **Relates to**: design/gdd/systems-index.md, all implementation plans

---

## Context

The game has 14 MVP systems with complex interdependencies. Systems range from
pure data models (MazeData) to full UI renderers (MatchRenderer). A clear
dependency direction is needed to prevent circular coupling and enable
incremental implementation.

## Decision

Organize all 14 MVP systems into **4 dependency layers** with a strict
top-down dependency rule: each layer may only depend on layers below it.

```
┌─────────────────────────────────────────────────┐
│  Presentation Layer                             │
│  MatchRenderer, PromptInput, MatchHUD,          │
│  ResultScreen                                   │
├─────────────────────────────────────────────────┤
│  Feature Layer                                  │
│  KeyCollection, WinCondition, LLMInfoFormat,    │
│  LLMAgentIntegration                            │
├─────────────────────────────────────────────────┤
│  Core Layer                                     │
│  MazeGenerator, GridMovement, FogOfWar          │
├─────────────────────────────────────────────────┤
│  Foundation Layer                               │
│  MazeData, MatchStateManager, SceneManager      │
└─────────────────────────────────────────────────┘
```

### Layer Rules

1. **Foundation** (no dependencies): Pure data models and state machines.
   May not import anything from Core, Feature, or Presentation.
2. **Core** (depends on Foundation only): Gameplay mechanics that operate
   on Foundation data.
3. **Feature** (depends on Foundation + Core): Higher-level game rules
   composed from Core systems.
4. **Presentation** (depends on all below): UI, rendering, and player
   interaction. Never contains game logic.

### Implementation Order

Layers are implemented bottom-up: Foundation → Core → Feature → Presentation.
Each layer's implementation plan is a separate document in
`docs/superpowers/plans/`.

## Alternatives Considered

### A. Flat architecture (no layers)

- **Pro**: Simpler to start, no layer restrictions
- **Con**: With 14 systems and 40+ dependency edges, circular dependencies
  become inevitable. No way to determine safe implementation order.
- **Rejected**: Doesn't scale even for 14 systems.

### B. Two layers (engine / game)

- **Pro**: Simple split
- **Con**: Doesn't capture the meaningful distinction between data models
  (MazeData), mechanics (GridMovement), rules (KeyCollection), and display
  (MatchRenderer). All end up in "game" with tangled dependencies.
- **Rejected**: Too coarse.

### C. Module-per-system (microservice style)

- **Pro**: Maximum isolation
- **Con**: 14 independent modules with explicit interfaces between every
  pair creates massive boilerplate. GDScript doesn't have a module system;
  this would fight the engine.
- **Rejected**: Over-engineered for a single-developer Godot project.

## Consequences

### Positive

- Clear implementation order: each layer can be built and tested before
  the layer above it exists
- Dependency direction is always downward — prevents spaghetti coupling
- Each layer has a dedicated implementation plan (38 tasks total across 4 plans)
- Bug isolation: rendering issues are in Presentation, logic bugs are in
  Feature/Core, data integrity is in Foundation
- Maps cleanly to the `src/` directory structure:
  `src/core/` (Foundation + Core), `src/gameplay/` (Feature),
  `src/ai/` (Feature), `src/ui/` (Presentation)

### Negative

- The one known cross-layer complexity: GridMovement (Core) and FogOfWar (Core)
  have a mutual dependency. This is resolved by lifecycle separation —
  GridMovement calls FoW during `initialize()` (one-time), FoW listens to
  GridMovement's `mover_moved` signal (runtime). Documented in systems-index.md.
- Layer boundaries can feel restrictive when a quick shortcut would work.
  Discipline is required to route communication through the proper layer.

## Compliance

- Systems index (`design/gdd/systems-index.md`) tracks every system's layer
  assignment and dependencies
- Implementation plans enforce bottom-up build order
- Code reviews should verify no upward dependencies (e.g., Foundation importing
  from Feature)
