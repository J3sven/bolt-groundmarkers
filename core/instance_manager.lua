-- core/instance_manager.lua - Simplified instance management with user control
local M = {}
local colors = require("core.colors")
local HEIGHT_STEP = 25
local ACTIVE_LAYOUTS_FILE = "active_layouts.json"
local boltRef = nil

-- Internal state
local state = {
    inInstance = false,
    activeLayoutIds = {},   -- Array of active layout IDs (can have multiple)
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
local function isInInstanceChunk(chunkX)
    return chunkX > 100 or chunkX < -100
end

-- Initialize the instance manager
local function trimString(value)
    if type(value) ~= "string" then
        return nil
    end
    local trimmed = value:match("^%s*(.-)%s*$") or ""
    if trimmed == "" then
        return nil
    end
    return trimmed
end

local function persistActiveLayouts()
    if not boltRef then
        return
    end
    local json = require("core.simplejson")
    local payload = json.encode(state.activeLayoutIds or {})
    if payload then
        boltRef.saveconfig(ACTIVE_LAYOUTS_FILE, payload)
    end
end

local function loadActiveLayouts()
    if not boltRef then
        return {}
    end
    local saved = boltRef.loadconfig(ACTIVE_LAYOUTS_FILE)
    if not saved or saved == "" then
        return {}
    end
    local json = require("core.simplejson")
    local decoded = json.decode(saved)
    if type(decoded) == "table" then
        return decoded
    end
    return {}
end

function M.init(bolt)
    boltRef = bolt
    state.inInstance = false
    state.activeLayoutIds = loadActiveLayouts()
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
    state.inInstance = isInInstanceChunk(chunkX)

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

    -- Entering instance
    if state.inInstance and not wasInInstance then
        state.instanceTiles = {}
        state.hoverPreview = nil
    end

    -- Leaving instance
    if not state.inInstance and wasInInstance then
        -- Clear temporary tiles when leaving instance
        state.instanceTiles = {}
        state.hoverPreview = nil
    end
end

-- Check if player is currently in an instance
function M.isInInstance()
    return state.inInstance
end

-- Get all active layout IDs
function M.getActiveLayoutIds()
    return state.activeLayoutIds or {}
end

-- Check if a specific layout is active
function M.isLayoutActive(layoutId)
    for _, id in ipairs(state.activeLayoutIds) do
        if id == layoutId then
            return true
        end
    end
    return false
end

-- Activate a layout (add to active list)
function M.activateLayout(layoutId)
    if type(layoutId) ~= "string" or layoutId == "" then
        return false
    end

    -- Check if already active
    if M.isLayoutActive(layoutId) then
        return true
    end

    table.insert(state.activeLayoutIds, layoutId)
    persistActiveLayouts()
    return true
end

-- Deactivate a layout (remove from active list)
function M.deactivateLayout(layoutId)
    for i, id in ipairs(state.activeLayoutIds) do
        if id == layoutId then
            table.remove(state.activeLayoutIds, i)
            persistActiveLayouts()
            return true
        end
    end
    return false
end

-- Clear all active layouts
function M.clearActiveLayouts()
    state.activeLayoutIds = {}
    persistActiveLayouts()
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
        activeLayoutIds = state.activeLayoutIds,
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
        previewColor = {255, 255, 255},
        previewAlpha = 45
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
        return true
    end

    local paletteCount = colors.count and colors.count() or 1
    local safeColorIndex = tonumber(colorIndex) or 1
    safeColorIndex = math.floor(safeColorIndex + 0.5)
    if paletteCount > 0 then
        if safeColorIndex < 1 then safeColorIndex = 1 end
        if safeColorIndex > paletteCount then safeColorIndex = paletteCount end
    else
        safeColorIndex = 1
    end

    local tileData = {
        x = worldX,
        z = worldZ,
        y = state.playerWorldY or 0,
        colorIndex = safeColorIndex,
        chunkX = chunkX,
        chunkZ = chunkZ,
        localX = localX,
        localZ = localZ,
        floor = state.playerFloor or 0
    }

    M.addInstanceTile(tileData)

    return true
end

function M.adjustInstanceTileHeight(localX, localZ, deltaSteps, bolt)
    localX = clampLocalCoord(localX)
    localZ = clampLocalCoord(localZ)

    local steps = tonumber(deltaSteps) or 0
    if steps == 0 then
        return false
    end

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
    local tile = state.instanceTiles[key]

    if not tile then
        return false
    end

    local newY = (tile.y or state.playerWorldY or 0) + steps * HEIGHT_STEP
    tile.y = newY
    tile.worldY = newY

    return true
end

return M
