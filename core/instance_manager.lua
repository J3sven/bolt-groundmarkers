local M = {}
local colors = require("core.colors")
local HEIGHT_STEP = 25
local ACTIVE_LAYOUTS_FILE = "active_layouts.json"
local boltRef = nil
local LABEL_MAX_LEN = 18

local state = {
    inInstance = false,
    is2x2Instance = false,
    activeLayoutIds = {},
    instanceTiles = {},
    currentChunkX = nil,
    currentChunkZ = nil,
    playerLocalX = nil,
    playerLocalZ = nil,
    playerFloor = nil,
    playerWorldY = 0,
    hoverPreview = nil,
    -- Track visited chunks in 2x2 instances to detect 2x2
    visitedChunks2x2 = {},
    -- Entry tile for instances (origin point for 2x2 layout coordinates)
    entryChunkX = nil,
    entryChunkZ = nil,
    entryLocalX = nil,
    entryLocalZ = nil,
    -- Surface position tracking for entrance linking
    lastSurfacePosition = {
        chunkX = nil,
        chunkZ = nil,
        localX = nil,
        localZ = nil,
        floor = nil
    },
    surfacePositionHistory = {},
}

local function isInInstanceChunk(chunkX)
    return chunkX > 100 or chunkX < -100
end

-- Check if two chunks are directly adjacent (differ by exactly 1 in X or Z, not both)
local function areChunksAdjacent(cx1, cz1, cx2, cz2)
    local dx = math.abs(cx1 - cx2)
    local dz = math.abs(cz1 - cz2)
    -- Adjacent if exactly 1 apart in one dimension and 0 in the other, or 1 in both (diagonal)
    return (dx == 1 and dz == 0) or (dx == 0 and dz == 1) or (dx == 1 and dz == 1)
end

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

local function findValidEntranceTile()
    if state.lastSurfacePosition.chunkX then
        return state.lastSurfacePosition
    end

    if #state.surfacePositionHistory > 0 then
        local pos = state.surfacePositionHistory[1]
        return pos
    end

    return nil
end

local function applyLayoutAutoSwitch(entranceTile)
    if not boltRef then
        return
    end

    local layoutPersist = require("data.layout_persistence")
    local layouts = layoutPersist.getAllLayouts(boltRef)
    local matchedLayouts = {}

    -- Find all instance layouts linked to this entrance
    for _, layout in ipairs(layouts) do
        if layout.layoutType == "instance" and layout.linkedEntrance then
            local link = layout.linkedEntrance

            -- Calculate tile-based distance (9 tile radius)
            local entryTileX = link.chunkX * 64 + link.localX
            local entryTileZ = link.chunkZ * 64 + link.localZ

            local currentTileX = entranceTile.chunkX * 64 + entranceTile.localX
            local currentTileZ = entranceTile.chunkZ * 64 + entranceTile.localZ

            local deltaX = math.abs(entryTileX - currentTileX)
            local deltaZ = math.abs(entryTileZ - currentTileZ)

            if deltaX <= 9 and deltaZ <= 9 then
                table.insert(matchedLayouts, layout.id)
            end
        end
    end

    local allInstanceLayouts = {}
    for _, layout in ipairs(layouts) do
        if layout.layoutType == "instance" then
            table.insert(allInstanceLayouts, layout.id)
        end
    end

    for _, layoutId in ipairs(allInstanceLayouts) do
        M.deactivateLayout(layoutId)
    end

    for _, layoutId in ipairs(matchedLayouts) do
        M.activateLayout(layoutId)
    end
end

