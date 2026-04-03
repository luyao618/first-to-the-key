# Game Concept: First to the Key

*Created: 2026-03-29*
*Status: Draft*

---

## Elevator Pitch

> A 2D top-down maze racing game where two LLM-powered agents compete to collect
> three keys in order and unlock a treasure chest — and the players' only weapon
> is the prompt they write before the race begins. It's competitive maze-running
> meets prompt engineering, where your words determine your AI's intelligence.

---

## Core Identity

| Aspect | Detail |
| ---- | ---- |
| **Genre** | Competitive puzzle-racing / AI strategy |
| **Platform** | PC |
| **Target Audience** | AI enthusiasts, prompt engineers, competitive puzzle fans |
| **Player Count** | 2 players (local) — each writes a prompt and spectates their agent |
| **Session Length** | Under 10 minutes per match |
| **Monetization** | TBD (personal project, not prioritized) |
| **Estimated Scope** | Small (4-8 weeks) |
| **Comparable Titles** | Screeps (AI programming competition), Gladiabots (bot behavior design), Labyrinth (board game maze racing) |

---

## Core Fantasy

> **You are a prompt strategist.** You craft the perfect instructions, then watch
> your AI agent navigate a maze you can see but it cannot. Your words are the
> only bridge between your bird's-eye view and its ground-level reality. The
> thrill isn't in pressing buttons — it's in watching your carefully crafted
> prompt outsmart your opponent's.
>
> In human vs human mode *(Core Tier)*, it flips: you're the explorer in the
> dark, and your LLM observer is your lifeline — but every time you call for
> help, you freeze in place while your rival keeps running.

---

## Unique Hook

> It's like a maze racing game, **AND ALSO** your opponent is an AI you
> programmed with a single natural-language prompt — turning competitive gaming
> into a prompt engineering arena.
>
> No other game lets you compete by writing better prompts. The prompt IS the
> gameplay. This creates an entirely new skill axis: understanding how LLMs
> think, what instructions they follow well, and how to communicate spatial
> reasoning through text.

---

## Player Experience Analysis (MDA Framework)

### Target Aesthetics (What the player FEELS)

| Aesthetic | Priority | How We Deliver It |
| ---- | ---- | ---- |
| **Sensation** (sensory pleasure) | 6 | Minimal — clean pixel art, satisfying key collection feedback |
| **Fantasy** (make-believe, role-playing) | 5 | "AI trainer" / "prompt strategist" identity |
| **Narrative** (drama, story arc) | N/A | No story — pure competitive gameplay |
| **Challenge** (obstacle course, mastery) | 1 | Core experience — maze navigation, prompt optimization, information trade-offs |
| **Fellowship** (social connection) | 3 | Local multiplayer, shared screen creates social moments |
| **Discovery** (exploration, secrets) | 2 | Exploring LLM capabilities, discovering effective prompt strategies, fog-of-war maze exploration |
| **Expression** (self-expression, creativity) | 4 | Prompt writing is inherently creative and personal |
| **Submission** (relaxation, comfort zone) | N/A | Not a relaxation game |

### Key Dynamics (Emergent player behaviors)

- Players will iterate on prompts between matches, refining their AI's strategy
- Players will develop mental models of how LLMs interpret spatial instructions
- *(Core Tier)* In observer mode, players will weigh the cost of stopping vs. the value of information
- Players will try to anticipate opponent's AI behavior and counter-strategy through prompt design
- Community will share and discuss effective prompt patterns

### Core Mechanics (Systems we build)

1. **Grid-based maze generation** — Procedurally generated mazes ensuring fair paths for both players
2. **Sequential key collection** — Three keys (Brass → Jade → Crystal) must be found in order, each appearing only after the previous is collected
3. **Fog-of-war vision system** — Explorers see only a limited radius; observers see the full map
4. **LLM Agent integration** — Agents receive local vision data and make movement decisions via LLM API calls
5. **Observer communication system** *(Core Tier)* — Text-based communication between player and observer, with movement-freeze cost

---

## Player Motivation Profile

