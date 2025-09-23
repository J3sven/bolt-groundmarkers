local M = {}

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

local function sampleHeight(bolt, state, x, z, fallbackY)
  if state and state.getHeightAt then
    local ok, y = pcall(state.getHeightAt, x, z)
    if ok and type(y) == "number" then return y end
  end
  if bolt and bolt.groundheight then
    local ok, y = pcall(bolt.groundheight, x, z)
    if ok and type(y) == "number" then return y end
  end
  return fallbackY or 0
end

function M.gridVertexToWorldPoint(bolt, state, coords, gx, gz, fallbackY)
  local S = coords.TILE_SIZE
  local wx = gx * S
  local wz = gz * S
  local wy = sampleHeight(bolt, state, wx, wz, fallbackY)
  return bolt.point(wx, wy, wz)
end

return M
