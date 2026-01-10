local M = {}
local draw = require("gfx.draw")

local function tileCount(marked)
  local n = 0
  for _ in pairs(marked) do n = n + 1 end
  return n
end

function M.hookRender3D(state, bolt, hooks)
  hooks.addRender3DHandler("viewproj", function(event)
    state.setViewProj(event:viewprojmatrix())
  end)
end

local EDGE_SUBDIVS = 2

local function normEdgeKey(ax, az, bx, bz)
  if (bx < ax) or (bx == ax and bz < az) then
    ax, az, bx, bz = bx, bz, ax, az
  end
  return ax .. "," .. az .. ">" .. bx .. "," .. bz
end

local function vkey(x, z) return x .. "," .. z end
local function parseVKey(k)
  local x, z = k:match("([^,]+),([^,]+)")
  return tonumber(x), tonumber(z)
end

local function terrainHeightOrNil(bolt, state, wx, wz)
  if state and state.getHeightAt then
    local ok, y = pcall(state.getHeightAt, wx, wz)
    if ok and type(y) == "number" then return y end
  end
  if bolt and bolt.groundheight then
    local ok, y = pcall(bolt.groundheight, wx, wz)
    if ok and type(y) == "number" then return y end
  end
  return nil
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
      if not edges[k] then
        edges[k] = { ax=e[1], az=e[2], bx=e[3], bz=e[4] }
      end
    end
  end
  return edges
end

local function buildVertexHeights(bolt, state, tiles, coords)
  local S = coords.TILE_SIZE
  local useTerrain = (state and state.getHeightAt) or (bolt and bolt.groundheight)

  local acc, cnt = {}, {}
  if not useTerrain then
    for _, t in ipairs(tiles) do
      local tx, tz = coords.worldToTileCoords(t.x, t.z)
      local y = t.y or 0
      local verts = {
        vkey(tx,     tz),
        vkey(tx + 1, tz),
        vkey(tx + 1, tz + 1),
        vkey(tx,     tz + 1),
      }
      for _, k in ipairs(verts) do
        acc[k] = (acc[k] or 0) + y
        cnt[k] = (cnt[k] or 0) + 1
      end
    end
  end

  local vh = {}
  local seen = {}
  for _, t in ipairs(tiles) do
    local tx, tz = coords.worldToTileCoords(t.x, t.z)
    local verts = {
      {tx,     tz},
      {tx + 1, tz},
      {tx + 1, tz + 1},
      {tx,     tz + 1},
    }
    for _, v in ipairs(verts) do
      local k = vkey(v[1], v[2])
      if not seen[k] then
        seen[k] = true
        local wx, wz = v[1] * S, v[2] * S
        local y = useTerrain and terrainHeightOrNil(bolt, state, wx, wz)
        if y == nil then
          y = (acc[k] and acc[k] / cnt[k]) or 0
        end
        vh[k] = y
      end
    end
  end
  return vh
end

local function anyEndpointInView(ax, ay, bx, by, vx, vy, vw, vh)
  if (ax >= vx and ay >= vy and ax <= vx+vw and ay <= vy+vh) then return true end
  if (bx >= vx and by >= vy and bx <= vx+vw and by <= vy+vh) then return true end
  return false
end

