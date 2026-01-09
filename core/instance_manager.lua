-- core/instance_manager.lua - Simplified instance management with user control
local M = {}

-- Internal state
local state = {
    inInstance = false,
    currentLayoutId = nil,  -- User-selected active layout
    instanceTiles = {},     -- Temporary tiles marked while in instance (before saving)
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
    local _, chunkX, chunkZ = coords.tileToRS(tileX, tileZ, py)

    local wasInInstance = state.inInstance
    state.inInstance = isInInstanceChunk(chunkX, chunkZ)

    -- Debug logging
    bolt.saveconfig("instance_debug.txt", string.format(
        "Update: chunk(%d,%d) inInstance=%s wasInInstance=%s",
        chunkX, chunkZ, tostring(state.inInstance), tostring(wasInInstance)
    ))

    -- Entering instance
    if state.inInstance and not wasInInstance then
        state.instanceTiles = {}
        bolt.saveconfig("instance_debug.txt", string.format(
            "ENTERED instance at chunk (%d, %d)", chunkX, chunkZ
        ))
    end

    -- Leaving instance
    if not state.inInstance and wasInInstance then
        -- Clear temporary tiles when leaving instance
        state.instanceTiles = {}
        state.currentLayoutId = nil
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

return M
