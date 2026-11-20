# Session 016 brief (first session on the Mac)

Archipelago is a turn-based strategy game in Godot 4.7.2 and GDScript. Start by reading README.md, spec.md, ASSUMPTIONS.md and PLAN.md at the root, then carry on with PLAN.md. Level 4, the spy, is next; agree the spy's details with the user before building it, as was done for the nuke in session 012.

Everything below was set up on the user's Windows PC and won't reach you any other way.

## Moving from Windows to the Mac

- **Godot.** README.md and the tool headers give Windows paths (`C:\Godot\...exe`). On the Mac the binary is normally `/Applications/Godot.app/Contents/MacOS/Godot`. Check where it actually is, and that it is 4.7.2.
  - Before anything else, build the import cache: `"$GODOT" --headless --path . --import`
  - Tests: `"$GODOT" --headless --path . -s tests/run_tests.gd`. 128 should pass. If any fail on the Mac, report it before changing anything.
- **Python** is `python3`. The `music_src/*.py` scripts are run with it.
- **Line endings.** `.gitattributes` forces LF.
- **Saved settings** go to `~/Library/Application Support/Godot/app_userdata/Archipelago/settings.json` (README.md gives the Windows path).
- **ETC2/ASTC texture import** is on in `project.godot` (`textures/vram_compression/import_etc2_astc=true`), for the macOS export. The user is the only person they send macOS builds to, so the export warnings can be left alone.
- **Source files.** The end-reel video sources (`music_src/*.ogv`) and the voice files are all committed. The game itself plays the copies in `assets/video/`.
- **The voice script.** `music_src/voice_parts.md` holds the user's own edits. Running `music_src/make_voice_parts.py` overwrites that file, so ask the user first.

## Working rules

- **Branches.** Work on a `session-NNN` branch made from `main`, which is `session-016` this time. Never commit to `main`; run `git branch --show-current` before every commit. The user merges into `main`.
- **Commits.** Commit and push at the end of each piece of work the user asks for. Don't commit `.vscode/`, or files the user changed but didn't ask you to touch. End each commit message with the co-author line your harness gives you.
- **ASSUMPTIONS.md.** Record every rule or design decision you make or change there as a new numbered row. D113 is the latest. When a row stops being true, update it.
- **Data first.** Numbers and text live in `data/*.json` (rules, levels, ai, sounds, dialogue), not in code. Each file has `_about` / `_<key>` notes that explain its fields; keep them current.
- **Tests.** Add or adjust tests in `tests/` with each change.

## The user's preferences

- Keep on-screen text minimal.
- Make only the appearance changes they ask for. Don't restyle anything nearby.
- The audio should feel relaxed, and music changes fade, never cut.
- The enemy AI gets everything the player gets, and plays it to win. Each new unit or upgrade needs strong-AI support (`ai/strong_ai.gd`, `data/ai.json`) and tests.
- Games should last a while. Check the effect of each new level or unit with `tools/level_study.gd`, which runs strong-against-strong matches per level and prints median rounds and nukes fired:

  ```
  "$GODOT" --headless --path . -s tools/level_study.gd -- --levels 1,2,3 --matches 150
  ```

  The last baseline: level 1 median 19 rounds, level 2 32, level 3 31, with a nuke fired in 34 of 150 level 3 matches. Report numbers like these to the user when balance changes.
- `tools/batch.gd` is the general AI-against-AI runner; `--set path=value` overrides one data value for a single run.
- The user play-tests and replies with short notes, often with typos. Read them generously; ask only when a note can genuinely be read two ways.

## Checking changes visually

To check interface changes, write a small `extends SceneTree` script in your scratchpad. It should:

1. instance `res://game/main.tscn`;
2. set the metas `seed_override` and `settings_path` (a temporary file, so the user's settings stay untouched);
3. drive the UI by calling main's methods;
4. save screenshots with `root.get_viewport().get_texture().get_image().save_png(...)` after `await RenderingServer.frame_post_draw`.

Run it windowed (not headless) with `"$GODOT" --path . --resolution 1600x900 -s <script>`, then look at the PNGs. `tools/capture.gd` is a fuller example.
