# Work queue

## Troops (agreed; rules in spec.md section 10, art brief in docs/troop_assets.md)

1. **Research tabs.** Buildings and Upgrades tabs on the research screen; radar and ballistic launcher move to Buildings; airport, bunker, docks and coastal cannon appear there.
2. **Airport, air transport, platoon, bunker.** Rules (landing, three-hex march, can jump down but not climb, bunker range 2, kills a base outright, anti-air on transports), two-click targeting with a direction arrow, playout with parachutes, AI use and defence, tests, batch.
3. **Docks, boats, coastal cannons.** Two-round crossing visible in the channel, coastal landings, cannon fire.
4. Spy helicopter and checkpoints: dropped.

Placeholder art until the brief's assets arrive: simple drawn soldiers, plane and boat.

## Waiting on a spec

- **To discuss: selling unused fuel.** Raised as a counter to a launcher being kept out of action (a side that can't fire could sell its fuel for money). Parked: it may be an unwelcome complication in a simple game. Notes: it should be a manual choice in the build phase (stockpiling fuel is a real strategy); the price must stay well under 5 money per fuel (around 2) or refineries become better banks; it helps most with a stockpile and little in the first rounds; the AI would need to learn it.

- **More characters.** The announcer space takes any character listed in `data/characters.json`; tips and announcements can name who speaks. Ginger is the only one so far.
- **Fog look and feel.** Edges are clean for now (no soft spill onto revealed ground); revisit the style later.

## Session 005 (play-test notes, 2026-11-18): done

All six items are built; ASSUMPTIONS.md D54 to D58 and P2 record the details.

1. **Minimap**: draw real hexes so it matches the board. Raise the minimap and the box beside it 44 px off the bottom of the screen.
2. **Map controls**: move the rotate buttons under the minimap. Add zoom + and zoom - buttons with a magnifying-glass icon, and put "Zoom in" and "Zoom out" in their hover titles.
3. **Resources, top right**:
   - Show next round's money in brackets after the current money, for example `260 (+43)`.
   - Fuel, Money and Research labels in small caps.
   - Make the panel smaller and tidier, with better spacing, font sizes, weight and colour.
4. **Balance**: bases take 2 hits instead of 3, and decoys reveal at 3 hits. Change the data files, record it as play-test change P2 in ASSUMPTIONS.md, and rerun the batch runner to check game length.
5. **Building sprites**: render the sheets from `tools/sprites/render_buildings.py`, matching the board's hex width, flattening and rotation direction. Then draw them on the board for every installation:
   - Loaded and empty launchers.
   - Scaffolding for repairs and rubble for destroyed buildings.
   - Bases and decoys: enemy decoys use the base sheet.
6. **Debug tools on the backtick key**: add money, and clear the fog of war.
