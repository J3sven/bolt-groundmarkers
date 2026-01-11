local M = {}

local render3dHandlers = {}
local swapBufferHandlers = {}
local renderGameViewHandlers = {}

function M.addRender3DHandler(name, handler)
    render3dHandlers[name] = handler
end

function M.addSwapBufferHandler(name, handler)
    swapBufferHandlers[name] = handler
end

function M.addRenderGameViewHandler(name, handler)
    renderGameViewHandlers[name] = handler
end

function M.removeRender3DHandler(name)
    render3dHandlers[name] = nil
end

function M.removeSwapBufferHandler(name)
    swapBufferHandlers[name] = nil
end

function M.removeRenderGameViewHandler(name)
    renderGameViewHandlers[name] = nil
end

function M.init(bolt)
    bolt.onrender3d(function(event)
        for name, handler in pairs(render3dHandlers) do
            local success = pcall(handler, event)
            if not success then
            end
        end
    end)

    bolt.onswapbuffers(function(event)
        for name, handler in pairs(swapBufferHandlers) do
            local success = pcall(handler, event)
            if not success then
            end
        end
    end)

    bolt.onrendergameview(function(event)
        for name, handler in pairs(renderGameViewHandlers) do
            local success = pcall(handler, event)
            if not success then
            end
        end
    end)
end

function M.getStatus()
    local render3dNames = {}
    local swapBufferNames = {}
    
    for name, _ in pairs(render3dHandlers) do
        table.insert(render3dNames, name)
    end
    
    for name, _ in pairs(swapBufferHandlers) do
        table.insert(swapBufferNames, name)
    end
    
    return {
        render3d = render3dNames,
        swapBuffer = swapBufferNames
    }
end

return M
