# Assumptions

Two kinds of entry:

- **Spec working assumptions**: marked "Working assumption" in spec.md and built as written.
- **Build decisions**: points where the spec says nothing and the simplest option was chosen.

Each entry says where it lives. Data keys are in `data/rules.json` unless another file is named.

## Spec working assumptions

| # | Assumption (spec section) | Where it lives |
| --- | --- | --- |
| W1 | First playable build is one island against the AI (§2) | Overall scope |
| W2 | Done button ends the build phase early (§3) | Presentation, step 4. Rules: `MatchState.end_build_phase()` |
| W3 | Targeting clock running out launches the orders placed so far (§3) | Presentation, step 4. Rules: orders are already stored by `set_launch_orders` |
| W4 | Three elevation levels (§4) | `map.levels`, `map.hill_level_fractions_from_top`, `rules/island.gd` `_raise_hill` |
| W5 | Radar range 2 / 3 / 4 by level (§4) | `radar.range_by_level`, `SideState.radar_range` |
| W6 | An impact reveals its own level or lower, not higher (§4) | `elevation.impact_reveals_uphill` (false), `Resolver._resolve_attack` |
| W7 | A blast does not cross a height step (§4) | `elevation.blast_crosses_height_step` (false), `Resolver._resolve_attack` |
| W8 | A motion-sensor missile cannot change level while seeking (§4) | `elevation.seek_can_change_level` (false), `Resolver._seek` |
| W9 | A motion-sensor missile that lands on an empty hex moves to the nearest enemy building within 3 hexes (§8) | `motion_sensor.seek_range`, `Resolver._seek` |
| W10 | A basic missile is one hit on a base or decoy; a ballistic missile is half a hit (§8) | `missiles.*.base_hits` |
| W11 | Non-weapon buildings drop to half strength as soon as they are damaged (§9) | `damage.half_strength_when_damaged`, `SideState.is_half_strength` |
| W12 | Bases and decoys cannot be repaired (§9) | `buildings.base/decoy.repairable`, `SideState.can_repair` |
| W13 | Positions of the rotate button, earnings button, round indicator and log are up to the build (§14) | Step 5 |
| W14 | First tooltips suggest building anti-air and researching radar (§14) | Step 5 |
| W15 | AI strength sources: placement, search, targeting, economy, adapting (§12) | Step 6, `ai/` |
| W16 | Difficulty comes from handicaps; the handicap settings live in data, with no option in the game (§12) | `data/ai.json` (step 3 onward) |

## Build decisions

