# DOME: Project Decisions Log

Permanent record of major technical, creative, and production decisions.  
**Never silently change direction.**

---

### 2026-08-01 — Navigation: dedicated per-dome map (SUPERSEDES 07-31 fallback)

| Field | Content |
|-------|--------|
| **Decision** | Each dome creates its own `NavigationServer3D` map (`OzarkWorld.nav_map`) at runtime, bakes the region navmesh onto it, and points creature agents at it via `Creature.use_navigation_map()`. Navmesh routing is now the primary locomotion; direct-steering stays as a safety net |
| **Reason** | The scene's shared world navigation map silently refused the runtime-baked region's polygons (never entered the query structure) — root-caused via minimal-repro isolation. A dedicated map accepts the same navmesh and syncs in ~20 physics frames. Bonus: a nav map per dome is cleaner modular architecture, matching the dome-content-pack rule |
| **Alternatives rejected** | Fighting the shared world map further; shipping on the direct-steering fallback alone (loses obstacle-aware routing) |
| **Impact** | Creatures path around trees/ruins on real navmesh; QA task GAME-5 closed; pattern reused for every future dome |

---

### 2026-08-01 — Art direction: zero-cost procedural stylized visuals

| Field | Content |
|-------|--------|
| **Decision** | First art pass is fully procedural/shader-based (no purchased assets): slope/height terrain shader, animated water, wind-swayed trees + grass (MultiMesh), stylized procedural creature rigs (sauropod/theropod) with speed-driven leg/tail animation, ambient birds, AgX + glow + volumetric-fog environment |
| **Reason** | North Star: creature quality is the selling point AND zero-cost-until-necessary. Procedural stylized look ships an attractive world now and reads clearly as a prehistoric forest with recognizable dinosaurs, while leaving the architecture ready for sculpted/skinned models to drop in without touching AI |
| **Alternatives rejected** | Buying/importing model packs (violates zero-cost); staying on block placeholders (fails the visual-quality bar the founder asked for) |
| **Impact** | Rigs are the seed silhouettes; final sculpted + skeletally-animated creatures replace `CreatureRig` later. Shaders live in `game/shaders/` |

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

### 2026-07-31 — Creature locomotion: navmesh-with-direct-steering fallback  ⟶ SUPERSEDED 2026-08-01

> **Superseded:** the navmesh sync bug is fixed (dedicated per-dome map, see the 2026-08-01 entry). Navmesh routing is now primary; direct steering remains only as a safety net.


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
