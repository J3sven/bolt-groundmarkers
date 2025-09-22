local M = {}

-- Small, smooth line via repeated blits
function M.drawLine(surface, x1, y1, x2, y2, thickness)
  local dx, dy = x2 - x1, y2 - y1
  local dist = math.sqrt(dx * dx + dy * dy)
  if dist < 1 then return end
  local steps = math.ceil(dist * 1.5)
  local sx, sy = dx / steps, dy / steps
  for i = 0, steps do
    local x = x1 + sx * i
    local y = y1 + sy * i
    surface:drawtoscreen(0, 0, 4, 4, x - thickness/2, y - thickness/2, thickness, thickness)
  end
end

function M.drawPolygonOutline(surface, corners, thickness)
  if #corners < 3 then return end
  for i = 1, #corners do
    local a = corners[i]
    local b = corners[(i % #corners) + 1]
    M.drawLine(surface, a.x, a.y, b.x, b.y, thickness)
  end
end

-- Build 3D corners, nudging shared edges toward neighbor heights
function M.getProperTileCorners(bolt, coords, markedTiles, markedTile)
  local S = coords.TILE_SIZE
  local tx, ty, tz = markedTile.x, markedTile.y, markedTile.z

  local corners = {
    bolt.point(tx,       ty, tz),        -- BL
    bolt.point(tx + S,   ty, tz),        -- BR
    bolt.point(tx + S,   ty, tz + S),    -- TR
    bolt.point(tx,       ty, tz + S),    -- TL
  }

  local key = coords.tileKey
  local north = markedTiles[key(tx, tz + S)]
  local east  = markedTiles[key(tx + S, tz)]
  local south = markedTiles[key(tx, tz - S)]
  local west  = markedTiles[key(tx - S, tz)]

  local function adjustEdge(i1, i2, neighbor)
    if neighbor and math.abs(neighbor.y - ty) > 10 then
      local edgeY = (ty + neighbor.y) / 2
      corners[i1] = bolt.point(corners[i1]:x(), edgeY, corners[i1]:z())
      corners[i2] = bolt.point(corners[i2]:x(), edgeY, corners[i2]:z())
    end
  end

  -- edges: south(BL,BR), north(TR,TL), east(BR,TR), west(BL,TL)
  adjustEdge(1, 2, south)
  adjustEdge(3, 4, north)
  adjustEdge(2, 3, east)
  adjustEdge(1, 4, west)

  return corners
end

return M
