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

colors.init(bolt)

state.init({ bolt = bolt, colors = colors, coords = coords })
state.setMarkerSurface(surfaces.createMarkerSurface(bolt))
persist.loadMarkers(state, bolt)
hooks.init(bolt)

instanceManager.init(bolt)

guiBridge.init(bolt)

render.hookRender3D(state, bolt, hooks)
render.hookSwapBuffers(state, bolt, surfaces, colors, hooks)

hooks.addSwapBufferHandler("instance_manager", function(event)
    instanceManager.update(bolt)
    local currentFrame = state.getFrame and state.getFrame() or 0
    guiBridge.periodicUpdate(bolt, state, currentFrame)
end)

input.bind(state, bolt, tiles, colors)

guiBridge.openLauncher(bolt, state)

-- Check if we need to show the migration popup for instance layouts
local versionTracker = require("core.version_tracker")
if versionTracker.needsInstanceLayoutMigration(bolt) and not versionTracker.migrationAlreadyShown(bolt) then
    hooks.addSwapBufferHandler("migration_popup_delay", function(event)
        hooks.removeSwapBufferHandler("migration_popup_delay")
        guiBridge.openMigrationPopup(bolt, state)
    end)
else
    versionTracker.saveVersion(bolt)
    versionTracker.saveVersion(bolt)
end
