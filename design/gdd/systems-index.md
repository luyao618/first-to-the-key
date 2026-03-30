# Systems Index: First to the Key

> **Status**: Approved
> **Created**: 2026-03-30
> **Last Updated**: 2026-03-30
> **Source Concept**: design/gdd/game-concept.md

---

## Overview

First to the Key 是一个 2D 俯视角迷宫竞速游戏，核心机制围绕 LLM Agent 导航。
游戏需要的系统相对精简：一个迷宫数据层、基于 tick 的实时移动、迷雾视野、
顺序钥匙收集、LLM API 集成（含信息格式设计）、以及驱动比赛流程的状态管理和 UI。
所有系统服务于一个核心假设：prompt 质量能显著影响 LLM Agent 的迷宫导航表现。

---

## Systems Enumeration

| # | System Name | Category | Priority | Status | Design Doc | Depends On |
|---|-------------|----------|----------|--------|------------|------------|
| 1 | Maze Data Model | Core | MVP | Not Started | — | — |
| 2 | Match State Manager | Core | MVP | Not Started | — | — |
| 3 | Scene Manager | Core | MVP | Not Started | — | — |
| 4 | Maze Generator | Gameplay | MVP | Not Started | — | Maze Data Model |
| 5 | Grid Movement | Gameplay | MVP | Not Started | — | Maze Data Model |
| 6 | Fog of War / Vision | Gameplay | MVP | Not Started | — | Maze Data Model |
| 7 | Key Collection | Gameplay | MVP | Not Started | — | Maze Data Model, Grid Movement, Fog of War |
| 8 | LLM Information Format | AI | MVP | Not Started | — | Maze Data Model, Fog of War |
| 9 | LLM Agent Integration | AI | MVP | Not Started | — | LLM Information Format, Grid Movement, Match State Manager |
| 10 | Win Condition / Chest | Gameplay | MVP | Not Started | — | Key Collection, Maze Data Model, Match State Manager |
| 11 | Match Renderer | UI | MVP | Not Started | — | Maze Data Model, Grid Movement, Fog of War, Key Collection |
| 12 | Prompt Input | UI | MVP | Not Started | — | Match State Manager, Scene Manager |
| 13 | Match HUD | UI | MVP | Not Started | — | Key Collection, Match State Manager |
| 14 | Result Screen | UI | MVP | Not Started | — | Win Condition, Match State Manager, Scene Manager |
| 15 | Observer Communication (inferred) | Gameplay | Core | Not Started | — | LLM Agent Integration, Grid Movement, Match State Manager |

---

## Categories

| Category | Description |
|----------|-------------|
| **Core** | Foundation systems everything depends on — data models, state management, scene flow |
| **Gameplay** | Systems that implement the game's rules — maze, movement, vision, keys, victory |
| **AI** | LLM integration — information formatting and API communication |
| **UI** | Player-facing displays — rendering, input, HUD, results |

---

## Priority Tiers

| Tier | Definition | Systems Count |
|------|------------|---------------|
| **MVP** | Required for Agent vs Agent core loop. Without these, can't test "is this fun?" | 14 |
| **Core** | Adds Player vs Player and Player vs Agent modes (observer system) | 1 |
| **Full** | Items, SFX/music, difficulty settings, UI polish | Future |
| **Dream** | Online mode, leaderboards, prompt sharing, replay | Future |

---

## Dependency Map

### Foundation Layer (no dependencies)

1. **Maze Data Model** — defines grid, walls, cells; read by 10+ systems
2. **Match State Manager** — state machine driving match lifecycle (pre-match → in-match → ended)
3. **Scene Manager** — Godot scene switching framework

### Core Layer (depends on Foundation)

4. **Maze Generator** — depends on: Maze Data Model
5. **Grid Movement** — depends on: Maze Data Model
6. **Fog of War / Vision** — depends on: Maze Data Model

### Feature Layer (depends on Core)

7. **Key Collection** — depends on: Maze Data Model, Grid Movement, Fog of War
8. **LLM Information Format** — depends on: Maze Data Model, Fog of War
9. **LLM Agent Integration** — depends on: LLM Information Format, Grid Movement, Match State Manager
10. **Win Condition / Chest** — depends on: Key Collection, Maze Data Model, Match State Manager

### Presentation Layer (depends on Features)

11. **Match Renderer** — depends on: Maze Data Model, Grid Movement, Fog of War, Key Collection
12. **Prompt Input** — depends on: Match State Manager, Scene Manager
13. **Match HUD** — depends on: Key Collection, Match State Manager
14. **Result Screen** — depends on: Win Condition, Match State Manager, Scene Manager

### Deferred (Core Tier)

15. **Observer Communication** — depends on: LLM Agent Integration, Grid Movement, Match State Manager

---

## Recommended Design Order

| Order | System | Priority | Layer | Est. Effort |
|-------|--------|----------|-------|-------------|
| 1 | Maze Data Model | MVP | Foundation | S |
| 2 | Match State Manager | MVP | Foundation | S |
| 3 | Scene Manager | MVP | Foundation | S |
| 4 | Maze Generator | MVP | Core | M |
| 5 | Grid Movement | MVP | Core | S |
| 6 | Fog of War / Vision | MVP | Core | S |
| 7 | Key Collection | MVP | Feature | S |
| 8 | LLM Information Format | MVP | Feature | M |
| 9 | LLM Agent Integration | MVP | Feature | M |
| 10 | Win Condition / Chest | MVP | Feature | S |
| 11 | Match Renderer | MVP | Presentation | M |
| 12 | Prompt Input | MVP | Presentation | S |
| 13 | Match HUD | MVP | Presentation | S |
| 14 | Result Screen | MVP | Presentation | S |

> **Effort**: S = 1 session, M = 2-3 sessions

---

## Circular Dependencies

None found. All dependencies are unidirectional.

---

## High-Risk Systems

| System | Risk Type | Risk Description | Mitigation |
|--------|-----------|-----------------|------------|
| LLM Information Format | Design / Technical | 核心假设完全取决于这个系统——如果 LLM 无法从文本表示中有效导航迷宫，游戏概念不成立 | 早期原型验证，测试多种格式（ASCII grid、坐标列表、自然语言），选最优方案 |
| LLM Agent Integration | Technical | Godot HTTPRequest + LLM API 延迟管理，首次在 Godot 中集成 LLM | 后端经验可迁移；tick 机制天然容忍延迟 |
| Maze Generator | Design | 公平性保证——两侧最优路径长度需大致相等 | 对称生成或路径长度后验证 |
| Maze Data Model | Design | 被 10+ 系统依赖的瓶颈——数据结构设计不当会导致大面积重构 | 先设计，充分审查后再开始下游系统 |

---

## Progress Tracker

| Metric | Count |
|--------|-------|
| Total systems identified | 15 |
| Design docs started | 0 |
| Design docs reviewed | 0 |
| Design docs approved | 0 |
| MVP systems designed | 0/14 |
| Core systems designed | 0/1 |

---

## Next Steps

- [ ] Design MVP-tier systems in order (use `/design-system [system-name]`)
- [ ] Start with #1: Maze Data Model (Foundation, highest dependency count)
- [ ] Prototype LLM Information Format early — this validates the core hypothesis
- [ ] Run `/design-review` on each completed GDD
- [ ] Run `/gate-check pre-production` when MVP systems are designed
