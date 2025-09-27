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

    local marked = state.getMarkedTiles()
    if tileCount(marked) == 0 then return end

    local playerPos = bolt.playerposition()
    if not playerPos then return end

    local px, py, pz = playerPos:get()
    local coords = state.getCoords()
    local tileX, tileZ = coords.worldToTileCoords(px, pz)
    local _, playerChunkX, playerChunkZ = coords.tileToRS(tileX, tileZ, py)

    local vx, vy, vw, vh = bolt.gameviewxywh()

    -- NEW: Transform instance markers to current player position
    local chunkTiles = {}
    local instanceRecognition = require("core.instances")
    local currentInstanceId = instanceRecognition.getCurrentInstanceId()
    local inInstance = instanceRecognition.isInInstance()

    for _, t in pairs(marked) do
      local shouldRender = false
      local transformedTile = t  -- Default to original tile
      
      if t.instanceId then
        -- Instance marker: render if we're in the same instance
        if inInstance and currentInstanceId == t.instanceId then
          shouldRender = true
          
          -- Transform coordinates: use stored local coords + current player chunk
          local newChunkX = playerChunkX
          local newChunkZ = playerChunkZ
          local localX = t.localX
          local localZ = t.localZ
          
          -- Convert new chunk + local to world coordinates
          local newTileX = newChunkX * 64 + localX
          local newTileZ = newChunkZ * 64 + localZ
          local newWorldX, newWorldZ = coords.tileToWorldCoords(newTileX, newTileZ)
          
          -- Create transformed tile with new coordinates
          transformedTile = {
            x = newWorldX, z = newWorldZ, y = t.y,
            colorIndex = t.colorIndex,
            chunkX = newChunkX, chunkZ = newChunkZ,
            localX = localX, localZ = localZ,
            floor = t.floor,
            instanceId = t.instanceId,
            isRecognized = t.isRecognized
          }
        end
      else
        -- Regular marker: use chunk proximity as before
        local dx = math.abs(t.chunkX - playerChunkX)
        local dz = math.abs(t.chunkZ - playerChunkZ)
        if dx <= 1 and dz <= 1 then
          shouldRender = true
        end
      end
      
      if shouldRender then
        chunkTiles[#chunkTiles + 1] = transformedTile
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

        local vHeights = buildVertexHeights(bolt, state, list, coords)
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
