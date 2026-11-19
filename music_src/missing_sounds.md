# Sounds still to make

The game already plays a sound wherever there is a file. To add one, put it in `assets/audio/` with the name below; `.ogg` or `.wav` both work. You can change any name in `data/sounds.json`.

## Hooked up, waiting for a file

These moments already play a sound. Only the file is missing.

| File | When it plays |
|---|---|
| `transport_engine.ogg` | Our transport plane takes off from its airport |
| `cannon_shot.ogg` | A coastal cannon fires at a boat |
| `bunker_fire.ogg` | A bunker wipes out a platoon |

## Not hooked up yet

These moments make no sound at present. Tell me which you want, and the file names, and I'll add them.

| Suggested file | When it would play |
|---|---|
| `siren.ogg` | The incoming-missile siren before the enemy attack lands |
| `research_done.ogg` | A research project finishes |
| `build_anti_air.ogg` | An anti-air gun is built |
| `build_bunker.ogg` | A bunker is built |
| `build_coastal_cannon.ogg` | A coastal cannon is built |
| `build_decoy.ogg` | A decoy is built |
| `build_base.ogg` | A base is placed in setup |
| `click.ogg` | A button click |
| `victory.ogg` | Winning the match |
| `defeat.ogg` | Losing the match |

The five building sounds could also be one shared construction sound.

## Placeholders to replace

These are synthesised stand-ins made by `music_src/make_ambient.py`. You can replace any of them with a real recording of the same name.

| File | What it is |
|---|---|
| `ambient_ocean.wav` | The sea: a seamless loop, louder when zoomed in |
| `ambient_island.wav` | Breeze and small birds: a seamless loop, heard mostly when zoomed in |
| `gull_1.wav` … `gull_4.wav` | Single gull calls, played now and then; list as many as you like in `data/sounds.json` |
