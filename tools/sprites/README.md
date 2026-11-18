# Building sprites

Renders every Archipelago installation from six map rotations into transparent PNG sprite sheets. Each building is a short list of 3D primitives in `render_buildings.py`; nothing is hand-drawn.

## Run

```
pip install numpy pillow
python tools/sprites/render_buildings.py --out assets/buildings
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

## Buildings

`missile_launcher`, `missile_launcher_empty`, `ballistic_launcher`, `ballistic_launcher_empty`, `anti_air`, `radar`, `bank`, `refinery`, `lab`, `base`, `decoy`, `repair` (shared scaffolding), `rubble` (shared destroyed state).

`decoy` is the base with a grey flag so the owner can tell them apart. Draw enemy decoys with the `base` sheet.

## Adding or changing a building

Write a function that returns `pad() + ...` using `prism`, `tube`, `box` and `beam`, then register it in `BUILDINGS`. Units: 1.0 is the hex centre-to-vertex distance before `BUILDING_SCALE`; weapons face +x; z is up.

Colour rule: the pad rim stays black. Red, yellow and orange are reserved for hex outlines, so keep them off the base of a structure. They are fine higher up.
