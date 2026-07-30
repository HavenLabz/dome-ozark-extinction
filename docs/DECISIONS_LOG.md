# DOME: Project Decisions Log

Permanent record of major technical, creative, and production decisions.  
**Never silently change direction.**

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
