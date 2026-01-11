local M = {}

local SAVE_FILE = "marked_tiles.json"

function M.loadMarkers(state, bolt)
    local saved = bolt.loadconfig(SAVE_FILE)
    local coords = state.getCoords()
    local markedTiles = {}
    
    if saved and saved ~= "" then
        local success, data = false, nil
        
        if bolt.json and bolt.json.decode then
            success, data = pcall(bolt.json.decode, saved)
        end
        
        if not success and bolt.loadjson then
            success, data = pcall(bolt.loadjson, SAVE_FILE)
        end
        
        if not success then
            success, data = pcall(function()
                local jsonData = {tiles = {}}
                local tilesMatch = saved:match('"tiles":%s*%[(.-)%]')
                if tilesMatch then
                    for tileStr in tilesMatch:gmatch('{.-}') do
                        local chunkX = tonumber(tileStr:match('"chunkX":%s*(%d+)'))
                        local chunkZ = tonumber(tileStr:match('"chunkZ":%s*(%d+)'))
                        local localX = tonumber(tileStr:match('"localX":%s*(%d+)'))
                        local localZ = tonumber(tileStr:match('"localZ":%s*(%d+)'))
                        local floor = tonumber(tileStr:match('"floor":%s*(%d+)'))
                        local worldY = tonumber(tileStr:match('"worldY":%s*([%d%.]+)'))
                        local colorIndex = tonumber(tileStr:match('"colorIndex":%s*(%d+)')) or 1
                        local label = tileStr:match('"label":%s*"([^"]*)"')
                        
                        if chunkX and chunkZ and localX and localZ and worldY then
                            table.insert(jsonData.tiles, {
                                chunkX = chunkX,
                                chunkZ = chunkZ,
                                localX = localX,
                                localZ = localZ,
                                floor = floor or 0,
                                worldY = worldY,
                                colorIndex = colorIndex,
                                label = label
                            })
                        end
                    end
                end
                return jsonData
            end)
        end
        
        if success and data and type(data) == "table" and data.tiles then
            for _, tileData in ipairs(data.tiles) do
                local chunkX = tonumber(tileData.chunkX)
                local chunkZ = tonumber(tileData.chunkZ)
                local localX = tonumber(tileData.localX)
                local localZ = tonumber(tileData.localZ)
                local floor = tonumber(tileData.floor) or 0
                local worldY = tonumber(tileData.worldY)
                local colorIndex = tonumber(tileData.colorIndex) or 1
                local label = nil
                if type(tileData.label) == "string" and tileData.label ~= "" then
                    label = tileData.label
                end
                
                if chunkX and chunkZ and localX and localZ and worldY then
                    -- Convert RS coordinates to world coordinates for the key
                    local tileX, tileZ = coords.rsToTileCoords(floor, chunkX, chunkZ, localX, localZ)
                    local worldX, worldZ = coords.tileToWorldCoords(tileX, tileZ)
                    local key = coords.tileKey(worldX, worldZ)
                    
                    markedTiles[key] = {
                        x = worldX, z = worldZ, y = worldY,
                        colorIndex = colorIndex,
                        chunkX = chunkX, chunkZ = chunkZ,
                        localX = localX, localZ = localZ,
                        floor = floor,
                        label = label
                    }
                end
            end
        end
    end
    
    state.setMarkedTiles(markedTiles)
    
end

function M.saveMarkers(state, bolt)
    local markedTiles = state.getMarkedTiles()
    local tiles = {}
    local count = 0
    
    for _, tile in pairs(markedTiles or {}) do
        local tileData = {
            chunkX = tile.chunkX,
            chunkZ = tile.chunkZ,
            localX = tile.localX,
            localZ = tile.localZ,
            floor = tile.floor,
            worldY = tile.y,
            colorIndex = tile.colorIndex or 1
        }

        if tile.label and tile.label ~= "" then
            tileData.label = tile.label
        end
        
        if tile.instanceId then
            tileData.instanceId = tile.instanceId
            tileData.isRecognized = tile.isRecognized or false
        end
        
        table.insert(tiles, tileData)
        count = count + 1
    end
    
    local jsonData = {
        version = 1,
        totalTiles = count,
        tiles = tiles
    }
    
    local success, jsonString = false, nil
    
    if bolt.json and bolt.json.encode then
        success, jsonString = pcall(bolt.json.encode, jsonData)
    elseif bolt.savejson then
        success = pcall(bolt.savejson, SAVE_FILE, jsonData)
        return
    else
        local jsonLines = {'{'}
        table.insert(jsonLines, '  "version": 1,')
        table.insert(jsonLines, '  "totalTiles": ' .. count .. ',')
        table.insert(jsonLines, '  "tiles": [')
        
        for i, tile in ipairs(tiles) do
            local comma = i < #tiles and ',' or ''
            local instanceFields = ""
            if tile.instanceId then
                instanceFields = string.format(', "instanceId": "%s", "isRecognized": %s', 
                    tile.instanceId, tostring(tile.isRecognized or false))
            end
            local labelField = ""
            if tile.label then
                local escaped = tile.label:gsub("\\", "\\\\"):gsub('"', '\\"')
                labelField = string.format(', "label": "%s"', escaped)
            end

            table.insert(jsonLines, string.format('    {"chunkX": %d, "chunkZ": %d, "localX": %d, "localZ": %d, "floor": %d, "worldY": %.0f, "colorIndex": %d%s%s}%s',
                tile.chunkX, tile.chunkZ, tile.localX, tile.localZ, tile.floor, tile.worldY, tile.colorIndex, labelField, instanceFields, comma))
        end
        
        table.insert(jsonLines, '  ]')
        table.insert(jsonLines, '}')
        jsonString = table.concat(jsonLines, '\n')
        success = true
    end
    
    if success and jsonString then
        bolt.saveconfig(SAVE_FILE, jsonString)
    end
end

return M
