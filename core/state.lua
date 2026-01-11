local M = {}

local _bolt
local _colors
local _coords

local _renderViewProj = nil
local _markerSurface  = nil
local _markedTiles    = {}
local _frameCount     = 0
local _currentColorIndex = 1
local _lineThickness = 4
local _showTileLabels = true
local _showTileFill = false
local _tileRevision = 0
local _tileFillOpacity = 50

function M.init(deps)
  _bolt   = deps.bolt
  _colors = deps.colors
  _coords = deps.coords
end

function M.getBolt() return _bolt end
function M.getColors() return _colors end
function M.getCoords() return _coords end

function M.getViewProj() return _renderViewProj end
function M.setViewProj(v) _renderViewProj = v end

function M.getMarkerSurface() return _markerSurface end
function M.setMarkerSurface(s) _markerSurface = s end

function M.getMarkedTiles() return _markedTiles end
function M.setMarkedTiles(tbl)
  _markedTiles = tbl
  _tileRevision = _tileRevision + 1
end

function M.bumpTileRevision()
  _tileRevision = _tileRevision + 1
end

function M.getTileRevision()
  return _tileRevision
end

function M.incFrame() _frameCount = _frameCount + 1 end
function M.getFrame() return _frameCount end

function M.getCurrentColorIndex() return _currentColorIndex end
function M.setCurrentColorIndex(i) _currentColorIndex = i end

function M.getLineThickness() return _lineThickness end
function M.setLineThickness(t)
  if type(t) == "number" and t >= 2 and t <= 8 then
    _lineThickness = math.floor(t)
  end
end

function M.getShowTileLabels() return _showTileLabels end
function M.setShowTileLabels(flag)
  _showTileLabels = flag and true or false
end

function M.getShowTileFill() return _showTileFill end
function M.setShowTileFill(flag)
  _showTileFill = flag and true or false
end

function M.getTileFillOpacity() return _tileFillOpacity end
function M.setTileFillOpacity(value)
  if type(value) == "number" then
    local clamped = math.max(5, math.min(100, math.floor(value + 0.5)))
    _tileFillOpacity = clamped
  end
end

return M
