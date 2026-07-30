# DOME: Project Decisions Log

Permanent record of major technical, creative, and production decisions.  
**Never silently change direction.**

---

### 2026-07-28 — Prototype engine: Three.js + Rapier + Vite

| Field | Content |
|-------|--------|
| **Decision** | Build first playable vertical slice in the browser using Three.js, Rapier.js physics, and Vite |
| **Reason** | Fast iteration, zero cost, immediate playable feedback, data-driven JSON content |
| **Alternatives** | Godot 4, Unity (free tier), Unreal |
| **Impact** | Working FPS survival-hunting slice exists in-repo. Creature visuals are procedural low-poly — acceptable for prototype only |

---

### 2026-07-30 — Commercial visual standard raised

| Field | Content |
|-------|--------|
| **Decision** | Creature visual quality is a primary commercial selling point; final builds must far exceed Carnivores: Ice Age fidelity |
| **Reason** | User directive; immersion and market differentiation |
| **Alternatives** | Accept stylized low-poly as final aesthetic |
| **Impact** | Prototype placeholders allowed; art pipeline and possibly engine path must support high-fidelity creatures. Open risk: Three.js browser may not be optimal for final creature fidelity — **engine evaluation for commercial path is a Critical Decision still pending** |

---

### 2026-07-30 — Zero-cost-until-necessary

| Field | Content |
|-------|--------|
| **Decision** | No spend until required for launch validation (Steam fee, legal, quality-critical assets) |
| **Reason** | User constraint; maximize playable quality before capital outlay |
| **Alternatives** | Early paid assets / outsourcing |
| **Impact** | Prefer free tools, procedural, AI-assisted, open licenses |

---

### 2026-07-30 — Narrative: World Reclamation / Dome Clearing

| Field | Content |
|-------|--------|
| **Decision** | Core fantasy is specialized hunter reclaiming Earth dome-by-dome; helicopter extraction reveal is signature moment |
| **Reason** | Core Vision Amendment; franchise longevity |
| **Alternatives** | Pure survival-only / no meta-map |
| **Impact** | Progression, extraction, and post-Ozark systems must be designed for multi-dome expansion |

---

### PENDING — Commercial engine path

| Field | Content |
|-------|--------|
| **Decision** | **OPEN** |
| **Context** | ChatGPT vision docs reference Godot 4.3+ for commercial build; current repo is Three.js prototype |
| **Must resolve before** | Heavy investment in final creature art pipelines |
| **Criteria** | Zero-cost, high creature fidelity, modular multi-dome, desktop (Steam) target, AI-agent friendliness |

---

*Add new entries at the top with date.*
