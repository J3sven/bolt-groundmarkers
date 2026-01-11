-- core/gui_bridge.lua - Bridge between Lua and Browser UI
local M = {}

local colors = require("core.colors")
local json = require("core.simplejson")
local persistence = require("data.persistence")

local browser = nil
local launcherBrowser = nil
local isOpen = false
local lastUpdateFrame = 0
local updateInterval = 60
local cachedState = nil
local cachedBolt = nil

local function sendBrowserPayload(payload)
    if not browser or not isOpen then
        return
    end
    local encoded = json.encode(payload)
    if encoded then
        browser:sendmessage(encoded)
    end
end

local function urlEncode(str)
    if type(str) ~= "string" then
        return ""
    end
    return (str:gsub("[^%w%-%._~]", function(char)
        return string.format("%%%02X", char:byte())
    end))
end

local function sendImportResult(success, message)
    sendBrowserPayload({
        type = "import_result",
        success = success,
        message = message or ""
    })
end

-- Config for embedded browser position and size
local cfg = {
    x = 0,
    y = 0,
    w = 500,
    h = 700
}
local cfgname = "gui_config.ini"

-- Config for launcher button position
local launcherCfg = {
    x = 100,
    y = 100
}
local launcherCfgname = "launcher_config.ini"

-- Load config from file
local function loadconfig(bolt)
    local cfgstring = bolt.loadconfig(cfgname)
    if cfgstring == nil then return end
    for k, v in string.gmatch(cfgstring, "(%w+)=([%-]?%d+)") do
        cfg[k] = tonumber(v)
    end
end

-- Save config to file
local function saveconfig(bolt)
    local cfgstring = ""
    for k, v in pairs(cfg) do
        cfgstring = string.format("%s%s=%s\n", cfgstring, k, tostring(v))
    end
    bolt.saveconfig(cfgname, cfgstring)
end

-- Load launcher config from file
local function loadlauncherconfig(bolt)
    local cfgstring = bolt.loadconfig(launcherCfgname)
    if cfgstring == nil then return end
    for k, v in string.gmatch(cfgstring, "(%w+)=([%-]?%d+)") do
        launcherCfg[k] = tonumber(v)
    end
end

-- Save launcher config to file
local function savelauncherconfig(bolt)
    local cfgstring = ""
    for k, v in pairs(launcherCfg) do
        cfgstring = string.format("%s%s=%s\n", cfgstring, k, tostring(v))
    end
    bolt.saveconfig(launcherCfgname, cfgstring)
end

-- Overlay browser for text input operations
local overlayBrowser = nil
local overlayUrl = nil

-- Initialize the GUI bridge
function M.init(bolt)
    browser = nil
    launcherBrowser = nil
    overlayBrowser = nil
    isOpen = false
    lastUpdateFrame = 0
    loadconfig(bolt)
    loadlauncherconfig(bolt)
end

-- Open the main embedded browser GUI
function M.open(bolt, state)
    if isOpen then
        return
    end

    -- Cache bolt and state for message handler
    cachedBolt = bolt
    cachedState = state

    -- Create embedded browser with saved position/size
    browser = bolt.createembeddedbrowser(cfg.x, cfg.y, cfg.w, cfg.h, "plugin://ui/layouts.html")
    isOpen = true

    -- Set up message handler for incoming messages from JavaScript
    browser:onmessage(function(msg)
        local data = json.decode(msg)
        if data then
            M.handleBrowserMessage(cachedBolt, cachedState, data)
        end
    end)

    -- Handle window close request
    browser:oncloserequest(function()
        M.close()
    end)

    -- Handle window reposition/resize
    browser:onreposition(function(event)
        local x, y, w, h = event:xywh()
        cfg.x = x
        cfg.y = y
        cfg.w = w
        cfg.h = h
        saveconfig(bolt)
    end)

end

-- Open overlay browser for text input operations
function M.openOverlay(bolt, state, url)
    if overlayBrowser then
        overlayBrowser:close()
    end

    -- Cache bolt and state for message handler
    cachedBolt = bolt
    cachedState = state
    overlayUrl = url

    -- Create overlay browser (supports keyboard input)
    overlayBrowser = bolt.createbrowser(400, 300, url)

    -- Set up message handler
    overlayBrowser:onmessage(function(msg)
        local data = json.decode(msg)
        if data then
            M.handleBrowserMessage(cachedBolt, cachedState, data)
        end
    end)
end

