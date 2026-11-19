# Archipelago: Game Spec

Nov 16, 2026 · @Alex Beuscher

## 1. Overview

Archipelago is a single-player, turn-based strategy roguelike built in Godot in 2D. The player builds weapons on a hex island and trades planned volleys with an AI-run island hidden under fog, until one side's three bases are destroyed. Winning an island moves the player on to the next.

**How to read this spec**

- Unmarked statements are decided.
- **Working assumption** marks something not yet confirmed. Build it as written and keep it easy to change.
- **Later** marks something outside the first playable build.
- Every number is part of a starting economy that will be tuned. Keep all numbers in data, not in code.

**Pillars**

- **The duel across the gap.** Hidden bases, a mix of offence and defence, and choosing where to strike on partial information.
- **Start small, ramp on purpose.** Every run opens with the same modest money and buildings. Complexity arrives through research and later islands.
- **No rails.** No fixed campaign, no story briefings, nothing unskippable.
- **One player against an AI** from the first playable build. There is no multiplayer.
- **Launch and watch.** Everything sent at the enemy runs automatically. The player decides what to build, where to put it and what to target.

**Setting.** The tone is bleak. The player fights island by island toward the last island to stop the enemy from destroying the world. When the player reaches the final victory, a short video shows the last enemy pressing a button deep underground. The view zooms out, a sea serpent awakes and the world is destroyed. The serpent was the world.

**Lineage.** The core loop comes from Metal Marines (SNES, 1993). The run structure and between-run unlocks follow FTL and Into the Breach.

## 2. First playable build

**Working assumption:** the first playable build is one island against the AI, with this scope.

- One 15 by 15 island per side, randomly generated, under full fog.
- The three-phase round, both clocks, and the win, loss and tie rules.
- The starting buildings, the decoy and radar.
- Research with these items: radar, scouting missile, anti-air capacity, motion sensor and the ballistic missile launcher.
- Damage, disabling and repair.
- The interface in section 14.
- A fair enemy AI, and a rules engine that runs without graphics.

Boats, aircraft, spies, the chain of islands, capture and between-run unlocks are all **Later**.

## 3. Round structure

Before round 1, each side places its three bases on its own island and may buy and place decoys.

Each round has three phases.

1. **Build and repair phase.** The view opens on the player's own island. The player can look at the stale view of the opposing space through the minimap, but cannot target. Income arrives at the start of every round from round 2 on. The player builds, repairs and assigns research. The clock is 2 minutes. **Working assumption:** a Done button ends the phase early.
2. **Targeting phase.** The view opens on the opposing space. The player can look at their own island through the minimap, but cannot build. The player assigns available weapons to target hexes, and each launch costs fuel. Any order can be undone at no cost. The clock is 1 minute. The Attack button ends the phase. **Working assumption:** if the clock runs out, the orders placed so far are launched.
3. **Playout.** Both sides launch. The enemy's strikes land on the player's island, then the player's strikes land on the enemy's island. Defences fire automatically and cost no fuel.

**Rules**

- Both sides plan in secret. The AI commits its plan without seeing the player's.
- All damage is applied at the end of the round. A building destroyed this round still fires this round.
- A side wins an island by destroying all three enemy bases.
- If both sides lose their last base in the same round, the side with more money wins. Fuel does not count. If the money is equal too, a coin flip decides: the enemy calls heads or tails, and the player flips the coin with a click. The animation comes later.
- Losing all three bases ends the run.
- Both clocks are game settings. Each can be changed or turned off.

## 4. Map

- Each side has a rectangular space of hexes that contains its island. Buildings sit on hexes, one building per hex.
- The first island is 15 by 15 hexes with about 70% land, roughly 157 land hexes. **Later** islands can grow toward about 21 across.
- Islands are randomly generated for both sides. Difficulty grows through shape and terrain more than size.
- Every island has a hill toward the middle.
- The player can pan with the mouse or the minimap, and zoom in and out generously.

