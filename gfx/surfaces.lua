local M = {}

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

function M.createColoredSurface(bolt, rgb)
  local size = 4
  local rgbaData = {}
  for y = 0, size - 1 do
    for x = 0, size - 1 do
      rgbaData[#rgbaData + 1] = string.char(rgb[1], rgb[2], rgb[3], 100)
    end
  end
  return bolt.createsurfacefromrgba(size, size, table.concat(rgbaData))
end

return M