-- Close overlay browser
function M.closeOverlay()
    if overlayBrowser then
        overlayBrowser:close()
        overlayBrowser = nil
        overlayUrl = nil
    end
end

-- Open the launcher button (persistent mini window)
function M.openLauncher(bolt, state)
    if launcherBrowser then
        return  -- Already open
    end

    -- Cache bolt and state for message handler
    cachedBolt = bolt
    cachedState = state

    -- Create small embedded browser for launcher button (35x35)
    launcherBrowser = bolt.createembeddedbrowser(launcherCfg.x, launcherCfg.y, 35, 35, "plugin://ui/launcher.html")

    -- Set up message handler for launcher
    launcherBrowser:onmessage(function(msg)
        local data = json.decode(msg)
        if data then
            M.handleBrowserMessage(cachedBolt, cachedState, data)
        end
    end)

    -- Handle launcher reposition
    launcherBrowser:onreposition(function(event)
        local x, y, w, h = event:xywh()
        launcherCfg.x = x
        launcherCfg.y = y
        savelauncherconfig(bolt)
    end)

end

-- Close the launcher button
function M.closeLauncher()
    if launcherBrowser then
        launcherBrowser:close()
        launcherBrowser = nil
    end
end

-- Close the embedded GUI
function M.close()
    if browser then
        browser:close()
        browser = nil
        isOpen = false
    end
    M.closeOverlay()
end

-- Toggle the main window open/closed
function M.toggle(bolt, state)
    if isOpen then
        M.close()
    else
        M.open(bolt, state)
    end
end

-- Count non-instance marked tiles in the current chunk that are not in any saved layout
local function countNonInstanceUnsavedTiles(state, bolt)
    local instanceManager = require("core.instance_manager")
    local chunkSnapshot = instanceManager.getChunkSnapshot()

    if not chunkSnapshot then
        return 0
    end

    local markedTiles = state.getMarkedTiles()
    local layoutPersist = require("data.layout_persistence")
    local layouts = layoutPersist.getAllLayouts(bolt)

    -- Create a set of all tiles in saved layouts
    local savedTileKeys = {}
    for _, layout in ipairs(layouts) do
        if layout.tiles then
            for _, tile in ipairs(layout.tiles) do
                -- Create a key based on chunk coords and local coords
                local key = string.format("%d_%d_%d_%d",
                    tile.chunkX or 0,
                    tile.chunkZ or 0,
                    tile.localX or 0,
                    tile.localZ or 0
                )
                savedTileKeys[key] = true
            end
        end
    end

    -- Count tiles in the current chunk that are not in any saved layout
    local count = 0
    for _, tile in pairs(markedTiles) do
        -- Only count tiles in the current chunk
        if tile.chunkX == chunkSnapshot.chunkX and tile.chunkZ == chunkSnapshot.chunkZ then
            local key = string.format("%d_%d_%d_%d",
                tile.chunkX or 0,
                tile.chunkZ or 0,
                tile.localX or 0,
                tile.localZ or 0
            )
            if not savedTileKeys[key] then
                count = count + 1
            end
        end
    end

    return count
end

