local M = {}
local draw = require("gfx.draw")
local text = require("gfx.text")
local LABEL_PIXEL_SCALE = 0.65
local LABEL_PIXEL_SCALE_MIN = 0.45
local LABEL_HEIGHT_OFFSET = 20
local vertexHeightCache = {}
local lastHeightRevision = -1

local function depthScaledScale(sd, baseScale)
  if not sd then
    return baseScale
  end
  local depth = math.min(1, math.max(0, sd))
  local factor = 0.65 + (1 - depth) * 0.55
  return math.max(LABEL_PIXEL_SCALE_MIN, baseScale * factor)
end

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

local EDGE_SUBDIVS = 1

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
    local tx, tz
    if t.tileX and t.tileZ then
      tx, tz = t.tileX, t.tileZ
    else
      tx, tz = coords.worldToTileCoords(t.x, t.z)
    end

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
      local tx, tz
      if t.tileX and t.tileZ then
        tx, tz = t.tileX, t.tileZ
      else
        tx, tz = coords.worldToTileCoords(t.x, t.z)
      end
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
    local tx, tz
    if t.tileX and t.tileZ then
      tx, tz = t.tileX, t.tileZ
    else
      tx, tz = coords.worldToTileCoords(t.x, t.z)
    end
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
        if useTerrain and vertexHeightCache[k] ~= nil then
          vh[k] = vertexHeightCache[k]
        else
          local wx, wz = v[1] * S, v[2] * S
          local y = useTerrain and terrainHeightOrNil(bolt, state, wx, wz)
          if y == nil then
            y = (acc[k] and acc[k] / cnt[k]) or 0
          end
          vh[k] = y
          if useTerrain then
            vertexHeightCache[k] = y
          end
        end
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

local function isEdgeNearView(ax, ay, bx, by, vx, vy, vw, vh, margin)
  -- Quick AABB check with margin - if edge bounding box doesn't overlap viewport, skip it
  local minX = math.min(ax, bx)
  local maxX = math.max(ax, bx)
  local minY = math.min(ay, by)
  local maxY = math.max(ay, by)

  if maxX < vx - margin or minX > vx + vw + margin then return false end
  if maxY < vy - margin or minY > vy + vh + margin then return false end
  return true
end

local function projectTileCenter(bolt, state, coords, tile, viewProj, heightOffset)
  local S = coords.TILE_SIZE
  local cx = tile.x + S * 0.5
  local cz = tile.z + S * 0.5
  local cy = tile.y or tile.worldY
  if not cy then
    cy = terrainHeightOrNil(bolt, state, cx, cz) or 0
  end
  cy = cy + (heightOffset or 0)
  local p3 = bolt.point(cx, cy, cz)
  return p3:transform(viewProj):aspixels()
end

