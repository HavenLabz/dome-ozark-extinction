# DOME: OZARK EXTINCTION
## Founder Operating Guide

**For the non-technical founder building an AI-assisted commercial game.**

---

## Your role (what only you can do)

You are the **studio owner / creative director / producer**, not the programmer.

You own:

1. **Vision** — does this still feel like DOME?
2. **Taste** — is the creature scary? is the forest immersive?
3. **Priorities** — what gets built next week?
4. **Money** — when (if ever) to spend on Steam, art, legal?
5. **Go / no-go** — ship, pivot, or kill a feature?

You do **not** need to write code. AI agents and tools write code. You review outcomes.

---

## Project status (honest)

| Fact | Status |
|------|--------|
| Project start | **2026-07-30** — GitHub push was the first official act |
| Code written so far | One AI-generated **browser vertical slice** (Three.js) from the founding conversation |
| Your coding skill | None required — by design |
| Production model | **Fully AI-assisted** from ideation → commercialization |
| ClickUp | Production command center (when connected) |
| GitHub | https://github.com/HavenLabz/dome-ozark-extinction |

The Three.js slice proves the *idea* can run. It is **not** the commercial product. Treat it as a disposable prototype if the commercial engine path changes.

---

## What “AAA” means here (important)

True **AAA** (Rockstar / Ubisoft scale) means hundreds of people and nine-figure budgets. That is not an AI-solo path in 2026.

**Realistic target for AI-assisted, zero-cost-first production:**

> **Premium commercial indie** — the quality bar of games like *The Long Dark*, *Subnautica*, or a high-polish hunting sim: professional feel, strong atmosphere, believable creatures, Steam-ready, expandable.

Aim language in docs and marketing:

- “Commercial-grade prehistoric survival hunting experience”
- “Premium indie / boutique studio quality”
- **Not** “AAA” in store copy unless budget and team later match that claim

The **ambition** (creature quality, reclamation fantasy, multi-dome) can still be huge. The **honest product tier** stays premium indie until proven otherwise.

---

## How you work day to day

### 1. One sentence to the AI

Always start sessions with:

> “Read `docs/NORTH_STAR.md`, `docs/CORE_VISION_AMENDMENT.md`, `docs/DECISIONS_LOG.md`, and inspect the repo. Then build the next vertical-slice item. Do not only plan.”

Or paste the **Claude Code Launch Prompt** from `docs/AI_DEVELOPER_PROTOCOL.md`.

### 2. Your review loop (no code required)

1. AI builds something
2. You **run** it (or watch a recording / screenshots)
3. You answer only:
   - Does it feel right?
   - What’s broken or boring?
   - What should be next — still Phase 1 slice, or a different priority?
4. AI fixes and continues

### 3. Tools you will use (all free-first)

| Purpose | Tool examples |
|---------|----------------|
| Code agent | Claude Code, Cursor, Grok, etc. |
| Project tasks | ClickUp (Space: DOME: OZARK EXTINCTION) |
| Source code | GitHub (this repo) |
| Engine (TBD) | Godot 4 (strong AI + free + Steam) or continue browser prototype |
| Art | AI image/3D tools, free/CC0 assets, procedural — placeholders until quality bar |
| Audio | Free libraries / AI audio until needed |
| Build & test | Agent runs local; you playtest |

### 4. What you never need to do

- Write or debug code yourself
- Learn a full engine curriculum before starting
- Approve every technical micro-choice (AI decides and **logs** it)

### 5. What you must always do

- Protect **non-negotiables** (creature quality goal, zero-cost rule, reclamation story, modular domes)
- Playtest when something is runnable
- Say “no” to scope creep
- Keep ClickUp / Decisions Log from going stale (ask the AI to update them every session)

---

## Recommended production sequence (you only choose direction)

1. **Freeze vision** — North Star + Core Vision Amendment (done)
2. **Settle commercial engine** — Critical Decision (Godot 4 recommended default for non-coder + Steam + free + AI agents)
3. **Phase 1 vertical slice** — enter, explore, survive, hunt, trophy, extract path
4. **Creature quality path** — one believable animal before ten placeholders
5. **M2 polish** — feels like a demo you could show a stranger
6. **Only then** consider Steam fee / paid assets

---

## How to talk to the AI (copy/paste patterns)

**Start build session**

```
You are building DOME under docs/AI_DEVELOPER_PROTOCOL.md.
I don't code. Inspect the repo, read North Star + Core Vision + Decisions Log,
then implement the next vertical-slice task. Update Decisions Log and summarize
what I should playtest. No long roadmap.
```

**After playtest**

```
I played it. Problems: [list]. Feeling: [scared / bored / confused / good].
Fix those, then continue the same slice. Don't start a new major system yet.
```

**Status check**

```
Status report only: Current State, Completed, Blockers, Risks, Next Actions.
No code dump.
```

**Decision you must make**

```
I need to decide: [engine / spend money / cut feature].
Give me 3 options with cost, risk, and impact on the vertical slice.
Recommend one. I'll choose.
```

---

## Success for you as founder

You succeed when:

- strangers can download and play a coherent Ozark Dome experience
- creatures feel like animals, not arcade targets
- the path to Steam is clear and mostly already built
- you never had to become a programmer to get there

The AI is the studio. **You are the director.**
