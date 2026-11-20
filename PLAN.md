# Work queue

## Troops: done (rules in spec.md section 10, art brief in docs/troop_assets.md)

1. **Research tabs.** Buildings and Upgrades tabs on the research screen; radar and ballistic launcher move to Buildings; airport, bunker, docks and coastal cannon appear there.
2. **Airport, air transport, platoon, bunker.** Rules (landing, three-hex march, can jump down but not climb, bunker range 2, kills a base outright, anti-air on transports), two-click targeting with a direction arrow, playout with parachutes, AI use and defence, tests, batch.
3. **Docks, boats, coastal cannons.** Two-round crossing visible in the channel, coastal landings, cannon fire.
4. Spy helicopter and checkpoints: dropped.

To watch in play-testing: the enemy rarely gets coastal cannons before its first boat lands, and a platoon kills a base outright, so boats hit hard (in AI-against-AI games, about one base in four matches falls to troops). Levers: cannon research earlier in data/ai.json, platoon base damage, boat cost.

## Campaign plan (discussed 2026-11-19, nothing built yet)

Aim: 9 or 10 levels, each adding one new thing (a unit or building) and one new upgrade, then a final challenge, then the end of the world (spec). Both sides always get everything new and the AI plays it to win.

- **Level 1:** the base game. **Level 2:** one stronghold per side (built).
- **Level 3: the nuke, plus a bank upgrade.** Built in session 012 (ASSUMPTIONS D108): to play-test.
  - Silo research, then each nuke costs money and takes rounds to build (one round to start; lengthen if nukes are too strong).
  - Gated by progress as well as cost: only after a number of research items are done (research rather than buildings, which can be padded with cheap decoys). Pick the number from AI-against-AI runs so nukes land mid to late game.
  - On impact: 2 hits to the building on the centre hex (a base falls outright), 1 hit to each of the 6 hexes around it.
  - Open: can anti-air shoot a nuke down (suggested: a low chance, about 20%, that radar doesn't raise)? Does it hit strongholds (would make it the stronghold-breaker)? One built nuke at a time, or a stockpile? Is the silo hidden from the enemy (needed for the spy to matter)? Two strongholds per side here or later?
  - Bank upgrade: not yet defined.
- **Level 4: the spy.** An add-on to the airport: costs money, takes a round to build, and the airport does nothing else that round. Flown in; if he lands on land he reveals the enemy's nukes (just those hexes, fog cleared). Must beat scouting missiles (1 fuel, 19 hexes) on value: his edge is certainty. Ideas: he stays and reports new silos as they're built; anti-air can shoot him down on the way in.
- **Level 5 (likely): the saboteur upgrade.** Once a nuke has been found, the spy goes in a second time and permanently disables it and its hex. Needs the nuke build time long enough for the spy-then-saboteur chain to catch the next nuke. Suggested: the silo is hardened (missile-proof or many hits) so sabotage is the clean answer; a disabled silo can be rebuilt elsewhere at full cost.
- Caution: gate + cost + build time + counters stacked too hard means nukes never appear (median match today is about 19 rounds). Set each moderately and tune with batch runs.

### Ideas for later levels (unsure, just kept in mind)

- **Stealth missile silo:** missiles anti-air can't hit, doing less damage (0.5 hit each).
- **Barracks:** upgrades for the airport, bunker and docks: soldiers march farther and are harder to hit on the way in.
- **Logistics:** radar and anti-air bonuses.
- **Radar scrambler:** a chance to disable radar and anti-air in a seven-hex patch of the enemy island.

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
