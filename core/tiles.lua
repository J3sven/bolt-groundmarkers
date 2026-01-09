local M = {}
local persistence = require("data.persistence")

local function count(tbl) local c=0 for _ in pairs(tbl) do c=c+1 end return c end

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
            -- Remove from temp tiles
            instanceManager.removeInstanceTile(key)

            bolt.saveconfig("marker_debug.txt", string.format(
                "Removed temp instance tile at local (%d, %d) [world: %.0f, %.0f]",
                localX, localZ, tile2D.x, tile2D.z))
        else
            -- Add to temp tiles
            local tileData = {
                x = tile2D.x, z = tile2D.z, y = py,
                colorIndex = state.getCurrentColorIndex(),
                chunkX = chunkX, chunkZ = chunkZ,
                localX = localX, localZ = localZ,
                floor = floor
            }

            instanceManager.addInstanceTile(tileData)

            bolt.saveconfig("marker_debug.txt", string.format(
                "Added temp instance tile at local (%d, %d) [world: %.0f, %.0f] (temp count: %d)",
                localX, localZ, tile2D.x, tile2D.z, instanceManager.getInstanceTileCount()))
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

            bolt.saveconfig("marker_debug.txt", string.format(
                "Removed marker at RS (%d,%d,%d,%d,%d) [world: %.0f, %.0f] (total: %d)",
                existing.floor or 0, existing.chunkX, existing.chunkZ, existing.localX, existing.localZ,
                tile2D.x, tile2D.z, count(marked)))
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

            bolt.saveconfig("marker_debug.txt", string.format(
                "Added %s marker at RS (%d,%d,%d,%d,%d) [world: %.0f, %.0f] at Y=%.0f (total: %d)",
                colors.getColorName(state.getCurrentColorIndex()),
                floor, chunkX, chunkZ, localX, localZ,
                tile2D.x, tile2D.z, py, count(marked)))
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
            local oldColorName = colors.getColorName(tempTiles[key].colorIndex or 1)
            tempTiles[key].colorIndex = state.getCurrentColorIndex()

            bolt.saveconfig("marker_debug.txt", string.format(
                "Recolored temp instance tile from %s to %s",
                oldColorName, colors.getColorName(state.getCurrentColorIndex())))

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
            local oldColorName = colors.getColorName(marked[key].colorIndex or 1)
            marked[key].colorIndex = state.getCurrentColorIndex()
            persistence.saveMarkers(state, bolt)

            bolt.saveconfig("marker_debug.txt", string.format(
                "Recolored tile RS (%d,%d,%d,%d,%d) from %s to %s",
                marked[key].floor or 0, marked[key].chunkX, marked[key].chunkZ,
                marked[key].localX, marked[key].localZ,
                oldColorName, colors.getColorName(state.getCurrentColorIndex())))
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
        if bolt then
            bolt.saveconfig("marker_debug.txt", string.format(
                "Removed world marker via grid at chunk (%d,%d) local (%d,%d)",
                chunkX, chunkZ, localX, localZ))
        end
        return true
    end

    local markerData = {
        x = worldX,
        z = worldZ,
        y = worldY or 0,
        colorIndex = colorIndex or state.getCurrentColorIndex(),
        chunkX = chunkX,
        chunkZ = chunkZ,
        localX = localX,
        localZ = localZ,
        floor = floor or 0
    }

    marked[key] = markerData
    persistence.saveMarkers(state, bolt)

    if bolt then
        bolt.saveconfig("marker_debug.txt", string.format(
            "Added world marker via grid at chunk (%d,%d) local (%d,%d)",
            chunkX, chunkZ, localX, localZ))
    end

    return true
end

return M
