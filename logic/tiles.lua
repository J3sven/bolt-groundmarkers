local M = {}
local persistence = require("data.persistence")

local function count(tbl) local c=0 for _ in pairs(tbl) do c=c+1 end return c end

function M.toggleTileMarker(state, bolt)
  local coords = state.getCoords()
  local colors = state.getColors()

  local playerPos = bolt.playerposition()
  if not playerPos then return end
  local px, py, pz = playerPos:get()

  local tile2D = coords.worldToTile2D(px, pz)
  local key    = coords.tileKey(tile2D.x, tile2D.z)

  local marked = state.getMarkedTiles()
  if marked[key] then
    local existing = marked[key]
    marked[key] = nil
    persistence.saveMarkers(state, bolt)
    bolt.saveconfig("marker_debug.txt", string.format(
      "Removed marker at tile (%d, %d) [world: %.0f, %.0f] (total: %d)",
      existing.tileX, existing.tileZ, tile2D.x, tile2D.z, count(marked)))
  else
    local tileX, tileZ = coords.worldToTileCoords(px, pz)

    local floor, chunkX, chunkZ, localX, localZ = coords.tileToRS(tileX, tileZ, py)

    -- derive absolute RS X and guard against > 6400
    local rsX = chunkX * 64 + localX
    if rsX > 6400 then
      bolt.saveconfig("marker_debug.txt", string.format(
        "Skipped marker at tile (%d, %d) [world: %.0f, %.0f]: rsX=%d > 6400",
        tileX, tileZ, tile2D.x, tile2D.z, rsX))
      return
    end

    marked[key] = {
      x = tile2D.x, z = tile2D.z, y = py,
      colorIndex = state.getCurrentColorIndex(),
      tileX = tileX, tileZ = tileZ
    }
    persistence.saveMarkers(state, bolt)

    bolt.saveconfig("marker_debug.txt", string.format(
      "Added %s marker at tile (%d, %d) [world: %.0f, %.0f] [RS: %d,%d,%d,%d,%d] at Y=%.0f (total: %d)",
      colors.getColorName(state.getCurrentColorIndex()), tileX, tileZ, tile2D.x, tile2D.z,
      floor, chunkX, chunkZ, localX, localZ, py, count(marked)))
  end
end


function M.recolorCurrentTile(state, bolt)
  local coords = state.getCoords()
  local colors = state.getColors()

  local playerPos = bolt.playerposition()
  if not playerPos then return false end
  local px, _, pz = playerPos:get()

  local tile2D = coords.worldToTile2D(px, pz)
  local key    = coords.tileKey(tile2D.x, tile2D.z)
  local marked = state.getMarkedTiles()

  if marked[key] then
    local oldColorName = colors.getColorName(marked[key].colorIndex or 1)
    marked[key].colorIndex = state.getCurrentColorIndex()
    persistence.saveMarkers(state, bolt)

    local tileX, tileZ = coords.worldToTileCoords(px, pz)
    bolt.saveconfig("marker_debug.txt", string.format(
      "Recolored tile (%d, %d) from %s to %s",
      tileX, tileZ, oldColorName, colors.getColorName(state.getCurrentColorIndex())))
    return true
  end
  return false
end

return M