function M.hookSwapBuffers(state, bolt, surfaces, colors, hooks)
  hooks.addSwapBufferHandler("rendering", function(event)
    state.incFrame()

    local markerSurface = state.getMarkerSurface()
    local viewProj = state.getViewProj()
    if not markerSurface or not viewProj then return end

    local playerPos = bolt.playerposition()
    if not playerPos then return end

    local px, py, pz = playerPos:get()
    local coords = state.getCoords()
    local tileX, tileZ = coords.worldToTileCoords(px, pz)
    local _, playerChunkX, playerChunkZ = coords.tileToRS(tileX, tileZ, py)

    local vx, vy, vw, vh = bolt.gameviewxywh()

    local instanceManager = require("core.instance_manager")
    local inInstance = instanceManager.isInInstance()

    -- Collect all tiles to render
    local tilesToRender = {}

    -- 1. Add regular (non-instance) markers if not in instance
    if not inInstance then
      local marked = state.getMarkedTiles()
      for _, t in pairs(marked) do
        local dx = math.abs(t.chunkX - playerChunkX)
        local dz = math.abs(t.chunkZ - playerChunkZ)
        if dx <= 1 and dz <= 1 then
          table.insert(tilesToRender, t)
        end
      end
    end

    -- 2. Add active layout tiles (can have multiple active layouts)
    local activeLayoutIds = instanceManager.getActiveLayoutIds()
    local layoutPersist = require("data.layout_persistence")

    for _, activeLayoutId in ipairs(activeLayoutIds) do
      local layout = layoutPersist.getLayout(bolt, activeLayoutId)

      if layout and layout.tiles then
        for _, layoutTile in ipairs(layout.tiles) do
          local localX = layoutTile.localX
          local localZ = layoutTile.localZ

          -- Check if this is a chunk layout using the layoutType property
          local isChunkLayout = layout.layoutType == "chunk"

          if isChunkLayout then
            -- Chunk layout: only render if player is in the same chunk and tile has chunk coords
            if not inInstance and layoutTile.chunkX == playerChunkX and layoutTile.chunkZ == playerChunkZ then
              -- Convert to world coordinates using the layout's chunk
              local tileX = layoutTile.chunkX * 64 + localX
              local tileZ = layoutTile.chunkZ * 64 + localZ
              local worldX, worldZ = coords.tileToWorldCoords(tileX, tileZ)

              local transformedTile = {
                x = worldX,
                z = worldZ,
                y = layoutTile.worldY,
                colorIndex = layoutTile.colorIndex,
                chunkX = layoutTile.chunkX,
                chunkZ = layoutTile.chunkZ,
                localX = localX,
                localZ = localZ,
                floor = 0
              }

              table.insert(tilesToRender, transformedTile)
            end
          else
            -- Instance layout: render in all instances
            if inInstance then
              -- Convert to world coordinates using current player chunk
              local newTileX = playerChunkX * 64 + localX
              local newTileZ = playerChunkZ * 64 + localZ
              local newWorldX, newWorldZ = coords.tileToWorldCoords(newTileX, newTileZ)

              local transformedTile = {
                x = newWorldX,
                z = newWorldZ,
                y = layoutTile.worldY,
                colorIndex = layoutTile.colorIndex,
                chunkX = playerChunkX,
                chunkZ = playerChunkZ,
                localX = localX,
                localZ = localZ,
                floor = 0
              }

              table.insert(tilesToRender, transformedTile)
            end
          end
        end
      end
    end

    -- 3. Add temporary instance tiles (overlaid on layout)
    if inInstance then
      local tempTiles = instanceManager.getInstanceTiles()
      for _, t in pairs(tempTiles) do
        table.insert(tilesToRender, t)
      end
    end

    local hoverTile = instanceManager.getHoverTile()
    if hoverTile then
      table.insert(tilesToRender, hoverTile)
    end

    if #tilesToRender == 0 then return end

    -- Group by color and render (supporting preview tiles)
    local groups = {}
    for _, t in ipairs(tilesToRender) do
      local key
      local rgbOverride = nil
      local alphaOverride = nil

      if t.previewColor then
        key = string.format("preview:%d,%d,%d", t.previewColor[1] or 0, t.previewColor[2] or 0, t.previewColor[3] or 0)
        rgbOverride = t.previewColor
        alphaOverride = t.previewAlpha
      else
        key = tostring(t.colorIndex or 1)
      end

      if not groups[key] then
        groups[key] = {
          tiles = {},
          rgb = rgbOverride or colors.get(t.colorIndex or 1),
          alpha = alphaOverride
        }
      end

      if alphaOverride then
        groups[key].alpha = alphaOverride
      end

      table.insert(groups[key].tiles, t)
    end

    for _, group in pairs(groups) do
      if #group.tiles > 0 then
        local coloredSurface = surfaces.createColoredSurface(bolt, group.rgb, group.alpha)
        if not coloredSurface then goto continue_color end

        local uniqueEdges = computeUniqueEdges(group.tiles, coords)

        local vHeights = buildVertexHeights(bolt, state, group.tiles, coords)
        local S = coords.TILE_SIZE

        for _, e in pairs(uniqueEdges) do
          local samples = {}
          local function pushSample(gx, gz)
            local k = vkey(gx, gz)
            local wy = vHeights[k] or 0
            local wx, wz = gx * S, gz * S
            local p3 = bolt.point(wx, wy, wz)
            local sx, sy, sd = p3:transform(viewProj):aspixels()
            table.insert(samples, {sx=sx, sy=sy, sd=sd})
          end

          pushSample(e.ax, e.az)

          if EDGE_SUBDIVS and EDGE_SUBDIVS > 0 then
            for s = 1, EDGE_SUBDIVS do
              local t = s / (EDGE_SUBDIVS + 1)
              local gx = e.ax + (e.bx - e.ax) * t
              local gz = e.az + (e.bz - e.az) * t

              local wx, wz = gx * S, gz * S
              local midY = terrainHeightOrNil(bolt, state, wx, wz)
              if midY == nil then
                local ya = vHeights[vkey(e.ax, e.az)] or 0
                local yb = vHeights[vkey(e.bx, e.bz)] or 0
                midY = ya + (yb - ya) * t
              end
              local p3 = bolt.point(wx, midY, wz)
              local sx, sy, sd = p3:transform(viewProj):aspixels()
              table.insert(samples, {sx=sx, sy=sy, sd=sd})
            end
          end

          pushSample(e.bx, e.bz)

          for i = 1, #samples - 1 do
            local a, b = samples[i], samples[i+1]
            if not (a.sd <= 0.0 or a.sd > 1.0 or b.sd <= 0.0 or b.sd > 1.0) then
              if anyEndpointInView(a.sx, a.sy, b.sx, b.sy, vx, vy, vw, vh) then
                draw.drawLine(coloredSurface, a.sx, a.sy, b.sx, b.sy, 3)
              end
            end
          end
        end
      end
      ::continue_color::
    end
  end)
end

return M
