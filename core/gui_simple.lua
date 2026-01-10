local M = {}

local window = nil
local isOpen = false

function M.init()
    window = nil
    isOpen = false
end

function M.open(bolt)
    if isOpen then return end

    window = bolt.createwindow(100, 100, 400, 300)
    isOpen = true

    window:onmousebutton(function(event)
        local ex, ey = event:xy()
        if event:button() == 1 and ey < 20 then
            M.close()
        end
    end)

    M.redraw(bolt)
end

function M.close()
    if window then
        window = nil
        isOpen = false
    end
end

function M.redraw(bolt)
    if not window or not isOpen then return end

    local instanceManager = require("core.instance_manager")
    local layoutPersist = require("data.layout_persistence")

    local managerState = instanceManager.getState()
    local layouts = layoutPersist.getAllLayouts(bolt)

    window:clear(0.1, 0.1, 0.15, 1)
end

function M.isOpen()
    return isOpen
end

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
