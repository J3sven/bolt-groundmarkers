local M = {}

local shaderProgram = nil

local screenWidth = 1920
local screenHeight = 1080

function M.setScreenDimensions(w, h)
  screenWidth = (w and w > 0) and w or screenWidth
  screenHeight = (h and h > 0) and h or screenHeight
end

local function createVertexShader(bolt)
  return bolt.createvertexshader(
    "layout(location=0) in highp vec2 surfacePos;" ..
    "layout(location=1) in highp vec4 inColor;" ..
    "layout(location=2) uniform highp vec2 screenSize;" ..
    "out highp vec4 vColor;" ..
    "void main() {" ..
      "vColor = inColor;" ..
      "highp vec2 normPos = surfacePos / screenSize;" ..
      "highp vec2 ndc = normPos * 2.0 - 1.0;" ..
      "gl_Position = vec4(ndc, 0.0, 1.0);" ..
    "}"
  )
end

local function createFragmentShader(bolt)
  return bolt.createfragmentshader(
    "in highp vec4 vColor;" ..
    "out highp vec4 fragColor;" ..
    "void main() {" ..
      "fragColor = vColor;" ..
    "}"
  )
end

function M.init(bolt)
  shaderProgram = nil

  local vs = createVertexShader(bolt)
  local fs = createFragmentShader(bolt)
  shaderProgram = bolt.createshaderprogram(vs, fs)

  vs = nil
  fs = nil

  local bytesPerVertex = 24 

  shaderProgram:setattribute(0, 4, true, true, 2, 0, bytesPerVertex)
  shaderProgram:setattribute(1, 4, true, true, 4, 8, bytesPerVertex)
end

local function addVertex(buf, offset, px, py, r, g, b, a)
  buf:setfloat32(offset + 0, px)
  buf:setfloat32(offset + 4, py)
  buf:setfloat32(offset + 8, r)
  buf:setfloat32(offset + 12, g)
  buf:setfloat32(offset + 16, b)
  buf:setfloat32(offset + 20, a)
  return offset + 24
end

local renderSurface = nil
local renderSurfaceW = 0
local renderSurfaceH = 0

function M.drawLinesShader(bolt, lines, viewportX, viewportY)
  if not shaderProgram then M.init(bolt) end
  if #lines == 0 then return end

  if not renderSurface or renderSurfaceW ~= screenWidth or renderSurfaceH ~= screenHeight then
    renderSurface = bolt.createsurface(screenWidth, screenHeight)
    renderSurface:setalpha(1.0)
    renderSurfaceW = screenWidth
    renderSurfaceH = screenHeight
  end

  local numLines = #lines
  local vertexCount = numLines * 6
  local bytesPerVertex = 24
  local bufferSize = vertexCount * bytesPerVertex

  local buf = bolt.createbuffer(bufferSize)

  local offset = 0
  for i, line in ipairs(lines) do
    local x1, y1, x2, y2 = line.x1, line.y1, line.x2, line.y2
    local thickness = line.thickness or 2.0
    local r = (line.r or 255) / 255.0
    local g = (line.g or 255) / 255.0
    local b = (line.b or 255) / 255.0
    local a = (line.a or 255) / 255.0

    local dx = x2 - x1
    local dy = y2 - y1
    local len = math.sqrt(dx * dx + dy * dy)
    if len < 0.001 then len = 0.001 end

    local px = (-dy / len) * (thickness / 2.0)
    local py = (dx / len) * (thickness / 2.0)

    local px1_top = x1 + px
    local py1_top = y1 + py
    local px1_bot = x1 - px
    local py1_bot = y1 - py
    local px2_top = x2 + px
    local py2_top = y2 + py
    local px2_bot = x2 - px
    local py2_bot = y2 - py

    offset = addVertex(buf, offset, px1_top, py1_top, r, g, b, a)
    offset = addVertex(buf, offset, px1_bot, py1_bot, r, g, b, a)
    offset = addVertex(buf, offset, px2_top, py2_top, r, g, b, a)

    offset = addVertex(buf, offset, px1_bot, py1_bot, r, g, b, a)
    offset = addVertex(buf, offset, px2_bot, py2_bot, r, g, b, a)
    offset = addVertex(buf, offset, px2_top, py2_top, r, g, b, a)
  end

  renderSurface:clear()

  shaderProgram:setuniform2f(2, screenWidth, screenHeight)

  local shaderbuf = bolt.createshaderbuffer(buf)
  shaderProgram:drawtosurface(renderSurface, shaderbuf, vertexCount)

  local vx = viewportX or 0
  local vy = viewportY or 0
  renderSurface:drawtoscreen(0, 0, screenWidth, screenHeight, vx, vy, screenWidth, screenHeight)

  buf = nil
  shaderbuf = nil
end

return M
