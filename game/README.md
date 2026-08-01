# DOME — Godot 4 Commercial Project

**This is the real game.**  
Path: `game/` · Engine: **Godot 4.3+** (decision locked 2026-07-30)

## What exists right now (Phase 1 foundation)

| System | Status |
|--------|--------|
| Project config | ✅ `project.godot` |
| Global GameState | ✅ health, stamina, hunger, hydration, dome id |
| First-person player | ✅ move, look, sprint, crouch, jump, stamina |
| Test environment | ✅ ground, light, fog, sky, simple landmarks |
| Input map | ✅ WASD, mouse, sprint, crouch, jump, interact, fire, aim |
| Physics layers | ✅ world / player / creatures / projectiles / interactables |

## Founder: how to playtest (no coding)

1. Download **Godot 4.3 or newer** (Standard version, not .NET): https://godotengine.org/download  
2. Unzip and open Godot.  
3. **Import** → navigate to this repo’s `game/` folder → select `project.godot` → Import & Edit.  
4. Press **F5** (or the Play button).  
5. Click the game window once (mouse lock).  
   - **WASD** move · **Mouse** look · **Shift** sprint · **Ctrl** crouch · **Space** jump · **Esc** free mouse  

If something fails, tell the AI: what you clicked, what you saw, any red error text.

## Folder plan (modular for multi-dome)

```
game/
  project.godot
  scenes/           # main, player, levels, UI
  scripts/
    autoload/       # global systems
    player/
    creatures/      # AI, species (later)
    systems/        # hunting, survival, extraction (later)
  data/             # JSON / resources for creatures, weapons, domes
  assets/           # art, audio (later)
```

## Next build targets (lead priority)

1. Survival drain + simple HUD  
2. Ozark forest slice (terrain / trees / atmosphere)  
3. One peaceful creature + one predator (placeholder mesh OK)  
4. Hunting + trophy pickup  
5. Extraction stub (toward helicopter reveal)

Do not expand scope past the vertical slice until it feels like DOME.
