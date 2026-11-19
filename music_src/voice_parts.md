# Voice parts

Every line the characters say, grouped by speaker. Each clip is named on the left: `[character]_[3 digits]`, e.g. `admiral_001.ogg`.

- Numbers that come from the rules (seconds, percentages) are filled in as the game says them today. If a rule changes, that line needs re-recording.
- **[n]** marks a number that changes during play. The game plays that speaker's number clip there (see *Numbers* in each speaker's section). Where a number falls in the middle of a line, the line is split into pieces recorded separately: `pilot_006a`, `pilot_006b`, and so on.
- Made by `music_src/make_voice_parts.py` from `data/dialogue.json`. Clip numbers are kept in `voice_ids.json`, so a line keeps its name when lines are added.

Clips: Admiral 3, Ginger 110, Pilot 156, Mechanic 3, Scientist 2.

---

## ADMIRAL

*Tutorial tip (shown once; the player can turn tips off).*

**admiral_001**  General, place our bases carefully. If we lose all three, we lose the war. A decoy can help draw the enemy away from our real targets.

*Start of level 2, introducing the stronghold.*

**admiral_002**  Congratulations on your victory, General. As you have been fighting, our scientists have come up with a new type of base: a stronghold. It is impervious to air attack and comes with a mounted anti-aircraft missile on its roof. The only way it can be taken is with ground troops.

*Level 2, when our missile first reveals the enemy's stronghold.*

**admiral_003**  General, bad news! Enemy spies have stolen the secrets of our stronghold tech and built one of their own. We're going to have to get some invasion forces ready to destroy it.

---

## GINGER

*Tutorial tip (shown once; the player can turn tips off).*

**ginger_001**  Very strategic choices, General! Now that our bases are in place, we need to place our offensive and defensive buildings. If you want to reposition any bases or decoys, now's the time. Hit undo to back up.

**ginger_002**  General, you have 45 seconds every round to place your buildings. Make sure we're producing fuel and money, and of course wreak as much havoc on the enemy as you can.

*Alarm: one enemy missile is about to land.*

**ginger_003**  General! An enemy missile is incoming!

*Alarm: several enemy missiles are about to land.*

General! **[n]** enemy missiles incoming!  (in pieces)

> **ginger_004a**  General!
>
> *(n number)*
>
> **ginger_004b**  enemy missiles incoming!

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

### Numbers

One clip per number, said on its own in the voice of the lines above, named for its value: `ginger_n024` says "twenty-four". Her warning counts incoming missiles. Past 100 it shows in the text only.

**ginger_n001**  one

**ginger_n002**  two

**ginger_n003**  three

**ginger_n004**  four

**ginger_n005**  five

**ginger_n006**  six

**ginger_n007**  seven

**ginger_n008**  eight

**ginger_n009**  nine

**ginger_n010**  ten

**ginger_n011**  eleven

**ginger_n012**  twelve

**ginger_n013**  thirteen

**ginger_n014**  fourteen

**ginger_n015**  fifteen

**ginger_n016**  sixteen

**ginger_n017**  seventeen

**ginger_n018**  eighteen

**ginger_n019**  nineteen

**ginger_n020**  twenty

**ginger_n021**  twenty-one

**ginger_n022**  twenty-two

**ginger_n023**  twenty-three

**ginger_n024**  twenty-four

**ginger_n025**  twenty-five

**ginger_n026**  twenty-six

**ginger_n027**  twenty-seven

**ginger_n028**  twenty-eight

**ginger_n029**  twenty-nine

**ginger_n030**  thirty

**ginger_n031**  thirty-one

**ginger_n032**  thirty-two

**ginger_n033**  thirty-three

**ginger_n034**  thirty-four

**ginger_n035**  thirty-five

**ginger_n036**  thirty-six

**ginger_n037**  thirty-seven

**ginger_n038**  thirty-eight

**ginger_n039**  thirty-nine

**ginger_n040**  forty

**ginger_n041**  forty-one

**ginger_n042**  forty-two

**ginger_n043**  forty-three

**ginger_n044**  forty-four

**ginger_n045**  forty-five

**ginger_n046**  forty-six

**ginger_n047**  forty-seven

**ginger_n048**  forty-eight

**ginger_n049**  forty-nine

**ginger_n050**  fifty

**ginger_n051**  fifty-one

**ginger_n052**  fifty-two

**ginger_n053**  fifty-three

**ginger_n054**  fifty-four

**ginger_n055**  fifty-five

**ginger_n056**  fifty-six

**ginger_n057**  fifty-seven

**ginger_n058**  fifty-eight

**ginger_n059**  fifty-nine

**ginger_n060**  sixty

**ginger_n061**  sixty-one

**ginger_n062**  sixty-two

**ginger_n063**  sixty-three

**ginger_n064**  sixty-four

**ginger_n065**  sixty-five

**ginger_n066**  sixty-six

**ginger_n067**  sixty-seven

