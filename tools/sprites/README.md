# Building sprites

Renders every Archipelago installation from six map rotations into transparent PNG sprite sheets. Each building is a short list of 3D primitives in `render_buildings.py`; nothing is hand-drawn.

## Run

```
pip install numpy pillow
python tools/sprites/render_buildings.py --out assets/buildings --hex-width 103.923 --reverse
```

Output per run:

- `<building>.png`: one sheet per building, 6 frames left to right (view 0 to 5)
- `sprites.json`: frame size and the anchor pixel that sits on the centre of the hex top face
- `_contact_sheet.png` and `_contact_sheet_3x.png`: previews on green tiles, not for the game

## Options to match the map

| Flag | Default | Meaning |
| --- | --- | --- |
| `--hex-width` | 52 | On-screen hex width in px. Use 104 for 2x art. |
| `--squash` | 0.58 | Vertical flattening of the ground plane. Estimated from a screenshot; set it to the map's real value. |
| `--facing` | 0 | Degrees counter-clockwise that weapons point in view 0. 0 is screen-right. |
| `--reverse` | off | Views advance clockwise instead of counter-clockwise. |
| `--no-outline` | off | Drop the 1px dark outline. |
| `--frames` | off | Also write one PNG per frame. |
| `--only a b` | all | Render just the named buildings. |
| `--no-fire`, `--no-smoke` | off | Damaged sheets without flames or smoke. |

## Buildings

`missile_launcher`, `missile_launcher_empty`, `ballistic_launcher`, `ballistic_launcher_empty`, `anti_air`, `radar`, `bank`, `refinery`, `lab`, `base`, `decoy`, `repair` (shared scaffolding), `rubble` (shared destroyed state).

Every building except the shared states also has a `<name>_damaged` sheet (hit, needs repair): the main feature is broken or knocked over, with soot, scorch marks, debris, a small fire and smoke. Damaged launchers have no missile, so there is no separate empty variant. `--no-fire` and `--no-smoke` drop those effects if you would rather do them as particles in-game.

`decoy` is the base with a grey flag so the owner can tell them apart. Draw enemy decoys with the `base` sheet.

## Troop buildings

`airport`, `bunker`, `docks` and `coastal_cannon`, each with a `_damaged` sheet, live in the block marked "troop buildings" in `render_buildings.py`. At `--hex-width 104` frames are 132 x 198 with the anchor at (66, 150).

## Units

```
python tools/sprites/render_units.py --out assets/units
```

Writes `platoon`, `parachutist`, `transport` and `boat` sheets in `_player` and `_enemy` colourways at 2x, plus `units.json` with each sheet's frame size, anchor, row order and column names. It imports the primitives and camera from `render_buildings.py`, so the two files must stay together.

| Sheet | Frame | Anchor | Rows | Columns |
| --- | --- | --- | --- | --- |
| `platoon_*` | 104 x 80 | (52, 56) | 6 directions | stand, walk 1-4, fight 1-2, wiped out |
| `parachutist_*` | 48 x 64 | (24, 60) | 1 | opening, sway left, sway right, landing |
| `transport_*` | 120 x 90 | (60, 45) | 1 | prop 1, prop 2, door open |
| `boat_*` | 120 x 90 | (60, 56) | 6 directions | bob 1, bob 2 |

Direction rows are E, SE, SW, W, NW, NE. Colours for each side are in `SIDES` at the top of `render_units.py`.

## Adding or changing a building

Write a function that returns `pad() + ...` using `prism`, `tube`, `box` and `beam`, then register it in `BUILDINGS`. For the damaged version, add a `damaged` branch that breaks the main feature and returns `wreck(parts, hit_point, seed)`. Units: 1.0 is the hex centre-to-vertex distance before `BUILDING_SCALE`; weapons face +x; z is up.

Colour rule: the pad rim stays black. Red, yellow and orange are reserved for hex outlines, so keep them off the base of a structure. They are fine higher up.