**Elevation**

- Elevation is in. It gives the map texture and creates advantages and disadvantages.
- Docks must be built at base level.
- Radar has limited range and works better at the top level than the bottom, so the player has a reason to put it in exposed spots.
- Elevation affects visibility to some degree.
- **Working assumption:** there are three levels.
- **Working assumption:** radar range is 2 hexes at base level, 3 at the middle level and 4 at the top.
- **Working assumption:** an impact reveals hexes at its own level or lower, not higher ones.
- **Working assumption:** a multi-hex blast does not cross a height step, and a motion-sensor missile cannot change level while seeking.

## 5. Fog and intel

- Fog covers the whole opposing space, ocean included. Missiles have to find the island's edges before they find anything on it.
- Every missile has a view radius and reveals the hexes around its impact.
- A revealed hex shows what was there when it was last seen. It goes stale between turns, so new enemy buildings do not appear until the hex is revealed again.
- Bases and decoys are hidden until revealed. A decoy looks exactly like a base.
- Each suspected base shows the number of hits it has taken. The number is drawn on the hex in perspective, like a football yard marker. Hovering shows the same information, for example "Potential base: 2 hits".
- A miss gives no extra information beyond what its view radius reveals.
- The AI is under the same fog and targets only what it has revealed.
- The fog has a visible texture, so the player can tell the map is moving when they pan.

## 6. Resources

Three resources: money builds, fuel launches and research unlocks.

| Resource | Spent on | Baseline per round | Building that adds more |
| --- | --- | --- | --- |
| Money | Buildings, repairs, starting research | 20 | Bank, +15 each |
| Fuel | Anything that leaves the island | 3 | Refinery, +3 each |
| Research points | Progress on research items | 0 | Lab, +2 each |

- Each side starts with 160 money and 3 fuel. The money buys a few of the starting buildings, not all of them.
- Income arrives at the start of each round, beginning with round 2. Round 1 is played on the starting money and fuel alone.
- Unspent money and fuel carry over. There is no fuel cap.
- Fuel is what limits how many weapons can fire in a round. Defences and anything on the player's own island use none.

**Research**

- Research only accumulates once the player has a lab.
- The player chooses the specific item to research. Each item has a money cost to start and a number of points to complete.
- Each lab works on one item at a time. With several labs, the player can research as many items at once as they have labs.
- A lab with no project of its own helps the oldest running project. Two labs on one item finish it twice as fast.
- Research unlocks new building types and upgrades. The research screen has two tabs: **Buildings** (new building types: radar, ballistic launcher, airport, bunker, docks, coastal cannon) and **Upgrades** (improvements to what the player already has: scouting missile, anti-air capacity, motion sensor). No item has a prerequisite.
- **Later:** destroying an enemy lab gives a research boost.

## 7. Buildings

| Building | Role | Cost | Durability | Available |
| --- | --- | --- | --- | --- |
| Base | A single hex. Each side places three. Lose all three and you lose. | Free | 3 hits | Start |
| Decoy | Looks exactly like a base. One per side by default; a game option allows up to three. | 20 | 4 hits | Start |
| Bank | Produces money | 50 | 40 HP | Start |
| Refinery | Produces fuel | 50 | 40 HP | Start |
| Lab | Produces research points | 60 | 40 HP | Start |
| Basic missile launcher | Fires one basic or scouting missile a round | 60 | 50 HP | Start |
| Anti-air | Shoots down incoming missiles | 40 | 50 HP | Start |
| Radar | Raises anti-air accuracy within its range | 50 | 30 HP | Research: 30 money, 6 points |
| Ballistic missile launcher | Fires one ballistic missile a round | 90 | 50 HP | Research: 60 money, 14 points |
| Docks | Launches a boat carrying a platoon. Must be on a coastal hex. | 80 | 60 HP | Research: 50 money, 12 points |
| Coastal cannon | Fires on boats landing nearby | 60 | 60 HP | Research: 40 money, 10 points |
| Airport | Sends an air transport carrying a platoon | 100 | 60 HP | Research: 80 money, 18 points |
| Bunker | Wipes out platoons that land or march within 2 hexes | 50 | 80 HP | Research: 40 money, 10 points |

