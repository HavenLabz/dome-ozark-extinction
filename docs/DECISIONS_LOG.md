# DOME: Project Decisions Log

Permanent record of major technical, creative, and production decisions.  
**Never silently change direction.**

---

### 2026-07-31 — Creature AI architecture: data-driven single-script FSM

| Field | Content |
|-------|--------|
| **Decision** | All wildlife runs on one `creature.gd` FSM driven by `CreatureData` (.tres) resources. States: IDLE, WANDER, INVESTIGATE, FLEE, HUNT, ATTACK, DEAD, with enter/exit hooks. Senses isolated in `perception.gd` |
| **Reason** | North Star "Wildlife First" + "build for expansion": new species = new data file, not new code. Enum-FSM chosen over node-graph FSM for robustness/readability at foundation stage |
| **Alternatives rejected** | Per-species subclasses (code bloat); node-based state machine (more moving parts, no benefit yet) |
| **Impact** | Add creatures by authoring `.tres` + a spawn line. New behaviors (Feed, Drink, Sleep, Mate, Migrate) drop in as new states without rewrites |

---

### 2026-07-31 — Hitscan weapon is the seed, not a placeholder

| Field | Content |
|-------|--------|
| **Decision** | Player `fire` does a camera hitscan applying real damage; this is the seed the full weapon system extends |
| **Reason** | Keeps the core loop honest and testable now (aim→fire→damage→trophy) without faking a "weapons coming soon" system (Hard Rule #2). Full weapons (AR-15/1911, ammo, reload, recoil) are a later slice |
| **Impact** | `weapon_hitscan`-style logic lives in the player controller; replace/extend, don't rebuild |

---

### 2026-07-31 — Creature locomotion: navmesh-with-direct-steering fallback

| Field | Content |
|-------|--------|
| **Decision** | Creatures follow the baked navmesh path when available, else steer straight at the goal (collision slides them around obstacles) |
| **Reason** | Runtime-baked navmesh is not yet syncing into the navigation map (map_get_path returns 0; see QA task GAME-5). Fallback keeps the AI fully functional and demonstrable now; navmesh routing engages automatically once the sync bug is fixed |
| **Alternatives rejected** | Blocking the whole creature foundation on the nav sync bug; ripping out navmesh entirely (it's correct and cheap to keep) |
| **Impact** | Behavior unaffected today; obstacle-aware routing improves for free later |

---

### 2026-07-30 — Commercial engine: Godot 4 (LOCKED)

| Field | Content |
|-------|--------|
| **Decision** | **Godot 4.3+** is the commercial production engine for DOME: Ozark Extinction |
| **Reason** | Founder authorized lead to decide. Best fit for AI-first, non-coder founder, zero-cost, Steam desktop target, creature fidelity headroom, modular multi-dome architecture |
| **Alternatives rejected** | Three.js (prototype only), Unity, Unreal |
| **Impact** | All new commercial systems are built in Godot under `game/`. Three.js browser slice remains under repo root as founding reference only — do not extend it as the product. Next work: Phase 1 vertical slice in Godot (player → environment → hunting loop) |

---

### 2026-07-30 — Project officially starts; AI-first, non-coder founder

| Field | Content |
|-------|--------|
| **Decision** | Fully AI-assisted production. Founder does not write code. GitHub push is first official act |
| **Impact** | Agents assume non-technical owner; playtest-friendly outputs; log decisions every session |

---

### 2026-07-30 — Three.js browser slice is founding prototype only

| Field | Content |
|-------|--------|
| **Decision** | Three.js + Rapier + Vite code is reference / history, not ship path |
| **Impact** | Do not invest final art or long-term systems in browser stack |

---

### 2026-07-30 — Commercial visual standard raised

| Field | Content |
|-------|--------|
| **Decision** | Creature quality is a primary selling point; final builds exceed Carnivores: Ice Age fidelity |
| **Impact** | Placeholders OK early; architecture must support high-fidelity replacement |

---

### 2026-07-30 — Zero-cost-until-necessary

| Field | Content |
|-------|--------|
| **Decision** | No spend until required for launch validation |
| **Impact** | Free tools, procedural, AI-assisted, open licenses first |

---

### 2026-07-30 — Narrative: World Reclamation / Dome Clearing

| Field | Content |
|-------|--------|
| **Decision** | Reclamation fantasy; helicopter extraction reveal; multi-dome long-term |
| **Impact** | Modular dome architecture required |

---

*Add new entries at the top with date.*