function M.hookSwapBuffers(state, bolt, surfaces, colors, hooks)
  text.init(bolt)
  hooks.addSwapBufferHandler("rendering", function(event)
    state.incFrame()

    local currentRevision = state.getTileRevision and state.getTileRevision() or 0
    if currentRevision ~= lastHeightRevision then
      vertexHeightCache = {}
      lastHeightRevision = currentRevision
    end

    local markerSurface = state.getMarkerSurface()
    local viewProj = state.getViewProj()
    if not markerSurface or not viewProj then return end

    local playerPos = bolt.playerposition()
    if not playerPos then return end

    local px, py, pz = playerPos:get()
    local coords = state.getCoords()
    local playerTileX, playerTileZ = coords.worldToTileCoords(px, pz)
    local _, playerChunkX, playerChunkZ, playerLocalX, playerLocalZ = coords.tileToRS(playerTileX, playerTileZ, py)

    local vx, vy, vw, vh = bolt.gameviewxywh()

    local instanceManager = require("core.instance_manager")
    local inInstance = instanceManager.isInInstance()
    local tilesToRender = {}

    if not inInstance then
      local marked = state.getMarkedTiles()
      for _, t in pairs(marked) do
        local markerTileX = t.tileX or (t.chunkX * 64 + t.localX)
        local markerTileZ = t.tileZ or (t.chunkZ * 64 + t.localZ)

        local tileDx = math.abs(markerTileX - playerTileX)
        local tileDz = math.abs(markerTileZ - playerTileZ)

        if tileDx <= 64 and tileDz <= 64 then
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
          local isChunkLayout = layout.layoutType == "chunk"

          if isChunkLayout then
            if not inInstance and layoutTile.chunkX ~= nil and layoutTile.chunkZ ~= nil then
              local layoutTileX = layoutTile.chunkX * 64 + localX
              local layoutTileZ = layoutTile.chunkZ * 64 + localZ
              local tileDx = math.abs(layoutTileX - playerTileX)
              local tileDz = math.abs(layoutTileZ - playerTileZ)

              if tileDx <= 64 and tileDz <= 64 then
                local worldX, worldZ = coords.tileToWorldCoords(layoutTileX, layoutTileZ)

                local transformedTile = {
                  x = worldX,
                  z = worldZ,
                  y = layoutTile.worldY,
                  colorIndex = layoutTile.colorIndex,
                  chunkX = layoutTile.chunkX,
                  chunkZ = layoutTile.chunkZ,
                  localX = localX,
                  localZ = localZ,
                  floor = 0,
                  tileX = layoutTileX,
                  tileZ = layoutTileZ
                }

                table.insert(tilesToRender, transformedTile)
              end
            end
          else
            if inInstance then
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
                floor = 0,
                tileX = newTileX,
                tileZ = newTileZ
              }

              table.insert(tilesToRender, transformedTile)
            end
          end
        end
      end
    end

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

    local shouldDrawLabels = state.getShowTileLabels and state.getShowTileLabels()

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
          -- Early culling: transform endpoints to screen space and check if edge is near viewport
          local k_a = vkey(e.ax, e.az)
          local k_b = vkey(e.bx, e.bz)
          local wy_a = vHeights[k_a] or 0
          local wy_b = vHeights[k_b] or 0
          local wx_a, wz_a = e.ax * S, e.az * S
          local wx_b, wz_b = e.bx * S, e.bz * S

          local p3_a = bolt.point(wx_a, wy_a, wz_a)
          local p3_b = bolt.point(wx_b, wy_b, wz_b)
          local sx_a, sy_a, sd_a = p3_a:transform(viewProj):aspixels()
          local sx_b, sy_b, sd_b = p3_b:transform(viewProj):aspixels()

          -- Skip if both endpoints are behind camera or edge is far from viewport
          if (sd_a <= 0.0 or sd_a > 1.0) and (sd_b <= 0.0 or sd_b > 1.0) then
            goto continue_edge
          end

          if not isEdgeNearView(sx_a, sy_a, sx_b, sy_b, vx, vy, vw, vh, 100) then
            goto continue_edge
          end

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

          local thickness = state.getLineThickness and state.getLineThickness() or 4
          for i = 1, #samples - 1 do
            local a, b = samples[i], samples[i+1]
            if not (a.sd <= 0.0 or a.sd > 1.0 or b.sd <= 0.0 or b.sd > 1.0) then
              if anyEndpointInView(a.sx, a.sy, b.sx, b.sy, vx, vy, vw, vh) then
                draw.drawLine(coloredSurface, a.sx, a.sy, b.sx, b.sy, thickness)
              end
            end
          end

          ::continue_edge::
        end

        if shouldDrawLabels then
          for _, tile in ipairs(group.tiles) do
            local labelText = tile.label
            if type(labelText) == "string" and labelText ~= "" then
              local sx, sy, sd = projectTileCenter(bolt, state, coords, tile, viewProj, LABEL_HEIGHT_OFFSET)
              if sd and sd > 0.0 and sd <= 1.0 then
                local margin = 50
                if sx >= vx - margin and sx <= vx + vw + margin and sy >= vy - margin and sy <= vy + vh + margin then
                  local labelScale = depthScaledScale(sd, LABEL_PIXEL_SCALE)
                  text.draw(labelText, sx, sy, labelScale)
                end
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
