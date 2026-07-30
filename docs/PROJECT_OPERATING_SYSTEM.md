# DOME: OZARK EXTINCTION
## Project Operating System — Production Management Framework

**Purpose:** Single production command framework for decisions, tasks, milestones, assets, bugs, research, testing, and release.

Whether tracked in ClickUp, GitHub Issues/Projects, or both — this hierarchy and format is mandatory.

---

## PROJECT STRUCTURE

```
DOME: OZARK EXTINCTION
├── 00 PROJECT COMMAND CENTER
├── 01 GAME DESIGN
├── 02 TECHNICAL DEVELOPMENT
├── 03 ART & ASSETS
├── 04 WORLD BUILDING
├── 05 CREATURE DEVELOPMENT
├── 06 GAMEPLAY SYSTEMS
├── 07 UI UX
├── 08 AUDIO
├── 09 TESTING & QA
├── 10 MARKETING & STORE
├── 11 RELEASE MANAGEMENT
└── 12 POST-LAUNCH CONTENT
```

---

## TASK TYPES

Every task belongs to **one** category:

| Type | Meaning | Example |
|------|---------|--------|
| **Feature** | New gameplay capability | Implement dinosaur tracking system |
| **System** | Underlying framework | Create creature AI state machine |
| **Asset** | Visual/audio content | Create Ozark forest environment assets |
| **Bug** | Something broken | Raptor AI gets stuck near rocks |
| **Research** | Investigation required | Analyze Steam survival game pricing |
| **Decision** | Choice that affects the project | Choose commercial engine path |

---

## TASK REQUIREMENT FORMAT

Every development task must contain:

| Field | Content |
|-------|--------|
| **Objective** | What needs to exist when complete |
| **Why It Matters** | How it improves the player experience |
| **Dependencies** | What must exist first |
| **Acceptance Criteria** | How we know it is finished |
| **Testing Method** | How it will be verified |
| **Priority** | Critical / High / Medium / Low |

Vague tasks are not allowed.

---

## DEVELOPMENT MILESTONES

### Milestone 1 — Foundation Prototype
**Goal:** Playable first-person survival hunting experience.  
**Required:** player controller, environment, weapons, basic dinosaur AI, hunting loop, survival basics.

### Milestone 2 — Vertical Slice
**Goal:** Polished demo representing the final game.  
**Includes:** complete hunting loop, trophy system, extraction, weather, day/night, base camp.

### Milestone 3 — Early Access Build
**Goal:** Commercially playable version.  
**Includes:** multiple creatures, expanded map, progression, save system, optimization.

### Milestone 4 — Launch Candidate
**Goal:** Steam-ready product.  
**Includes:** final polish, achievements, settings, performance testing, store assets.

### Milestone 5 — Post Launch
**Goal:** Long-term expansion.  
**Includes:** new domes, new species, DLC, updates.

---

## QUALITY CONTROL

Every completed feature requires:

1. **Functional Test** — Does it work?
2. **Performance Test** — Does it run efficiently?
3. **Player Experience Test** — Is it fun / immersive?
4. **Commercial Test** — Does this improve the product?

---

## DECISION LOG

Permanent document: [`docs/DECISIONS_LOG.md`](./DECISIONS_LOG.md)

Every major decision records:

- Date
- Decision
- Reason
- Alternatives Considered
- Impact

---

## CHANGE MANAGEMENT

Before adding new features, ask:

1. Improve player enjoyment?
2. Increase replayability?
3. Improve sales potential?
4. Fit development capacity?

If no → **Future Ideas** (do not pollute active sprint).

---

## ALIGNMENT WITH NORTH STAR PHASES

| OS Milestone | North Star Phase |
|--------------|------------------|
| M1 Foundation Prototype | Phase 0–1 |
| M2 Vertical Slice | Phase 1 complete |
| M3 Early Access | Phase 2–4 |
| M4 Launch Candidate | Phase 5 |
| M5 Post Launch | Expansion |
