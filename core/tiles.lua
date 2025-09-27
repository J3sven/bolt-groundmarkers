local M = {}
local persistence = require("data.persistence")

-- ADD this line for instance recognition
local instanceRecognition = require("core.instances")

local function count(tbl) local c=0 for _ in pairs(tbl) do c=c+1 end return c end

function M.toggleTileMarker(state, bolt)
    local coords = state.getCoords()
    local colors = state.getColors()
    local playerPos = bolt.playerposition()
    if not playerPos then return end
    
    local px, py, pz = playerPos:get()
    local tile2D = coords.worldToTile2D(px, pz)
    local key = coords.tileKey(tile2D.x, tile2D.z)
    local marked = state.getMarkedTiles()
    local tileX, tileZ = coords.worldToTileCoords(px, pz)
    local floor, chunkX, chunkZ, localX, localZ = coords.tileToRS(tileX, tileZ, py)
    
    -- ADD: Check if we're in an instance (safely)
    local inInstance = false
    local instanceId = nil
    local isRecognized = false
    
    local success = pcall(function()
        inInstance = instanceRecognition.isInInstance()
        instanceId = instanceRecognition.getCurrentInstanceId()
        isRecognized = instanceRecognition.isInstanceRecognized()
    end)

    -- ADD: Debug what instance recognition returns
    bolt.saveconfig("instance_flow_debug.txt", string.format(
        "Instance detection results:\n" ..
        "success: %s\n" ..
        "inInstance: %s\n" ..
        "instanceId: %s\n" ..
        "isRecognized: %s\n" ..
        "Current chunk: (%d, %d)",
        tostring(success), tostring(inInstance), tostring(instanceId), tostring(isRecognized),
        chunkX, chunkZ
    ))
    
    if not success then
        bolt.saveconfig("marker_debug.txt", "Instance recognition failed, treating as regular marker")
    end
    
    if marked[key] then
        local existing = marked[key]
        marked[key] = nil
        persistence.saveMarkers(state, bolt)
        
        -- ADD: Show instance info if available
        local instanceInfo = ""
        if existing.instanceId then
            instanceInfo = string.format(" [Instance: %s]", existing.instanceId)
        end
        
        bolt.saveconfig("marker_debug.txt", string.format(
            "Removed marker at RS (%d,%d,%d,%d,%d) [world: %.0f, %.0f] (total: %d)%s",
            existing.floor or 0, existing.chunkX, existing.chunkZ, existing.localX, existing.localZ,
            tile2D.x, tile2D.z, count(marked), instanceInfo))
    else
        
        -- REMOVE the old instance blocking code and REPLACE with instance-aware logic
        local markerData = {
            x = tile2D.x, z = tile2D.z, y = py,
            colorIndex = state.getCurrentColorIndex(),
            chunkX = chunkX, chunkZ = chunkZ,
            localX = localX, localZ = localZ,
            floor = floor
        }
        
        -- ADD: Add instance information if we're in an instance
        if inInstance and instanceId then
            markerData.instanceId = instanceId
            markerData.isRecognized = isRecognized
        end
        
        marked[key] = markerData
        persistence.saveMarkers(state, bolt)
        
        -- ADD: Show instance info in debug
        local instanceInfo = ""
        if inInstance then
            local recognitionStatus = isRecognized and "RECOGNIZED" or "NEW"
            instanceInfo = string.format(" [Instance: %s - %s]", instanceId or "unknown", recognitionStatus)
        end
        
        bolt.saveconfig("marker_debug.txt", string.format(
            "Added %s marker at RS (%d,%d,%d,%d,%d) [world: %.0f, %.0f] at Y=%.0f (total: %d)%s",
            colors.getColorName(state.getCurrentColorIndex()),
            floor, chunkX, chunkZ, localX, localZ,
            tile2D.x, tile2D.z, py, count(marked), instanceInfo))
    end
end

function M.recolorCurrentTile(state, bolt)
    local coords = state.getCoords()
    local colors = state.getColors()
    local playerPos = bolt.playerposition()
    if not playerPos then return false end
    
    local px, _, pz = playerPos:get()
    local tile2D = coords.worldToTile2D(px, pz)
    local key = coords.tileKey(tile2D.x, tile2D.z)
    local marked = state.getMarkedTiles()
    
    if marked[key] then
        local oldColorName = colors.getColorName(marked[key].colorIndex or 1)
        marked[key].colorIndex = state.getCurrentColorIndex()
        persistence.saveMarkers(state, bolt)
        
        -- ADD: Show instance info if available
        local instanceInfo = ""
        if marked[key].instanceId then
            instanceInfo = string.format(" [Instance: %s]", marked[key].instanceId)
        end
        
        bolt.saveconfig("marker_debug.txt", string.format(
            "Recolored tile RS (%d,%d,%d,%d,%d) from %s to %s%s",
            marked[key].floor or 0, marked[key].chunkX, marked[key].chunkZ,
            marked[key].localX, marked[key].localZ,
            oldColorName, colors.getColorName(state.getCurrentColorIndex()), instanceInfo))
        return true
    end
    return false
end

return M