-- Send state update to GUI
function M.sendStateUpdate(state, bolt)
    if not isOpen then
        return
    end

    local instanceManager = require("core.instance_manager")
    local managerState = instanceManager.getState()

    local chunkSnapshot = instanceManager.getChunkSnapshot()
    local chunkGrid = {
        enabled = chunkSnapshot ~= nil,
        size = 64,
        mode = managerState.inInstance and "instance" or "world",
    }

    if chunkSnapshot then
        chunkGrid.chunkX = chunkSnapshot.chunkX
        chunkGrid.chunkZ = chunkSnapshot.chunkZ
        chunkGrid.playerLocalX = chunkSnapshot.localX
        chunkGrid.playerLocalZ = chunkSnapshot.localZ
        chunkGrid.floor = chunkSnapshot.floor

        local gridTiles = {}
        local layoutTiles = {}

        if managerState.inInstance then
            local tempTiles = instanceManager.getInstanceTiles()
            for _, tile in pairs(tempTiles) do
                table.insert(gridTiles, {
                    localX = tile.localX,
                    localZ = tile.localZ,
                    label = tile.label
                })
            end
        else
            local markedTiles = state.getMarkedTiles()
            for _, tile in pairs(markedTiles) do
                if tile.chunkX == chunkSnapshot.chunkX and tile.chunkZ == chunkSnapshot.chunkZ then
                    table.insert(gridTiles, {
                        localX = tile.localX,
                        localZ = tile.localZ,
                        label = tile.label
                    })
                end
            end
        end

        -- Add tiles from active layouts in the current chunk
        local layoutPersist = require("data.layout_persistence")
        local activeLayoutIds = managerState.activeLayoutIds or {}
        for _, layoutId in ipairs(activeLayoutIds) do
            local layout = layoutPersist.getLayout(bolt, layoutId)
            if layout and layout.tiles then
                local isChunkLayout = layout.layoutType == "chunk"

                for _, layoutTile in ipairs(layout.tiles) do
                    -- For chunk layouts, check if tile is in current chunk
                    -- For instance layouts, include all tiles when in instance
                    local shouldInclude = false

                    if isChunkLayout and not managerState.inInstance then
                        if layoutTile.chunkX == chunkSnapshot.chunkX and layoutTile.chunkZ == chunkSnapshot.chunkZ then
                            shouldInclude = true
                        end
                    elseif not isChunkLayout and managerState.inInstance then
                        shouldInclude = true
                    end

                    if shouldInclude then
                        table.insert(layoutTiles, {
                            localX = layoutTile.localX,
                            localZ = layoutTile.localZ
                        })
                    end
                end
            end
        end

        chunkGrid.marked = gridTiles
        chunkGrid.layoutTiles = layoutTiles
    else
        chunkGrid.marked = {}
    end

    local palette = colors.getPaletteForUI()
    local currentColorIndex = state.getCurrentColorIndex and state.getCurrentColorIndex() or 1

    -- Calculate non-instance unsaved tile count
    local nonInstanceTileCount = 0
    if not managerState.inInstance then
        nonInstanceTileCount = countNonInstanceUnsavedTiles(state, bolt)
    end

    local message = {
        type = "state_update",
        inInstance = managerState.inInstance,
        tempTileCount = managerState.tempTileCount,
        nonInstanceTileCount = nonInstanceTileCount,
        activeLayoutIds = managerState.activeLayoutIds or {},
        chunkGrid = chunkGrid,
        palette = palette,
        currentColorIndex = currentColorIndex,
        lineThickness = state.getLineThickness(),
        showTileLabels = state.getShowTileLabels(),
        showTileFill = state.getShowTileFill(),
        tileFillOpacity = state.getTileFillOpacity and state.getTileFillOpacity() or 50
    }

    sendBrowserPayload(message)
end

-- Send layouts list to GUI
function M.sendLayoutsUpdate(bolt)
    if not isOpen then
        return
    end

    local layoutPersist = require("data.layout_persistence")
    local layouts = layoutPersist.getAllLayouts(bolt)

    local message = {
        type = "layouts_update",
        layouts = layouts
    }

    sendBrowserPayload(message)
end

-- Send full update (state + layouts)
function M.sendFullUpdate(bolt, state)
    M.sendStateUpdate(state, bolt)
    M.sendLayoutsUpdate(bolt)
end

-- Periodic update function (call from swap buffer handler)
function M.periodicUpdate(bolt, state, currentFrame)
    if not isOpen then return end

    if currentFrame - lastUpdateFrame >= updateInterval then
        M.sendFullUpdate(bolt, state)
        lastUpdateFrame = currentFrame
    end
end

-- Check if GUI is open
function M.isOpen()
    return isOpen
end

