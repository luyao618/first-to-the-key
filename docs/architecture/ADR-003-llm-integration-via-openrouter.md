# ADR-003: LLM Integration via OpenRouter API

> **Status**: Accepted
> **Date**: 2026-04-09 (recorded 2026-04-10)
> **Deciders**: Project lead
> **Relates to**: design/gdd/llm-agent-integration.md, design/gdd/llm-information-format.md

---

## Context

The game's core mechanic is LLM-driven maze navigation: each agent receives
a text representation of its visible surroundings and returns a movement
decision. This requires calling an LLM API every tick (~0.5s) for each of
the 2 agents. The game must support multiple LLM providers (players may prefer
different models) while keeping the integration simple for an indie game.

The prototype (`prototypes/llm-maze-nav/`) validated that LLM agents can
meaningfully navigate mazes from text descriptions (45% exploration vs 25%
random baseline).

## Decision

Use **OpenRouter** as the default LLM API gateway, with a standard
OpenAI-compatible chat completions endpoint. The integration is structured
as two systems:

### LLMInformationFormat (`src/ai/llm_info_format.gd`)

Pure-logic formatter (RefCounted, no Node dependency) that serializes
game state into LLM prompts:

- Visible cells with `[NEW]`/`[visited]` annotations
- Available directions with wall/passable status
- Current key objective and collected keys
- Last action feedback (moved/bumped/idle)
- Player's custom prompt injected as system instructions

### LLMAgentManager (`src/ai/llm_agent_manager.gd`)

Autoload singleton managing per-agent "brains":

- Each brain has its own HTTPRequest node, prompt, and request queue
- Tick-driven: on each `MatchStateManager.tick` signal, formats state and
  sends API request
- Async response handling: movement is applied when the response arrives,
  not synchronously
- Auto-advance fallback: if a response is pending when the next tick fires,
  the agent repeats its last direction
- API key loaded from environment variable (`OPENROUTER_API_KEY` via `.env`)

### API Contract

```
POST https://openrouter.ai/api/v1/chat/completions
{
  "model": "google/gemini-2.0-flash-001",
  "messages": [
    {"role": "system", "content": "<player prompt>"},
    {"role": "user", "content": "<formatted maze state>"}
  ],
  "temperature": 0.3,
  "max_tokens": 100
}
```

Response is parsed for a single direction keyword: `NORTH`, `SOUTH`,
`EAST`, `WEST`, or `NONE`.

## Alternatives Considered

### A. Direct provider SDKs (OpenAI, Anthropic, Google separately)

- **Pro**: No middleman, potentially lower latency
- **Con**: Three different auth flows, request formats, and error handling
  paths. Players would need provider-specific API keys.
- **Rejected**: OpenRouter provides a single endpoint that routes to 100+
  models. One API key, one request format, any model.

### B. Local-only (Ollama)

- **Pro**: Free, no API key needed, privacy
- **Con**: Prototype showed 10s/tick with local 14B model — too slow for
  real-time gameplay. Requires players to install and run Ollama.
- **Rejected as default**: May be supported as an alternative endpoint
  in the future (the OpenAI-compatible interface means Ollama would work
  by changing the endpoint URL).

### C. Embedded small model (ONNX / llama.cpp via GDExtension)

- **Pro**: Zero latency, offline play
- **Con**: Massive binary size, GPU memory requirements, GDExtension
  complexity. Small models (< 7B) showed poor maze navigation in prototype.
- **Rejected**: Not viable for the game's target quality and distribution model.

## Consequences

### Positive

- Players choose their own model via config — can use cheap fast models
  (Gemini Flash) or expensive smart models (GPT-4o, Claude)
- OpenAI-compatible endpoint means any provider that speaks this protocol
  works (OpenRouter, Ollama, LM Studio, vLLM, etc.)
- Tick-based architecture naturally handles API latency: the game doesn't
  freeze waiting for responses
- Separation of formatting (LLMInfoFormat) from transport (LLMAgentManager)
  means the prompt engineering can evolve independently from the API layer

### Negative

- Requires internet connection for default configuration
- API costs are borne by the player (mitigated by using cheap models as default:
  Gemini Flash is ~$0.10/1M tokens)
- API latency varies: 0.5-2s for cloud APIs, 5-15s for local models.
  The auto-advance fallback means agents may repeat moves during slow responses.
- `.env` file for API key is a simple but not user-friendly approach.
  Future: in-game settings UI for key entry.

## Configuration

All LLM parameters are data-driven via `assets/data/game_config.json`:

```json
{
  "llm": {
    "api_endpoint": "https://openrouter.ai/api/v1/chat/completions",
    "model": "google/gemini-2.0-flash-001",
    "api_timeout": 15.0,
    "temperature": 0.3,
    "max_tokens": 100,
    "env_key_name": "OPENROUTER_API_KEY"
  }
}
```