function M.update(bolt)
    local playerPos = bolt.playerposition()
    if not playerPos then return end

    local px, py, pz = playerPos:get()
    local coords = require("core.coords")
    local tileX, tileZ = coords.worldToTileCoords(px, pz)
    local floor, chunkX, chunkZ, localX, localZ = coords.tileToRS(tileX, tileZ, py)

    local wasInInstance = state.inInstance
    local newInInstance = isInInstanceChunk(chunkX)

    local chunkChanged = state.currentChunkX ~= chunkX or state.currentChunkZ ~= chunkZ
    local previousChunkX = state.currentChunkX
    local previousChunkZ = state.currentChunkZ
    local previousLocalX = state.playerLocalX
    local previousLocalZ = state.playerLocalZ
    local previousFloor = state.playerFloor

    -- Track surface position continuously when on surface
    -- Also capture the transition moment when entering instance
    if not newInInstance and not wasInInstance then
        state.lastSurfacePosition.chunkX = chunkX
        state.lastSurfacePosition.chunkZ = chunkZ
        state.lastSurfacePosition.localX = localX
        state.lastSurfacePosition.localZ = localZ
        state.lastSurfacePosition.floor = floor

        if chunkChanged then
            table.insert(state.surfacePositionHistory, 1, {
                chunkX = chunkX,
                chunkZ = chunkZ,
                localX = localX,
                localZ = localZ,
                floor = floor
            })
            if #state.surfacePositionHistory > 3 then
                table.remove(state.surfacePositionHistory)
            end
        end
    elseif newInInstance and not wasInInstance then
        if previousChunkX and previousChunkZ and previousLocalX and previousLocalZ then
            state.lastSurfacePosition.chunkX = previousChunkX
            state.lastSurfacePosition.chunkZ = previousChunkZ
            state.lastSurfacePosition.localX = previousLocalX
            state.lastSurfacePosition.localZ = previousLocalZ
            state.lastSurfacePosition.floor = previousFloor or floor
        end
    end

    -- Now update the instance state
    state.inInstance = newInInstance

    -- Detect instance-to-instance teleport: large chunk jump while in instance
    -- Adjacent chunks differ by 1, teleports jump much further (typically 100+)
    local isTeleportBetweenInstances = false
    if state.inInstance and wasInInstance and chunkChanged and previousChunkX and previousChunkZ then
        local chunkDeltaX = math.abs(chunkX - previousChunkX)
        local chunkDeltaZ = math.abs(chunkZ - previousChunkZ)
        -- If chunk jump is larger than adjacent (> 1), it's a teleport
        if chunkDeltaX > 1 or chunkDeltaZ > 1 then
            isTeleportBetweenInstances = true
        end
    end

    state.currentChunkX = chunkX
    state.currentChunkZ = chunkZ
    state.playerLocalX = localX
    state.playerLocalZ = localZ
    state.playerFloor = floor
    state.playerWorldY = py

    if chunkChanged then
        state.hoverPreview = nil
    end

    if state.inInstance and not wasInInstance then

        state.instanceTiles = {}
        state.hoverPreview = nil
        state.visitedChunks2x2 = {}
        state.is2x2Instance = false

        -- Store entry tile (chunk + local) as the origin point for this instance
        state.entryChunkX = chunkX
        state.entryChunkZ = chunkZ
        state.entryLocalX = localX
        state.entryLocalZ = localZ

        local chunkKey = chunkX .. "," .. chunkZ
        state.visitedChunks2x2[chunkKey] = true

        -- Auto-switch layouts based on entrance
        local entranceTile = findValidEntranceTile()
        if entranceTile then
            applyLayoutAutoSwitch(entranceTile)
        end
    end

    if isTeleportBetweenInstances then
        state.instanceTiles = {}
        state.hoverPreview = nil
        state.visitedChunks2x2 = {}
        state.is2x2Instance = false

        -- Reset entry tile for new instance
        state.entryChunkX = chunkX
        state.entryChunkZ = chunkZ
        state.entryLocalX = localX
        state.entryLocalZ = localZ

        -- Track first chunk of new instance
        local chunkKey = chunkX .. "," .. chunkZ
        state.visitedChunks2x2[chunkKey] = true

        -- Auto-switch layouts based on last surface entrance
        local entranceTile = findValidEntranceTile()
        if entranceTile then
            applyLayoutAutoSwitch(entranceTile)
        end
    end

    if not state.inInstance and wasInInstance then
        -- Leaving instance to surface
        state.instanceTiles = {}
        state.hoverPreview = nil
        state.visitedChunks2x2 = {}
        state.is2x2Instance = false
        state.entryChunkX = nil
        state.entryChunkZ = nil
        state.entryLocalX = nil
        state.entryLocalZ = nil

        -- Disable all instance layouts when exiting
        if boltRef then
            local layoutPersist = require("data.layout_persistence")
            local layouts = layoutPersist.getAllLayouts(boltRef)
            local disabledCount = 0
            for _, layout in ipairs(layouts) do
                if layout.layoutType == "instance" and M.isLayoutActive(layout.id) then
                    M.deactivateLayout(layout.id)
                    disabledCount = disabledCount + 1
                end
            end
        end
    end

    -- Detect 2x2 instance when crossing to adjacent chunk (normal walking, not teleport)
    if state.inInstance and chunkChanged and previousChunkX and previousChunkZ and not isTeleportBetweenInstances then
        local chunkKey = chunkX .. "," .. chunkZ

        -- Check if new chunk is adjacent to any previously visited chunk
        local isAdjacentToVisited = false
        for visitedKey, _ in pairs(state.visitedChunks2x2) do
            local vcx, vcz = visitedKey:match("([^,]+),([^,]+)")
            vcx = tonumber(vcx)
            vcz = tonumber(vcz)

            if vcx and vcz and areChunksAdjacent(chunkX, chunkZ, vcx, vcz) then
                isAdjacentToVisited = true
                break
            end
        end

        if isAdjacentToVisited then
            state.is2x2Instance = true
        end

        -- Track this chunk
        state.visitedChunks2x2[chunkKey] = true
    end
end

function M.isInInstance()
    return state.inInstance
end

function M.is2x2Instance()
    return state.is2x2Instance
end

function M.getActiveLayoutIds()
    return state.activeLayoutIds or {}
