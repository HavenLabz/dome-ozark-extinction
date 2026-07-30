# DOME: OZARK EXTINCTION

**First-person prehistoric survival hunting simulator** — browser vertical slice.

Year 2038. A containment dome seals a failed prehistoric revival experiment in the Ozark wilderness. You are the last authorized entry. Survive, track, hunt, collect trophies, and extract.

## Run

```bash
git clone https://github.com/HavenLabz/dome-ozark-extinction.git
cd dome-ozark-extinction
npm install
npm run dev
```

Open the URL shown (usually http://localhost:5173). Click **ENTER THE DOME**, then click the game view to capture the mouse.

## Controls

| Key | Action |
|-----|--------|
| WASD | Move |
| Shift | Sprint |
| Ctrl | Crouch |
| Space | Jump |
| Mouse | Look |
| LMB | Fire |
| RMB | Aim (ADS) |
| R | Reload |
| 1 / 2 | AR-15 / 1911 |
| E | Collect trophy (near carcass) |
| T | Deploy extraction flare |
| F | Build campfire |
| B | Binoculars (info) |
| Esc | Release mouse |

## Vertical Slice Features

- Procedural forest terrain with height variation, lakes, trees, rocks
- First-person movement with physics (Rapier)
- AR-15 (full-auto) + 1911 handgun with ammo, reload, recoil, ADS
- Herbivores: Triceratops, Stegosaurus (flee / graze)
- Predators: Utahraptor pack + Carnotaurus (investigate → attack)
- Footprint tracking system
- Day/night cycle + dynamic weather (rain/storm)
- Survival: health, hunger, thirst, temperature
- Campfires (warmth + light)
- Trophy collection + extraction flare
- HUD: vitals, weapon, compass, time, messages

## Tech

- Three.js (WebGL)
- Rapier.js physics
- Vite
- Data-driven creatures & weapons (JSON)

## Notes

This is a **playable vertical slice**, not a full AAA title. Models are low-poly procedural. World is ~360 m across for performance. Expand biomes, AI behavior trees, building, and taming in later phases.

## License

MIT