-- Handle messages from the browser
function M.handleBrowserMessage(bolt, state, data)
    if not data or not data.action then
        return
    end

    local instanceManager = require("core.instance_manager")
    local layoutPersist = require("data.layout_persistence")

    if data.action == "ready" then
        M.sendFullUpdate(bolt, state)

    elseif data.action == "toggle_main_window" then
        -- Toggle the main window from launcher button
        M.toggle(bolt, state)

    elseif data.action == "open_save_overlay" then
        -- Open overlay for saving a layout
        local tempCount = instanceManager.getInstanceTileCount()
        M.openOverlay(bolt, state, string.format("plugin://ui/save-layout.html?tempCount=%d", tempCount))

    elseif data.action == "open_save_chunk_overlay" then
        -- Open overlay for saving a chunk layout
        local nonInstanceCount = countNonInstanceUnsavedTiles(state, bolt)
        M.openOverlay(bolt, state, string.format("plugin://ui/save-chunk-layout.html?tempCount=%d", nonInstanceCount))

    elseif data.action == "open_import_overlay" then
        -- Open overlay for importing a layout
        M.openOverlay(bolt, state, "plugin://ui/import-layout.html")

    elseif data.action == "open_merge_overlay" then
        -- Open overlay for merging chunk layouts
        M.openOverlay(bolt, state, "plugin://ui/merge-layouts.html")

    elseif data.action == "get_chunk_layouts_for_merge" then
        -- Send chunk layouts data to merge overlay
        if overlayBrowser then
            local chunkLayouts = layoutPersist.getChunkLayouts(bolt)
            local message = {
                type = "chunk_layouts_data",
                layouts = chunkLayouts
            }
            local encoded = json.encode(message)
            if encoded then
                overlayBrowser:sendmessage(encoded)
            end
        end

    elseif data.action == "open_export_overlay" then
        -- Open overlay for exporting a layout
        if data.layoutId then
            M.openOverlay(bolt, state, string.format("plugin://ui/export-layout.html?layoutId=%s", data.layoutId))
        end

    elseif data.action == "get_layout_export" then
        -- Send layout data to overlay for export
        if data.layoutId and overlayBrowser then
            local layout = layoutPersist.getLayout(bolt, data.layoutId)
            if layout then
                local exportData = {
                    version = 1,
                    name = layout.name or "",
                    displayName = layout.displayName or layout.name or "",
                    tiles = layout.tiles or {}
                }
                local message = {
                    type = "export_layout_data",
                    layout = exportData
                }
                local encoded = json.encode(message)
                if encoded then
                    overlayBrowser:sendmessage(encoded)
                end
            end
        end

    elseif data.action == "close_overlay" then
        -- Close overlay browser
        M.closeOverlay()

    elseif data.action == "close" then
        M.close()

    elseif data.action == "save_layout" then
        -- Save current instance tiles as a layout
        if not instanceManager.isInInstance() then
            return
        end

        local tempTiles = instanceManager.getInstanceTiles()
        local layoutId = layoutPersist.createLayout(bolt, data.name, tempTiles, "instance")

        -- Automatically activate the newly saved layout
        instanceManager.activateLayout(layoutId)

        -- Clear temporary tiles after saving
        instanceManager.clearInstanceTiles()

        -- Send updates
        M.sendFullUpdate(bolt, state)

    elseif data.action == "save_chunk_layout" then
        -- Save non-instance marked tiles in the current chunk as a chunk layout
        if instanceManager.isInInstance() then
            return
        end

        local chunkSnapshot = instanceManager.getChunkSnapshot()
        if not chunkSnapshot then
            return
        end

        -- Get non-instance marked tiles in the current chunk that aren't in saved layouts
        local markedTiles = state.getMarkedTiles()
        local layouts = layoutPersist.getAllLayouts(bolt)

        -- Create a set of all tiles in saved layouts
        local savedTileKeys = {}
        for _, layout in ipairs(layouts) do
            if layout.tiles then
                for _, tile in ipairs(layout.tiles) do
                    local key = string.format("%d_%d_%d_%d",
                        tile.chunkX or 0,
                        tile.chunkZ or 0,
                        tile.localX or 0,
                        tile.localZ or 0
                    )
                    savedTileKeys[key] = true
                end
            end
        end

        -- Collect unsaved tiles in the current chunk only
        local unsavedTiles = {}
        local tilesToRemove = {}
        for tileKey, tile in pairs(markedTiles) do
            -- Only include tiles in the current chunk
            if tile.chunkX == chunkSnapshot.chunkX and tile.chunkZ == chunkSnapshot.chunkZ then
                local key = string.format("%d_%d_%d_%d",
                    tile.chunkX or 0,
                    tile.chunkZ or 0,
                    tile.localX or 0,
                    tile.localZ or 0
                )
                if not savedTileKeys[key] then
                    table.insert(unsavedTiles, tile)
                    table.insert(tilesToRemove, tileKey)
                end
            end
        end

        -- Save the chunk layout and remove the saved tiles from marked tiles
        if #unsavedTiles > 0 then
            local layoutId = layoutPersist.createLayout(bolt, data.name, unsavedTiles, "chunk")

            -- Automatically activate the newly saved layout
            instanceManager.activateLayout(layoutId)

            -- Remove saved tiles from the marked tiles
            for _, tileKey in ipairs(tilesToRemove) do
                markedTiles[tileKey] = nil
            end

            -- Save the updated marked tiles
            local persistence = require("data.persistence")
            persistence.saveMarkers(state, bolt)

            M.sendFullUpdate(bolt, state)
        end

    elseif data.action == "activate_layout" then
        local layoutId = data.layoutId
        if not layoutId or layoutId == "" then
            return
        end

        local layout = layoutPersist.getLayout(bolt, layoutId)
        if not layout then
            return
        end

        if instanceManager.activateLayout(layoutId) then
            M.sendStateUpdate(state, bolt)
        end

    elseif data.action == "deactivate_layout" then
        local layoutId = data.layoutId
        if layoutId and layoutId ~= "" then
            instanceManager.deactivateLayout(layoutId)
        end
        M.sendStateUpdate(state, bolt)

    elseif data.action == "delete_layout" then
        -- Delete a layout
        layoutPersist.deleteLayout(bolt, data.layoutId)

        -- If this was active, deactivate it
        if instanceManager.isLayoutActive(data.layoutId) then
            instanceManager.deactivateLayout(data.layoutId)
        end

        M.sendFullUpdate(bolt, state)

    elseif data.action == "import_layout" then
        local layoutData = data.layout
        if type(layoutData) ~= "table" then
            sendImportResult(false, "Import failed: invalid payload.")
            return
        end

        local success, result = layoutPersist.importLayoutFromData(bolt, layoutData)
        if success then
            -- Automatically activate the imported layout
            if result and result.id then
                instanceManager.activateLayout(result.id)
            end

            M.sendFullUpdate(bolt, state)
            local name = result and (result.displayName or result.name) or "Imported Layout"
            sendImportResult(true, string.format('Imported layout "%s".', name))
        else
            sendImportResult(false, result or "Import failed.")
        end

    elseif data.action == "merge_layouts" then
        local layoutIds = data.layoutIds
        local newName = data.name
        local keepOriginals = data.keepOriginals

        if type(layoutIds) ~= "table" or type(newName) ~= "string" then
            sendImportResult(false, "Merge failed: invalid parameters.")
            return
        end

        local success, result = layoutPersist.mergeLayouts(bolt, layoutIds, newName, keepOriginals)
        if success then
            -- Deactivate original layouts if they were removed
            if not keepOriginals then
                for _, layoutId in ipairs(layoutIds) do
                    if instanceManager.isLayoutActive(layoutId) then
                        instanceManager.deactivateLayout(layoutId)
                    end
                end
            end

            -- Automatically activate the merged layout
            if result and result.id then
                instanceManager.activateLayout(result.id)
            end

            M.sendFullUpdate(bolt, state)
            local name = result and (result.displayName or result.name) or "Merged Layout"
            local tileCount = result and result.tiles and #result.tiles or 0
            sendImportResult(true, string.format('Created merged layout "%s" with %d tiles.', name, tileCount))
        else
            sendImportResult(false, result or "Merge failed.")
        end

    elseif data.action == "toggle_chunk_tile" then
        local localX = tonumber(data.localX)
        local localZ = tonumber(data.localZ)
        if localX and localZ then
            local scope = data.scope or (instanceManager.isInInstance() and "instance" or "world")
            local requestedColorIndex = tonumber(data.colorIndex)
            if scope == "instance" then
                local colorIndex = requestedColorIndex or (state.getCurrentColorIndex and state.getCurrentColorIndex() or 1)
                if instanceManager.toggleTileAtLocal(localX, localZ, colorIndex, bolt) then
                    M.sendStateUpdate(state, bolt)
                end
            else
                local chunkInfo = instanceManager.getChunkSnapshot()
                if chunkInfo then
                    local tiles = require("core.tiles")
                    local currentColor = requestedColorIndex or (state.getCurrentColorIndex and state.getCurrentColorIndex() or 1)
                    if tiles.toggleWorldTileAtChunkLocal(
                        state,
                        bolt,
                        chunkInfo.chunkX,
                        chunkInfo.chunkZ,
                        localX,
                        localZ,
                        chunkInfo.floor,
                        chunkInfo.worldY,
                        currentColor
                    ) then
                        M.sendStateUpdate(state, bolt)
                    end
                end
            end
        end

    elseif data.action == "open_tile_label_overlay" then
        local localX = tonumber(data.localX)
        local localZ = tonumber(data.localZ)
        if not localX or not localZ then
            return
        end
        local scope = data.scope == "instance" and "instance" or "world"
        local chunkInfo = instanceManager.getChunkSnapshot()
        if not chunkInfo then
            return
        end

        local existingLabel = nil
        if scope == "instance" then
            existingLabel = instanceManager.getInstanceTileLabel(localX, localZ)
        else
            local tiles = require("core.tiles")
            existingLabel = tiles.getWorldTileLabel(state, chunkInfo.chunkX, chunkInfo.chunkZ, localX, localZ)
        end

        local query = string.format("?chunkX=%d&chunkZ=%d&localX=%d&localZ=%d&scope=%s",
            chunkInfo.chunkX, chunkInfo.chunkZ, localX, localZ, scope)
        if existingLabel and existingLabel ~= "" then
            query = query .. "&label=" .. urlEncode(existingLabel)
        end

        M.openOverlay(bolt, state, "plugin://ui/tile-label.html" .. query)

    elseif data.action == "set_tile_label" then
        local chunkX = tonumber(data.chunkX)
        local chunkZ = tonumber(data.chunkZ)
        local localX = tonumber(data.localX)
        local localZ = tonumber(data.localZ)
        if not localX or not localZ then
            return
        end

        local scope = data.scope == "instance" and "instance" or "world"
        if scope == "instance" and instanceManager.isInInstance() then
            if instanceManager.setInstanceTileLabel(localX, localZ, data.label) then
                M.sendStateUpdate(state, bolt)
            end
        else
            if not chunkX or not chunkZ then
                return
            end
            local tiles = require("core.tiles")
            if tiles.setWorldTileLabel(state, bolt, chunkX, chunkZ, localX, localZ, data.label) then
                M.sendStateUpdate(state, bolt)
            end
        end

    elseif data.action == "hover_chunk_tile" then
        if data.clear then
            instanceManager.clearHoverTile()
        else
            local localX = tonumber(data.localX)
            local localZ = tonumber(data.localZ)
            if localX and localZ then
                instanceManager.setHoverTile(localX, localZ)
            end
        end

    elseif data.action == "update_palette_color" then
        local index = tonumber(data.index)
        if not index then return end

        local rgb = colors.hexToRgb(data.color)
        if not rgb then return end

        local updated = colors.setPaletteEntry(index, rgb, data.name, bolt)
        if updated then
            local surfaces = require("gfx.surfaces")
            surfaces.clearCache()
            M.sendStateUpdate(state, bolt)
        end

    elseif data.action == "update_line_thickness" then
        local thickness = tonumber(data.thickness)
        if thickness and thickness >= 2 and thickness <= 8 then
            state.setLineThickness(thickness)
            persistence.saveMarkers(state, bolt)
            M.sendStateUpdate(state, bolt)
        end

    elseif data.action == "set_tile_label_visibility" then
        local enabled = data.enabled and true or false
        state.setShowTileLabels(enabled)
        persistence.saveMarkers(state, bolt)
        M.sendStateUpdate(state, bolt)

    elseif data.action == "set_tile_fill_visibility" then
        local enabled = data.enabled and true or false
        state.setShowTileFill(enabled)
        persistence.saveMarkers(state, bolt)
        M.sendStateUpdate(state, bolt)

    elseif data.action == "set_tile_fill_opacity" then
        local opacity = tonumber(data.opacity)
        if opacity then
            state.setTileFillOpacity(opacity)
            persistence.saveMarkers(state, bolt)
            M.sendStateUpdate(state, bolt)
        end

    elseif data.action == "adjust_chunk_tile_height" then
        local localX = tonumber(data.localX)
        local localZ = tonumber(data.localZ)

        local direction = tonumber(data.direction)
        if not direction or direction == 0 then
            local dirLabel = data.directionLabel
            if type(dirLabel) == "string" then
                dirLabel = string.lower(dirLabel)
                if dirLabel == "down" then
                    direction = -1
                elseif dirLabel == "up" then
                    direction = 1
                end
            end
        end

        if not (localX and localZ and direction and direction ~= 0) then
            return
        end

        if direction > 0 then
            direction = 1
        elseif direction < 0 then
            direction = -1
        end

        local scope = data.scope or (instanceManager.isInInstance() and "instance" or "world")
        if scope == "instance" then
            if instanceManager.adjustInstanceTileHeight(localX, localZ, direction, bolt) then
                M.sendStateUpdate(state, bolt)
            end
        else
            local chunkInfo = instanceManager.getChunkSnapshot()
            if chunkInfo then
                local tiles = require("core.tiles")
                if tiles.adjustWorldTileHeight(
                    state,
                    bolt,
                    chunkInfo.chunkX,
                    chunkInfo.chunkZ,
                    localX,
                    localZ,
                    direction
                ) then
                    M.sendStateUpdate(state, bolt)
                end
            end
        end
    end
end

return M
