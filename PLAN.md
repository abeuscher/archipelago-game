# Work queue

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
