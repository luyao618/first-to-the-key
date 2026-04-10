# ADR-004: Data-Driven Configuration via External JSON

> **Status**: Accepted
> **Date**: 2026-04-07 (recorded 2026-04-10)
> **Deciders**: Project lead
> **Relates to**: Coding standards ("gameplay values must be data-driven")

---

## Context

The game has ~40 tunable parameters across 14 systems: maze dimensions,
tick intervals, vision radius, LLM model selection, UI layout ratios,
animation durations, key sequences, and more. Per coding standards, these
values must not be hardcoded. A configuration strategy is needed that
supports rapid iteration during development and potential player
customization later.

## Decision

Use **external JSON files** loaded at runtime via a shared `ConfigLoader`
utility. Configuration is split into two files by domain:

### `assets/data/game_config.json` — Gameplay & Systems

| Section | Example Keys | Consumers |
|---------|-------------|-----------|
| `maze` | `width`, `height`, `cell_size`, `max_fairness_delta` | MazeData, MazeGenerator |
| `match` | `tick_interval`, `countdown_duration`, `max_match_duration` | MatchStateManager |
| `vision` | `vision_radius`, `vision_strategy` | FogOfWar |
| `generator` | `max_generation_retries` | MazeGenerator |
| `llm_format` | `include_ascii_map`, `max_visited_count` | LLMInfoFormat |
| `llm` | `api_endpoint`, `model`, `temperature`, `max_tokens` | LLMAgentManager |
| `scene` | `initial_scene`, `config_file_path` | SceneManager |

### `assets/data/ui_config.json` — Presentation

| Section | Example Keys | Consumers |
|---------|-------------|-----------|
| `layout` | `panel_ratio` | Match scene 3-column layout |
| `renderer` | `cell_size`, `move_anim_ratio`, `agent_a_color` | MatchRenderer |
| `hud` | `toast_duration`, `timer_font_size` | MatchHUD |
| `prompt_input` | `placeholder_text`, `text_edit_min_lines` | PromptInput |
| `result` | `result_title_font_size`, `winner_color_a` | ResultScreen |

### `assets/data/scene_registry.json` — Scene Routing

Maps logical scene names to `.tscn` paths:

```json
{
  "match": "res://scenes/match/Match.tscn",
  "result": "res://scenes/result/Result.tscn"
}
```

### ConfigLoader (`src/shared/config_loader.gd`)

A static utility class (RefCounted, no Autoload) providing:

- `load_json(path) -> Dictionary` — parse JSON with error handling
- `get_or_default(config, key, default) -> Variant` — safe access with
  warning on missing keys

Every system loads its config section in `_ready()` or `initialize()`,
falling back to hardcoded defaults if the JSON key is missing. This means
the game runs even if a config file is deleted or malformed.

## Alternatives Considered

### A. Godot Resource files (.tres / .res)

- **Pro**: Native Godot format, editor integration, typed properties
- **Con**: Binary or Godot-specific text format — not human-editable
  outside the editor. Harder to diff in version control. Custom Resource
  classes add boilerplate for each config section.
- **Rejected**: JSON is universally readable and editable with any text
  editor. For a project where rapid iteration on ~40 parameters matters
  more than editor integration, JSON wins.

### B. GDScript constants / enums

- **Pro**: Type-safe, zero parsing overhead
- **Con**: Changing a value requires editing code and reloading the project.
  Violates the "data-driven" coding standard. Can't support player
  customization without exposing code files.
- **Rejected**: Directly contradicts the project's coding standards.

### C. Godot ProjectSettings

- **Pro**: Built-in, accessible via `ProjectSettings.get_setting()`
- **Con**: All settings in one flat namespace, no hierarchical grouping.
  Settings are stored in `project.godot` which is already cluttered with
  engine config. Not designed for game-specific tuning knobs.
- **Rejected**: Poor separation of engine settings from game settings.

### D. Single monolithic config file

- **Pro**: One file to manage
- **Con**: Gameplay programmers editing LLM parameters risk breaking UI
  config in the same file. Separation by domain reduces merge conflicts
  and cognitive load.
- **Rejected**: Two files (game + UI) provide clean domain separation
  without excessive fragmentation.

## Consequences

### Positive

- All tunable values are in 2 human-readable JSON files — easy to find,
  easy to change, easy to diff
- Systems degrade gracefully: `get_or_default()` ensures missing keys
  don't crash the game
- Config changes don't require code changes or engine restart (for values
  read during `initialize()`)
- Clean domain separation: gameplay programmers touch `game_config.json`,
  UI programmers touch `ui_config.json`
- Future-ready for player-facing settings UI: just read/write the JSON

### Negative

- No compile-time validation of config values — a typo in a key name
  silently falls back to the default. Mitigation: `get_or_default()` emits
  `push_warning()` for missing keys, visible in Godot's output panel.
- No schema validation — invalid types (string where int expected) may
  cause runtime errors. Mitigation: each system validates its own config
  values during `_ready()`.
- JSON doesn't support comments. Mitigation: each config key is documented
  in the corresponding GDD's "Tuning Knobs" section.

## Compliance

- Satisfies coding standard: "Gameplay values must be data-driven
  (external config), never hardcoded"
- Each GDD's "Tuning Knobs" section documents the config keys, safe ranges,
  and gameplay effects
- Data file rules (`.claude/rules/data-files.md`) govern naming and structure
