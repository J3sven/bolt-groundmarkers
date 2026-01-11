# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [unreleased]

## Fixed
- When merging layouts, labels on tiles are now preserved correctly.

## [v1.8] - 2026-01-11

## Fixed
- Labels on tiles wil now save and load correctly with layouts.

## [v1.7] - 2026-01-11

## Fixed
- Tile fills will no longer explode if one or more boundaries of a tile are off-screen.

## [v1.6] - 2026-01-11

## Added
- Added a setting to hide connecting lines between tiles.

## [v1.5] - 2026-01-11

## Added
- Added a setting that lets tiles be rendered with a fill.
- Added a fill opacity setting for filled tiles.

## Changed
- Moved to a shader based rendering approach for drawing tiles, greatly improving performance and visual quality

## [v1.4] - 2026-01-11

## Added
- Added setting to adjust line thickness for drawn markers, accessible in the Settings tab
- Added the ability to label tiles with text, `ctrl + click` on a tile in the chunk map to add or edit a label, showing/hiding labels can be toggled in settings

## Changed
- The palette tab has been replaced with a Settings tab, which now includes the palette editor as well as other settings such as line thickness adjustment
- Palette colors now save on change without needing to click a save button
- Further performance improvements when rendering many tiles

## [v1.3] - 2026-01-10

## Added
- Merge feature: Surface layouts can now be merged together, combining their markers into a single layout for easier sharing and management
- The Chunk map UI now also displays actively marked tiles originating from saved layouts, these are marked in grey as layouts cannot be modified directly from the chunk map UI, but this should help with orientation when placing new markers.

## Changed
- Tiles will now render within a chunk-sized area around the player, rather than relative to the player's current actual chunk on the map. This allows for better visibility of nearby tiles and prevents sudden disappearances when crossing chunk boundaries.
- Improved performance of tile rendering by optimizing edge calculations and reducing redundant surface creations, this should hopefully improve frame rates when many tiles are marked.

## [v1.2] - 2026-01-10

### Added
- Regular overworld tiles can now also be saved and exported as layouts per chunk

### Changed
- Layouts are now automatically activated when saved
- Imported layouts are now automatically activated upon successful import
- Some minor UI improvements