**ginger_n068**  sixty-eight

**ginger_n069**  sixty-nine

**ginger_n070**  seventy

**ginger_n071**  seventy-one

**ginger_n072**  seventy-two

**ginger_n073**  seventy-three

**ginger_n074**  seventy-four

**ginger_n075**  seventy-five

**ginger_n076**  seventy-six

**ginger_n077**  seventy-seven

**ginger_n078**  seventy-eight

**ginger_n079**  seventy-nine

**ginger_n080**  eighty

**ginger_n081**  eighty-one

**ginger_n082**  eighty-two

**ginger_n083**  eighty-three

**ginger_n084**  eighty-four

**ginger_n085**  eighty-five

**ginger_n086**  eighty-six

**ginger_n087**  eighty-seven

**ginger_n088**  eighty-eight

**ginger_n089**  eighty-nine

**ginger_n090**  ninety

**ginger_n091**  ninety-one

**ginger_n092**  ninety-two

**ginger_n093**  ninety-three

**ginger_n094**  ninety-four

**ginger_n095**  ninety-five

**ginger_n096**  ninety-six

**ginger_n097**  ninety-seven

**ginger_n098**  ninety-eight

**ginger_n099**  ninety-nine

**ginger_n100**  one hundred

---

## PILOT

*Tutorial tip (shown once; the player can turn tips off).*

**pilot_001**  General, the missile launcher is our first offensive weapon. Build one early so we can start hitting back and find out where the enemy's bases are before it's too late.

**pilot_002**  We need anti-air, General. Each one shoots at missiles aimed within 3 hexes of it, up to 2 a round.

**pilot_003**  Looks like you're trying to land your troops on enemy territory, General. Click once on where you want them to land, then click on an adjacent hex to tell them which way to move once boots are on the ground.

**pilot_004**  Pick a weapon on the left, then click on the map to aim it. Expect to miss a few times as we clear the fog of war and learn the layout of their island.

**pilot_005**  We don't have the fuel to fire every launcher, General. Each refinery adds 3 fuel a round.

*Start of each round from round 2, reporting what came in.*

General, we took in **[money]** money, **[fuel]** fuel and **[research]** research.  (in pieces)

> **pilot_006a**  General, we took in
>
> *(money number)*
>
> **pilot_006b**  money,
>
> *(fuel number)*
>
> **pilot_006c**  fuel and
>
> *(research number)*
>
> **pilot_006d**  research.

*After the battle summary, the round's income.*

And we took in **[money]** money, **[fuel]** fuel and **[research]** research.  (in pieces)

> **pilot_007a**  And we took in
>
> *(money number)*
>
> **pilot_007b**  money,
>
> *(fuel number)*
>
> **pilot_007c**  fuel and
>
> *(research number)*
>
> **pilot_007d**  research.

*Start of each round after an attack, opening the battle summary. The summary lines below follow it, then the income.*

**pilot_008**  General, I have the battle summary.

*Battle summary, after the opening line. Only the lines for what happened are said, in this order.*

**pilot_009**  One enemy missile got through to us.

**pilot_010**  **[n]** enemy missiles got through to us.

> Record without the number: "enemy missiles got through to us."

**pilot_011**  One of our buildings was damaged.

**pilot_012**  **[n]** of our buildings were damaged.

> Record without the number: "of our buildings were damaged."

**pilot_013**  We lost one building.

We lost **[n]** buildings.  (in pieces)

> **pilot_014a**  We lost
>
> *(n number)*
>
> **pilot_014b**  buildings.

**pilot_015**  Our anti-air shot down one of their missiles.

Our anti-air shot down **[n]** of their missiles.  (in pieces)

> **pilot_016a**  Our anti-air shot down
>
> *(n number)*
>
> **pilot_016b**  of their missiles.

**pilot_017**  We brought down one of their transports.

We brought down **[n]** of their transports.  (in pieces)

> **pilot_018a**  We brought down
>
> *(n number)*
>
> **pilot_018b**  of their transports.

**pilot_019**  One of our missiles found its target.

**pilot_020**  **[n]** of our missiles found their targets.

> Record without the number: "of our missiles found their targets."

**pilot_021**  They shot down one of our missiles.

They shot down **[n]** of our missiles.  (in pieces)

> **pilot_022a**  They shot down
>
> *(n number)*
>
> **pilot_022b**  of our missiles.

**pilot_023**  They shot down one of our transports.

They shot down **[n]** of our transports.  (in pieces)

> **pilot_024a**  They shot down
>
> *(n number)*
>
> **pilot_024b**  of our transports.

**pilot_025**  We damaged one enemy building.

We damaged **[n]** enemy buildings.  (in pieces)

> **pilot_026a**  We damaged
>
> *(n number)*
>
> **pilot_026b**  enemy buildings.

**pilot_027**  We destroyed one enemy building.

We destroyed **[n]** enemy buildings.  (in pieces)

