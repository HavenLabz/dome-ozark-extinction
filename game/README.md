# DOME — Godot 4 Commercial Project

**This is the real game.**  
Path: `game/` · Engine: **Godot 4.3+** (decision locked 2026-07-30)

## What exists right now

| System | Status |
|--------|--------|
| Project config | ✅ |
| First-person player | ✅ move, look, sprint, crouch, jump, stamina |
| Survival drain | ✅ hunger, water, damage when empty |
| HUD | ✅ health / stamina / hunger / water bars |
| Test environment | ✅ ground, light, fog, landmarks |

## Founder: how to playtest

1. Download **Godot 4.3+** Standard: https://godotengine.org/download  
2. Import the **`game/`** folder (`project.godot`).  
3. **Project → Project Settings → Display → Window → Mode = Windowed** (if Play embedding fails).  
4. Press **F5**. Click the game view once.  

Controls: WASD · Mouse · Shift sprint · Ctrl crouch · Space jump · Esc free mouse  

Sprint to watch **Stamina** drop. Wait to watch **Hunger / Water** slowly fall.

## Updating after AI pushes

Re-download the GitHub ZIP and re-import `game/`, **or** replace the changed files inside your existing `game` folder, then in Godot: **Project → Reload Current Project**.

## Next build targets

1. Ozark forest atmosphere  
2. Creatures (peaceful + predator)  
3. Hunting + trophies  
4. Extraction stub  
