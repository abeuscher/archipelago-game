# Archipelago

A turn-based strategy roguelike in Godot 4.7, GDScript, 2D. The design is in [spec.md](spec.md). Interpretations and gap-fills are in [ASSUMPTIONS.md](ASSUMPTIONS.md).

## Layout

| Folder | What it holds |
| --- | --- |
| `data/` | Every number: `rules.json`, `settings.json`, `ai.json`. Also `required_assets.txt`, which lists the media the game needs. |
| `rules/` | The rules engine: plain GDScript classes with no scenes or rendering. |
| `ai/` | The enemy AIs. Each sees only a `SideView`. `strong_ai.gd` is the section 12 AI the game uses; `simple_ai.gd` is the step 3 baseline. |
| `tools/` | The headless batch runner. |
| `tests/` | Rules tests and a small test runner. |
| `game/` | Scenes and presentation (step 4 onward). Interface pieces: `hud.gd`, `research_panel.gd`, `esc_menu.gd`, `tips.gd`, `earnings.gd`. Tip wording is in `data/tips.json`. |

## Play

```powershell
& "C:\Godot\Godot_v4.7.2-stable_win64.exe" --path .                   # new game, random seed
& "C:\Godot\Godot_v4.7.2-stable_win64.exe" --path . -- --seed 1234    # reproducible island and dice
```

You can also open the folder in the Godot editor and press F5.

Controls:

| Action | How |
| --- | --- |
| Select or place | Left click |
| Pan | Right-drag or middle-drag, or the arrow keys |
| Zoom | Mouse wheel |
| Rotate the board 60° | Q / E, or the arrow buttons at the top |
| Look at the other island | Click its half of the minimap |
| Cancel a tool or selection | Right click |
| Pause, options, quit | Esc |

The screen follows section 14 of the spec:

- **Left toolbar.** Buildings during build and repair. During targeting: the fuel planner, your launchers, Undo and Attack. The timer is at the bottom.
- **Right strip.** A beaker for each research project, then a button for each base showing its hits left. Click a beaker to open the research panel. Click a base to jump to it.
- **Research.** Select a lab and press "Research...", or click a beaker.
- **Top right.** "Next round" shows next round's projected income. "Log" opens the full game log; events also flash at the top as they happen.

Settings and tip progress are saved to `user://settings.json`. On Windows that is `%APPDATA%\Godot\app_userdata\Archipelago\settings.json`. Delete the file to reset them.

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
& $GODOT --headless --path . -s tools/batch.gd -- --matches 200 --ai0 strong --ai1 simple --swap
& $GODOT --headless --path . -s tools/batch.gd -- --matches 200 --ai0 strong --ai1 strong:easy --swap
```

`--ai0` and `--ai1` pick the AI for each side: `simple`, `strong`, or `strong:<handicap>` with a preset from `data/ai.json` (`none`, `medium`, `easy`). Both default to `strong`, which is the AI the game uses. `--swap` alternates sides match by match and reports wins by AI.

`--set` overrides a data value for that run only. It never edits the data files. The defaults for match count, seed and the round cap are in `data/ai.json` under `batch`. A match that reaches the round cap is reported as a timeout.

Screenshots (development aid: drives the real scene through setup, a build with research, targeting, the Esc menu and one playout, in a window; it uses its own settings file):

```powershell
& "C:\Godot\Godot_v4.7.2-stable_win64_console.exe" --path . -s tools/capture.gd -- <output folder> [seed]
```
