# Sounds still to make

The game already plays a sound wherever there is a file. To add one, put it in `assets/audio/` with the name below; `.ogg` or `.wav` both work. You can change any name in `data/sounds.json`.

## Hooked up, waiting for a file

These moments already play a sound. Only the file is missing.

| File | When it plays |
|---|---|
| `transport_engine.ogg` | Our transport plane takes off from its airport |
| `cannon_shot.ogg` | A coastal cannon fires at a boat |
| `bunker_fire.ogg` | A bunker wipes out a platoon |

## Sharing a sound for now

These buildings have no sound of their own yet. They play the shared construction sound (`build` → `default` in `data/sounds.json`, currently `missile_build.ogg`). To give one its own sound, add a line for it under `build`.

| Building | Name to add under `build` |
|---|---|
| Anti-air gun | `anti_air` |
| Bunker | `bunker` |
| Coastal cannon | `coastal_cannon` |
| Decoy | `decoy` |
| Base (placed in setup) | `base` |
| Stronghold (placed in setup, level 2) | `stronghold` |

## Placeholders to replace

These are synthesised stand-ins made by `music_src/make_ambient.py`. You can replace any of them with a real recording of the same name.

| File | What it is |
|---|---|
| `ambient_ocean.wav` | The sea: a seamless loop, louder when zoomed in |
| `ambient_island.wav` | Breeze and small birds: a seamless loop, heard mostly when zoomed in |
| `gull_1.wav` … `gull_4.wav` | Single gull calls, played now and then; list as many as you like in `data/sounds.json` |

## Done

Missile launch, missile explosion, anti-air fire and hit, countdown, lab, bank, missile launcher, airport, docks, radar, repair, siren, research complete, button click, you win, you lose.