**Placing bases and decoys**

- A base or decoy can go on any land hex at any level, except that none may be adjacent to another base or decoy.
- A decoy is an optional purchase. It can be bought during setup out of the starting money, or in any later build and repair phase, up to the decoys-per-side setting.
- A destroyed decoy can be rebuilt.

**Upgrades, unlocked by research**

| Upgrade | Effect | Research |
| --- | --- | --- |
| Scouting missile | The basic launcher can fire a scouting missile | 20 money, 4 points |
| Anti-air capacity | Each anti-air engages 3 missiles a round instead of 2 | 20 money, 4 points |
| Motion sensor | A basic missile moves up to 3 hexes to hit an enemy target | 50 money, 12 points |
| Anti-air range | Later. Each anti-air covers a wider radius than 3 hexes | To be set |

One lab makes 2 points a round, so radar takes 3 rounds with one lab.

## 8. Weapons and defences

**Missiles**

Every missile type is defined by damage, blast radius and view radius. Both launchers reach anywhere on the opposing space.

| Missile | Fuel | Damage | Blast | View radius |
| --- | --- | --- | --- | --- |
| Basic | 3 | 30 to 50, rolled | 1 hex | 1 (the hex and its six neighbours) |
| Scouting | 1 | 0 | None | 2 (19 hexes) |
| Ballistic | 5 | 15 to 25 per hex, rolled | 7 hexes: the target and its six neighbours. A tuning lever. | 1 |

- The basic missile is dumb. It lands on the hex the player aimed at and explodes there.
- The ballistic missile does half the damage of the basic missile over a wider area.
- **Working assumption:** a motion-sensor missile that lands on an empty hex moves to the nearest enemy building within 3 hexes.

**Hits on bases and decoys**

- A base is destroyed by 3 hits. A decoy takes 4, so on the third hit the attacker learns it was a fake.
- **Working assumption:** a basic missile counts as one hit and a ballistic missile as half a hit.

**Anti-air and radar**

- Anti-air fires automatically and uses no fuel.
- Each anti-air covers a radius of 3 hexes around itself and engages only missiles aimed inside that radius. The radius is a tuning lever, and a later upgrade can increase it. Each anti-air engages up to 2 incoming missiles a round. The anti-air capacity upgrade raises that to 3.
- Each engagement hits 45% of the time, or 90% when the anti-air is inside a radar's range.
- Radar has a limited range that grows with height (section 4). Destroying a radar drops the anti-air it covered back to 45%.

* No missile is engaged more than once a round.
* Incoming missiles are shuffled with the seeded dice, and engagements are handed out with radar-covered anti-air first.

## 9. Damage and repair

- Every building other than a base or decoy has HP. Damage is rolled, and the numbers can be tuned.
- **Weapons.** One hit that does not destroy a launcher or an anti-air puts it out of action until it is repaired.
- **Non-weapon buildings.** Banks, refineries, labs and radar work at half strength while they are being repaired. **Working assumption:** they drop to half strength from the moment they are damaged. Half strength rounds up for income: a bank makes 8, a refinery 2 and a lab 1. A radar at half strength has half its range, rounded down with a minimum of 1, and keeps 90% accuracy inside it.
- **Repair** is ordered in the build and repair phase and costs 30% of the building's price. A weapon under repair is out for that round and returns the next. A non-weapon building under repair keeps working at half strength for that round.
- A hex under repair shows a common under-construction graphic, such as scaffolding, with a work-crew sound. The sound is listed in required\_assets.txt and plays only if its file exists.
- A building reduced to 0 HP is destroyed and must be rebuilt at full price.
- **Working assumption:** bases and decoys cannot be repaired.

