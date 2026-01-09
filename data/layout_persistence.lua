-- data/layout_persistence.lua - Persistence for instance tile layouts
local M = {}

local simplejson = require("core.simplejson")

local LAYOUTS_FILE = "instance_layouts.json"

local function sanitizeDisplayName(name, fallback)
    if type(name) ~= "string" then
        name = fallback
    end
    if type(name) ~= "string" then
        return nil
    end
    local trimmed = (name:match("^%s*(.-)%s*$") or ""):gsub("[%c]", "")
    if trimmed == "" then
        return nil
    end
    if #trimmed > 80 then
        trimmed = trimmed:sub(1, 80)
    end
    return trimmed
end

local function sanitizeStoredName(name, fallback)
    local pretty = sanitizeDisplayName(name, fallback) or "Layout"
    local cleaned = pretty:gsub("[^%w%s%-_]", "")
    cleaned = cleaned:gsub("%s+", " ")
    if cleaned == "" then
        cleaned = "Layout"
    end
    if #cleaned > 60 then
        cleaned = cleaned:sub(1, 60)
    end
    return cleaned
end

local function normalizeTile(tile)
    local localX = tonumber(tile.localX)
    local localZ = tonumber(tile.localZ)
    if not localX or not localZ then
        return nil
    end
    localX = math.floor(localX + 0.5)
    localZ = math.floor(localZ + 0.5)
    if localX < 0 or localX > 63 or localZ < 0 or localZ > 63 then
        return nil
    end

    local worldY = tonumber(tile.worldY) or 0
    local colorIndex = tonumber(tile.colorIndex) or 1
    colorIndex = math.floor(colorIndex + 0.5)
    if colorIndex < 1 then
        colorIndex = 1
    end

    return {
        localX = localX,
        localZ = localZ,
        worldY = worldY,
        colorIndex = colorIndex
    }
end

local function normalizeLayoutEntry(layout, fallbackIndex)
    if type(layout) ~= "table" then
        return nil
    end

    layout.id = layout.id or ("layout_" .. tostring(fallbackIndex or 0))
    layout.name = sanitizeStoredName(layout.name, layout.displayName or layout.id)
    layout.displayName = sanitizeDisplayName(layout.displayName, layout.name) or layout.name
    layout.created = tonumber(layout.created) or fallbackIndex or 0

    local normalizedTiles = {}
    if type(layout.tiles) == "table" then
        for _, tile in ipairs(layout.tiles) do
            local normalized = normalizeTile(tile)
            if normalized then
                table.insert(normalizedTiles, normalized)
            end
        end
    end
    layout.tiles = normalizedTiles

    return layout
end

local function decodeLayoutsJSON(jsonStr)
    jsonStr = jsonStr:gsub("%s+", "")
    local version = jsonStr:match('"version":(%d+)')
    local layoutsStr = jsonStr:match('"layouts":%[(.*)%]')
    if not layoutsStr then
        return { version = tonumber(version) or 1, layouts = {} }
    end

    local layouts = {}
    for layoutStr in layoutsStr:gmatch('%b{}') do
        local layout = {}
        layout.id = layoutStr:match('"id":"([^"]*)"')
        layout.name = layoutStr:match('"name":"([^"]*)"')
        layout.displayName = layoutStr:match('"displayName":"([^"]*)"')
        layout.created = tonumber(layoutStr:match('"created":(%d+)'))

        if layout.id and layout.name then
            local tilesStr = layoutStr:match('"tiles":%[(.-)%]')
            layout.tiles = {}
            if tilesStr then
                for tileStr in tilesStr:gmatch('%b{}') do
                    local tile = {}
                    tile.localX = tonumber(tileStr:match('"localX":(%-?%d+)'))
                    tile.localZ = tonumber(tileStr:match('"localZ":(%-?%d+)'))
                    tile.worldY = tonumber(tileStr:match('"worldY":(%-?%d+%.?%d*)'))
                    tile.colorIndex = tonumber(tileStr:match('"colorIndex":(%d+)'))
                    table.insert(layout.tiles, tile)
                end
            end
            table.insert(layouts, layout)
        end
    end

    return { version = tonumber(version) or 1, layouts = layouts }
end

