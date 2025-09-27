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
local instanceRecognition = require("core.instances")

state.init({ bolt = bolt, colors = colors, coords = coords })
state.setMarkerSurface(surfaces.createMarkerSurface(bolt))
persist.loadMarkers(state, bolt)

-- Initialize hooks FIRST
hooks.init(bolt)

-- Pass hooks to render functions
render.hookRender3D(state, bolt, hooks)  -- ADD hooks parameter
render.hookSwapBuffers(state, bolt, surfaces, colors, hooks)  -- ADD hooks parameter

input.bind(state, bolt, tiles, colors)
instanceRecognition.init(bolt, hooks)  -- ADD hooks parameter

bolt.saveconfig("marker_debug.txt", "Plugin initialized with hooks")