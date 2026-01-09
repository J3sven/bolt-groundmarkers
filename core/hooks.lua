-- core/hooks.lua - Central event hook coordinator
local M = {}

-- Handler registries
local render3dHandlers = {}
local swapBufferHandlers = {}

-- Register handlers for render3d events
function M.addRender3DHandler(name, handler)
    render3dHandlers[name] = handler
end

-- Register handlers for swapbuffer events  
function M.addSwapBufferHandler(name, handler)
    swapBufferHandlers[name] = handler
end

-- Remove handlers (useful for cleanup)
function M.removeRender3DHandler(name)
    render3dHandlers[name] = nil
end

function M.removeSwapBufferHandler(name)
    swapBufferHandlers[name] = nil
end

-- Initialize the consolidated hooks
function M.init(bolt)
    -- Single render3d hook that calls all registered handlers
    bolt.onrender3d(function(event)
        for name, handler in pairs(render3dHandlers) do
            local success = pcall(handler, event)
            if not success then
                -- swallow handler errors to avoid crashing Bolt
            end
        end
    end)
    
    -- Single swapbuffers hook that calls all registered handlers
    bolt.onswapbuffers(function(event)
        for name, handler in pairs(swapBufferHandlers) do
            local success = pcall(handler, event)
            if not success then
                -- swallow handler errors to avoid crashing Bolt
            end
        end
    end)
end

-- Debug function to see what handlers are registered
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
