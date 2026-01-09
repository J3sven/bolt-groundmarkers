local bolt = require("bolt")
bolt.checkversion(1, 0)

local state = require("core.state")
local colors = require("core.colors")
local coords = require("core.coords")
local persist = require("data.persistence")
local surfaces = require("gfx.surfaces")
local tiles = require("core.tiles")
local input = require("input.input")
local render = require("gfx.render")
local hooks = require("core.hooks")
local instanceManager = require("core.instance_manager")
local guiBridge = require("core.gui_bridge")

-- Initialize color palette before other modules consume it
colors.init(bolt)

-- Initialize core modules
state.init({ bolt = bolt, colors = colors, coords = coords })
state.setMarkerSurface(surfaces.createMarkerSurface(bolt))
persist.loadMarkers(state, bolt)

-- Initialize hooks FIRST
hooks.init(bolt)

-- Initialize instance manager
instanceManager.init(bolt)

-- Initialize GUI bridge
guiBridge.init(bolt)

-- Set up rendering hooks
render.hookRender3D(state, bolt, hooks)
render.hookSwapBuffers(state, bolt, surfaces, colors, hooks)

-- Add instance manager update and GUI update to swap buffer handler
hooks.addSwapBufferHandler("instance_manager", function(event)
    instanceManager.update(bolt)
    -- Also periodically update GUI
    local currentFrame = state.getFrame and state.getFrame() or 0
    guiBridge.periodicUpdate(bolt, state, currentFrame)
end)

-- Set up input bindings
input.bind(state, bolt, tiles, colors)

-- Open the launcher button on startup (persistent mini window)
guiBridge.openLauncher(bolt, state)
