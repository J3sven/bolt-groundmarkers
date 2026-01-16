local M = {}

local boltRef = nil
local glyphCache = {}

local SPECIAL_GLYPHS = {
    ["?"] = "question",
    ["!"] = "exclamation",
    ["#"] = "hash",
    ["$"] = "dollar"
}

local VALID_CHARS = {}
for char in ("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"):gmatch(".") do
    VALID_CHARS[char] = true
end
for symbol in pairs(SPECIAL_GLYPHS) do
    VALID_CHARS[symbol] = true
end

local LETTER_SPACING = 0
local LINE_HEIGHT_PX = 32
local SPACE_WIDTH = math.floor(LINE_HEIGHT_PX * 0.35 + 0.5)
local DEFAULT_GLYPH_WIDTH = math.floor(LINE_HEIGHT_PX * 0.6 + 0.5)

local function loadGlyphSurface(name)
    if not (boltRef and boltRef.createsurfacefrompng) then
        return nil
    end

    local ok, surface, width, height = pcall(boltRef.createsurfacefrompng, string.format("gfx.glyphs.%s", name))
    if not ok or not surface then
        return nil
    end

    return {
        surface = surface,
        width = width or DEFAULT_GLYPH_WIDTH,
        height = height or LINE_HEIGHT_PX
    }
end

local function loadGlyph(char)
    local isSpecial = SPECIAL_GLYPHS[char]
    local cacheKey = isSpecial and char or char:upper()
    local cached = glyphCache[cacheKey]
    if cached ~= nil then
        return cached or nil
    end

    if not VALID_CHARS[cacheKey] then
        glyphCache[cacheKey] = false
        return nil
    end

    local glyph
    if isSpecial then
        glyph = loadGlyphSurface(SPECIAL_GLYPHS[char])
    else
        glyph = loadGlyphSurface(cacheKey)
    end

    glyphCache[cacheKey] = glyph or false
    return glyph
end

local function measure(text, scale)
    local totalWidth = 0
    local length = #text
    local maxHeight = LINE_HEIGHT_PX

    for i = 1, length do
        local ch = text:sub(i, i)

        local advance = SPACE_WIDTH
        local glyphHeight = LINE_HEIGHT_PX
        if ch ~= " " then
            local glyph = loadGlyph(ch)
            if glyph then
                advance = glyph.width
                glyphHeight = glyph.height or glyphHeight
            end
        end

        if glyphHeight > maxHeight then
            maxHeight = glyphHeight
        end

        totalWidth = totalWidth + (advance * scale)
        if i < length then
            totalWidth = totalWidth + (LETTER_SPACING * scale)
        end
    end

    return totalWidth, (maxHeight * scale)
end

local function drawTextString(text, centerX, centerY, scale)
    local width, height = measure(text, scale)
    local cursorX = centerX - (width / 2)
    local topY = centerY - (height / 2)

    for i = 1, #text do
        local ch = text:sub(i, i)

        local advance = SPACE_WIDTH * scale
        if ch ~= " " then
            local glyph = loadGlyph(ch)
            if glyph and glyph.surface then
                local glyphWidth = glyph.width
                local glyphHeight = glyph.height or LINE_HEIGHT_PX
                local destW = glyphWidth * scale
                local destH = glyphHeight * scale
                glyph.surface:drawtoscreen(0, 0, glyphWidth, glyphHeight, cursorX, topY, destW, destH)
                advance = destW
            else
                advance = DEFAULT_GLYPH_WIDTH * scale
            end
        end

        cursorX = cursorX + advance
        if i < #text then
            cursorX = cursorX + (LETTER_SPACING * scale)
        end
    end
end

function M.init(bolt)
    boltRef = bolt
end

function M.draw(text, centerX, centerY, scale)
    if not text or text == "" then
        return
    end

    local normalized = text:upper():gsub("[^A-Z0-9 ?!#$]", " ")
    if normalized == "" then
        return
    end

    drawTextString(normalized, centerX, centerY, scale or 1)
end

return M
