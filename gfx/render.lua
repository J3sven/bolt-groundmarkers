local M = {}
local draw = require("gfx.draw")

local function tileCount(marked)
  local n=0 for _ in pairs(marked) do n=n+1 end return n
end

function M.hookRender3D(state, bolt)
  bolt.onrender3d(function(event)
    state.setViewProj(event:viewprojmatrix())
  end)
end

function M.hookSwapBuffers(state, bolt, surfaces, colors)
  bolt.onswapbuffers(function(event)
    state.incFrame()

    local markerSurface = state.getMarkerSurface()
    local viewProj = state.getViewProj()
    if not markerSurface or not viewProj then return end

    local marked = state.getMarkedTiles()
    if tileCount(marked) == 0 then return end

    local gx, gy, gw, gh = bolt.gameviewxywh()
    local coords = state.getCoords()

    local byColor = {}
    for _, t in pairs(marked) do
      local idx = t.colorIndex or 1
      byColor[idx] = byColor[idx] or {}
      table.insert(byColor[idx], t)
    end

    for colorIndex, list in pairs(byColor) do
      local rgb = colors.get(colorIndex)
      local coloredSurface = surfaces.createColoredSurface(bolt, rgb)

      if coloredSurface then
        for _, t in ipairs(list) do
          local corners3D = draw.getProperTileCorners(bolt, coords, marked, t)

          local corners2D, allVisible = {}, true
          for i, corner in ipairs(corners3D) do
            local sx, sy, depth = corner:transform(viewProj):aspixels()
            if depth <= 0.0 or depth > 1.0 then allVisible = false; break end
            corners2D[i] = { x = sx, y = sy }
          end

          if allVisible then
            local inView = false
            for _, c in ipairs(corners2D) do
              if c.x >= gx and c.y >= gy and c.x <= (gx + gw) and c.y <= (gy + gh) then
                inView = true; break
              end
            end
            if inView then
              draw.drawPolygonOutline(coloredSurface, corners2D, 3)
            end
          end
        end
      end
    end
  end)
end

return M
