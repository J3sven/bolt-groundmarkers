local M = {}
local persistence = require("data.persistence")
local HEIGHT_STEP = 25

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
        -- Handle instance tiles separately
        local tempTiles = instanceManager.getInstanceTiles()

        if tempTiles[key] then
            instanceManager.removeInstanceTile(key)
        else
            local tileData = {
                x = tile2D.x, z = tile2D.z, y = py,
                colorIndex = state.getCurrentColorIndex(),
                chunkX = chunkX, chunkZ = chunkZ,
                localX = localX, localZ = localZ,
                floor = floor
            }

            instanceManager.addInstanceTile(tileData)
        end

        -- Update GUI if it's open (pass bolt parameter)
        local guiBridge = require("core.gui_bridge")
        if guiBridge.isOpen() then
            guiBridge.sendStateUpdate(state, bolt)
        end
    else
        -- Handle regular tiles as before
        local marked = state.getMarkedTiles()

        if marked[key] then
            local existing = marked[key]
            marked[key] = nil
            persistence.saveMarkers(state, bolt)
        else
            local markerData = {
                x = tile2D.x, z = tile2D.z, y = py,
                colorIndex = state.getCurrentColorIndex(),
                chunkX = chunkX, chunkZ = chunkZ,
                localX = localX, localZ = localZ,
                floor = floor
            }

            marked[key] = markerData
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
        -- Recolor temp instance tile
        local tempTiles = instanceManager.getInstanceTiles()

        if tempTiles[key] then
            tempTiles[key].colorIndex = state.getCurrentColorIndex()

            -- Update GUI if open (pass bolt parameter)
            local guiBridge = require("core.gui_bridge")
            if guiBridge.isOpen() then
                guiBridge.sendStateUpdate(state, bolt)
            end

            return true
        end
    else
        -- Recolor regular tile
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
        floor = floor or 0
    }

    marked[key] = markerData
    persistence.saveMarkers(state, bolt)

    return true
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

    return true
end

return M
