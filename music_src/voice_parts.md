# Voice parts

Every line the characters say, grouped by speaker. Each clip is named on the left: `[character]_[3 digits]`, e.g. `admiral_001.ogg`.

- Numbers that come from the rules (seconds, percentages) are filled in as the game says them today. If a rule changes, that line needs re-recording.
- **[n]** marks a number that changes during play. See *Numbers* at the end.
- Made by `music_src/make_voice_parts.py` from `data/dialogue.json`. Clip numbers are kept in `voice_ids.json`, so a line keeps its name when lines are added.

Clips: Admiral 28, Ginger 9, Pilot 6, Mechanic 3, Scientist 2.

---

## ADMIRAL

*Tutorial tip (shown once; the player can turn tips off).*

**admiral_001**  General, place our bases carefully. If we lose all three, we lose the war. A decoy can help draw the enemy away from our real targets.

*Start of level 2, introducing the stronghold.*

**admiral_002**  Congratulations on your victory, General. As you have been fighting, our scientists have come up with a new type of base: a stronghold. It is impervious to air attack and comes with a mounted anti-aircraft missile on its roof. The only way it can be taken is with ground troops.

*Level 2, when our missile first reveals the enemy's stronghold.*

**admiral_003**  General, bad news! Enemy spies have stolen the secrets of our stronghold tech and built one of their own. We're going to have to get some invasion forces ready to destroy it.

*End of each round, opening the battle summary. The summary lines below follow it.*

**admiral_004**  General, I have the battle summary.

*Battle summary, after the opening line. Only the lines for what happened are said, in this order.*

**admiral_005**  One enemy missile got through to us.

**admiral_006**  **[n]** enemy missiles got through to us.

**admiral_007**  One of our buildings was damaged.

**admiral_008**  **[n]** of our buildings were damaged.

**admiral_009**  We lost one building.

**admiral_010**  We lost **[n]** buildings.

**admiral_011**  Our anti-air shot down one of their missiles.

**admiral_012**  Our anti-air shot down **[n]** of their missiles.

**admiral_013**  We brought down one of their transports.

**admiral_014**  We brought down **[n]** of their transports.

**admiral_015**  One of our missiles found its target.

**admiral_016**  **[n]** of our missiles found their targets.

**admiral_017**  They shot down one of our missiles.

**admiral_018**  They shot down **[n]** of our missiles.

**admiral_019**  They shot down one of our transports.

**admiral_020**  They shot down **[n]** of our transports.

**admiral_021**  We damaged one enemy building.

**admiral_022**  We damaged **[n]** enemy buildings.

**admiral_023**  We destroyed one enemy building.

**admiral_024**  We destroyed **[n]** enemy buildings.

**admiral_025**  We lost one soldier.

**admiral_026**  We lost **[n]** soldiers.

**admiral_027**  We stopped one of their soldiers.

**admiral_028**  We stopped **[n]** of their soldiers.

---

## GINGER

*Tutorial tip (shown once; the player can turn tips off).*

**ginger_001**  Very strategic choices, General! Now that our bases are in place, we need to place our offensive and defensive buildings. If you want to reposition any bases or decoys, now's the time. Hit undo to back up.

**ginger_002**  General, you have 45 seconds every round to place your buildings. Make sure we're producing fuel and money, and of course wreak as much havoc on the enemy as you can.

*Alarm: one enemy missile is about to land.*

**ginger_003**  General! An enemy missile is incoming!

*Alarm: several enemy missiles are about to land.*

**ginger_004**  General! **[n]** enemy missiles incoming!

*Alarm: an enemy transport is about to drop troops.*

**ginger_005**  General! Enemy transport inbound! They're dropping troops on us!

*Alarm: an enemy boat is coming ashore.*

**ginger_006**  General! Enemy boat coming ashore! They're landing troops on our coast!

*First time the player presses Attack with weapons not aimed.*

**ginger_007**  Don't forget to target your weapons before you click attack. Otherwise you're a sitting duck!

*Level 1, when the player loses their first base.*

**ginger_008**  Oh no! We lost our first base! Two more and we're toast!

*Start of a round when an enemy boat is crossing the channel.*

**ginger_009**  General, an enemy boat is crossing the channel. It will come ashore on our coast when this round's attack plays out.

---

## PILOT

*Tutorial tip (shown once; the player can turn tips off).*

**pilot_001**  General, the missile launcher is our first offensive weapon. Build one early so we can start hitting back and find out where the enemy's bases are before it's too late.

**pilot_002**  We need anti-air, General. Each one shoots at missiles aimed within 3 hexes of it, up to 2 a round.

**pilot_003**  Looks like you're trying to land your troops on enemy territory, General. Click once on where you want them to land, then click on an adjacent hex to tell them which way to move once boots are on the ground.

**pilot_004**  Pick a weapon on the left, then click on the map to aim it. Expect to miss a few times as we clear the fog of war and learn the layout of their island.

**pilot_005**  We don't have the fuel to fire every launcher, General. Each refinery adds 3 fuel a round.

*Start of each round from round 2, reporting what came in.*

**pilot_006**  General, we took in **[money]** money, **[fuel]** fuel and **[research]** research.

---

## MECHANIC

*Tutorial tip (shown once; the player can turn tips off).*

**mechanic_001**  Careful, General! We've got some damage on the ground. Damaged buildings can be repaired for 30% of their original cost.

**mechanic_002**  General, they keep hitting the same launcher. Repairs won't hold while they're aiming at it. Build a new one somewhere they haven't seen.

**mechanic_003**  General, the number on a possible base counts the hits it's taken. A base falls at 2 hits. A decoy falls at 1, and then we'll know it was a fake.

---

## SCIENTIST

*Tutorial tip (shown once; the player can turn tips off).*

**scientist_001**  Ah, General! Welcome to the research lab! One project per lab. Research ticks along each round. More labs, more projects! Idle labs help existing projects go faster.

**scientist_002**  General, I'd research radar next. Anti-air inside a radar's range hits 90% of the time instead of 45%. Build a lab, then select it or click its beaker to pick the research.

---

## Numbers

Some lines say a number that changes during play. Three ways to handle them, line by line:

1. **Record each number as its own clip** for that speaker and play them in the gap: e.g. `admiral_n02` ... `admiral_n20` for *two* to *twenty* (the battle summary says up to twenty in words). Ginger's missile count needs the same, roughly two to ten.
2. **Record a version without the number**: e.g. "General, several enemy missiles incoming!" and keep the number on screen only.
3. **Leave that line as text only** and voice the rest.

The Pilot's income report (money, fuel, research) has numbers into the hundreds, so option 2 or 3 suits it best; we can reword it when you get there.
