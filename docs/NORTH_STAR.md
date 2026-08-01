# 🧭 DOME: OZARK EXTINCTION — North Star

**The Constitutional Document for the DOME Ecosystem**

---

## How to Use This Document (Instructions for Claude / AI Developers)

This document is the **directional authority** for DOME: Ozark Extinction.

It defines:

- **WHAT** we are building
- **WHY** we are building it
- **HOW** decisions should be made
- **WHAT order** systems should be developed

This document is **not** a task tracker.

The repository defines:

- what exists
- what is implemented
- current technical reality

This document defines:

- what **SHOULD** exist
- why it matters
- what direction development moves

### Rules

1. Read this document before beginning every development session.
2. Do not modify the sections above the Appendices without explicit approval.
3. The vision is the constitution. Code is the implementation.
4. When conflicts occur:
   1. This North Star determines direction.
   2. The repository determines current reality.
   3. Settled decisions files determine technical choices already made.
5. Do not rebuild systems that already exist.
6. Do not add features because they sound impressive.
7. Every feature must pass the **Five Tests**. If it fails one test, redesign or remove it.

---

# PART 1: THE WHY

## Vision

Create the greatest prehistoric wilderness survival hunting experience ever built.

DOME: Ozark Extinction is **not** a dinosaur shooting game.

It is a digital wilderness simulator where players experience the wonder, danger, and humility of entering an ecosystem where humans are no longer dominant.

**The player is not the apex predator.**  
**The player is an intruder.**  
**The wilderness belongs to the creatures.**

## Mission

DOME exists to recreate the feeling of:

- exploring unknown wilderness
- discovering lost worlds
- studying living ecosystems
- tracking dangerous animals
- making difficult survival decisions
- earning legendary trophies

The goal is not destruction.  
The goal is discovery.  
The hunt is meaningful because the animal is meaningful.

## Core Thesis

### Wildlife First

Dinosaurs are not monsters.  
They are animals.

Every creature exists independently of the player.

They:

- eat
- sleep
- migrate
- defend territory
- flee
- hunt
- interact with other species

The player enters **their** world.  
The ecosystem does not exist for the player.  
The player exists inside the ecosystem.

## The Five Tests

Every feature must pass **ALL five**.

### 1. Immersion Test
Does this make the player feel more present inside the prehistoric wilderness?  
If it breaks immersion, reject it.

### 2. Wildlife Test
Does this make creatures feel more alive?  
A dinosaur should never feel like a walking enemy.  
It should feel like an animal.

### 3. Discovery Test
Does this reward curiosity and exploration?  
The greatest moments should come from:

- finding something unknown
- tracking something rare
- surviving something unexpected

### 4. Fear Test
Does this preserve vulnerability?  
The player should always respect the wilderness.  
Power progression should never remove danger completely.

### 5. Longevity Test
Does this create a system that can expand?  
Every feature should support:

- new creatures
- new biomes
- new stories
- new discoveries

## Founding Principles

### Principle 1 — The Ecosystem Is The Game
The weapons are not the game.  
The dinosaurs are not the game.  
**The ecosystem is the game.**

### Principle 2 — Realism Over Power Fantasy
The player should feel:

- small
- curious
- cautious
- rewarded
- impressed

Not:

- unstoppable
- invincible
- arcade-like

### Principle 3 — Emergent Gameplay Over Scripted Gameplay
The best stories are created by systems interacting.

Examples:

- A storm hides your tracks.
- A wounded predator follows you home.
- A herd migrates through your base.
- A fire drives animals into unknown territory.

The world creates the story.

### Principle 4 — Build For Expansion
Every system must be data-driven.

Creatures. Weapons. Biomes. Items. Weather. Missions.

Do not hard-code content.  
The game should become larger by adding data.

---

# PART 2: THE GAME IDENTITY

## DOME: OZARK EXTINCTION

**Genre**  
First-person prehistoric survival hunting simulator.

## Experience Pillars

The player fantasy:

> "I entered a lost world and survived long enough to bring back proof."

## Inspirations

Combined lessons from:

- Carnivores
- The Long Dark
- Red Dead Redemption hunting
- Jurassic Park survival
- ARK survival
- Far Cry exploration

But DOME must become its own identity.

## The Player Experience

Every session should contain:

| Feeling | Line |
|---------|------|
| **Wonder** | "I cannot believe I found this." |
| **Fear** | "I may not survive this." |
| **Strategy** | "I need a plan." |
| **Reward** | "I earned this discovery." |

---

# PART 3: THE WORLD

## The Dome

Year 2038.  
A government prehistoric revival experiment failed.  
A 400-acre containment research zone in the Ozarks was sealed.  
The evacuation failed.  
The scientists disappeared.  
The ecosystem continued.

The player enters as the final authorized expedition.

**Mission:**

- survive
- document species
- recover specimens
- collect legendary trophies
- escape

## World Rule

The Dome does not wait for the player.  
The Dome continues without the player.

## Ecosystems

### Ozark Forest
Primary biome. Contains forests, streams, caves, cliffs, abandoned roads, research stations.

### Mountains
Nesting areas, predator territories, military locations, viewpoints.

