local M = {}

local COLOR_PRESETS = {
  {0, 255, 255},    -- Cyan
  {255, 100, 100},  -- Red
  {100, 255, 100},  -- Green
  {255, 255, 100},  -- Yellow
  {255, 150, 255},  -- Magenta
  {150, 150, 255},  -- Light Blue
  {255, 200, 100},  -- Orange
  {200, 100, 255},  -- Purple
}

local COLOR_NAMES = {
  "Cyan", "Red", "Green", "Yellow", "Magenta", "Light Blue", "Orange", "Purple"
}

function M.list() return COLOR_PRESETS end
function M.get(index) return COLOR_PRESETS[index] or COLOR_PRESETS[1] end
function M.count() return #COLOR_PRESETS end
function M.getColorName(index) return COLOR_NAMES[index] or "Unknown" end

function M.setColorIndex(state, bolt, newIndex)
  local n = #COLOR_PRESETS
  local wrapped = ((newIndex - 1) % n) + 1
  state.setCurrentColorIndex(wrapped)
  if bolt then
    bolt.saveconfig("marker_debug.txt", string.format("Selected color: %s", M.getColorName(wrapped)))
  end
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

return M
