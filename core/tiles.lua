local M = {}
local persistence = require("data.persistence")
local HEIGHT_STEP = 25
local MAX_LABEL_LENGTH = 36

function M.toggleTileMarker(state, bolt)
    local coords = state.getCoords()
    local colors = state.getColors()
    local instanceManager = require("core.instance_manager")

    local playerPos = bolt.playerposition()
    if not playerPos then return end

    local px, py, pz = playerPos:get()
    local tile2D = coords.worldToTile2D(px, pz)
    local key = coords.tileKey(tile2D.x, tile2D.z)
    local tileX, tileZ = coords.worldToTileCoords(px, pz)
    local floor, chunkX, chunkZ, localX, localZ = coords.tileToRS(tileX, tileZ, py)

    local inInstance = instanceManager.isInInstance()

    if inInstance then
        local tempTiles = instanceManager.getInstanceTiles()

        if tempTiles[key] then
            instanceManager.removeInstanceTile(key)
        else
            local tileData = {
                x = tile2D.x,
                z = tile2D.z,
                y = py,
                colorIndex = state.getCurrentColorIndex(),
                chunkX = chunkX,
                chunkZ = chunkZ,
                localX = localX,
                localZ = localZ,
                floor = floor,
                tileX = tileX,
                tileZ = tileZ
            }

            instanceManager.addInstanceTile(tileData)
        end

        local guiBridge = require("core.gui_bridge")
        if guiBridge.isOpen() then
            guiBridge.sendStateUpdate(state, bolt)
        end
    else
        local marked = state.getMarkedTiles()

        if marked[key] then
            local existing = marked[key]
            marked[key] = nil
            state.bumpTileRevision()
            persistence.saveMarkers(state, bolt)
        else
            local markerData = {
                x = tile2D.x,
                z = tile2D.z,
                y = py,
                colorIndex = state.getCurrentColorIndex(),
                chunkX = chunkX,
                chunkZ = chunkZ,
                localX = localX,
                localZ = localZ,
                floor = floor,
                tileX = tileX,
                tileZ = tileZ
            }

            marked[key] = markerData
            state.bumpTileRevision()
            persistence.saveMarkers(state, bolt)
        end
    end
end

function M.recolorCurrentTile(state, bolt)
    local coords = state.getCoords()
    local colors = state.getColors()
    local instanceManager = require("core.instance_manager")

    local playerPos = bolt.playerposition()
    if not playerPos then return false end

    local px, _, pz = playerPos:get()
    local tile2D = coords.worldToTile2D(px, pz)
    local key = coords.tileKey(tile2D.x, tile2D.z)

    local inInstance = instanceManager.isInInstance()

    if inInstance then
        local tempTiles = instanceManager.getInstanceTiles()

        if tempTiles[key] then
            tempTiles[key].colorIndex = state.getCurrentColorIndex()

            local guiBridge = require("core.gui_bridge")
            if guiBridge.isOpen() then
                guiBridge.sendStateUpdate(state, bolt)
            end

            return true
        end
    else
        local marked = state.getMarkedTiles()

        if marked[key] then
            marked[key].colorIndex = state.getCurrentColorIndex()
            persistence.saveMarkers(state, bolt)
            return true
        end
    end

    return false
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
    if #cleaned > MAX_LABEL_LENGTH then
        cleaned = cleaned:sub(1, MAX_LABEL_LENGTH)
    end
    return cleaned
end

local function getMarkedTileAt(state, chunkX, chunkZ, localX, localZ)
    local coords = state.getCoords()
    if not coords or not chunkX or not chunkZ or not localX or not localZ then
        return nil, nil
    end

    local tileX = chunkX * 64 + localX
    local tileZ = chunkZ * 64 + localZ
    local worldX, worldZ = coords.tileToWorldCoords(tileX, tileZ)
    local key = coords.tileKey(worldX, worldZ)

    local marked = state.getMarkedTiles()
    return marked[key], key