### Primary Psychological Needs Served

| Need | How This Game Satisfies It | Strength |
| ---- | ---- | ---- |
| **Autonomy** (freedom, meaningful choice) | Prompt design is entirely free-form; strategic choices emerge from how you instruct your AI | Core |
| **Competence** (mastery, skill growth) | Prompt quality directly correlates to AI performance; players can see measurable improvement | Core |
| **Relatedness** (connection, belonging) | Local multiplayer creates shared moments; prompt sharing builds community | Supporting |

### Player Type Appeal (Bartle Taxonomy)

- [x] **Achievers** (goal completion, collection, progression) — Winning races, optimizing prompts for faster completion times
- [x] **Explorers** (discovery, understanding systems, finding secrets) — Discovering LLM capabilities, testing prompt strategies, understanding maze patterns
- [ ] **Socializers** (relationships, cooperation, community) — Secondary: local play creates social moments
- [x] **Killers/Competitors** (domination, PvP, leaderboards) — Primary: head-to-head competition, outsmarting opponent's AI

### Flow State Design

- **Onboarding curve**: First match uses a small maze with guided prompt example. Player watches their AI succeed or fail, immediately understanding the game loop
- **Difficulty scaling**: Maze size and complexity increase; later mazes may have loops, dead ends, or multiple paths requiring more sophisticated prompts
- **Feedback clarity**: Real-time visualization of both agents moving through the maze; players see exactly where their AI made good/bad decisions
- **Recovery from failure**: Matches are under 10 minutes — lose a round, tweak the prompt, try again immediately

---

## Core Loop

### Moment-to-Moment (30 seconds)

**Agent vs Agent mode**: Watch your AI navigate the maze — it hits a fork, chooses a direction. Did your prompt teach it to explore systematically or does it wander randomly? The tension is in watching your words come to life.

**Player vs Player mode** *(Core Tier)*: Move through the maze grid-by-grid, choosing directions at each fork. Do you call your observer for help (and freeze) or trust your instincts and keep running?

### Short-Term (5 minutes — one key hunt)

Search the maze → discover key location → plan route → reach key → next key appears → new search begins. Each key hunt is a mini-race with a clear finish line.

### Session-Level (under 10 minutes — one match)

Maze generates → players see full map (God View) → write prompts for their agents → countdown → hunt Brass Key 🔑 → hunt Jade Key 🔑 → hunt Crystal Key 🔑 → treasure chest appears → race to chest → victory! → review AI performance → tweak prompt → rematch.

### Long-Term Progression

- Build a personal library of effective prompts
- Understand LLM spatial reasoning patterns
- Master different maze types and sizes
- Develop meta-strategies (exploration vs. exploitation; *(Core Tier)* when to call observer)
- (Future) Unlock new maze types, visual themes, items

### Retention Hooks

- **Curiosity**: "What if I phrase the prompt differently? Would the AI handle dead-ends better?"
- **Investment**: Growing understanding of LLM behavior patterns
- **Social**: "I bet my prompt can beat yours" — natural rivalry in local play
- **Mastery**: Optimizing prompt strategy is an infinitely deep skill

---

## Game Pillars

### Pillar 1: Information Trade-off

Every piece of information has a cost. Every pause is a gamble.

*Design test*: "If we're debating whether to add a free mini-map or compass, this pillar says: no — information must always cost something (time, position, or resources)."

### Pillar 2: Human-AI Symbiosis

LLM is not an enemy or a tool — it's a teammate, opponent, or a player you coach through prompts.

*Design test*: "If we're debating whether to replace the LLM with a traditional A* pathfinding bot, this pillar says: no — the LLM's unpredictability and malleability IS the fun."

### Pillar 3: Fair Racing

Victory is determined by decision quality, not luck or information asymmetry.

*Design test*: "If we're debating whether to let one player start closer to the first key, this pillar says: no — maze generation must guarantee roughly equal path distances for both sides."

