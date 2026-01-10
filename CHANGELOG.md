# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

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

