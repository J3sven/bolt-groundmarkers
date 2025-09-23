local M = {}

local TILE_SIZE = 512

function M.worldToTileCoords(worldX, worldZ)
  return math.floor(worldX / TILE_SIZE), math.floor(worldZ / TILE_SIZE)
end

function M.tileToWorldCoords(tileX, tileZ)
  return tileX * TILE_SIZE, tileZ * TILE_SIZE
end

function M.worldToTile2D(worldX, worldZ)
  return {
    x = math.floor(worldX / TILE_SIZE) * TILE_SIZE,
    z = math.floor(worldZ / TILE_SIZE) * TILE_SIZE
  }
end

function M.rsToTileCoords(floor, chunkX, chunkZ, localX, localZ)
    local tileX = chunkX * 64 + localX - 1
    local tileZ = chunkZ * 64 + localZ - 128
    return tileX, tileZ
end

function M.tileKey(tileX, tileZ)
  return tileX .. "," .. tileZ
end

function M.tileToRS(tileX, tileZ, worldY)
  local floor = math.floor((worldY - 965) / 960)
  local chunkX = math.floor((tileX + 1) / 64)
  local chunkZ = math.floor((tileZ + 128) / 64)
  local localX = (tileX + 1) % 64
  local localZ = (tileZ + 128) % 64
  return floor, chunkX, chunkZ, localX, localZ
end

M.TILE_SIZE = TILE_SIZE
return M