> **pilot_028a**  We destroyed
>
> *(n number)*
>
> **pilot_028b**  enemy buildings.

**pilot_029**  We lost one soldier.

We lost **[n]** soldiers.  (in pieces)

> **pilot_030a**  We lost
>
> *(n number)*
>
> **pilot_030b**  soldiers.

**pilot_031**  We stopped one of their soldiers.

We stopped **[n]** of their soldiers.  (in pieces)

> **pilot_032a**  We stopped
>
> *(n number)*
>
> **pilot_032b**  of their soldiers.

### Numbers

One clip per number, said on its own in the voice of the lines above, named for its value: `pilot_n024` says "twenty-four". The battle summary and income report (the summary counts missiles, buildings and soldiers; soldiers go up in eights). A number over 99 is said as its hundreds clip then the rest: 345 is `pilot_n300` + `pilot_n045` ("three hundred" + "forty-five"); 300 is just `pilot_n300`.

**pilot_n000**  zero

**pilot_n001**  one

**pilot_n002**  two

**pilot_n003**  three

**pilot_n004**  four

**pilot_n005**  five

**pilot_n006**  six

**pilot_n007**  seven

**pilot_n008**  eight

**pilot_n009**  nine

**pilot_n010**  ten

**pilot_n011**  eleven

**pilot_n012**  twelve

**pilot_n013**  thirteen

**pilot_n014**  fourteen

**pilot_n015**  fifteen

**pilot_n016**  sixteen

**pilot_n017**  seventeen

**pilot_n018**  eighteen

**pilot_n019**  nineteen

**pilot_n020**  twenty

**pilot_n021**  twenty-one

**pilot_n022**  twenty-two

**pilot_n023**  twenty-three

**pilot_n024**  twenty-four

**pilot_n025**  twenty-five

**pilot_n026**  twenty-six

**pilot_n027**  twenty-seven

**pilot_n028**  twenty-eight

**pilot_n029**  twenty-nine

**pilot_n030**  thirty

**pilot_n031**  thirty-one

**pilot_n032**  thirty-two

**pilot_n033**  thirty-three

**pilot_n034**  thirty-four

**pilot_n035**  thirty-five

**pilot_n036**  thirty-six

**pilot_n037**  thirty-seven

**pilot_n038**  thirty-eight

**pilot_n039**  thirty-nine

**pilot_n040**  forty

**pilot_n041**  forty-one

**pilot_n042**  forty-two

**pilot_n043**  forty-three

**pilot_n044**  forty-four

**pilot_n045**  forty-five

**pilot_n046**  forty-six

**pilot_n047**  forty-seven

**pilot_n048**  forty-eight

**pilot_n049**  forty-nine

**pilot_n050**  fifty

**pilot_n051**  fifty-one

**pilot_n052**  fifty-two

**pilot_n053**  fifty-three

**pilot_n054**  fifty-four

**pilot_n055**  fifty-five

**pilot_n056**  fifty-six

**pilot_n057**  fifty-seven

**pilot_n058**  fifty-eight

**pilot_n059**  fifty-nine

**pilot_n060**  sixty

**pilot_n061**  sixty-one

**pilot_n062**  sixty-two

**pilot_n063**  sixty-three

**pilot_n064**  sixty-four

**pilot_n065**  sixty-five

**pilot_n066**  sixty-six

**pilot_n067**  sixty-seven

**pilot_n068**  sixty-eight

**pilot_n069**  sixty-nine

**pilot_n070**  seventy

**pilot_n071**  seventy-one

**pilot_n072**  seventy-two

**pilot_n073**  seventy-three

**pilot_n074**  seventy-four

**pilot_n075**  seventy-five

**pilot_n076**  seventy-six

**pilot_n077**  seventy-seven

**pilot_n078**  seventy-eight

**pilot_n079**  seventy-nine

**pilot_n080**  eighty

**pilot_n081**  eighty-one

**pilot_n082**  eighty-two

**pilot_n083**  eighty-three

**pilot_n084**  eighty-four

**pilot_n085**  eighty-five

**pilot_n086**  eighty-six

**pilot_n087**  eighty-seven

**pilot_n088**  eighty-eight

**pilot_n089**  eighty-nine

**pilot_n090**  ninety

**pilot_n091**  ninety-one

**pilot_n092**  ninety-two

**pilot_n093**  ninety-three

**pilot_n094**  ninety-four

**pilot_n095**  ninety-five

**pilot_n096**  ninety-six

**pilot_n097**  ninety-seven

**pilot_n098**  ninety-eight

**pilot_n099**  ninety-nine

**pilot_n100**  one hundred

**pilot_n200**  two hundred

**pilot_n300**  three hundred

**pilot_n400**  four hundred

**pilot_n500**  five hundred

**pilot_n600**  six hundred

**pilot_n700**  seven hundred

**pilot_n800**  eight hundred

**pilot_n900**  nine hundred

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