### Rivers
Aquatic creatures, hazards, resources.

### Lakes
Deep exploration, prehistoric aquatic predators.

### Bogs
Dangerous terrain, amphibious creatures, rare discoveries.

---

# PART 4: DEVELOPMENT PHILOSOPHY

## Architecture Rules

The game must be:

### Data Driven
Creature data lives separately from creature code.

Example: `creatures.json` controls species, stats, behavior, rarity, trophy value.

### Modular
Systems must be independent.

AI system + weather system + tracking system should interact without being permanently coupled.

### Expandable
Prototype architecture should allow:

- Prototype: ~1 km wilderness
- Future: 400-acre Dome
- Future: multiple Domes

---

# PART 5: TECHNICAL NORTH STAR

| Layer | Choice |
|-------|--------|
| **Engine** | Three.js |
| **Renderer** | WebGL / WebGPU |
| **Physics** | Rapier.js (collisions, projectiles, terrain, destruction) |
| **World** | Procedural generation — chunk loading, biome generation, LOD, streaming |
| **AI** | Behavior-driven |

### Creature Needs
Hunger · Thirst · Fear · Territory · Sleep · Reproduction

### Creature States
Idle · Explore · Feed · Drink · Sleep · Flee · Investigate · Hunt · Attack · Return

---

# PART 6: BUILD DEFINITION

## Version 0.1 — First Playable Dome

**This is the only goal until it is true.**

A stranger should be able to launch the game and experience:

> "Why did I walk into this forest?"

### Required Systems

**Player** — first-person camera, movement, sprint, crouch, jump  
**Weapons** — AR-15, 1911, ammo, reload, recoil  
**World** — forest, terrain, weather, day/night  
**Creatures** — minimum one herbivore, one predator  
**Hunting** — tracking, shooting, carcass interaction, trophy collection  
**Survival** — health, hunger, hydration, temperature, fire  
**Extraction** — trophy recovery, radio call, extraction event

## Version 1.0 Definition

DOME is complete when a player can:

Enter the Dome → Explore → Track creatures → Survive weather → Hunt → Recover trophies → Upgrade equipment → Return home → Display discoveries → Repeat.

---

# PART 7: DEVELOPMENT PHASES

| Phase | Goal | Includes |
|-------|------|----------|
| **0 — Foundation** | Permanent architecture | Repository, engine, folder structure, data systems, build pipeline |
| **1 — Survival Loop** | Make the game playable | Movement, weapons, first creatures, tracking, trophies |
| **2 — Living Ecosystem** | Make the world alive | Advanced AI, migration, predator/prey, reproduction |
| **3 — Wilderness Expansion** | Expand the Dome | Additional biomes, caves, rivers, mountains |
| **4 — Persistence** | Make the world remember | Saves, bases, trophies, discoveries |
| **5 — Commercial Release** | Complete product | Optimization, multiplayer research, additional maps, content updates |

---

# PART 8: HARD RULES

1. **Never sacrifice gameplay for graphics.** A beautiful empty world is failure. A simple living world is success.
2. **Never create fake systems.** A button that says "tracking coming soon" does not exist.
3. **Never prioritize quantity over depth.** One believable dinosaur is better than fifty lifeless ones.
4. **Never make dinosaurs bullet sponges.** Creatures are animals.
5. **Never break immersion unnecessarily.**

---

# PART 9: AI DEVELOPMENT RULES

You are not writing documentation.  
You are building the game.

### Every session:

1. Read this document.
2. Inspect the repository.
3. Continue from current reality.
4. Build the next highest-value system.

### Do not:

- rewrite architecture without reason
- create unnecessary frameworks
- add features outside scope
- generate fake completion reports

### Definition of Success

DOME succeeds when players say:

> "I forgot I was playing a game. I was surviving somewhere."

---

# APPENDICES

## Appendix A — Repository Links

| Resource | URL |
|----------|-----|
| **GitHub** | https://github.com/HavenLabz/dome-ozark-extinction |
| **Default branch** | `main` |
| **Production** | TBD (browser build / hosting not yet configured) |

## Appendix B — Developer Handoff

A new developer must be able to continue development with:

- repository access
- build instructions (`npm install` → `npm run dev`)
- architecture documentation (this North Star + settled decisions)
- asset pipeline notes
- deployment instructions (when available)

**Quick start:**

```bash
git clone https://github.com/HavenLabz/dome-ozark-extinction.git
cd dome-ozark-extinction
npm install
npm run dev
```

## Appendix C — Settled Decisions

| Decision | Choice |
|----------|--------|
| Engine | Three.js |
| Physics | Rapier.js (`@dimforge/rapier3d-compat`) |
| Architecture | Data-driven (JSON for creatures, weapons, future biomes/items) |
| Primary platform | Desktop browser |
| Prototype scope | Vertical slice first |
| Build tool | Vite |
| Controls | Custom pointer-lock FPS (no Three.js examples dependency) |

---

*The North Star should stay stable while supporting documents evolve:*

1. DOME Master Game Design Document
2. DOME Technical Architecture Document
3. DOME Creature Bible
4. DOME World Generation Bible
5. DOME Development Roadmap
6. DOME AI Developer Protocol
