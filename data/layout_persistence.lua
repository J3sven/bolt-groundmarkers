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

local LABEL_MAX_LEN = 18

local function sanitizeTileLabel(label)
    if type(label) ~= "string" then
        return nil
    end
    local cleaned = label:gsub("[%c]", " "):gsub("%s+", " ")
    cleaned = cleaned:match("^%s*(.-)%s*$") or ""
    if cleaned == "" then
        return nil
    end
    if #cleaned > LABEL_MAX_LEN then
        cleaned = cleaned:sub(1, LABEL_MAX_LEN)
    end
    return cleaned
end

local function tileAbsFromChunkLocal(tile)
    if tile and tile.chunkX ~= nil and tile.chunkZ ~= nil and tile.localX ~= nil and tile.localZ ~= nil then
        local cx = tonumber(tile.chunkX)
        local cz = tonumber(tile.chunkZ)
        local lx = tonumber(tile.localX)
        local lz = tonumber(tile.localZ)
        if cx and cz and lx and lz then
            return cx * 64 + lx, cz * 64 + lz
        end
    end
    return nil, nil
end

local function tileAbsFromLocal(tile)
    if tile and tile.localX ~= nil and tile.localZ ~= nil then
        local lx = tonumber(tile.localX)
        local lz = tonumber(tile.localZ)
        if lx and lz then
            return lx, lz
        end
    end
    return nil, nil
end

local function isInstanceChunkCoord(tile)
    if not tile or tile.chunkX == nil then
        return false
    end
    local cx = tonumber(tile.chunkX)
    if not cx then
        return false
    end
    return math.abs(cx) > 100
end

local function detectLayoutType(layout)
    -- Prefer explicit type if present.
    if layout.layoutType == "instance" or layout.layoutType == "chunk" then
        return layout.layoutType
    end

    local hasInstanceChunkCoords = false
    local hasNormalChunkCoords = false

    if type(layout.tiles) == "table" and #layout.tiles > 0 then
        for _, tile in ipairs(layout.tiles) do
            if tile.chunkX and tile.chunkZ then
                local cx = math.abs(tonumber(tile.chunkX) or 0)
                -- Instance range heuristic
                if cx > 100 then
                    hasInstanceChunkCoords = true
                    break
                elseif cx > 10 then
                    hasNormalChunkCoords = true
                    break
                end
            end
        end
    end

    return hasInstanceChunkCoords and "instance" or (hasNormalChunkCoords and "chunk" or "instance")
end

local function computeIs2x2FromRelative(tiles)
    if type(tiles) ~= "table" then
        return false
    end
    for _, tile in ipairs(tiles) do
        if tile.relativeX ~= nil and tile.relativeZ ~= nil then
            local rx = math.abs(tonumber(tile.relativeX) or 0)
            local rz = math.abs(tonumber(tile.relativeZ) or 0)
            if rx >= 64 or rz >= 64 then
                return true
            end
        end
    end
    return false
end

