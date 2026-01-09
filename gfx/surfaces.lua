local M = {}

local function clampByte(value)
    if type(value) ~= "number" then return 0 end
    value = math.floor(value + 0.5)
    if value < 0 then value = 0 end
    if value > 255 then value = 255 end
    return value
end

function M.createMarkerSurface(bolt)
  local size = 4
  local rgbaData = {}
  for y = 0, size - 1 do
    for x = 0, size - 1 do
      rgbaData[#rgbaData + 1] = string.char(0, 255, 255, 100)
    end
  end
  return bolt.createsurfacefromrgba(size, size, table.concat(rgbaData))
end

function M.createColoredSurface(bolt, rgb, alpha)
  local size = 4
  local rgbaData = {}
  local a = clampByte(alpha or 100)
  for y = 0, size - 1 do
    for x = 0, size - 1 do
      rgbaData[#rgbaData + 1] = string.char(rgb[1], rgb[2], rgb[3], a)
    end
  end
  return bolt.createsurfacefromrgba(size, size, table.concat(rgbaData))
end

return M
