# Ground Markers
Ground Markers is a [Bolt launcher](https://github.com/adamcake/Bolt) plugin for RuneScape 3 that brings the comfort of RuneLite / HDOS style tile markers to RS3, including fully user-controlled layouts for both instanced content and regular overworld chunks.

<img width="955" height="608" alt="image" src="https://github.com/user-attachments/assets/ea406ae2-88de-4528-b5d9-c7aec7eb5d2b" />

---

## Installation
Copy the following URL and add it as a custom plugin in Bolt:

```https://j3sven.github.io/bolt-groundmarkers/dist/meta.json```

---

## Quick Controls
<table>
  <thead>
    <tr>
      <th>Action</th>
      <th>Shortcut</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <td>Mark / unmark the tile under your cursor</td>
      <td><code>Alt + Middle Click</code></td>
    </tr>
    <tr>
      <td>Cycle a tile through the color palette</td>
      <td><code>Ctrl + Middle Click</code></td>
    </tr>
    <tr>
      <td>Cycle the global palette selection</td>
      <td><code>Ctrl + Scroll</code></td>
    </tr>
    <tr>
      <td>Open / close the layouts UI</td>
      <td>Click the tile launcher button (<code>Shift + Drag</code> to move it)</td>
    </tr>
    <tr>
      <td>Adjust chunk-tile height in the grid</td>
      <td><code>Shift + Scroll</code> over a marked cell</td>
    </tr>
    <tr>
      <td>Zoom the chunk grid</td>
      <td>Scroll (no modifier)</td>
    </tr>
  </tbody>
</table>

---

## User Interface

### 1. Layouts
* **Status Bar** – shows whether you are in an instance, how many unsaved tiles are waiting to be saved, and which layout(s) are active.
* **Save Current Tiles** – mark tiles and click _Save Layout_ to store them. Saved layouts use chunk-local coordinates and can be reused anywhere.
  * **Instance Layouts** – when in an instance, all marked tiles are temporary and can be saved as a reusable instance layout.
  * **Chunk Layouts** – when in the overworld, only unsaved tiles in the current chunk can be saved as a chunk-specific layout.
* **Saved Layouts** – list of every stored layout (both instance and chunk layouts). Each item includes:
  * A badge indicating the layout type (Instance or Chunk)
  * A toggle switch to activate/deactivate the layout. Layouts are automatically activated when saved or imported. Active layouts are remembered and auto-apply when you enter matching locations.
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
