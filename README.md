# Archipelago

A turn-based strategy roguelike in Godot 4.7, GDScript, 2D. The design is in [spec.md](spec.md). Interpretations and gap-fills are in [ASSUMPTIONS.md](ASSUMPTIONS.md).

## Layout

| Folder | What it holds |
| --- | --- |
| `data/` | Every number: `rules.json`, `settings.json`, `ai.json`. Also `required_assets.txt`, which lists the media the game needs. |
| `rules/` | The rules engine: plain GDScript classes with no scenes or rendering. |
| `ai/` | The enemy AI. It sees only a `SideView`. |
| `tools/` | The headless batch runner. |
| `tests/` | Rules tests and a small test runner. |
| `game/` | Scenes and presentation (step 4 onward). |

## Commands

Set `GODOT` to the console build, for example `C:\Godot\Godot_v4.7.2-stable_win64_console.exe`.

PowerShell:

```powershell
$GODOT = "C:\Godot\Godot_v4.7.2-stable_win64_console.exe"
& $GODOT --headless --path . --import            # first time only: builds the .godot cache
& $GODOT --headless --path . -s tests/run_tests.gd               # all tests
& $GODOT --headless --path . -s tests/run_tests.gd -- combat     # tests whose file:name contains "combat"
```

The test runner exits with code 0 when every test passes.

Batch runner (AI against AI, headless):

```powershell
& $GODOT --headless --path . -s tools/batch.gd -- --matches 500
& $GODOT --headless --path . -s tools/batch.gd -- --matches 500 --seed 501
& $GODOT --headless --path . -s tools/batch.gd -- --matches 500 --set rules.anti_air.engagements=1
& $GODOT --headless --path . -s tools/batch.gd -- --matches 100 --csv batch_results/run.csv
```

`--set` overrides a data value for that run only. It never edits the data files. The defaults for match count, seed and the round cap are in `data/ai.json` under `batch`. A match that reaches the round cap is reported as a timeout.