-- ----------------------------
-- Normalization / Migration
-- ----------------------------
local function normalizeTile(tile, layoutType)
    -- Instance layouts: we WANT relativeX/relativeZ.
    -- Chunk layouts: we WANT chunkX/chunkZ + localX/localZ.
    -- Legacy instance tiles may only have localX/localZ or may have absolute chunk coords.
    if type(tile) ~= "table" then
        return nil
    end

    local worldY = tonumber(tile.worldY) or tonumber(tile.y) or 0
    local colorIndex = tonumber(tile.colorIndex) or 1
    colorIndex = math.floor(colorIndex + 0.5)
    if colorIndex < 1 then
        colorIndex = 1
    end

    local normalized = {
        worldY = worldY,
        colorIndex = colorIndex
    }

    local label = sanitizeTileLabel(tile.label)
    if label then
        normalized.label = label
    end

    layoutType = layoutType or (isInstanceChunkCoord(tile) and "instance" or (tile.chunkX and tile.chunkZ and "chunk" or "instance"))

    if layoutType == "chunk" then
        -- Require chunkX/chunkZ + localX/localZ
        if tile.chunkX == nil or tile.chunkZ == nil or tile.localX == nil or tile.localZ == nil then
            return nil
        end
        local cx = tonumber(tile.chunkX)
        local cz = tonumber(tile.chunkZ)
        local lx = tonumber(tile.localX)
        local lz = tonumber(tile.localZ)
        if not (cx and cz and lx and lz) then
            return nil
        end

        normalized.chunkX = cx
        normalized.chunkZ = cz
        normalized.localX = math.floor(lx + 0.5)
        normalized.localZ = math.floor(lz + 0.5)
        return normalized
    end

    -- layoutType == "instance"
    -- Prefer relative coords if present; otherwise keep legacy locals for now (we'll migrate in normalizeLayoutEntry).
    if tile.relativeX ~= nil and tile.relativeZ ~= nil then
        normalized.relativeX = math.floor((tonumber(tile.relativeX) or 0) + 0.5)
        normalized.relativeZ = math.floor((tonumber(tile.relativeZ) or 0) + 0.5)
        return normalized
    end

    -- Legacy: accept local coords (0..63) OR absolute chunk coords (instance range) for migration.
    if tile.localX ~= nil and tile.localZ ~= nil then
        local lx = tonumber(tile.localX)
        local lz = tonumber(tile.localZ)
        if not (lx and lz) then
            return nil
        end
        lx = math.floor(lx + 0.5)
        lz = math.floor(lz + 0.5)
        -- For instance legacy locals, constrain.
        if tile.chunkX == nil and (lx < 0 or lx > 63 or lz < 0 or lz > 63) then
            return nil
        end
        normalized.localX = lx
        normalized.localZ = lz
        -- If absolute chunk coords are present, preserve them for migration.
        if tile.chunkX ~= nil and tile.chunkZ ~= nil then
            normalized.chunkX = tonumber(tile.chunkX)
            normalized.chunkZ = tonumber(tile.chunkZ)
        end
        return normalized
    end

    return nil
end
-- -----------------------------------------
-- Migration helpers (MUST be above normalizeLayoutEntry)
-- -----------------------------------------

local function normalizeLayoutEntry(layout, fallbackIndex, bolt)
    if type(layout) ~= "table" then
        return nil
    end

    layout.id = layout.id or ("layout_" .. tostring(fallbackIndex or 0))
    layout.name = sanitizeStoredName(layout.name, layout.displayName or layout.id)
    layout.displayName = sanitizeDisplayName(layout.displayName, layout.name) or layout.name
    layout.created = tonumber(layout.created) or fallbackIndex or 0

    layout.layoutType = detectLayoutType(layout)

    local normalizedTiles = {}
    if type(layout.tiles) == "table" then
        for _, tile in ipairs(layout.tiles) do
            local normalized = normalizeTile(tile, layout.layoutType)
            if normalized then
                table.insert(normalizedTiles, normalized)
            end
        end
    end

    layout.tiles = normalizedTiles

    -- Auto-detect is2x2 for instance layouts.
    if layout.layoutType == "instance" then
        if layout.is2x2 == nil then
            layout.is2x2 = computeIs2x2FromRelative(layout.tiles)
        end
    else
        layout.is2x2 = nil
    end

    return layout
end

-- Very simple fallback decoder for broken JSON environments.
-- Updated to also read relative coords and chunk coords if present.
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
        layout.layoutType = layoutStr:match('"layoutType":"([^"]*)"')
        local is2x2 = layoutStr:match('"is2x2":(true)') and true or (layoutStr:match('"is2x2":(false)') and false or nil)
        layout.is2x2 = is2x2

        if layout.id and layout.name then
            local tilesStr = layoutStr:match('"tiles":%[(.-)%]')
            layout.tiles = {}
            if tilesStr then
                for tileStr in tilesStr:gmatch('%b{}') do
                    local tile = {}
                    tile.localX = tonumber(tileStr:match('"localX":(%-?%d+)'))
                    tile.localZ = tonumber(tileStr:match('"localZ":(%-?%d+)'))
                    tile.chunkX = tonumber(tileStr:match('"chunkX":(%-?%d+)'))
                    tile.chunkZ = tonumber(tileStr:match('"chunkZ":(%-?%d+)'))
                    tile.relativeX = tonumber(tileStr:match('"relativeX":(%-?%d+)'))
                    tile.relativeZ = tonumber(tileStr:match('"relativeZ":(%-?%d+)'))
                    tile.worldY = tonumber(tileStr:match('"worldY":(%-?%d+%.?%d*)'))
                    tile.colorIndex = tonumber(tileStr:match('"colorIndex":(%d+)'))
                    local label = tileStr:match('"label":"([^"]*)"')
                    if label and label ~= "" then
                        tile.label = label
                    end
                    table.insert(layout.tiles, tile)
                end
            end
            table.insert(layouts, layout)
        end
    end

    return { version = tonumber(version) or 1, layouts = layouts }
end

-- ----------------------------
-- Public API
-- ----------------------------

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
                    local entry = normalizeLayoutEntry(layout, index, bolt)
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
                local entry = normalizeLayoutEntry(layout, index, bolt)
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
                local entry = normalizeLayoutEntry(layout, index, bolt)
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

function M.saveLayouts(bolt, layoutsData)
    layoutsData.version = layoutsData.version or 1
    layoutsData.layouts = layoutsData.layouts or {}

    for i, layout in ipairs(layoutsData.layouts) do
        if layout.linkedEntrance then
        end
    end

    if bolt.json and bolt.json.encode then
        local ok, encoded = pcall(bolt.json.encode, layoutsData)
        if ok and encoded then
            bolt.saveconfig(LAYOUTS_FILE, encoded)
            return true
        else
        end
    end

    local encoded = simplejson.encode(layoutsData)
    if encoded then
        bolt.saveconfig(LAYOUTS_FILE, encoded)
        return true
    end

    return false
end

-- Create a new layout
-- layoutType should be "instance" or "chunk"
function M.createLayout(bolt, name, instanceTiles, layoutType)
    local layoutsData = M.loadLayouts(bolt)

    local id = "layout_" .. (#layoutsData.layouts + 1) .. "_" .. math.random(1000, 9999)
    local resolvedType = layoutType or "instance"

    -- For instance layouts: convert absolute instance coords (chunk/local) to relative coords.
    local instanceManager = nil
    local entryAbsX, entryAbsZ = nil, nil
    if resolvedType == "instance" then
        instanceManager = require("core.instance_manager")
        local entryChunkX, entryChunkZ, entryLocalX, entryLocalZ = instanceManager.getEntryTile()
        if entryChunkX and entryChunkZ and entryLocalX and entryLocalZ then
            entryAbsX = entryChunkX * 64 + entryLocalX
            entryAbsZ = entryChunkZ * 64 + entryLocalZ
        end
    end

    local tiles = {}
    for _, tile in pairs(instanceTiles or {}) do
        local t = tile

        if resolvedType == "instance" then
            -- Prefer precomputed relative coords.
            if t.relativeX == nil or t.relativeZ == nil then
                -- If absolute chunk/local given, convert using entry.
                if entryAbsX and entryAbsZ then
                    local absX, absZ = tileAbsFromChunkLocal(t)
                    if absX and absZ then
                        t = {
                            relativeX = absX - entryAbsX,
                            relativeZ = absZ - entryAbsZ,
                            worldY = t.worldY or t.y,
                            colorIndex = t.colorIndex,
                            label = t.label
                        }
                    elseif t.localX ~= nil and t.localZ ~= nil then
                        -- Legacy: local coords relative to entry chunk locals (1x1 only).
                        local lx = tonumber(t.localX)
                        local lz = tonumber(t.localZ)
                        if lx and lz then
                            t = {
                                relativeX = math.floor(lx + 0.5) - (instanceManager.getEntryTile() and select(3, instanceManager.getEntryTile()) or 0),
                                relativeZ = math.floor(lz + 0.5) - (instanceManager.getEntryTile() and select(4, instanceManager.getEntryTile()) or 0),
                                worldY = t.worldY or t.y,
                                colorIndex = t.colorIndex,
                                label = t.label
                            }
                        end
                    end
                end
            end
        end

        local normalized = normalizeTile(t, resolvedType)
        if normalized then
            normalized.worldY = tonumber(tile.worldY) or tonumber(tile.y) or normalized.worldY
            if tile.label and not normalized.label then
                normalized.label = sanitizeTileLabel(tile.label)
            end
            table.insert(tiles, normalized)
        end
    end

    -- Detect if instance layout should be 2x2
    local is2x2 = false
    if resolvedType == "instance" then
        is2x2 = computeIs2x2FromRelative(tiles)
    end

    local layout = {
        id = id,
        name = sanitizeStoredName(name, id),
        displayName = sanitizeDisplayName(name, id) or sanitizeStoredName(name, id),
        created = #layoutsData.layouts + 1,
        layoutType = resolvedType,
        is2x2 = (resolvedType == "instance") and is2x2 or nil,
        tiles = tiles
    }

    table.insert(layoutsData.layouts, layout)
    M.saveLayouts(bolt, layoutsData)

    return id
end

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

function M.getLayout(bolt, layoutId)
    local layoutsData = M.loadLayouts(bolt)
    for _, layout in ipairs(layoutsData.layouts) do
        if layout.id == layoutId then
            return layout
        end
    end
    return nil
end

function M.getAllLayouts(bolt)
    local layoutsData = M.loadLayouts(bolt)
    return layoutsData.layouts or {}
end

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
        -- layoutType unknown here; normalizeLayoutEntry will re-detect and migrate if needed.
        local prepared = normalizeTile(tile, nil)
        if prepared then
            prepared.worldY = tonumber(tile.worldY) or prepared.worldY
            if tile.label and not prepared.label then
                prepared.label = sanitizeTileLabel(tile.label)
            end
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
    local displayName = sanitizeDisplayName(layoutData.displayName, layoutData.name)
        or ("Imported Layout " .. tostring(#layoutsData.layouts + 1))
    local storageName = sanitizeStoredName(layoutData.name, displayName)

    local layout = {
        id = id,
        name = storageName,
        displayName = displayName,
        created = #layoutsData.layouts + 1,
        layoutType = layoutData.layoutType, -- may be nil; normalize will detect
        is2x2 = layoutData.is2x2,
        tiles = tiles
    }

    layout = normalizeLayoutEntry(layout, #layoutsData.layouts + 1, bolt)
    table.insert(layoutsData.layouts, layout)
    local saved = M.saveLayouts(bolt, layoutsData)

    if not saved then
        return false, "Failed to save imported layout."
    end

    return true, layout
end

function M.getChunkLayouts(bolt)
    local allLayouts = M.getAllLayouts(bolt)
    local chunkLayouts = {}
    for _, layout in ipairs(allLayouts) do
        if layout.layoutType == "chunk" then
            table.insert(chunkLayouts, layout)
        end
    end
    return chunkLayouts
end

-- Toggle add/remove tile in a layout.
-- IMPORTANT FIX: instance layouts key on relativeX/relativeZ (NOT localX/localZ).
function M.updateLayoutTile(bolt, layoutId, tileData)
    local layoutsData = M.loadLayouts(bolt)

    for _, layout in ipairs(layoutsData.layouts) do
        if layout.id == layoutId then
            local tiles = layout.tiles or {}
            local key

            if layout.layoutType == "chunk" then
                key = string.format("%d_%d_%d_%d",
                    tileData.chunkX or 0,
                    tileData.chunkZ or 0,
                    tileData.localX or 0,
                    tileData.localZ or 0
                )
            else
                key = string.format("%d_%d",
                    tileData.relativeX or 0,
                    tileData.relativeZ or 0
                )
            end

            local existingIndex = nil
            for i, tile in ipairs(tiles) do
                local tileKey
                if layout.layoutType == "chunk" then
                    tileKey = string.format("%d_%d_%d_%d",
                        tile.chunkX or 0,
                        tile.chunkZ or 0,
                        tile.localX or 0,
                        tile.localZ or 0
                    )
                else
                    tileKey = string.format("%d_%d",
                        tile.relativeX or 0,
                        tile.relativeZ or 0
                    )
                end

                if tileKey == key then
                    existingIndex = i
                    break
                end
            end

            if existingIndex then
                table.remove(tiles, existingIndex)
            else
                local newTile = normalizeTile(tileData, layout.layoutType)
                if newTile then
                    table.insert(tiles, newTile)
                end
            end

            layout.tiles = tiles
            M.saveLayouts(bolt, layoutsData)
            return true
        end
    end

    return false
end

-- Update a tile's label.
-- IMPORTANT FIX: instance layouts match by relativeX/relativeZ.
function M.updateLayoutTileLabel(bolt, layoutId, localX, localZ, chunkX, chunkZ, label)
    local layoutsData = M.loadLayouts(bolt)

    for _, layout in ipairs(layoutsData.layouts) do
        if layout.id == layoutId then
            local tiles = layout.tiles or {}

            for _, tile in ipairs(tiles) do
                local match = false
                if layout.layoutType == "chunk" then
                    match = tile.localX == localX and tile.localZ == localZ and
                            tile.chunkX == chunkX and tile.chunkZ == chunkZ
                else
                    match = tile.relativeX == localX and tile.relativeZ == localZ
                end

                if match then
                    tile.label = sanitizeTileLabel(label)
                    M.saveLayouts(bolt, layoutsData)
                    return true
                end
            end

            return false
        end
    end

    return false
end



-- Adjust a tile's height in a layout.
-- IMPORTANT FIX: instance layouts match by relativeX/relativeZ.
function M.adjustLayoutTileHeight(bolt, layoutId, localX, localZ, chunkX, chunkZ, deltaSteps)
    local HEIGHT_STEP = 25
    local steps = tonumber(deltaSteps) or 0
    if steps == 0 then
        return false
    end

    local layoutsData = M.loadLayouts(bolt)

    for _, layout in ipairs(layoutsData.layouts) do
        if layout.id == layoutId then
            local tiles = layout.tiles or {}

            for _, tile in ipairs(tiles) do
                local match = false
                if layout.layoutType == "chunk" then
                    match = tile.localX == localX and tile.localZ == localZ and
                            tile.chunkX == chunkX and tile.chunkZ == chunkZ
                else
                    match = tile.relativeX == localX and tile.relativeZ == localZ
                end

                if match then
                    local baseY = tile.worldY or 0
                    tile.worldY = baseY + steps * HEIGHT_STEP
                    M.saveLayouts(bolt, layoutsData)
                    return true
                end
            end

            return false
        end
    end

    return false
end

-- Merge chunk layouts only (unchanged logic, but keeps normalization).
function M.mergeLayouts(bolt, layoutIds, newName, keepOriginals)
    if type(layoutIds) ~= "table" or #layoutIds < 2 then
        return false, "Need at least 2 layouts to merge."
    end

    local layoutsData = M.loadLayouts(bolt)

    local layoutsToMerge = {}
    for _, layoutId in ipairs(layoutIds) do
        for _, layout in ipairs(layoutsData.layouts) do
            if layout.id == layoutId then
                if layout.layoutType ~= "chunk" then
                    return false, "Only chunk layouts can be merged."
                end
                table.insert(layoutsToMerge, layout)
                break
            end
        end
    end

    if #layoutsToMerge < 2 then
        return false, "Could not find enough layouts to merge."
    end

    local mergedTilesMap = {}
    local mergedTiles = {}

    for _, layout in ipairs(layoutsToMerge) do
        if type(layout.tiles) == "table" then
            for _, tile in ipairs(layout.tiles) do
                local key = string.format("%d_%d_%d_%d_%d",
                    tile.chunkX or 0,
                    tile.chunkZ or 0,
                    tile.localX or 0,
                    tile.localZ or 0,
                    tile.worldY or 0
                )

                if not mergedTilesMap[key] then
                    mergedTilesMap[key] = true
                    local mergedTile = {
                        localX = tile.localX,
                        localZ = tile.localZ,
                        worldY = tile.worldY,
                        colorIndex = tile.colorIndex,
                        chunkX = tile.chunkX,
                        chunkZ = tile.chunkZ
                    }
                    local lbl = sanitizeTileLabel(tile.label)
                    if lbl then
                        mergedTile.label = lbl
                    end
                    table.insert(mergedTiles, mergedTile)
                end
            end
        end
    end

    if #mergedTiles == 0 then
        return false, "No tiles found in selected layouts."
    end

    local id = "merged_" .. (#layoutsData.layouts + 1) .. "_" .. math.random(1000, 9999)
    local displayName = sanitizeDisplayName(newName, "Merged Layout") or "Merged Layout"
    local storageName = sanitizeStoredName(newName, displayName)

    local mergedLayout = {
        id = id,
        name = storageName,
        displayName = displayName,
        created = #layoutsData.layouts + 1,
        layoutType = "chunk",
        tiles = mergedTiles
    }

    mergedLayout = normalizeLayoutEntry(mergedLayout, #layoutsData.layouts + 1, bolt)

    local newLayoutsList = {}
    table.insert(newLayoutsList, mergedLayout)

    for _, layout in ipairs(layoutsData.layouts) do
        local shouldRemove = false
        if not keepOriginals then
            for _, layoutId in ipairs(layoutIds) do
                if layout.id == layoutId then
                    shouldRemove = true
                    break
                end
            end
        end
        if not shouldRemove then
            table.insert(newLayoutsList, layout)
        end
    end

    local newLayoutsData = {
        version = layoutsData.version,
        layouts = newLayoutsList
    }

    local saved = M.saveLayouts(bolt, newLayoutsData)
    if not saved then
        return false, "Failed to save merged layout."
    end

    return true, mergedLayout
end

-- Delete all instance layouts while preserving chunk layouts
-- Used for migration after breaking changes to instance layout format
function M.deleteAllInstanceLayouts(bolt)
    local layoutsData = M.loadLayouts(bolt)
    local originalCount = #layoutsData.layouts
    local newLayouts = {}
    local deletedCount = 0

    -- Keep only chunk layouts
    for _, layout in ipairs(layoutsData.layouts) do
        if layout.layoutType == "chunk" then
            table.insert(newLayouts, layout)
        else
            deletedCount = deletedCount + 1
        end
    end

    layoutsData.layouts = newLayouts
    M.saveLayouts(bolt, layoutsData)

    return deletedCount, originalCount - deletedCount
end

-- Link a layout to an entrance location
function M.linkLayoutToEntrance(bolt, layoutId, entranceData)

    if not bolt then
        return false
    end

    local layoutsData = M.loadLayouts(bolt)

    for i, layout in ipairs(layoutsData.layouts) do
        if layout.id == layoutId then

            -- Only allow linking instance layouts
            if layout.layoutType ~= "instance" then
                return false
            end

            layout.linkedEntrance = {
                chunkX = entranceData.chunkX,
                chunkZ = entranceData.chunkZ,
                localX = entranceData.localX,
                localZ = entranceData.localZ,
                floor = entranceData.floor
            }

            if layout.linkedEntrance then
            end

            -- Save updated layouts
            local success = M.saveLayouts(bolt, layoutsData)

            if success then
                -- Verify it was saved by reloading
                local reloaded = M.loadLayouts(bolt)
                for _, reloadedLayout in ipairs(reloaded.layouts) do
                    if reloadedLayout.id == layoutId then
                        if reloadedLayout.linkedEntrance then
                        end
                        break
                    end
                end

                return true
            end
            return false
        end
    end

    return false
end

-- Unlink a layout from its entrance
function M.unlinkLayout(bolt, layoutId)
    if not bolt then
        return false
    end

    local layoutsData = M.loadLayouts(bolt)

    for i, layout in ipairs(layoutsData.layouts) do
        if layout.id == layoutId then
            layout.linkedEntrance = nil

            -- Save updated layouts
            local success = M.saveLayouts(bolt, layoutsData)
            if success then
                return true
            end
            return false
        end
    end

    return false
end

-- Get entrance info for a layout
function M.getLayoutEntranceInfo(layoutId)
    local layout = M.getLayout(layoutId)
    if layout and layout.linkedEntrance then
        return layout.linkedEntrance
    end
    return nil
end

return M
