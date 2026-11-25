# Work queue

## Troops: done (rules in spec.md section 10, art brief in docs/troop_assets.md)

1. **Research tabs.** Buildings and Upgrades tabs on the research screen; radar and ballistic launcher move to Buildings; airport, bunker, docks and coastal cannon appear there.
2. **Airport, air transport, platoon, bunker.** Rules (landing, three-hex march, can jump down but not climb, bunker range 2, kills a base outright, anti-air on transports), two-click targeting with a direction arrow, playout with parachutes, AI use and defence, tests, batch.
3. **Docks, boats, coastal cannons.** Two-round crossing visible in the channel, coastal landings, cannon fire.
4. Spy helicopter and checkpoints: dropped.

To watch in play-testing: the enemy rarely gets coastal cannons before its first boat lands, and a platoon kills a base outright, so boats hit hard (in AI-against-AI games, about one base in four matches falls to troops). Levers: cannon research earlier in data/ai.json, platoon base damage, boat cost.

## Campaign plan (discussed 2026-11-19; levels 1 to 5 built)

Aim: 9 or 10 levels, each adding one new thing (a unit or building) and one new upgrade, then a final challenge, then the end of the world (spec). Both sides always get everything new and the AI plays it to win.

- **Level 1:** the base game. **Level 2:** one stronghold per side (built).
- **Level 3: the nuke, plus a bank upgrade.** Built (ASSUMPTIONS D108, tuned in D111 and D113): to play-test. Silo research needs 4 other items first; a nuke costs 120, is ready the round after, and costs 10 fuel to fire; 2 hits on the centre hex, 1 on the ring; anti-air 5% (20% with radar); 2 nuke hits in a round break a stronghold; bank upgrade makes banks 25. Strong-against-strong: median 31 rounds, a nuke in about 1 match in 4 (`tools/level_study.gd`).
- **Level 4: the enclave, plus a refinery upgrade.** Built (ASSUMPTIONS D118 to D128). Level 3's research carries over. The enclave (a building, no research) sends foreign agents by helicopter, who uncover three hexes a round and disarm nukes within a hex; it keeps a domestic agent patrolling within reach of it (back every 5 rounds) who kills foreign agents within a hex. A nuke launch reveals its silo. Refinery upgrade: 6 fuel per refinery instead of 3.
- **Level 5: the stealth silo, plus logistics.** Built (ASSUMPTIONS D129): to play-test. Level 4's research and the enclave carry over. The stealth silo fires one stealth missile a round: anti-air can't hit it, it does half a basic missile's damage (half a hit on a base), and it kills an enemy domestic agent on the hex it hits (a new one musters 2 rounds later). Logistics (research): anti-air and radar reach one hex farther.
- **Level 6 (candidate): the radar scrambler.** A chance to switch off radar and anti-air in a seven-hex patch of the enemy island.
- Caution: gate + cost + build time + counters stacked too hard means nukes never appear (level 1's median match is about 19 rounds). Set each moderately and tune with batch runs.

### Ideas for later levels (unsure, just kept in mind)

- **Barracks:** upgrades for the airport, bunker and docks: soldiers march farther and are harder to hit on the way in.

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