| # | Decision | Where it lives |
| --- | --- | --- |
| D1 | **One generator, several named streams.** Every random number comes from `rules/rng.gd` (xoshiro128**, plain integer maths, so it doesn't depend on the engine version). The match has one seed. Island generation, dice and each AI draw from streams derived from that seed by name (`island_0`, `island_1`, `dice`, `ai_0`, `ai_1`), so changing the AI doesn't change the dice. A test bans engine randomness in `rules/` and `ai/`. | `Rng.derive`, `MatchState.create` |
| D2 | Ocean counts as base level (level 0) for reveals, blasts and seeking. So a miss in the sea still reveals the low coast next to it. | `elevation.ocean_level` |
| D3 | "Height step" means any difference in level, up or down. | `Resolver._resolve_attack`, `Resolver._seek` |
| D4 | Seeking travels hex by hex through hexes at the impact's level, ocean included, up to 3 steps. The nearest building wins, and ties are broken by the dice. The reveal happens where the missile finally lands. | `Resolver._seek` |
| D5 | A scouting missile does no damage. It is not a hit, so it doesn't disable weapons or add hits to bases. Anti-air can shoot it down. | `missiles.scouting` |
| D6 | A missile that is shot down reveals nothing. | `Resolver._resolve_attack` |
| D7 | Anti-air uses the hex the missile was aimed at to decide whether it is in range, not where a seeking missile ends up. Among anti-air of equal priority (radar-covered or not), the oldest building engages first. | `Resolver._resolve_attack` |
| D8 | Repair restores full HP when it is ordered. A weapon is out for that round. A non-weapon building works at half strength for that round. Both are fully back at the next round start. | `SideState.repair`, `SideState.begin_round` |
| D9 | Any hit on a building under repair cancels the repair. A weapon hit during its repair round therefore stays disabled until it is repaired again. | `Resolver._apply_damage` |
| D10 | Income and research points are both paid at the round start, from round 2, using building states at that moment. Repairs from the previous round finish first. | `SideState.begin_round` |
| D11 | Buildings work in the round they are built. A new launcher can fire and new anti-air can defend that round. A new bank first pays at the next round start. Section 16's opening implies this. | `SideState.build` |
| D12 | Research progress belongs to the item, not the lab. If the lab is destroyed, the project keeps its progress and has no owner. Idle labs still help it if it is the oldest. Any idle lab can take it over at no cost. Points beyond what an item needs are lost. A project can't be cancelled. | `SideState._accrue_research`, `start_research`, `remove_building` |
| D13 | Fuel is checked when orders are placed and spent at playout, so undoing an order is free. | `MatchState.set_launch_orders`, `Resolver.resolve` |
| D14 | Game settings are copied into the match when it is created and can be overridden there (for example, decoys per side). | `MatchState.create`, `data/settings.json` |
| D15 | Money for the tie-break is compared after the round's damage, using whatever is unspent. | `MatchState._check_outcome` |
| D16 | Coin flip: the enemy calls (seeded dice) as soon as the tie happens, so the call can be shown before the player clicks. The click triggers the flip, which also comes from the dice. If the flip matches the call, the enemy wins. | `MatchState.resolve_coin_flip` |
| D17 | What the attacker sees on a revealed hex: terrain, any building with its displayed type, and the building's state (damaged, disabled, under repair, hits). Bases and decoys show as `suspected_base` until a decoy reaches 3 hits. A destroyed building leaves a "destroyed" marker that stays until something new is seen there. | `MatchState.record_sighting`, `_public_building` |
| D18 | Each side learns which enemy bases it has destroyed, because the impact hex is always revealed. | `MatchState.bases_destroyed_by` |
| D19 | Island generation: land grows outward from the centre, with random weighting that favours hexes near the centre, until `floor(width × height × land_fraction)` hexes are land (157 on 15×15). A hill is centred within 1 hex of the middle. The nearest land, with some noise, is raised: 12% to the top level and 30% to the middle level. Lakes are allowed. | `map.*`, `rules/island.gd` |
| D20 | Data uses JSON. Tests and the batch runner can override any value with a dotted path (`GameData.set_path`). The game itself never does. | `rules/game_data.gd` |
| D21 | Simple AI (step 3): follows a build order from data and rebuilds anything it loses. It waits for research it has planned, and skips a launcher it couldn't fuel from its income. It repairs in a fixed priority order. It researches only radar, matching the opening in section 16. It places anti-air where it covers the most weighted own buildings, and radar where it covers the most anti-air. It aims first at known suspected bases (one missile per hit still needed), then at known active weapons. Otherwise it aims where the missile's view covers the most unexplored hexes, with a mild pull toward the centre. | `ai/simple_ai.gd`, `data/ai.json` `simple` |
| D22 | Both AIs plan from views taken before either side acts, then their actions are applied. Neither sees the other's build or targets. | `ai/match_runner.gd` |
| D23 | Each new game picks a random seed and prints it in the log. `--seed N` reproduces a game. | `game/main.gd` `_seed_from_args` |
| D24 | The enemy commits its build at the start of each build phase, and its targets at the start of each targeting phase. Each time it uses its own view at that moment. | `game/main.gd` `_start_round`, `_end_build` |
| D25 | Enemy launches are shown as missiles rising from the middle of the fogged enemy space, so the playout never reveals where enemy launchers are. When enemy anti-air hits one of our missiles, the tracer comes in from the side for the same reason. | `game/main.gd` `_run_playout`, `_strike` |
| D26 | A revealed enemy hex last seen in an earlier round gets a light grey tint to show it is stale. | `game/board_view.gd` `STALE_TINT` |
| D27 | Your own decoys carry a small dot so you can tell them from your bases. The enemy sees them exactly as bases. | `game/pieces.gd` |
| D28 | During playout the boards show the state from before the playout until each side's strikes have landed. Then they switch to the state after damage. | `game/main.gd` `_run_playout` |
| D29 | The view counts as being on whichever island the camera is nearer. The minimap highlights that half. | `game/main.gd` `_update_viewing` |
| D30 | Interim (step 4): the left toolbar uses plain buttons, research is started from the info box when a lab is selected, and the timer is a plain red counter. Step 5 replaces these with the section 14 versions. | `game/hud.gd`, `game/main.gd` |