-- Load all saved layouts
function M.loadLayouts(bolt)
    local saved = bolt.loadconfig(LAYOUTS_FILE)
    if not saved or saved == "" then
        return { version = 1, layouts = {} }
    end

    if bolt.json and bolt.json.decode then
        local ok, data = pcall(bolt.json.decode, saved)
        if ok and type(data) == "table" then
            local normalized = {}
            if type(data.layouts) == "table" then
                for index, layout in ipairs(data.layouts) do
                    local entry = normalizeLayoutEntry(layout, index)
                    if entry then
                        table.insert(normalized, entry)
                    end
                end
            end
            data.layouts = normalized
            return data
        end
    end

    local decoded = simplejson.decode(saved)
    if decoded and type(decoded) == "table" then
        local normalized = {}
        if type(decoded.layouts) == "table" then
            for index, layout in ipairs(decoded.layouts) do
                local entry = normalizeLayoutEntry(layout, index)
                if entry then
                    table.insert(normalized, entry)
                end
            end
        end
        decoded.layouts = normalized
        return decoded
    end

    local success, fallback = pcall(decodeLayoutsJSON, saved)
    if success and type(fallback) == "table" then
        local normalized = {}
        if type(fallback.layouts) == "table" then
            for index, layout in ipairs(fallback.layouts) do
                local entry = normalizeLayoutEntry(layout, index)
                if entry then
                    table.insert(normalized, entry)
                end
            end
        end
        fallback.layouts = normalized
        return fallback
    end

    return { version = 1, layouts = {} }
end

-- Save all layouts
function M.saveLayouts(bolt, layoutsData)
    layoutsData.version = layoutsData.version or 1
    layoutsData.layouts = layoutsData.layouts or {}

    if bolt.json and bolt.json.encode then
        local ok, encoded = pcall(bolt.json.encode, layoutsData)
        if ok and encoded then
            bolt.saveconfig(LAYOUTS_FILE, encoded)
            return true
        end
    end

    local encoded = simplejson.encode(layoutsData)
    if encoded then
        bolt.saveconfig(LAYOUTS_FILE, encoded)
        return true
    end

    return false
end

-- Create a new layout from current instance tiles
function M.createLayout(bolt, name, instanceTiles)
    local layoutsData = M.loadLayouts(bolt)

    local id = "layout_" .. (#layoutsData.layouts + 1) .. "_" .. math.random(1000, 9999)

    local tiles = {}
    for _, tile in pairs(instanceTiles) do
        local normalized = normalizeTile(tile)
        if normalized then
            normalized.worldY = tile.y or normalized.worldY
            table.insert(tiles, normalized)
        end
    end

    local layout = {
        id = id,
        name = sanitizeStoredName(name, id),
        displayName = sanitizeDisplayName(name, id) or sanitizeStoredName(name, id),
        created = #layoutsData.layouts + 1,
        tiles = tiles
    }

    layout = normalizeLayoutEntry(layout, #layoutsData.layouts + 1)
    table.insert(layoutsData.layouts, layout)
    M.saveLayouts(bolt, layoutsData)

    return id
end

-- Delete a layout by ID
function M.deleteLayout(bolt, layoutId)
    local layoutsData = M.loadLayouts(bolt)

    for i, layout in ipairs(layoutsData.layouts) do
        if layout.id == layoutId then
            table.remove(layoutsData.layouts, i)
            M.saveLayouts(bolt, layoutsData)

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
    return layoutsData.layouts or {}
end

-- Rename a layout
function M.renameLayout(bolt, layoutId, newName)
    local layoutsData = M.loadLayouts(bolt)

    for _, layout in ipairs(layoutsData.layouts) do
        if layout.id == layoutId then
            layout.name = sanitizeStoredName(newName, layout.name)
            layout.displayName = sanitizeDisplayName(newName, layout.displayName) or layout.name
            M.saveLayouts(bolt, layoutsData)
            return true
        end
    end

    return false
end

local function convertImportedTiles(tileList)
    local normalized = {}
    if type(tileList) ~= "table" then
        return normalized
    end

    for _, tile in ipairs(tileList) do
        local prepared = normalizeTile(tile)
        if prepared then
            prepared.worldY = tonumber(tile.worldY) or prepared.worldY
            table.insert(normalized, prepared)
        end
    end

    return normalized
end

function M.importLayoutFromData(bolt, layoutData)
    if type(layoutData) ~= "table" then
        return false, "Invalid layout data."
    end

    local layoutsData = M.loadLayouts(bolt)
    local tiles = convertImportedTiles(layoutData.tiles or {})
    if #tiles == 0 then
        return false, "No valid tiles found."
    end

    local id = "import_" .. (#layoutsData.layouts + 1) .. "_" .. math.random(1000, 9999)
    local displayName = sanitizeDisplayName(layoutData.displayName, layoutData.name) or ("Imported Layout " .. tostring(#layoutsData.layouts + 1))
    local storageName = sanitizeStoredName(layoutData.name, displayName)

    local layout = {
        id = id,
        name = storageName,
        displayName = displayName,
        created = #layoutsData.layouts + 1,
        tiles = tiles
    }

    layout = normalizeLayoutEntry(layout, #layoutsData.layouts + 1)
    table.insert(layoutsData.layouts, layout)
    local saved = M.saveLayouts(bolt, layoutsData)

    if not saved then
        return false, "Failed to save imported layout."
    end

    return true, layout
end

return M
