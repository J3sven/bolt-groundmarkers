local bolt = require("bolt")
bolt.checkversion(1, 0)

local state    = require("core.state")
local colors   = require("core.colors")
local coords   = require("core.coords")
local persist  = require("data.persistence")
local surfaces = require("gfx.surfaces")
local tiles    = require("logic.tiles")
local input    = require("input.input")
local render   = require("gfx.render")

state.init({ bolt = bolt, colors = colors, coords = coords })
state.setMarkerSurface(surfaces.createMarkerSurface(bolt))
persist.loadMarkers(state, bolt)
render.hookRender3D(state, bolt)
render.hookSwapBuffers(state, bolt, surfaces, colors)
input.bind(state, bolt, tiles, colors)

bolt.saveconfig("marker_debug.txt", string.format(
  "Current color: %s\n",
  colors.getColorName(state.getCurrentColorIndex())
))
