-- core/instance_manager.lua - Simplified instance management with user control
local M = {}

-- Internal state
local state = {
    inInstance = false,
    currentLayoutId = nil,  -- User-selected active layout
    instanceTiles = {},     -- Temporary tiles marked while in instance (before saving)
    currentChunkX = nil,
    currentChunkZ = nil,
    playerLocalX = nil,
    playerLocalZ = nil,
    playerFloor = nil,
    playerWorldY = 0,
    hoverPreview = nil,
}

-- Check if player is in an instance based on chunk coordinates
local function isInInstanceChunk(chunkX, chunkZ)
    return chunkX > 100 or chunkX < -100
end

-- Initialize the instance manager
function M.init()
    state.inInstance = false
    state.currentLayoutId = nil
    state.instanceTiles = {}
    return true
end

-- Update instance state based on player position
function M.update(bolt)
    local playerPos = bolt.playerposition()
    if not playerPos then return end

    local px, py, pz = playerPos:get()
    local coords = require("core.coords")
    local tileX, tileZ = coords.worldToTileCoords(px, pz)
    local floor, chunkX, chunkZ, localX, localZ = coords.tileToRS(tileX, tileZ, py)

    local wasInInstance = state.inInstance
    state.inInstance = isInInstanceChunk(chunkX, chunkZ)

    local chunkChanged = state.currentChunkX ~= chunkX or state.currentChunkZ ~= chunkZ
    state.currentChunkX = chunkX
    state.currentChunkZ = chunkZ
    state.playerLocalX = localX
    state.playerLocalZ = localZ
    state.playerFloor = floor
    state.playerWorldY = py

    if chunkChanged then
        state.hoverPreview = nil
    end

    -- Debug logging
    bolt.saveconfig("instance_debug.txt", string.format(
        "Update: chunk(%d,%d) inInstance=%s wasInInstance=%s",
        chunkX, chunkZ, tostring(state.inInstance), tostring(wasInInstance)
    ))

    -- Entering instance
    if state.inInstance and not wasInInstance then
        state.instanceTiles = {}
        state.hoverPreview = nil
        bolt.saveconfig("instance_debug.txt", string.format(
            "ENTERED instance at chunk (%d, %d)", chunkX, chunkZ
        ))
    end

    -- Leaving instance
    if not state.inInstance and wasInInstance then
        -- Clear temporary tiles when leaving instance
        state.instanceTiles = {}
        state.currentLayoutId = nil
        state.hoverPreview = nil
        bolt.saveconfig("instance_debug.txt", string.format(
            "LEFT instance at chunk (%d, %d)", chunkX, chunkZ
        ))
    end
end

-- Check if player is currently in an instance
function M.isInInstance()
    return state.inInstance
end

-- Get the currently active layout ID (user-selected)
function M.getActiveLayoutId()
    return state.currentLayoutId
end

-- Set the active layout (called from GUI)
function M.setActiveLayout(layoutId)
    state.currentLayoutId = layoutId
end

-- Clear the active layout
function M.clearActiveLayout()
    state.currentLayoutId = nil
end

-- Add a tile to the temporary instance buffer
function M.addInstanceTile(tileData)
    local coords = require("core.coords")
    local key = coords.tileKey(tileData.x, tileData.z)
    state.instanceTiles[key] = tileData
end

-- Remove a tile from the temporary instance buffer
function M.removeInstanceTile(key)
    state.instanceTiles[key] = nil
end

-- Get all temporary instance tiles (not yet saved to a layout)
function M.getInstanceTiles()
    return state.instanceTiles
end

-- Clear all temporary instance tiles
function M.clearInstanceTiles()
    state.instanceTiles = {}
end

-- Count temporary instance tiles
function M.getInstanceTileCount()
    local count = 0
    for _ in pairs(state.instanceTiles) do
        count = count + 1
    end
    return count
end

-- Get state for debugging
function M.getState()
    return {
        inInstance = state.inInstance,
        currentLayoutId = state.currentLayoutId,
        tempTileCount = M.getInstanceTileCount()
    }
end

function M.getChunkSnapshot()
    if not state.currentChunkX or not state.currentChunkZ then
        return nil
    end

    return {
        chunkX = state.currentChunkX,
        chunkZ = state.currentChunkZ,
        localX = state.playerLocalX,
        localZ = state.playerLocalZ,
        floor = state.playerFloor or 0,
        worldY = state.playerWorldY or 0
    }
end

local function clampLocalCoord(value)
    if type(value) ~= "number" then
        return nil
    end
    value = math.floor(value + 0.5)
    if value < 0 or value > 63 then
        return nil
    end
    return value
end

function M.setHoverTile(localX, localZ)
    localX = clampLocalCoord(localX)
    localZ = clampLocalCoord(localZ)

    if not localX or not localZ then
        state.hoverPreview = nil
        return false
    end

    if not state.currentChunkX or not state.currentChunkZ then
        state.hoverPreview = nil
        return false
    end

    local coords = require("core.coords")
    local tileX = state.currentChunkX * 64 + localX
    local tileZ = state.currentChunkZ * 64 + localZ
    local worldX, worldZ = coords.tileToWorldCoords(tileX, tileZ)

    state.hoverPreview = {
        x = worldX,
        z = worldZ,
        y = state.playerWorldY or 0,
        chunkX = state.currentChunkX,
        chunkZ = state.currentChunkZ,
        localX = localX,
        localZ = localZ,
        floor = state.playerFloor or 0,
        previewColor = {255, 255, 255}
    }

    return true
end

function M.clearHoverTile()
    state.hoverPreview = nil
end

function M.getHoverTile()
    return state.hoverPreview
end

function M.toggleTileAtLocal(localX, localZ, colorIndex, bolt)
    localX = clampLocalCoord(localX)
    localZ = clampLocalCoord(localZ)

    if not localX or not localZ or not state.inInstance then
        return false
    end

    if not state.currentChunkX or not state.currentChunkZ then
        return false
    end

    local coords = require("core.coords")
    local chunkX, chunkZ = state.currentChunkX, state.currentChunkZ
    local tileX = chunkX * 64 + localX
    local tileZ = chunkZ * 64 + localZ
    local worldX, worldZ = coords.tileToWorldCoords(tileX, tileZ)
    local key = coords.tileKey(worldX, worldZ)

    if state.instanceTiles[key] then
        M.removeInstanceTile(key)
        if bolt then
            bolt.saveconfig("marker_debug.txt", string.format(
                "Removed grid-marked tile at chunk (%d,%d) local (%d,%d)",
                chunkX, chunkZ, localX, localZ))
        end
        return true
    end

    local tileData = {
        x = worldX,
        z = worldZ,
        y = state.playerWorldY or 0,
        colorIndex = colorIndex or 1,
        chunkX = chunkX,
        chunkZ = chunkZ,
        localX = localX,
        localZ = localZ,
        floor = state.playerFloor or 0
    }

    M.addInstanceTile(tileData)

    if bolt then
        bolt.saveconfig("marker_debug.txt", string.format(
            "Added grid-marked tile at chunk (%d,%d) local (%d,%d)",
            chunkX, chunkZ, localX, localZ))
    end

    return true
end

return M
