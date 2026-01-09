local M = {}

local PALETTE_FILE = "color_palette.json"

local DEFAULT_PALETTE = {
  { name = "Cyan",       rgb = {0, 255, 255} },
  { name = "Red",        rgb = {255, 100, 100} },
  { name = "Green",      rgb = {100, 255, 100} },
  { name = "Yellow",     rgb = {255, 255, 100} },
  { name = "Magenta",    rgb = {255, 150, 255} },
  { name = "Light Blue", rgb = {150, 150, 255} },
  { name = "Orange",     rgb = {255, 200, 100} },
  { name = "Purple",     rgb = {200, 100, 255} },
}

local palette = {}
local boltRef = nil

local function clampByte(value)
  if type(value) ~= "number" then return 0 end
  value = math.floor(value + 0.5)
  if value < 0 then value = 0 end
  if value > 255 then value = 255 end
  return value
end

local function copyEntry(entry)
  return {
    name = entry.name,
    rgb = { entry.rgb[1], entry.rgb[2], entry.rgb[3] }
  }
end

local function resetPalette()
  palette = {}
  for i, entry in ipairs(DEFAULT_PALETTE) do
    palette[i] = copyEntry(entry)
  end
end

resetPalette()

local function rgbToHex(rgb)
  return string.format("#%02x%02x%02x", clampByte(rgb[1]), clampByte(rgb[2]), clampByte(rgb[3]))
end

local function savePalette(bolt)
  local targetBolt = bolt or boltRef
  if not targetBolt then return false end

  local data = { colors = {} }
  for i, entry in ipairs(palette) do
    data.colors[i] = {
      name = entry.name,
      r = entry.rgb[1],
      g = entry.rgb[2],
      b = entry.rgb[3]
    }
  end

  local ok, encoded = false, nil
  if targetBolt.json and targetBolt.json.encode then
    ok, encoded = pcall(targetBolt.json.encode, data)
  end

  if ok and encoded then
    targetBolt.saveconfig(PALETTE_FILE, encoded)
    return true
  end

  local lines = {"{\"colors\":["}
  for i, entry in ipairs(data.colors) do
    local comma = (i < #data.colors) and "," or ""
    table.insert(lines, string.format(
      '{"name":"%s","r":%d,"g":%d,"b":%d}%s',
      (entry.name or ""):gsub('"', '\\"'),
      entry.r, entry.g, entry.b, comma
    ))
  end
  table.insert(lines, "]}")
  targetBolt.saveconfig(PALETTE_FILE, table.concat(lines))
  return true
end

local function applyPaletteData(data)
  if not data or type(data.colors) ~= "table" then
    return
  end

  for i, entry in ipairs(data.colors) do
    if palette[i] and type(entry) == "table" then
      local r = clampByte(entry.r or entry[1] or palette[i].rgb[1])
      local g = clampByte(entry.g or entry[2] or palette[i].rgb[2])
      local b = clampByte(entry.b or entry[3] or palette[i].rgb[3])
      palette[i] = {
        name = entry.name or palette[i].name or ("Color " .. i),
        rgb = { r, g, b }
      }
    end
  end
end

function M.init(bolt)
  boltRef = bolt
  resetPalette()

  if not bolt then
    return
  end

  local raw = bolt.loadconfig(PALETTE_FILE)
  local decoded = nil

  if raw and raw ~= "" then
    if bolt.json and bolt.json.decode then
      local ok, data = pcall(bolt.json.decode, raw)
      if ok and type(data) == "table" then
        decoded = data
      end
    end

    if not decoded and bolt.loadjson then
      local ok, data = pcall(bolt.loadjson, PALETTE_FILE)
      if ok and type(data) == "table" then
        decoded = data
      end
    end
  end

  if decoded then
    applyPaletteData(decoded)
  end
end

function M.list()
  local list = {}
  for i, entry in ipairs(palette) do
    list[i] = { entry.rgb[1], entry.rgb[2], entry.rgb[3] }
  end
  return list
end

function M.get(index)
  return (palette[index] and palette[index].rgb) or (palette[1] and palette[1].rgb) or {0, 255, 255}
end

function M.count()
  return #palette
end

function M.getColorName(index)
  if palette[index] and palette[index].name then
    return palette[index].name
  end
  return "Color " .. tostring(index)
end

function M.setColorIndex(state, bolt, newIndex)
  local n = #palette
  if n == 0 then return end
  local wrapped = ((newIndex - 1) % n) + 1
  state.setCurrentColorIndex(wrapped)
end

function M.stepColor(state, bolt, forward)
  local idx = state.getCurrentColorIndex()
  if forward then
    M.setColorIndex(state, bolt, idx + 1)
  else
    M.setColorIndex(state, bolt, idx - 1)
  end
end

function M.cycleColor(state, bolt)
  M.stepColor(state, bolt, true)
end

function M.getPalette()
  local copy = {}
  for i, entry in ipairs(palette) do
    copy[i] = {
      name = entry.name,
      rgb = { entry.rgb[1], entry.rgb[2], entry.rgb[3] }
    }
  end
  return copy
end

function M.getPaletteForUI()
  local result = {}
  for i, entry in ipairs(palette) do
    result[#result + 1] = {
      index = i,
      name = entry.name,
      hex = rgbToHex(entry.rgb),
      rgb = { entry.rgb[1], entry.rgb[2], entry.rgb[3] }
    }
  end
  return result
end

function M.hexToRgb(hex)
  if type(hex) ~= "string" then
    return nil
  end

  local cleaned = hex:gsub("#", "")
  if #cleaned ~= 6 then
    return nil
  end

  local r = tonumber(cleaned:sub(1, 2), 16)
  local g = tonumber(cleaned:sub(3, 4), 16)
  local b = tonumber(cleaned:sub(5, 6), 16)

  if not (r and g and b) then
    return nil
  end

  return { clampByte(r), clampByte(g), clampByte(b) }
end

function M.setPaletteEntry(index, rgb, name, bolt)
  if not palette[index] or type(rgb) ~= "table" then
    return false
  end

  local r = clampByte(rgb.r or rgb[1])
  local g = clampByte(rgb.g or rgb[2])
  local b = clampByte(rgb.b or rgb[3])

  palette[index].rgb = { r, g, b }
  if type(name) == "string" then
    local trimmed = name:match("^%s*(.-)%s*$")
    if trimmed ~= "" then
      palette[index].name = trimmed
    end
  end

  savePalette(bolt)

  return true
end

return M
