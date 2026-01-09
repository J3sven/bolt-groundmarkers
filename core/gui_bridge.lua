-- core/gui_bridge.lua - Bridge between Lua and Browser UI
local M = {}

local browser = nil
local isOpen = false
local lastUpdateFrame = 0
local updateInterval = 60  -- Update GUI every 60 frames
local cachedState = nil
local cachedBolt = nil

-- Simple JSON decoder (basic, for our needs)
local function decodeJSON(str)
    if not str or str == "" then return nil end

    -- Try using a simple pattern-based approach for our simple messages
    -- Our messages are simple: {"action":"...", "name":"...", "layoutId":"..."}

    local result = {}

    -- Extract key-value pairs from JSON string
    for key, value in str:gmatch('"([^"]+)"%s*:%s*"([^"]*)"') do
        result[key] = value
    end

    -- Also try to match boolean and null values
    for key, value in str:gmatch('"([^"]+)"%s*:%s*([%w]+)') do
        if value == "true" then
            result[key] = true
        elseif value == "false" then
            result[key] = false
        elseif value == "null" then
            result[key] = nil
        elseif not result[key] then  -- Don't overwrite string values
            result[key] = value
        end
    end

    -- Return nil if we didn't parse anything
    if next(result) == nil then
        return nil
    end

    return result
end

-- Simple JSON encoder (basic, for our needs)
local function encodeJSON(tbl)
    if type(tbl) ~= "table" then
        if type(tbl) == "string" then
            return '"' .. tbl:gsub('"', '\\"') .. '"'
        elseif type(tbl) == "number" or type(tbl) == "boolean" then
            return tostring(tbl)
        elseif tbl == nil then
            return "null"
        end
    end

    -- Check if it's an array
    local isArray = true
    local maxIndex = 0
    for k, v in pairs(tbl) do
        if type(k) ~= "number" or k < 1 or k ~= math.floor(k) then
            isArray = false
            break
        end
        maxIndex = math.max(maxIndex, k)
    end

    if isArray then
        local parts = {}
        for i = 1, maxIndex do
            table.insert(parts, encodeJSON(tbl[i]))
        end
        return "[" .. table.concat(parts, ",") .. "]"
    else
        local parts = {}
        for k, v in pairs(tbl) do
            local key = type(k) == "string" and ('"' .. k .. '"') or tostring(k)
            table.insert(parts, key .. ":" .. encodeJSON(v))
        end
        return "{" .. table.concat(parts, ",") .. "}"
    end
end

-- Initialize the GUI bridge
function M.init()
    browser = nil
    isOpen = false
    lastUpdateFrame = 0
end

-- Open the layouts GUI
function M.open(bolt, state)
    if isOpen then
        return
    end

    -- Cache bolt and state for message handler
    cachedBolt = bolt
    cachedState = state

    local width = 500
    local height = 700

    -- No custom JS needed - we'll use the bolt-api endpoints
    browser = bolt.createbrowser(width, height, "plugin://ui/layouts.html")
    isOpen = true

    -- Set up message handler for incoming messages from JavaScript via https://bolt-api/send-message
    browser:onmessage(function(msg)
        bolt.saveconfig("browser_incoming_debug.txt", string.format("Received from browser: %s", msg))

        -- Parse JSON message using our simple decoder
        local data = decodeJSON(msg)

        if data then
            M.handleBrowserMessage(cachedBolt, cachedState, data)
        else
            bolt.saveconfig("browser_incoming_debug.txt", string.format("Failed to parse message: %s", msg))
        end
    end)

    bolt.saveconfig("instance_debug.txt", "Opened layouts GUI with bolt-api message handler")
end

-- Close the GUI
function M.close()
    if browser then
        browser:close()
        browser = nil
        isOpen = false
    end
end

-- Send state update to GUI
function M.sendStateUpdate(state, bolt)
    if not browser or not isOpen then
        return
    end

    local instanceManager = require("core.instance_manager")
    local managerState = instanceManager.getState()

    local message = {
        type = "state_update",
        inInstance = managerState.inInstance,
        tempTileCount = managerState.tempTileCount,
        activeLayoutId = managerState.currentLayoutId
    }

    local json = encodeJSON(message)
    browser:sendmessage(json)

    -- Debug log
    bolt.saveconfig("gui_debug.txt", string.format(
        "Sent state update: inInstance=%s tempTiles=%d json=%s",
        tostring(managerState.inInstance), managerState.tempTileCount, json
    ))
end

-- Send layouts list to GUI
function M.sendLayoutsUpdate(bolt)
    if not browser or not isOpen then
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

    local json = encodeJSON(message)
    browser:sendmessage(json)

    -- Debug log with actual JSON
    bolt.saveconfig("gui_debug.txt", string.format(
        "Sent layouts update: %d layouts, json=%s",
        #layouts, json:sub(1, 200)  -- First 200 chars
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
        return
    end

    local instanceManager = require("core.instance_manager")
    local layoutPersist = require("data.layout_persistence")

    if data.action == "ready" then
        -- Browser loaded, send initial state
        M.sendFullUpdate(bolt, state)

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
        -- Activate a saved layout
        if not instanceManager.isInInstance() then
            bolt.saveconfig("instance_debug.txt", "Cannot activate layout: not in instance")
            return
        end

        instanceManager.setActiveLayout(data.layoutId)
        M.sendStateUpdate(state, bolt)

        bolt.saveconfig("instance_debug.txt", string.format(
            "Activated layout %s", data.layoutId
        ))

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
    end
end

return M
