-- core/gui_bridge.lua - Bridge between Lua and Browser UI
local M = {}

local colors = require("core.colors")
local json = require("core.simplejson")

local browser = nil
local launcherBrowser = nil
local isOpen = false
local lastUpdateFrame = 0
local updateInterval = 60  -- Update GUI every 60 frames
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
        local debugMsg = string.format("[EMBEDDED] Received: %s (type: %s, len: %d)",
            tostring(msg), type(msg), type(msg) == "string" and #msg or 0)
        bolt.saveconfig("browser_incoming_debug.txt", debugMsg)

        local data = json.decode(msg)

        if data then
            bolt.saveconfig("browser_incoming_debug.txt", string.format("[EMBEDDED] Decoded action: %s", tostring(data.action)))
            M.handleBrowserMessage(cachedBolt, cachedState, data)
        else
            bolt.saveconfig("browser_incoming_debug.txt", string.format("[EMBEDDED] Failed to parse: %s", msg))
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

    bolt.saveconfig("instance_debug.txt", "Opened layouts GUI with embedded browser")
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
        local debugMsg = string.format("[OVERLAY] Received: %s (type: %s, len: %d)",
            tostring(msg), type(msg), type(msg) == "string" and #msg or 0)
        bolt.saveconfig("browser_incoming_debug.txt", debugMsg)

        local data = json.decode(msg)

        if data then
            bolt.saveconfig("browser_incoming_debug.txt", string.format("[OVERLAY] Decoded action: %s", tostring(data.action)))
            M.handleBrowserMessage(cachedBolt, cachedState, data)
        else
            bolt.saveconfig("browser_incoming_debug.txt", string.format("[OVERLAY] Failed to parse: %s", msg))
        end
    end)

    bolt.saveconfig("instance_debug.txt", string.format("Opened overlay browser: %s", url))
end

-- Close overlay browser
function M.closeOverlay()
    if overlayBrowser then
        overlayBrowser:close()
        overlayBrowser = nil
        overlayUrl = nil
        if cachedBolt then
            cachedBolt.saveconfig("instance_debug.txt", "Closed overlay browser")
        end
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

    bolt.saveconfig("instance_debug.txt", "Opened launcher button")
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
        if managerState.inInstance then
            local tempTiles = instanceManager.getInstanceTiles()
            for _, tile in pairs(tempTiles) do
                table.insert(gridTiles, { localX = tile.localX, localZ = tile.localZ })
            end
        else
            local markedTiles = state.getMarkedTiles()
            for _, tile in pairs(markedTiles) do
                if tile.chunkX == chunkSnapshot.chunkX and tile.chunkZ == chunkSnapshot.chunkZ then
                    table.insert(gridTiles, { localX = tile.localX, localZ = tile.localZ })
                end
            end
        end

        chunkGrid.marked = gridTiles
    else
        chunkGrid.marked = {}
    end

    local palette = colors.getPaletteForUI()
    local currentColorIndex = state.getCurrentColorIndex and state.getCurrentColorIndex() or 1

    local message = {
        type = "state_update",
        inInstance = managerState.inInstance,
        tempTileCount = managerState.tempTileCount,
        activeLayoutId = managerState.currentLayoutId,
        chunkGrid = chunkGrid,
        palette = palette,
        currentColorIndex = currentColorIndex
    }

    sendBrowserPayload(message)

    -- Debug log
    local encoded = json.encode(message)
    bolt.saveconfig("gui_debug.txt", string.format(
        "Sent state update: inInstance=%s tempTiles=%d json=%s",
        tostring(managerState.inInstance), managerState.tempTileCount, encoded or "nil"
    ))
end

-- Send layouts list to GUI
function M.sendLayoutsUpdate(bolt)
    if not isOpen then
        return
    end

    local layoutPersist = require("data.layout_persistence")
    local layouts = layoutPersist.getAllLayouts(bolt)

    -- Debug: log first layout structure
    if layouts[1] then
        local debugStr = "First layout keys: "
        for k, v in pairs(layouts[1]) do
            debugStr = debugStr .. k .. "=" .. type(v) .. " "
        end
        bolt.saveconfig("gui_debug.txt", debugStr)
    end

    local message = {
        type = "layouts_update",
        layouts = layouts
    }

    sendBrowserPayload(message)

    -- Debug log with actual JSON
    local encoded = json.encode(message)
    bolt.saveconfig("gui_debug.txt", string.format(
        "Sent layouts update: %d layouts, json=%s",
        #layouts, encoded and encoded:sub(1, 200) or "nil"
    ))
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
        bolt.saveconfig("browser_incoming_debug.txt", "[HANDLER] No data or no action field")
        return
    end

    bolt.saveconfig("browser_incoming_debug.txt", string.format("[HANDLER] Processing action: %s", data.action))

    local instanceManager = require("core.instance_manager")
    local layoutPersist = require("data.layout_persistence")

    if data.action == "ready" then
        -- Browser loaded, send initial state
        bolt.saveconfig("browser_incoming_debug.txt", "[HANDLER] Sending full update for ready")
        M.sendFullUpdate(bolt, state)

    elseif data.action == "toggle_main_window" then
        -- Toggle the main window from launcher button
        bolt.saveconfig("browser_incoming_debug.txt", "[HANDLER] Toggling main window")
        M.toggle(bolt, state)

    elseif data.action == "open_save_overlay" then
        bolt.saveconfig("browser_incoming_debug.txt", "[HANDLER] Opening save overlay")
        -- Open overlay for saving a layout
        local tempCount = instanceManager.getInstanceTileCount()
        M.openOverlay(bolt, state, string.format("plugin://ui/save-layout.html?tempCount=%d", tempCount))

    elseif data.action == "open_import_overlay" then
        -- Open overlay for importing a layout
        M.openOverlay(bolt, state, "plugin://ui/import-layout.html")

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
            bolt.saveconfig("instance_debug.txt", "Cannot save layout: not in instance")
            return
        end

        local tempTiles = instanceManager.getInstanceTiles()
        local layoutId = layoutPersist.createLayout(bolt, data.name, tempTiles)

        -- Clear temporary tiles after saving
        instanceManager.clearInstanceTiles()

        -- Send updates
        M.sendFullUpdate(bolt, state)

        bolt.saveconfig("instance_debug.txt", string.format(
            "Saved layout '%s' with ID %s", data.name, layoutId
        ))

    elseif data.action == "activate_layout" then
        local layoutId = data.layoutId
        if not layoutId or layoutId == "" then
            return
        end

        local layout = layoutPersist.getLayout(bolt, layoutId)
        if not layout then
            bolt.saveconfig("instance_debug.txt", string.format(
                "Cannot activate layout %s: missing definition", layoutId
            ))
            return
        end

        if instanceManager.setActiveLayout(layoutId) then
            M.sendStateUpdate(state, bolt)

            bolt.saveconfig("instance_debug.txt", string.format(
                "Activated layout %s (auto-apply ready)", layoutId
            ))
        end

    elseif data.action == "deactivate_layout" then
        -- Deactivate current layout
        instanceManager.clearActiveLayout()
        M.sendStateUpdate(state, bolt)

        bolt.saveconfig("instance_debug.txt", "Deactivated layout")

    elseif data.action == "delete_layout" then
        -- Delete a layout
        layoutPersist.deleteLayout(bolt, data.layoutId)

        -- If this was the active layout, deactivate it
        if instanceManager.getActiveLayoutId() == data.layoutId then
            instanceManager.clearActiveLayout()
        end

        M.sendFullUpdate(bolt, state)

        bolt.saveconfig("instance_debug.txt", string.format(
            "Deleted layout %s", data.layoutId
        ))

    elseif data.action == "import_layout" then
        local layoutData = data.layout
        if type(layoutData) ~= "table" then
            sendImportResult(false, "Import failed: invalid payload.")
            return
        end

        local success, result = layoutPersist.importLayoutFromData(bolt, layoutData)
        if success then
            M.sendFullUpdate(bolt, state)
            local name = result and (result.displayName or result.name) or "Imported Layout"
            sendImportResult(true, string.format('Imported layout "%s".', name))
            bolt.saveconfig("instance_debug.txt", string.format(
                "Imported layout %s with %d tiles",
                tostring(name),
                result and #result.tiles or 0
            ))
        else
            sendImportResult(false, result or "Import failed.")
            bolt.saveconfig("instance_debug.txt", string.format(
                "Import layout failed: %s",
                tostring(result or "unknown error")
            ))
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
