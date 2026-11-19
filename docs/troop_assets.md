# Troop assets brief

Art needed for troops in Archipelago: four new buildings, platoons, parachutists, the air transport and the boat. Everything matches the existing building sprites: flat colours with a dark ink outline, lit the same way, on a transparent background. The game handles all movement, timing and effects; the art supplies frames.

## Conventions (same as the existing building sprites)

- **Scale:** art is drawn at 2x. A hex is 104 px wide on the sheet and drawn at half size in the game, so it stays sharp when zoomed in.
- **Ground plane:** pointy-top hexes, flattened vertically to 0.58 (the `--squash` value in `tools/sprites/render_buildings.py`).
- **Format:** PNG with transparency, frames laid out in a grid with no gaps, plus a note (or JSON) of the frame size and the anchor pixel. The anchor is the point that sits on the ground at the centre of the hex.
- **Colour rule:** red, yellow and orange are reserved for the hex outlines the game draws, so keep them off the ground-level edges of a sprite. They are fine higher up (a flag, a light).
- **Two sides:** units need two colourways, one for the player and one for the enemy, so they can be told apart at a glance. Suggestion: player olive green, enemy charcoal grey with tan.

### Screen directions

Units face one of six screen directions: the directions to the six neighbouring hexes, as they look on screen. In this order:

| # | Name | Screen angle |
| --- | --- | --- |
| 0 | E | right (0°) |
| 1 | SE | down-right (about 45°) |
| 2 | SW | down-left (about 135°) |
| 3 | W | left (180°) |
| 4 | NW | up-left (about 225°) |
| 5 | NE | up-right (about 315°) |

The board can rotate, but the game picks the right row from the direction of movement on screen, so units need only these six.

## 1. Buildings

Four new buildings, each with a normal and a `_damaged` version, made the same way as the existing ones: added as models to `tools/sprites/render_buildings.py`, six frames per sheet (one per board rotation), same frame size (132 × 198) and anchor (66, 150).

| Sheet | What it is | Notes |
| --- | --- | --- |
| `airport` | A short runway or hangar with a small plane parked | The biggest of the four; keep it on the pad |
| `bunker` | A low, thick concrete pillbox with gun slits | Should read as tough and defensive |
| `docks` | A small pier or slipway with a crane | Built on a coastal hex; keep it on the pad (the game doesn't know which side the sea is) |
| `coastal_cannon` | A heavy gun on a turret, pointing out to sea | Like the anti-air, but one big barrel |

## 2. Platoon (on the ground)

Eight tiny soldiers moving as a group.

- **Sheet:** `platoon_player.png` and `platoon_enemy.png`.
- **Frame:** 104 × 80 px, anchor (52, 56), at the middle of the group's feet. Soldiers about 22 px tall.
- **Rows:** the six screen directions, in the order above.
- **Columns (7):** 1 standing, 4 walking (a loop), 2 fighting (a loop with muzzle flashes).
- **Optional:** a "wiped out" pose (soldiers down) as an eighth column. The game can do without it, using a puff of smoke.

## 3. Parachutist (dropping from the transport)

One soldier under a canopy. The game drops eight of them from the plane, spreads them out, and animates the fall and the sway; on landing they become the platoon sprite.

- **Sheet:** `parachutist_player.png` and `parachutist_enemy.png`.
- **Frame:** 48 × 64 px, anchor at the soldier's feet.
- **Frames (4):** canopy opening, open and swaying left, open and swaying right, landing (canopy collapsing).

## 4. Air transport

A simple plane seen from above, nose pointing right. The game rotates it to its heading and draws its shadow on the ground.

- **Sheet:** `transport_player.png` and `transport_enemy.png`.
- **Frame:** 120 × 90 px, anchor at the centre.
- **Frames (2):** propellers blurred, two positions (loops in flight).
- **Optional third frame:** cargo door open, for the drop.

## 5. Boat (landing craft)

Crosses the channel over two rounds and lands on a coastal hex.

- **Sheet:** `boat_player.png` and `boat_enemy.png`.
- **Frame:** 120 × 90 px, anchor at the centre of the waterline.
- **Rows:** the six screen directions, in the order above.
- **Columns (2):** bobbing with a small bow wave (loops).
- **Optional:** 3 sinking frames. The game can tilt and fade it with a splash instead.

## Done in the game (no art needed)

Bunker and coastal cannon gunfire, the cannon shot and splash, the platoon being wiped out (smoke), dust while marching, transport anti-air hits (the existing burst), rubble (the existing sheet), and the icons on the research screen.

## Sounds (optional)

The game plays each only if the file exists, like the repair sound. Short OGG files in `assets/audio/`:

| File | Use |
| --- | --- |
| `transport_engine.ogg` | Plane engine, looping while it flies |
| `parachute_open.ogg` | Canopies opening |
| `small_arms.ogg` | Platoon fighting, looping |
| `bunker_fire.ogg` | A bunker wiping out a platoon |
| `boat_engine.ogg` | Boat crossing, looping |
| `cannon_shot.ogg` | Coastal cannon firing |
| `splash.ogg` | Cannon miss, or a boat sinking |
