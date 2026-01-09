-- data/layout_persistence.lua - Persistence for instance tile layouts
local M = {}

local LAYOUTS_FILE = "instance_layouts.json"

-- Simple JSON decoder for our specific format
local function decodeLayoutsJSON(jsonStr)
    -- Remove whitespace for easier parsing
    jsonStr = jsonStr:gsub("%s+", "")

    -- Extract version
    local version = jsonStr:match('"version":(%d+)')

    -- Find the layouts array - use greedy match
    local layoutsStr = jsonStr:match('"layouts":%[(.*)%]')
    if not layoutsStr then
        return {version = tonumber(version) or 1, layouts = {}}
    end

    local layouts = {}
    local layoutCount = 0
    local skippedCount = 0

    -- Parse each layout object
    for layoutStr in layoutsStr:gmatch('%b{}') do
        layoutCount = layoutCount + 1
        local layout = {}

        -- Extract layout fields (allow empty strings with [^"]*)
        layout.id = layoutStr:match('"id":"([^"]*)"')
        layout.name = layoutStr:match('"name":"([^"]*)"')
        layout.created = tonumber(layoutStr:match('"created":(%d+)'))

        -- Skip layouts with empty id or name
        if not layout.id or layout.id == "" or not layout.name or layout.name == "" then
            skippedCount = skippedCount + 1
        else
            -- Extract tiles array
            local tilesStr = layoutStr:match('"tiles":%[(.-)%]')
            layout.tiles = {}

            if tilesStr then
                for tileStr in tilesStr:gmatch('%b{}') do
                    local tile = {}
                    tile.localX = tonumber(tileStr:match('"localX":(%d+)'))
                    tile.localZ = tonumber(tileStr:match('"localZ":(%d+)'))
                    tile.worldY = tonumber(tileStr:match('"worldY":(%-?%d+%.?%d*)'))
                    tile.colorIndex = tonumber(tileStr:match('"colorIndex":(%d+)'))
                    table.insert(layout.tiles, tile)
                end
            end

            table.insert(layouts, layout)
        end
    end

    -- Debug info
    if layoutCount > 0 then
        local debugMsg = string.format("Parsed %d layouts, skipped %d empty, kept %d",
            layoutCount, skippedCount, #layouts)
        if layouts[1] then
            debugMsg = debugMsg .. string.format(" - First: id=%s name=%s",
                tostring(layouts[1].id), tostring(layouts[1].name))
        end
        -- We can't use bolt here, so just return the data
    end

    return {version = tonumber(version) or 1, layouts = layouts}
end

-- Load all saved layouts
function M.loadLayouts(bolt)
    local saved = bolt.loadconfig(LAYOUTS_FILE)

    if not saved or saved == "" then
        return {
            version = 1,
            layouts = {}
        }
    end

    -- Use our custom JSON decoder
    local success, data = pcall(decodeLayoutsJSON, saved)

    if success and data and type(data) == "table" then
        local layoutCount = data.layouts and #data.layouts or 0
        bolt.saveconfig("layout_load_debug.txt", string.format(
            "loadLayouts: successfully parsed %d layouts", layoutCount
        ))
        return data
    else
        bolt.saveconfig("layout_load_debug.txt", string.format(
            "loadLayouts: parse failed. success=%s type=%s",
            tostring(success), type(data)
        ))
        return {
            version = 1,
            layouts = {}
        }
    end
end

-- Save all layouts
function M.saveLayouts(bolt, layoutsData)
    -- Always use manual JSON encoding (bolt.json APIs don't exist)
    local jsonLines = {'{'}
    table.insert(jsonLines, '  "version": ' .. (layoutsData.version or 1) .. ',')
    table.insert(jsonLines, '  "layouts": [')

    local layouts = layoutsData.layouts or {}
    for i, layout in ipairs(layouts) do
        local comma = i < #layouts and ',' or ''
        table.insert(jsonLines, '    {')
        table.insert(jsonLines, '      "id": "' .. (layout.id or '') .. '",')
        table.insert(jsonLines, '      "name": "' .. (layout.name or '') .. '",')
        table.insert(jsonLines, '      "created": ' .. (layout.created or 0) .. ',')
        table.insert(jsonLines, '      "tiles": [')

        local tiles = layout.tiles or {}
        for j, tile in ipairs(tiles) do
            local tileComma = j < #tiles and ',' or ''
            table.insert(jsonLines, string.format(
                '        {"localX": %d, "localZ": %d, "worldY": %.0f, "colorIndex": %d}%s',
                tile.localX, tile.localZ, tile.worldY, tile.colorIndex, tileComma
            ))
        end

        table.insert(jsonLines, '      ]')
        table.insert(jsonLines, '    }' .. comma)
    end

    table.insert(jsonLines, '  ]')
    table.insert(jsonLines, '}')

    local jsonString = table.concat(jsonLines, '\n')
    bolt.saveconfig(LAYOUTS_FILE, jsonString)

    bolt.saveconfig("layout_save_debug.txt", string.format(
        "Saved %d layouts to file", #layouts
    ))

    return true
end

-- Create a new layout from current instance tiles
function M.createLayout(bolt, name, instanceTiles)
    local layoutsData = M.loadLayouts(bolt)

    -- Generate unique ID using layout count and random number
    local id = "layout_" .. (#layoutsData.layouts + 1) .. "_" .. math.random(1000, 9999)

    -- Extract tile data (only store local coordinates, worldY, and color)
    local tiles = {}
    for _, tile in pairs(instanceTiles) do
        table.insert(tiles, {
            localX = tile.localX,
            localZ = tile.localZ,
            worldY = tile.y,
            colorIndex = tile.colorIndex or 1
        })
    end

    -- Create layout object (without timestamp since os.time isn't available)
    local layout = {
        id = id,
        name = name,
        created = #layoutsData.layouts + 1,  -- Use layout count as a simple timestamp
        tiles = tiles
    }

    table.insert(layoutsData.layouts, layout)
    M.saveLayouts(bolt, layoutsData)

    bolt.saveconfig("instance_debug.txt", string.format(
        "Created layout '%s' with %d tiles", name, #tiles
    ))

    return id
end

-- Delete a layout by ID
function M.deleteLayout(bolt, layoutId)
    local layoutsData = M.loadLayouts(bolt)

    for i, layout in ipairs(layoutsData.layouts) do
        if layout.id == layoutId then
            table.remove(layoutsData.layouts, i)
            M.saveLayouts(bolt, layoutsData)

            bolt.saveconfig("instance_debug.txt", string.format(
                "Deleted layout '%s'", layout.name or layoutId
            ))

            return true
        end
    end

    return false
end

-- Get a specific layout by ID
function M.getLayout(bolt, layoutId)
    local layoutsData = M.loadLayouts(bolt)

    for _, layout in ipairs(layoutsData.layouts) do
        if layout.id == layoutId then
            return layout
        end
    end

    return nil
end

-- Get all layouts
function M.getAllLayouts(bolt)
    local layoutsData = M.loadLayouts(bolt)
    local layouts = layoutsData.layouts or {}

    bolt.saveconfig("instance_debug.txt", string.format(
        "getAllLayouts: returning %d layouts", #layouts
    ))

    return layouts
end

-- Rename a layout
function M.renameLayout(bolt, layoutId, newName)
    local layoutsData = M.loadLayouts(bolt)

    for _, layout in ipairs(layoutsData.layouts) do
        if layout.id == layoutId then
            layout.name = newName
            M.saveLayouts(bolt, layoutsData)
            return true
        end
    end

    return false
end

return M
