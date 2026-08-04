# HANDOFF — DOME: Ozark Extinction (slug: dome-phase1)
_Last session: 2026-07-31 → 2026-08-01. Engine: Godot 4.7.1 (bundled at `../../_godot_bin/`)._

Addressed to the **next dev session**. Read `docs/NORTH_STAR.md` + `docs/DECISIONS_LOG.md` first, then this.

---
## SESSION 2026-08-03 (latest — read first)
Branch `phase1-creatures-visuals`, HEAD **`85b954e`**, pushed & remote-verified. Smoke **13/13**. Fresh Windows exe at `game/dist/DOME-Ozark-Extinction.exe` (~397 MB, rebuilt 19:10 — contains all fixes; NOT in git, it's the build artifact).

**DONE this session:**
- **Ambush stalker no longer erupts on the player** (`game/scripts/creatures/ambush_stalker.gd`). Root cause: it homed to the player's *exact* XZ underground and surfaced inside the camera — invisible, unshootable, 3-hit kill. Fix: holds a `STANDOFF` (5 m) while lurking, snaps to a visible `EMERGE_STANDOFF` (9 m) surface point before erupting, keeps `MELEE_RANGE` 5 m so it stays shootable, `REGROUP` 3 s between strikes, `DAMAGE` 34→22. It's invisible underground so the pre-eruption XZ snap reads as an ambush, not a teleport.
- **Wind ambience no longer reads as looping "waves"** (`game/scripts/autoload/sound_manager.gd`). Two passes: first added a seamless crossfade loop (`_seamless`) killing the click; then replaced the swelling gust envelope with a **steady band-limited hiss** (no amplitude envelope) — the swell was what pulsed like waves on every loop. Rain got the same crossfade. **If the old build still sounded wavy, it predated the fix — the 19:10 exe is correct.**
- **First-person procedural leg walk** (earlier this session, commit `7e8a3b7`): `player_controller.gd` loads `assets/character.glb`, disables its A-pose AnimationPlayer, drives a procedural walk (flex about skeleton-space X via parent-bone frame — `_pose_leg`). `--shotlegs` debug harness kept.
- **Mixamo pipeline set up:** installed **Blender 5.2** (`C:\Program Files\Blender Foundation\Blender 5.2\blender.exe`) and **uv** (both via winget). `tools/glb_to_fbx.py` converts the character; produced `C:\Users\Jamon\Desktop\DOME Ozark Extinction\character.fbx` (50 MB) ready for Mixamo upload.

**LEFT / next:**
- **Mixamo (Jamon's hands):** upload `character.fbx`, apply rifle Idle/Walk/Run (In Place), download FBX (30fps, keyframe none; With Skin on first, Without Skin on rest) into `game/assets/anims/`. Then next session wires them to the AnimationPlayer and **deletes the procedural walk**.
- **BlenderMCP:** addon extracted at `blender-mcp-extracted/blender-mcp-main/addon.py`; NOT yet registered in Claude config and won't load until an app restart. Install addon in Blender → enable → N-panel → Connect to Claude; register with `claude mcp add`; restart. Not on the critical path (headless Blender handles conversions).
- Verify licenses of user-supplied GLBs (character, dragon/phoenix/pterodactyl) before commercial ship.

**Scope not touched this session:** creature AI FSM, world gen, weapons, UI, shaders — all untouched. No master merge / production deploy.

---
## TL;DR
Phase 1 vertical slice is **playable and validated**: first-person player, procedural navigable Ozark world, data-driven creature AI (herbivore + predator), working hunt→trophy loop, and a real stylized visual pass (shaders, animated procedural dinosaurs, grass, water, birds). Behavioral smoke test: **10/10**.

## How to run / playtest
- **Play:** double-click `PLAY DOME.bat` (in the outer `DOME Ozark Extinction/` folder). Controls in `HOW TO PLAY.md`.
- **Run from CLI (windowed):** `_godot_bin\Godot_v4.7.1-stable_win64.exe --path game`
- **Headless behavioral test:** `..\..\_godot_bin\Godot_v4.7.1-stable_win64_console.exe --headless --quit-after 1800 --path game -- --smoke` → prints PASS/FAIL, exits non-zero on failure.
- **Beauty screenshots:** add `-- --shot <path>` (overview), `--shot <path> --shotcreature` (creature closeup), or `--shot <path> --shotground` (player eye).
- **After adding any new `class_name` script:** run `--headless --editor --quit --path game` once to rebuild the global class cache, or you'll get "Could not find type X" parse errors.

## DONE this session
- **Creature AI foundation** — `game/scripts/creatures/`: `creature_data.gd` (data resource), `creature.gd` (FSM: IDLE/WANDER/INVESTIGATE/FLEE/HUNT/ATTACK/DEAD + territory, memory, combat, death→trophy), `perception.gd` (sight FOV+LOS raycast, hearing louder on sprint), `creature_rig.gd` (procedural sauropod/theropod visual + leg/tail animation). Species data: `game/data/creatures/ozark_grazer.tres`, `ridge_raptor.tres`.
- **World** — `game/scripts/world/`: `terrain_generator.gd` (noise heightfield mesh + trimesh collision + slope/height shader), `ozark_world.gd` (assembles terrain, forest, grass MultiMesh, water, ruins, cache; bakes navmesh onto a dedicated map; spawns wildlife + player; also hosts `--smoke`/`--shot`), `trophy_pickup.gd`, `water_source.gd`, `bird_flock.gd`.
- **Player** — `game/scripts/player/player_controller.gd`: added `player` group, `is_making_noise()`, `apply_damage()`, seed hitscan weapon (fire), interaction ray (E) + prompt signal.
- **UI** — `game/scripts/ui/hud.gd` (crosshair, vitals, trophy score, interact prompt).
- **Shaders** — `game/shaders/`: `terrain.gdshader`, `water.gdshader`, `wind_foliage.gdshader`.
- **Scene** — `game/scenes/main.tscn` rewired as the Ozark world + polished environment (AgX, glow, volumetric fog, soft-shadow sun).
- **Bug fixed:** runtime navmesh sync (was empty map). See DECISIONS_LOG 2026-08-01 and ClickUp GAME-5. Root cause: shared world nav map rejected the baked region; solution = dedicated per-dome nav map + ~20-frame sync wait.

## LEFT
**Buildable now (no blockers):**
- Full **weapon system** (AR-15 + 1911: ammo, reload, recoil) — replaces the hitscan seed in `player_controller.gd`.
- **Survival drain** (hunger/hydration over time) + **day/night cycle** + **fire/campfire**.
- **Hunting depth** from the Master Build Prompt: footprints/tracks, sound cues, binocular ID (species/danger/trophy rating).
- **Trophy extraction** per spec: flare → wait → survive → extract (current version is instant interact-to-collect).
- Named species from spec (Brachiosaurus/Velociraptor/T-Rex) + apex predator territory; add as `.tres` + spawn lines.
- **Base building** (campfire/shelter/storage); **weather** (rain/fog/storms/lightning).
- Art: sculpted/skinned creature models to replace `CreatureRig`; mesh variety for trees/rocks.

**Blocked on Jamon (decisions):** see the decision list I left in chat.

## Gotchas / traps hit (don't re-learn these)
- **Terrain winding matters twice:** inverted winding = down-facing normals = no collision (one-sided trimesh) AND empty navmesh (Recast culls). Keep terrain triangles wound so normals point +Y.
- **Runtime navmesh:** the shared world nav map will silently stay empty. Use a **dedicated** `NavigationServer3D.map_create()` map and wait ~20 physics frames before querying. `map_force_update` alone is not enough.
- **`CollisionShape3D` must be a DIRECT child** of the `StaticBody3D` (not nested under a MeshInstance) or it won't register.
- **Project treats "inferred-from-Variant" as an error** — type your vars (`var sc: Script = ...`).
- **New `class_name` → rebuild class cache** (see above) before headless runs.
- Headless can't validate shaders — run **windowed** to catch shader compile errors.
- Non-blocking warning at bake: "navigation region … edge error(s)" from dense terrain edges; navmesh still works.

## Git / scope
- Repo initialized at `dome-ozark-extinction-main/dome-ozark-extinction-main/`. Work committed on branch **`phase1-creatures-visuals`** and **pushed to `origin` (HavenLabz/dome-ozark-extinction)**.
- ⚠️ **Unrelated history:** local was created from a zip, not a clone, so this branch shares no history with `origin/main`. To integrate: either treat this branch as the new baseline, or in a fresh clone copy `game/` + `docs/` over and commit. **Do not force-merge to main without Jamon's approval.**
- **Scope not touched:** the Three.js browser prototype under repo root (`src/`, `index.html`, `vite.config.js`) is reference-only per DECISIONS_LOG — left untouched. No production deploy/export was made (no export templates installed); playtest runs on the bundled engine via `PLAY DOME.bat`.