> **当前验证状态**：Maze Generator 对每个目标独立验证双方最短路径差（≤ 2 步），但尚未覆盖真实比赛中的累计路线公平性（Spawn → Brass → Jade → Crystal → Chest）。这是已识别的待解决项，见 `maze-generator.md` Open Questions。

### Pillar 4: Simple Rules, Deep Play

Learn the rules in under ten minutes. Start glimpsing the strategic depth after ten matches.

*Design test*: "If we're debating whether to add a complex skill tree or ability system, this pillar says: first prove that the core racing + prompt strategy mechanic is already engaging enough on its own."

### Anti-Pillars (What This Game Is NOT)

- **NOT an action game**: No combat, no abilities, no reflex-based challenges. The game rewards thinking, not reaction speed.
- **NOT a narrative game**: No plot, no dialogue trees, no character arcs. Pure competitive gameplay.
- **NOT content-driven**: Not built on hand-crafted levels or massive asset libraries. Replayability comes from procedural generation and the infinite space of prompt strategies.
- **NOT a social platform**: No online matchmaking, friend lists, or leaderboards (at least not in MVP). Local play only.

---

## Inspiration and References

| Reference | What We Take From It | What We Do Differently | Why It Matters |
| ---- | ---- | ---- | ---- |
| Screeps / Gladiabots | Programming agents to compete autonomously | Natural language prompts instead of code — dramatically lower barrier to entry | Validates the "program your AI" gameplay loop |
| Labyrinth (board game) | Maze racing with imperfect information | Digital procedural generation + LLM integration | Validates that maze racing is inherently fun |
| Pac-Man Championship Edition | Top-down maze navigation with tension | Two-player competitive + fog of war | Validates moment-to-moment maze gameplay |
| Civilization | Strategic depth from simple rules, "one more turn" | Compressed into 10-minute matches | Validates that strategy games create retention |

**Non-game inspirations**:
- **Prompt engineering culture** — the growing community of people who treat LLM interaction as a skill to master
- **Chess clock mechanics** — the time-pressure trade-off of thinking vs. acting
- **Escape rooms** — collaborative puzzle-solving under pressure with limited information

---

## Target Player Profile

| Attribute | Detail |
| ---- | ---- |
| **Age range** | 18-40 |
| **Gaming experience** | Mid-core to hardcore; comfortable with strategy and puzzle games |
| **Time availability** | 10-30 minute sessions; quick matches fit into breaks |
| **Platform preference** | PC |
| **Current games they play** | Puzzle/strategy games, indie titles, AI tools and experiments |
| **What they're looking for** | A novel competitive experience that combines AI interaction with gaming; something they haven't seen before |
| **What would turn them away** | Slow pacing, heavy narrative, complex controls, pay-to-win mechanics |

---

## Technical Considerations

| Consideration | Assessment |
| ---- | ---- |
| **Recommended Engine** | Godot 4.6 — lightweight, excellent 2D/TileMap support, GDScript is Python-like (good for backend developer), free and open source |
| **Key Technical Challenges** | LLM API integration in Godot (HTTPRequest), designing effective maze-state representation for LLM input, managing API latency, fair maze generation |
| **Art Style** | Pixel art / minimalist 2D — grid-based tileset, simple character sprites, color-coded keys |
| **Art Pipeline Complexity** | Low — simple tilesets, color variations for keys, minimal animation |
| **Audio Needs** | Minimal for MVP; basic SFX for key collection and victory |
| **Networking** | None — local only |
| **Content Volume** | Procedurally generated mazes; 3 key types; 1 treasure chest; 2 character sprites |
| **Procedural Systems** | Maze generation (core system — must produce fair, interesting mazes) |

---

## Risks and Open Questions

### Design Risks

- **LLM spatial reasoning may be poor**: If LLMs can't effectively navigate mazes from text descriptions, the core concept falls apart. Mitigation: early prototype to test, design the information format to be LLM-friendly (grid coordinates, compass directions).
- **Prompt meta may converge**: If everyone discovers the "one best prompt," the game loses depth. Mitigation: varying maze types, maze sizes, and (future) items create shifting metas.
- **Observer call pacing** *(Core Tier)*: If the freeze penalty is too harsh, no one calls; if too lenient, everyone calls constantly. Mitigation: tunable freeze duration, playtest early.

