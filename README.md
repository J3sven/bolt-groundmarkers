# Ground Markers
Ground Markers is a [Bolt launcher](https://codeberg.org/Adamcake/Bolt) plugin for RuneScape 3 that brings the comfort of RuneLite / HDOS style tile markers to RS3, including fully user-controlled layouts for both instanced content and regular overworld chunks.

<img width="955" height="608" alt="image" src="https://github.com/user-attachments/assets/ea406ae2-88de-4528-b5d9-c7aec7eb5d2b" />

---

## Installation
Copy the following URL and add it as a custom plugin in Bolt:

```https://j3sven.github.io/bolt-groundmarkers/dist/meta.json```

View the [CHANGELOG](CHANGELOG.md) to see what's new in the latest version.

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
  </tbody>
</table>


## Editor Controls
<table>
  <thead>
    <tr>
      <th>Action</th>
      <th>Shortcut</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <td>Zoom the chunk grid</td>
      <td>Scroll (no modifier)</td>
    </tr>
    <tr>
      <td>Add a Tile</td>
      <td>Click the desired tile</td>
    </tr>
    <tr>
      <td>Add or edit a label on a tile</td>
      <td><code>Ctrl + Click</code> on a tile in the chunk map</td>
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
  * A toggle switch to activate/deactivate the layout (hidden for linked layouts - see below)
  * **Link Button** (Instance layouts only) – link the layout to your current entrance location. When linked:
    * The button turns green to indicate the layout is linked
    * The layout will automatically enable when you enter the instance from within a 9-tile radius of the linked location
    * All instance layouts automatically disable when you exit any instance
    * Multiple layouts can be linked to the same entrance
    * You must be on the surface world (not in an instance) to link a layout
  * **Edit Button** – opens the layout in the Chunk Map editor where you can add, remove, or modify individual tiles. Changes are automatically saved.
  * **Export Button** – copies the layout JSON to your clipboard (or opens a modal fallback) so you can share layouts with others.
  * **Delete Button** – removes the layout permanently after confirmation.
  * The _Import Layout_ button opens a modal where you can paste JSON from an exported layout.

### 2. Chunk Map
* Provides an interactive top-down grid map of the current chunk (64×64 tiles). The player tile is highlighted in orange; blue tiles are marked; white indicates the hover preview.
* **Zooming** – scroll to zoom in/out. The viewport always tries to keep you centered while respecting chunk boundaries.
* **Editing** – click to mark or unmark tiles, matching the selected color in the dropdown. Hovering a tile previews it in-game.
* **Height Control** – hold `Shift` and scroll over a marked tile to raise or lower its elevation.
* The legend, status line, and dropdown all update live as layouts and palettes change.

### 3. Settings
* **Line Thickness** – adjust the thickness of the tile outlines drawn in-game.
* **Tile Fill** – toggle filled tiles on or off, and adjust the fill opacity.
* **Fill Opacity** – adjust the opacity of filled tiles when tile fills are enabled.
* **Connecting Lines** – toggle the visibility of lines connecting adjacent marked tiles.
* **Tile Labels** – toggle the visibility of text labels on tiles.
* **Palette Editor** – customize the global color palette used for marking tiles. Each slot can be renamed and recolored. Changes apply immediately everywhere.

---

## Typical Instance Workflow

### Option 1: Manual Toggling
1. **Prep** – enter your instance.
2. **Mark Tiles** – use `Alt+Middle Click` or the chunk map to paint tiles as usual. These are stored as temporary tiles until you save them.
3. **Save a Layout** – Open the UI and give the tiles a descriptive name (e.g., "Croesus North"). They are saved chunk-relative, so the markers automatically shift to match whatever instance chunk you stand in next.
4. **Activate Layouts** – toggle the layout you need. The plugin remembers your choice and reapplies it whenever you re-enter an instance until you toggle it off.
5. **Edit with the Chunk Map (Optional)** – use the Chunk Map tab to fine-tune tiles, preview placements from afar, and set heights via `Shift+Scroll`.
6. **Reuse Later** – when you load into a different run of the same encounter, simply enter the instance and the active layout will appear. You can still place temporary tiles on top if needed.

### Option 2: Automatic Entrance Linking (Recommended)
1. **Create Your Layout** – enter the instance, mark tiles, and save the layout as described above.
2. **Link to Entrance** – exit the instance and return to the entrance location on the surface world (within ~9 tiles of where you usually enter).
3. **Click the Link Button** – in the layouts list, click the link icon next to your instance layout and confirm your link. The button will turn green.
4. **Automatic Switching** – from now on, whenever you enter the instance from this entrance area, the linked layout will automatically enable and all other instance layouts will disable.
5. **Exit Behavior** – when you leave any instance, linked instance layouts automatically disable.

### Note:
The reason layouts are chunk-relative is that bolt currently has no reliable way to identify specific instances or encounters. We can however detect whether you are in an instanced area. Layouts can be reused across multiple runs of the same content, and with entrance linking, they automatically activate when you enter from the correct location.

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
