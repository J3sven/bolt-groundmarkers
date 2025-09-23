local M = {}
local draw = require("gfx.draw")

local function tileCount(marked)
  local n = 0
  for _ in pairs(marked) do n = n + 1 end
  return n
end

function M.hookRender3D(state, bolt)
  bolt.onrender3d(function(event)
    state.setViewProj(event:viewprojmatrix())
  end)
end

local function normEdgeKey(ax, az, bx, bz)
  if (bx < ax) or (bx == ax and bz < az) then
    ax, az, bx, bz = bx, bz, ax, az
  end
  return ax .. "," .. az .. ">" .. bx .. "," .. bz
end

local function computeUniqueEdges(tiles, coords)
  local edges = {}
  for _, t in ipairs(tiles) do
    local tx, tz = coords.worldToTileCoords(t.x, t.z)

    local c00x, c00z = tx,     tz
    local c10x, c10z = tx + 1, tz
    local c11x, c11z = tx + 1, tz + 1
    local c01x, c01z = tx,     tz + 1

    local tileEdges = {
      {c00x,c00z,c10x,c10z}, -- top
      {c10x,c10z,c11x,c11z}, -- right
      {c11x,c11z,c01x,c01z}, -- bottom
      {c01x,c01z,c00x,c00z}, -- left
    }

    for _, e in ipairs(tileEdges) do
      local k = normEdgeKey(e[1],e[2],e[3],e[4])
      edges[k] = edges[k] or { ax=e[1], az=e[2], bx=e[3], bz=e[4] }
    end
  end
  return edges
end

-- Simple rectangle check in screen space
local function anyEndpointInView(ax, ay, bx, by, vx, vy, vw, vh)
  if (ax >= vx and ay >= vy and ax <= vx+vw and ay <= vy+vh) then return true end
  if (bx >= vx and by >= vy and bx <= vx+vw and by <= vy+vh) then return true end
  return false
end

function M.hookSwapBuffers(state, bolt, surfaces, colors)
  bolt.onswapbuffers(function(event)
    state.incFrame()

    local markerSurface = state.getMarkerSurface()
    local viewProj = state.getViewProj()
    if not markerSurface or not viewProj then return end

    local marked = state.getMarkedTiles()
    if tileCount(marked) == 0 then return end

    local playerPos = bolt.playerposition()
    if not playerPos then return end

    local px, py, pz = playerPos:get()
    local coords = state.getCoords()
    local tileX, tileZ = coords.worldToTileCoords(px, pz)
    local _, playerChunkX, playerChunkZ = coords.tileToRS(tileX, tileZ, py)

    local vx, vy, vw, vh = bolt.gameviewxywh()

    -- Filter tiles to those within 1 chunk of the player (3x3 area)
    local chunkTiles = {}
    for _, t in pairs(marked) do
      local dx = math.abs(t.chunkX - playerChunkX)
      local dz = math.abs(t.chunkZ - playerChunkZ)
      if dx <= 1 and dz <= 1 then
        chunkTiles[#chunkTiles + 1] = t
      end
    end
    if #chunkTiles == 0 then return end

    local byColor = {}
    for _, t in ipairs(chunkTiles) do
      local idx = t.colorIndex or 1
      byColor[idx] = byColor[idx] or {}
      table.insert(byColor[idx], t)
    end

    for colorIndex, list in pairs(byColor) do
      if #list > 0 then
        local rgb = colors.get(colorIndex)
        local coloredSurface = surfaces.createColoredSurface(bolt, rgb)
        if not coloredSurface then goto continue_color end

        local uniqueEdges = computeUniqueEdges(list, coords)

        local fallbackY = list[1] and list[1].y or 0

        for _, e in pairs(uniqueEdges) do
          local pA = draw.gridVertexToWorldPoint(bolt, state, coords, e.ax, e.az, fallbackY)
          local pB = draw.gridVertexToWorldPoint(bolt, state, coords, e.bx, e.bz, fallbackY)

          local ax, ay, ad = pA:transform(viewProj):aspixels()
          local bx, by, bd = pB:transform(viewProj):aspixels()

          if not (ad <= 0.0 or ad > 1.0 or bd <= 0.0 or bd > 1.0) then
            if anyEndpointInView(ax, ay, bx, by, vx, vy, vw, vh) then
              draw.drawLine(coloredSurface, ax, ay, bx, by, 3)
            end
          end
        end
      end
      ::continue_color::
    end
  end)
end

return M