end

function M.toggleWorldTileAtChunkLocal(state, bolt, chunkX, chunkZ, localX, localZ, floor, worldY, colorIndex)
    localX = clampLocalCoord(localX)
    localZ = clampLocalCoord(localZ)
    if not chunkX or not chunkZ or not localX or not localZ then
        return false
    end

    local coords = state.getCoords()
    local tileX = chunkX * 64 + localX
    local tileZ = chunkZ * 64 + localZ
    local worldX, worldZ = coords.tileToWorldCoords(tileX, tileZ)
    local key = coords.tileKey(worldX, worldZ)

    local marked = state.getMarkedTiles()
    if marked[key] then
        marked[key] = nil
        state.bumpTileRevision()
        persistence.saveMarkers(state, bolt)
        return true
    end

    local paletteCount = 1
    if state.getColors then
        local paletteModule = state.getColors()
        if paletteModule and paletteModule.count then
            paletteCount = math.max(1, paletteModule.count())
        end
    end
    local safeColorIndex = tonumber(colorIndex) or (state.getCurrentColorIndex and state.getCurrentColorIndex() or 1)
    safeColorIndex = math.floor(safeColorIndex + 0.5)
    if safeColorIndex < 1 then safeColorIndex = 1 end
    if safeColorIndex > paletteCount then safeColorIndex = paletteCount end

    local markerData = {
        x = worldX,
        z = worldZ,
        y = worldY or 0,
        colorIndex = safeColorIndex,
        chunkX = chunkX,
        chunkZ = chunkZ,
        localX = localX,
        localZ = localZ,
        floor = floor or 0,
        tileX = tileX,
        tileZ = tileZ
    }

    marked[key] = markerData
    state.bumpTileRevision()
    persistence.saveMarkers(state, bolt)

    return true
end

function M.setWorldTileLabel(state, bolt, chunkX, chunkZ, localX, localZ, labelText)
    localX = clampLocalCoord(localX)
    localZ = clampLocalCoord(localZ)
    if not chunkX or not chunkZ or not localX or not localZ then
        return false
    end

    local tile, key = getMarkedTileAt(state, chunkX, chunkZ, localX, localZ)
    if not tile then
        return false
    end

    local normalized = normalizeLabel(labelText)
    if tile.label == normalized then
        return false
    end

    tile.label = normalized
    persistence.saveMarkers(state, bolt)
    return true
end

function M.getWorldTileLabel(state, chunkX, chunkZ, localX, localZ)
    localX = clampLocalCoord(localX)
    localZ = clampLocalCoord(localZ)
    if not chunkX or not chunkZ or not localX or not localZ then
        return nil
    end

    local tile = getMarkedTileAt(state, chunkX, chunkZ, localX, localZ)
    if tile then
        return tile.label
    end
    return nil
end

function M.adjustWorldTileHeight(state, bolt, chunkX, chunkZ, localX, localZ, deltaSteps)
    localX = clampLocalCoord(localX)
    localZ = clampLocalCoord(localZ)

    local steps = tonumber(deltaSteps) or 0
    if steps == 0 then
        return false
    end

    if not chunkX or not chunkZ or not localX or not localZ then
        return false
    end

    local coords = state.getCoords()
    local tileX = chunkX * 64 + localX
    local tileZ = chunkZ * 64 + localZ
    local worldX, worldZ = coords.tileToWorldCoords(tileX, tileZ)
    local key = coords.tileKey(worldX, worldZ)

    local marked = state.getMarkedTiles()
    local tile = marked[key]
    if not tile then
        return false
    end

    local baseY = tile.y or tile.worldY or 0
    local newY = baseY + steps * HEIGHT_STEP
    tile.y = newY
    tile.worldY = newY
    persistence.saveMarkers(state, bolt)
    state.bumpTileRevision()

    return true
end

return M
