-- core/gui_simple.lua - Simple text-based GUI using bolt windows
local M = {}

local window = nil
local isOpen = false

-- Initialize
function M.init()
    window = nil
    isOpen = false
end

-- Open the GUI window
function M.open(bolt)
    if isOpen then return end

    -- Create a simple window
    window = bolt.createwindow(100, 100, 400, 300)
    isOpen = true

    -- Setup window handlers
    window:onmousebutton(function(event)
        local ex, ey = event:xy()
        -- Simple close on click for now
        if event:button() == 1 and ey < 20 then
            M.close()
        end
    end)

    M.redraw(bolt)
end

-- Close the window
function M.close()
    if window then
        window = nil
        isOpen = false
    end
end

-- Redraw window content
function M.redraw(bolt)
    if not window or not isOpen then return end

    local instanceManager = require("core.instance_manager")
    local layoutPersist = require("data.layout_persistence")

    local managerState = instanceManager.getState()
    local layouts = layoutPersist.getAllLayouts(bolt)

    -- Clear window
    window:clear(0.1, 0.1, 0.15, 1)

    -- For now, just show basic info
    -- In the future, we could draw text/buttons here
    -- This is a placeholder - the window will be blank
    -- but won't crash the plugin
end

-- Check if open
function M.isOpen()
    return isOpen
end

-- Update state
function M.sendStateUpdate(state)
    if isOpen then
        M.redraw(require("bolt"))
    end
end

function M.sendLayoutsUpdate(bolt)
    if isOpen then
        M.redraw(bolt)
    end
end

function M.sendFullUpdate(bolt, state)
    if isOpen then
        M.redraw(bolt)
    end
end

return M