### Technical Risks

- **LLM API latency**: API calls may take 1-5 seconds, disrupting game flow. Mitigation: path queue + prefetch mechanism lets agents continue moving while the next API call is in flight; agents rarely stall (see `llm-agent-integration.md`).
- **Godot + LLM integration**: First time using Godot; HTTP request handling and JSON parsing need to work smoothly. Mitigation: backend experience transfers well.
- **Maze generation fairness**: Ensuring both players have roughly equal-length optimal paths to each key. Mitigation: symmetric maze generation or path-length validation.

### Market Risks

- **Niche audience**: AI-enthusiast gamers are a small (but growing) segment. Mitigation: the game is also fun as a pure maze racer for non-AI players *(Core Tier: human vs human mode)*.
- **LLM API costs**: Each match requires multiple API calls. Mitigation: players provide their own API key; optimize prompt/response size.

### Scope Risks

- **Feature creep from item system**: The planned item system could balloon in scope. Mitigation: strict MVP boundary — no items until core loop is validated.
- **Three game modes**: Three distinct modes triple the UI and testing surface. Mitigation: MVP focuses on Agent vs Agent only; other modes are structurally simpler (subset of Agent vs Agent systems).

### Open Questions

- **What information format works best for LLMs?** — Prototype with different representations (grid ASCII, coordinate lists, natural language descriptions) and measure navigation success rate.
- **What's the right fog-of-war radius?** — Too small = frustrating random wandering; too large = trivial navigation. Needs playtesting.
- ~~**How should the prompt input work?**~~ — *Resolved: MVP uses single prompt before match. See Design Clarifications §3.*
- ~~**Should agents see their own movement history?**~~ — *Resolved: Yes. LLM Information Format includes visited cell history in every state message. See `llm-information-format.md`.*
- ~~**How does the treasure chest location work?**~~ — *Resolved: Chest follows fog-of-war rules. See Design Clarifications §4.*

---

## MVP Definition

**Core hypothesis**: LLM agents can meaningfully navigate procedurally generated mazes using natural language prompts, and the quality of the prompt measurably affects the agent's performance — creating a "prompt engineering competition" that is fun to watch and strategize around.

**Required for MVP**:
1. Procedural maze generation (grid-based, fair for both sides)
2. Grid-based movement system
3. Sequential key collection (Brass → Jade → Crystal) with progressive reveal
4. Treasure chest spawn after Crystal Key collection, victory on chest opening
5. Fog-of-war / local vision system
6. LLM API integration (agent receives local vision, returns movement decisions)
7. Agent vs Agent mode with pre-match prompt input for each player
8. Basic UI (prompt input screen, match view with both agents visible, victory screen)

**Explicitly NOT in MVP** (defer to later):
- Player vs Player mode (with LLM observer)
- Player vs Agent mode
- Item/power-up system
- Sound effects and music
- Menu system and settings
- Multiple maze types or difficulty levels
- Visual polish beyond functional pixel art

### Scope Tiers

| Tier | Content | Features | Timeline |
| ---- | ---- | ---- | ---- |
| **MVP** | Single maze type, basic visuals | Agent vs Agent + prompt input + core maze/key loop | 2-3 weeks |
| **Core** | Improved visuals, multiple maze sizes | + Player vs Agent + Player vs Player + observer system | +1-2 weeks |
| **Full** | Polished art, multiple themes | + Item system + SFX/music + difficulty settings + UI polish | +2-4 weeks |
| **Dream** | Rich visual themes, community features | + Online mode + leaderboards + prompt sharing + replay system | Future |

---

## Game Modes Detail

### Mode 1: Agent vs Agent (MVP)

