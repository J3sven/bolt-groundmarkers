local M = {}

local shaderProgram = nil

local screenWidth = 1920
local screenHeight = 1080

local BYTES_PER_VERTEX = 28
local UNIFORM_SCREEN = 3
local UNIFORM_HALF_THICKNESS = 4

function M.setScreenDimensions(w, h)
  screenWidth = (w and w > 0) and w or screenWidth
  screenHeight = (h and h > 0) and h or screenHeight
end

local function createVertexShader(bolt)
  return bolt.createvertexshader(
    "layout(location=0) in highp vec2 surfacePos;" ..
    "layout(location=1) in highp vec4 inColor;" ..
    "layout(location=2) in highp float edgeCoord;" ..
    "layout(location=3) uniform highp vec2 screenSize;" ..
    "out highp vec4 vColor;" ..
    "out highp float vEdgeCoord;" ..
    "void main() {" ..
      "vColor = inColor;" ..
      "vEdgeCoord = edgeCoord;" ..
      "highp vec2 normPos = surfacePos / screenSize;" ..
      "highp vec2 ndc = normPos * 2.0 - 1.0;" ..
      "gl_Position = vec4(ndc, 0.0, 1.0);" ..
    "}"
  )
end

local function createFragmentShader(bolt)
  return bolt.createfragmentshader(
    "in highp vec4 vColor;" ..
    "in highp float vEdgeCoord;" ..
    "layout(location=4) uniform highp float halfThickness;" ..
    "out highp vec4 fragColor;" ..
    "void main() {" ..
      "highp float coverage = 1.0;" ..
      "if (halfThickness > 0.0) {" ..
        "const highp float FEATHER_PX = 1.0;" ..
        "highp float distToEdge = 1.0 - clamp(abs(vEdgeCoord), 0.0, 1.0);" ..
        "highp float feather = clamp(FEATHER_PX / (halfThickness + 0.0001), 0.0, 1.0);" ..
        "coverage = smoothstep(0.0, feather, distToEdge);" ..
      "}" ..
      "fragColor = vec4(vColor.rgb, vColor.a * coverage);" ..
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

  shaderProgram:setattribute(0, 4, true, true, 2, 0, BYTES_PER_VERTEX)
  shaderProgram:setattribute(1, 4, true, true, 4, 8, BYTES_PER_VERTEX)
  shaderProgram:setattribute(2, 4, true, true, 1, 24, BYTES_PER_VERTEX)
end

local function addVertex(buf, offset, px, py, r, g, b, a, edgeCoord)
  buf:setfloat32(offset + 0, px)
  buf:setfloat32(offset + 4, py)
  buf:setfloat32(offset + 8, r)
  buf:setfloat32(offset + 12, g)
  buf:setfloat32(offset + 16, b)
  buf:setfloat32(offset + 20, a)
  buf:setfloat32(offset + 24, edgeCoord or 0.0)
  return offset + BYTES_PER_VERTEX
end

local renderSurface = nil
local renderSurfaceW = 0
local renderSurfaceH = 0

function M.drawQuadsShader(bolt, quads, viewportX, viewportY)
  if not shaderProgram then M.init(bolt) end
  if #quads == 0 then return end

  if not renderSurface or renderSurfaceW ~= screenWidth or renderSurfaceH ~= screenHeight then
    renderSurface = bolt.createsurface(screenWidth, screenHeight)
    renderSurface:setalpha(1.0)
    renderSurfaceW = screenWidth
    renderSurfaceH = screenHeight
  end

  local numQuads = #quads
  local vertexCount = numQuads * 6
  local bufferSize = vertexCount * BYTES_PER_VERTEX

  local buf = bolt.createbuffer(bufferSize)

  local offset = 0
  for i, quad in ipairs(quads) do
    local x1, y1 = quad.x1, quad.y1
    local x2, y2 = quad.x2, quad.y2
    local x3, y3 = quad.x3, quad.y3
    local x4, y4 = quad.x4, quad.y4
    local r = (quad.r or 255) / 255.0
    local g = (quad.g or 255) / 255.0
    local b = (quad.b or 255) / 255.0
    local a = (quad.a or 255) / 255.0

    offset = addVertex(buf, offset, x1, y1, r, g, b, a, 0.0)
    offset = addVertex(buf, offset, x2, y2, r, g, b, a, 0.0)
    offset = addVertex(buf, offset, x3, y3, r, g, b, a, 0.0)

    offset = addVertex(buf, offset, x1, y1, r, g, b, a, 0.0)
    offset = addVertex(buf, offset, x3, y3, r, g, b, a, 0.0)
    offset = addVertex(buf, offset, x4, y4, r, g, b, a, 0.0)
  end

  renderSurface:clear()
  shaderProgram:setuniform2f(UNIFORM_SCREEN, screenWidth, screenHeight)
  shaderProgram:setuniform1f(UNIFORM_HALF_THICKNESS, -1.0)

  local shaderbuf = bolt.createshaderbuffer(buf)
  shaderProgram:drawtosurface(renderSurface, shaderbuf, vertexCount)

  local vx = viewportX or 0
  local vy = viewportY or 0
  renderSurface:drawtoscreen(0, 0, screenWidth, screenHeight, vx, vy, screenWidth, screenHeight)

  buf = nil
  shaderbuf = nil
end

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
  local bufferSize = vertexCount * BYTES_PER_VERTEX

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

    offset = addVertex(buf, offset, px1_top, py1_top, r, g, b, a, 1.0)
    offset = addVertex(buf, offset, px1_bot, py1_bot, r, g, b, a, -1.0)
    offset = addVertex(buf, offset, px2_top, py2_top, r, g, b, a, 1.0)

    offset = addVertex(buf, offset, px1_bot, py1_bot, r, g, b, a, -1.0)
    offset = addVertex(buf, offset, px2_bot, py2_bot, r, g, b, a, -1.0)
    offset = addVertex(buf, offset, px2_top, py2_top, r, g, b, a, 1.0)
  end

  renderSurface:clear()

  shaderProgram:setuniform2f(UNIFORM_SCREEN, screenWidth, screenHeight)
  local uniformThickness = 2.0
  for i = 1, #lines do
    if type(lines[i].thickness) == "number" then
      uniformThickness = lines[i].thickness
      break
    end
  end
  shaderProgram:setuniform1f(UNIFORM_HALF_THICKNESS, math.max(0.5, uniformThickness) / 2.0)

  local shaderbuf = bolt.createshaderbuffer(buf)
  shaderProgram:drawtosurface(renderSurface, shaderbuf, vertexCount)

  local vx = viewportX or 0
  local vy = viewportY or 0
  renderSurface:drawtoscreen(0, 0, screenWidth, screenHeight, vx, vy, screenWidth, screenHeight)

  buf = nil
  shaderbuf = nil
end

return M