end

function M.isLayoutActive(layoutId)
    for _, id in ipairs(state.activeLayoutIds) do
        if id == layoutId then
            return true
        end
    end
    return false
end

function M.activateLayout(layoutId)
    if type(layoutId) ~= "string" or layoutId == "" then
        return false
    end

    if M.isLayoutActive(layoutId) then
        return true
    end

    table.insert(state.activeLayoutIds, layoutId)
    persistActiveLayouts()
    return true
end

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

function M.clearActiveLayouts()
    state.activeLayoutIds = {}
    persistActiveLayouts()
end

function M.getLastSurfacePosition()
    return state.lastSurfacePosition
end
function M.addInstanceTile(tileData)
    local coords = require("core.coords")
    local key = coords.tileKey(tileData.x, tileData.z)
    state.instanceTiles[key] = tileData
end

function M.removeInstanceTile(key)
    state.instanceTiles[key] = nil
end

function M.getInstanceTiles()
    return state.instanceTiles
end

function M.clearInstanceTiles()
    state.instanceTiles = {}
end

function M.getInstanceTileCount()
    local count = 0
    for _ in pairs(state.instanceTiles) do
        count = count + 1
    end
    return count
end

function M.getState()
    return {
        inInstance = state.inInstance,
        is2x2Instance = state.is2x2Instance,
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

-- Get the entry tile (first tile visited in this instance session)
-- This is used as the origin point for 2x2 layouts
function M.getEntryTile()
    return state.entryChunkX, state.entryChunkZ, state.entryLocalX, state.entryLocalZ
end

-- Calculate base chunk (minimum coords) from all visited chunks (for tile placement)
local function getBaseChunk2x2()
    local minChunkX = nil
    local minChunkZ = nil

    for chunkKey, _ in pairs(state.visitedChunks2x2) do
        local cx, cz = chunkKey:match("([^,]+),([^,]+)")
        cx = tonumber(cx)
        cz = tonumber(cz)

        if cx and cz then
            if not minChunkX or cx < minChunkX then
                minChunkX = cx
            end
            if not minChunkZ or cz < minChunkZ then
                minChunkZ = cz
            end
        end
    end

    return minChunkX, minChunkZ
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

local function normalizeLabel(input)
    if type(input) ~= "string" then
        return nil
    end
    local cleaned = input:gsub("[%c]", " "):gsub("%s+", " ")
    cleaned = cleaned:match("^%s*(.-)%s*$") or ""
    if cleaned == "" then
        return nil
    end
    if #cleaned > LABEL_MAX_LEN then
        cleaned = cleaned:sub(1, LABEL_MAX_LEN)
    end
    return cleaned
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
        tileX = tileX,
        tileZ = tileZ,
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
        floor = state.playerFloor or 0,
        tileX = tileX,
        tileZ = tileZ
    }

    -- Always store coordinates RELATIVE to entry tile for all instances
    -- This way tiles placed before 2x2 detection still work correctly
    if state.entryChunkX and state.entryChunkZ and state.entryLocalX and state.entryLocalZ then
        -- Calculate entry tile position
        local entryTileX = state.entryChunkX * 64 + state.entryLocalX
        local entryTileZ = state.entryChunkZ * 64 + state.entryLocalZ

        -- Store relative offset from entry tile
        -- For 1x1 instances, these will be in 0-63 range
        -- For 2x2 instances, these can be larger
        tileData.relativeX = tileX - entryTileX
        tileData.relativeZ = tileZ - entryTileZ
    end

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

function M.setInstanceTileLabel(localX, localZ, labelText)
    localX = clampLocalCoord(localX)
    localZ = clampLocalCoord(localZ)

    if not localX or not localZ or not state.currentChunkX or not state.currentChunkZ then
        return false
    end

    local coords = require("core.coords")
    local tileX = state.currentChunkX * 64 + localX
    local tileZ = state.currentChunkZ * 64 + localZ
    local worldX, worldZ = coords.tileToWorldCoords(tileX, tileZ)
    local key = coords.tileKey(worldX, worldZ)
    local tile = state.instanceTiles[key]
    if not tile then
        return false
    end

    local normalized = normalizeLabel(labelText)
    if tile.label == normalized then
        return false
    end

    tile.label = normalized
    return true
end

function M.getInstanceTileLabel(localX, localZ)
    localX = clampLocalCoord(localX)
    localZ = clampLocalCoord(localZ)
    if not localX or not localZ or not state.currentChunkX or not state.currentChunkZ then
        return nil
    end

    local coords = require("core.coords")
    local tileX = state.currentChunkX * 64 + localX
    local tileZ = state.currentChunkZ * 64 + localZ
    local worldX, worldZ = coords.tileToWorldCoords(tileX, tileZ)
    local key = coords.tileKey(worldX, worldZ)
    local tile = state.instanceTiles[key]
    if tile then
        return tile.label
    end
    return nil
end

return M