```
┌─────────────────────────────────────────────┐
│  PRE-MATCH                                  │
│  Player 1 writes prompt ──► Agent 1         │
│  Player 2 writes prompt ──► Agent 2         │
├─────────────────────────────────────────────┤
│  MATCH                                      │
│  Both agents navigate with LOCAL vision     │
│  Players watch from GOD VIEW (full map)     │
│  No mid-match intervention — prompt only    │
│  First to open chest wins                   │
└─────────────────────────────────────────────┘
```

> Core Tier 扩展：赛中可向 Agent 发消息（Agent 冻结接收），见 Design Clarifications §3 Mid-Match Messaging。

### Mode 2: Player vs Agent (Core)

```
┌─────────────────────────────────────────────┐
│  MATCH                                      │
│  Player navigates with LOCAL vision         │
│  Agent navigates with LOCAL vision          │
│  No observers — pure skill vs AI            │
│  First to open chest wins                   │
└─────────────────────────────────────────────┘
```

### Mode 3: Player vs Player (Core)

```
┌─────────────────────────────────────────────┐
│  MATCH                                      │
│  Player 1 navigates with LOCAL vision       │
│    └─ LLM Observer 1 sees FULL map          │
│       Call observer = FREEZE in place       │
│  Player 2 navigates with LOCAL vision       │
│    └─ LLM Observer 2 sees FULL map          │
│       Call observer = FREEZE in place        │
│  First to open chest wins                   │
└─────────────────────────────────────────────┘
```

---

## Design Clarifications

*Resolved 2026-03-30 during design review.*

### 1. Movement Model: Real-Time with Tick + Path Queue

Agent 按固定 tick 间隔移动（每 tick 移动一格）。LLM 不需要每 tick 都做决策——它返回一个**目标坐标**，系统自动 A* 寻路生成路径队列（path queue），Agent 沿队列连续移动。只有在到达**决策点**（岔路口、死胡同、新目标出现）时才请求新的 LLM 决策，且采用**预请求**机制：到达决策点时提前发起 API 调用，Agent 继续沿旧路径行进，响应到达后无缝切换新路径。

- **不是回合制**：两个 Agent 独立运行，不需要等对方决策完成
- **不是每 tick 一次 API 调用**：路径队列 + 直道自动前进减少约 80% 的 API 调用
- **Tick 间隔**：待原型测试确定（建议起始值 0.5-1.0 秒）
- **详细规则**：见 `llm-agent-integration.md`

### 2. Key Progression: Independent Progress, Shared Positions

- 两个玩家各有独立的钥匙进度（Brass → Jade → Crystal）
- **钥匙位置共享**：同一把钥匙对双方来说在同一个位置
- A 拿走钥匙后，钥匙仍然存在于该位置，B 仍然可以在同一位置拾取
- 可以理解为：钥匙是"检查点"，而非"消耗品"

### 3. Mid-Match Messaging: Deferred to Core Tier

- MVP 仅支持赛前 prompt 输入
- 比赛中途发消息给 Agent 的功能（含冻结惩罚）延后到 Core 阶段
- MVP 专注验证核心假设："赛前 prompt 能否让 LLM 有效导航迷宫"

### 4. Treasure Chest Visibility: Follows Fog-of-War Rules

- **宝箱遵循迷雾规则，没有特殊待遇**
- 观察员（God View 的人类玩家）：可以看到宝箱出现的位置
- 探索员（Agent / 迷雾中的玩家）：宝箱只有进入视野范围后才可见，不会因为出现就强制暴露
- 这意味着先拿到水晶钥匙触发宝箱的一方不一定有优势——除非宝箱恰好在其视野内

---

## Next Steps

- [x] Configure Godot 4.6 engine (`/setup-engine godot 4.6`)
- [x] Validate concept completeness (`/design-review design/gdd/game-concept.md`)
- [x] Decompose concept into systems (`/map-systems`)
- [x] Prototype core loop: maze generation + agent navigation (`/prototype maze-agent`) — Concluded
- [x] Validate LLM maze navigation capability (the core hypothesis) — 已验证，LLM 探索率 45% vs 随机 25%
- [ ] Create architecture decision: LLM information format (`/architecture-decision`)
- [ ] Plan first sprint (`/sprint-plan new`)
