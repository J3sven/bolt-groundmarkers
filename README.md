# Ground Markers
Ground Markers is a [Bolt launcher](https://github.com/adamcake/Bolt) plugin for RuneScape 3 that brings the comfort of RuneLite / HDOS style tile markers to RS3, including fully user-controlled layouts for instanced content.

<img width="955" height="608" alt="image" src="https://github.com/user-attachments/assets/ea406ae2-88de-4528-b5d9-c7aec7eb5d2b" />

---

## Installation
1. Copy this directory (or the packaged release) into your Bolt `plugins` folder.
2. Launch Bolt and enable **Ground Markers** in the Plugin Manager.
3. A small tile launcher button appears in-game. Click it to toggle the UI and **Shift+Drag** it to reposition.

---

## Quick Controls
| Action | Shortcut |
| --- | --- |
| Mark / unmark the tile under your cursor | `Alt + Middle Click` |
| Cycle a tile through the color palette | `Ctrl + Middle Click` |
| Cycle the global palette selection | `Ctrl + Scroll` |
| Open / close the layouts UI | Click the tile launcher button (`Shift+Drag` to move it) |
| Adjust chunk-tile height in the grid | `Shift + Scroll` over a marked cell |
| Zoom the chunk grid | Scroll (no modifier) |

---

## User Interface

### 1. Layouts
* **Status Bar** – shows whether you are in an instance, how many temporary tiles are waiting to be saved, and which layout (if any) is active.
* **Save Current Tiles** – once you are in an instance and have marked tiles, type a name and click _Save Layout_ to store them. Saved layouts use chunk-local coordinates and can be reused anywhere.
* **Saved Layouts** – list of every stored layout. Each item includes:
  * A toggle switch to activate/deactivate the layout. The last active layout is remembered and auto-applies the next time you step into an instance.
  * Copy (export) and delete buttons. Export copies JSON to your clipboard (or opens a modal fallback) so you can share layouts. Delete prompts for confirmation.
  * The _Import Layout_ button in this section opens a modal where you can paste JSON that someone else exported.

### 2. Chunk Map
* Provides an interactive top-down grid map of the current chunk (64×64 tiles). The player tile is highlighted in orange; blue tiles are marked; white indicates the hover preview.
* **Zooming** – scroll to zoom in/out. The viewport always tries to keep you centered while respecting chunk boundaries.
* **Editing** – click to mark or unmark tiles, matching the selected color in the dropdown. Hovering a tile previews it in-game.
* **Height Control** – hold `Shift` and scroll over a marked tile to raise or lower its elevation.
* The legend, status line, and dropdown all update live as layouts and palettes change.

### 3. Palette
* Shows every color slot in the active palette.
* Click the square swatch to pick a new color and rename it in the adjacent field.
* Press _Save_ to push the change back to the plugin. Colors sync immediately to layouts and the chunk map.

---

## Typical Instance Workflow
1. **Prep** – enter your instance.
2. **Mark Tiles** – use `Alt+Middle Click` or the chunk map to paint tiles as usual. These are stored as temporary tiles until you save them.
4. **Save a Layout** – Open the UI and give the tiles a descriptive name (e.g., “Croesus North”). They are saved chunk-relative, so the markers automatically shift to match whatever instance chunk you stand in next.
5. **Activate Layouts** – toggle the layout you need. The plugin remembers your choice and reapplies it whenever you re-enter an instance until you toggle it off.
6. **Edit with the Chunk Map (Optional)** – use the Chunk Map tab to fine-tune tiles, preview placements from afar, and set heights via `Shift+Scroll`.
7. **Reuse Later** – when you load into a different run of the same encounter, simply enter the instance and the active layout will appear. You can still place temporary tiles on top if needed.

### Note:
The reason layouts are chunk-relative is that bolt currently has no reliable way to identify specific instances or encounters. We can however detect whether you are in an instanced area, layouts can thus be reused across multiple runs of the same content, but will need to be switched between different encounters.

---

## Importing & Exporting Layouts
* **Export** – click the copy icon next to a layout. The layout JSON is copied to your clipboard (or shown in a modal) and includes name, pretty display name, and every tile.
* **Import** – click **Import Layout**, paste JSON that matches the export format, and confirm. You can rename or recolor tiles after importing.

---

## Customising the Palette
Ground Markers ships with a sensible default palette, but every slot can be renamed and recolored in the Palette tab. Palette changes are global:
* Existing ground markers, instance layouts, and the chunk editor update immediately.
* The chunk map color picker always reflects the latest palette state.

---

## Launcher Tips
* Clicking the tile button toggles the layouts window.
* Holding **Shift** while dragging the button lets you move it anywhere on the screen. Its position is remembered between sessions.

---