## 10. Troops

Troops are hard to field and devastating when they get through. The difficulty: the buildings and research are expensive, each launch costs fuel and money, and the carrier can be lost on the way. The advantage: a platoon that lands destroys what it walks over unless a bunker is in range.

**Carriers**

| Carrier | Sent from | Launch cost | Lands on | Lost to | When lost |
| --- | --- | --- | --- | --- | --- |
| Air transport | Airport | 6 fuel, 40 money | Any hex | Anti-air, in flight, like a missile (it takes one of that anti-air's engagements) | 40 money to replace before the airport can launch again |
| Boat | Docks | 4 fuel, 30 money | A coastal land hex | Coastal cannons, as it lands | 30 money to replace before the docks can launch again |

- An airport sends at most one transport a round, and docks at most one boat.
- A transport lands in the round it is launched. A boat takes two rounds: it crosses the channel in the round it is launched, where both sides can see it, and lands in the next round's playout.
- A carrier that delivers its platoon comes back for the next launch.

**Platoons**

- Targeting a troop launch takes two clicks: the landing hex, then a neighbouring hex to choose the direction of the march, shown with an arrow.
- The platoon fights on its landing hex, then marches two more hexes in a straight line in the chosen direction: three hexes in all.
- On each of those hexes it destroys whatever stands there outright, a base included.
- It can march down a height step but not up one: they can jump but they can't climb. A step up, the sea or the edge of the space ends the march.
- A platoon that lands on the sea is lost.
- A bunker wipes out a platoon that lands or marches within 2 hexes of it. The platoon does nothing on that hex or any after it.
- The hexes a platoon lands on and marches through are revealed to the attacker.
- As with missiles, all damage is applied at the end of the round: a bunker destroyed this round still stops troops this round.

**Working assumptions** (to set while building and tune by testing):

- A coastal cannon fires on a boat landing within 3 hexes of it, one shot per boat, hitting half the time.
- Docks and coastal cannons must be built on coastal hexes (land next to the sea).

## 11. Run structure and progression (Later)

- A run is a chain of islands. The player fights from the island they just won toward the next.
- Every run starts the same way: the same money, the same starting buildings, a random island against a random enemy island.
- **Capture.** Enemy buildings the player did not destroy become the player's when the island falls. **Working assumption:** they arrive in whatever damage state they were left in.
- **Income carries forward.** Each island the player holds passes half its fuel production and half its money income to the next island, and the effect is cumulative.
- **Losing** ends the run. A game option, off by default, lets the player fall back one island instead.
- **Between runs,** a larger unlock tree carries over, in the manner of Into the Breach. Every individual run still starts small.
- **Later, further out:** a custom map mode that lets the player jump straight into full complexity.

## 12. Enemy AI

The enemy AI is built to be as hard to beat as possible without any unfair advantage. Difficulty levels are then made by scaling that AI back.

**Fair means**

- Same rules, costs, income and dice as the player.
- It sees only what its own strikes and scouts have revealed.
- It commits its plan for the round without seeing the player's plan.

**Working assumption: where its strength comes from**

- **Placement.** Bases spread out, away from obvious spots, never two within one blast or view radius, with the decoy where a player would expect a base.
- **Search.** A running estimate of where the player's bases can still be, with each shot aimed at the most unexplored ground.
- **Targeting.** Weapons and radar first while the player has known active launchers, always keeping a shot for bases or scouting.
- **Economy.** A build order found by testing, which never buys a launcher it cannot fuel.
- **Adapting.** Rebuilding on hexes the player has not seen, and repairing in priority order.

**Working assumption: difficulty levels** are the same AI with handicaps: noisier choices, weaker memory of what it has revealed, a less efficient build order, and plainer placement. For now the handicap settings live in data and there is no difficulty option in the game.

## 13. Presentation

- The game is 2D, drawn at a single fixed isometric angle that fakes 3D in the manner of Zaxxon and RollerCoaster Tycoon.
- The player can rotate the board in 60-degree steps, six views in all, to see behind hills.
- Each building has one sprite that always faces the camera. The board turns and the pieces do not.
- No sprite spans more than one hex.
- Sprite states come from gameplay: intact, damaged, under repair, destroyed, and upgrade levels where they should show.
- A higher hex is the same hex drawn further up the screen with taller sides. Objects in flight show their height with a shadow on the hex beneath.
- The playout shows both sides launching, then the enemy's strikes landing, then the player's. The Metal Marines launch sequences are a starting reference, not something to copy.
- There is no speed-up or skip for the playout, and no height toggle, for now.
- **Later:** sound effects and sequence-specific audio for each phase. The build does not generate audio. Every sound the game needs is listed in required\_assets.txt in the project's data folder, and Al creates the files when he can. The final victory video.

## 14. Interface

**Layout**

- **Left toolbar.** Its contents change with the phase.
  - Build and repair phase: the available buildings.
  - Targeting phase: the fuel planner at the top, then the list of available weapons with the fuel each one uses, an Undo control and the Attack button.
- **Timer** at the bottom of the left toolbar. It looks like a digital watch or an old scoreboard counter, and is a black box when it is not running.
- **Resources** at the top right.
- **Right side, toward the middle:** a strip of buttons of the same width.
  - One per research item in progress: a beaker icon that fills as the item progresses. Hovering shows its details in a title bar. Clicking opens the research panel.
  - One per own base, showing the hits it has left: green for 3, yellow for 2, red for 1.
- **Info box** at the bottom middle, to the left of the minimap. It can be hex-shaped to tie it to the selected hex. It shows the selected building's details.
- **Minimap** at the bottom, to the right of the info box. It moves the view, and it is how the player looks at the other island during a phase if they want to. There is no separate toggle.
- **Also on screen:** a rotate button, a button that shows projected earnings for the next turn, a round indicator, and a game log. Log events flash as they happen and build into a history that can be read back. **Working assumption:** their positions are up to the build.

**Research panel**

- It belongs to the build and repair phase.
- Each panel covers a single lab. A pager moves between labs when there is more than one.
- The left side shows the lab that is selected. The right side shows its current research.
- A lab with no project of its own shows that it is working on another lab's project, and lists the research available. Choosing an item starts that lab on it.

**Other**

- Tooltips are in from the start and introduce the game as the player goes. **Working assumption:** the first suggestions are to build anti-air and to research radar.
- The Esc menu pauses the game and offers options and quit.
- **Later:** saving, either manual or automatic in the manner of FTL.

**Game settings**

| Setting | Default | Range |
| --- | --- | --- |
| Build and repair clock | 2 minutes | Adjustable, or off |
| Targeting clock | 1 minute | Adjustable, or off |
| Decoys per side | 1 | 1 to 3 |
| Fall back one island on a loss (Later) | Off | On or off |

## 15. Technical requirements

- **Engine:** Godot, in 2D.
- **Rules separate from presentation.** The game rules run without graphics, so matches can be played headless.
- **Seeded dice.** The same seed and the same orders produce the same result.
- **AI against AI.** The headless rules can run many matches in a batch. This is how the AI is tuned and how balance is checked.
- **Numbers in data.** Costs, HP, damage, income, ranges, accuracy, clocks and research values live in data files, not in code.
- **Placeholder art.** The game is playable with simple placeholder hexes and pieces. Final sprites are supplied separately.

* **Audio assets.** The build generates no audio. Each sound the spec calls for gets a line in required\_assets.txt in the project's data folder, and the game plays a sound only if its file exists.
* **Isometric view from the start.** The isometric view, rotation and drawn height are built with the first playable loop, not after a flat-hex version.

## 16. Balance notes from simulation

These come from a small simulation of a 15 by 15 island run while this spec was written. They are a reference for checking the build, not rules.

**Expected income from a sensible opening**

| Stage | Rounds | What has been added | Money per round | Fuel per round | Research per round | Missiles per round |
| --- | --- | --- | --- | --- | --- | --- |
| Opening | 1 to 2 | Launcher, bank, refinery | 35 | 6 | 0 | 1 |
| Early | 3 to 7 | Lab, radar research, anti-air, radar | 35 | 6 | 2 | 1 |
| Middle | 8 to 11 | Second launcher, second bank, second refinery | 35, then 50 | 6, then 9 | 2 | 2 |
| Late | 12 on | Third launcher, second lab | 50 | 9 | 4 | 3 |

- Money is the early limit: about one purchase a round.
- Fuel is the firing limit: 6 fuel a round is exactly two basic missiles, so a third launcher is useless without a second refinery.

**Length of the first island, two identical AI sides**

| Anti-air engages | Rounds to a result (median) | Range | Missiles fired by the busier side |
| --- | --- | --- | --- |
| 1 missile a round | 21 | 17 to 29 | 58 |
| 2 missiles a round (the decided rule) | 34 | 24 to 47 | 119 |
| 3 missiles a round (with the upgrade) | 80 | 39 to 152 | 382 |

- **Anti-air may be too strong.** At 90% accuracy, two engagements per anti-air push the first island from 21 rounds to 34, and three produce a stalemate. Test this early.
- The simulation overstates the problem in two ways. It treats radar as covering the whole island, and its AI never targets radar. In the game, radar has limited range and dies to one hit.
- **Attacking weapons pays.** With the disable rule, a side that hits weapons first beat a side that only went for bases 70% of the time.
- **Decoys cost the attacker about two missiles each.**
- Fog over the ocean barely changes the length, because a search that starts at the centre finds land at once. These runs predate the 3-hex anti-air radius, the 7-hex ballistic blast and the 3 starting fuel.

## 17. Open questions

**Affects the first playable build**

- [ ] **Elevation rules.** Confirm three levels, radar range of 2, 3 and 4 hexes by level, impacts not revealing uphill, and blasts not crossing a height step.
- [ ] **Anti-air strength.** Whether 90% accuracy with 2 or 3 engagements is too strong, now that each anti-air covers only a 3-hex radius (see section 16).
- [ ] **Ballistic missiles against bases.** Whether a ballistic hit counts as half a hit.
- [ ] **Half strength.** Whether a non-weapon building drops to half strength when damaged, or only during the round it is repaired.
- [ ] **Positions** of the rotate button, the earnings button, the round indicator and the game log.

**Later**

- [ ] **Research and islands.** Whether the island number limits what can be researched, and whether research carries from island to island.
- [ ] **Labs.** Destroying an enemy lab boosts research, while sparing it lets the player capture it. Confirm that trade-off is intended.
- [x] **Counters.** Anti-air shoots down air transports; bunkers stop platoons; coastal cannons fire on boats. No spies or checkpoints (section 10).
- [x] **Boats.** Land on coastal hexes only; the crossing takes two rounds, visible in the channel (section 10).
- [ ] **Missile roster.** Types beyond the basic, ballistic and scouting missiles.
- [ ] **Income forwarding.** How the cumulative half is calculated.
- [ ] **Run map.** Linear or branching, and how many islands.
- [ ] **Enemy start state** on later islands.
- [ ] **Between-run unlocks.** What earns them and what the tree holds.
- [ ] **Ending.** Whether the war itself is what wakes the serpent, and whether the ending leads into the next run.
- [ ] **Theming of the pieces.** What the weapons and buildings look like.
- [ ] **Platforms** to target.
- [ ] **Saving.** Manual or automatic.
