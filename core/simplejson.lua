-- core/simplejson.lua - minimal JSON encode/decode helpers
local M = {}

local ESCAPE_MAP = {
    ['"']  = '\\"',
    ['\\'] = '\\\\',
    ['\b'] = '\\b',
    ['\f'] = '\\f',
    ['\n'] = '\\n',
    ['\r'] = '\\r',
    ['\t'] = '\\t',
}

local UNESCAPE_MAP = {
    ['"']  = '"',
    ['\\'] = '\\',
    ['/']  = '/',
    ['b']  = '\b',
    ['f']  = '\f',
    ['n']  = '\n',
    ['r']  = '\r',
    ['t']  = '\t',
}

local function encodeString(value)
    return '"' .. (value or ""):gsub('[%c\\"%z]', function(char)
        return ESCAPE_MAP[char] or string.format("\\u%04x", char:byte())
    end) .. '"'
end

local function isArray(tbl)
    local maxIndex = 0
    for k, _ in pairs(tbl) do
        if type(k) ~= "number" or k < 1 or k ~= math.floor(k) then
            return false, 0
        end
        if k > maxIndex then
            maxIndex = k
        end
    end
    return true, maxIndex
end

local function encodeValue(value)
    local t = type(value)
    if t == "string" then
        return encodeString(value)
    elseif t == "number" then
        if value ~= value or value == math.huge or value == -math.huge then
            return "null"
        end
        return tostring(value)
    elseif t == "boolean" then
        return value and "true" or "false"
    elseif t == "table" then
        local array, length = isArray(value)
        if array then
            local parts = {}
            for i = 1, length do
                parts[i] = encodeValue(value[i])
            end
            return "[" .. table.concat(parts, ",") .. "]"
        else
            local parts = {}
            for k, v in pairs(value) do
                if type(k) == "string" then
                    parts[#parts + 1] = encodeString(k) .. ":" .. encodeValue(v)
                end
            end
            return "{" .. table.concat(parts, ",") .. "}"
        end
    else
        return "null"
    end
end

function M.encode(value)
    local ok, result = pcall(function()
        return encodeValue(value)
    end)
    if ok then
        return result
    end
    return nil
end

local function createParser(str)
    local len = #str
    local pos = 1

    local function peek()
        return str:sub(pos, pos)
    end

    local function nextChar()
        local char = str:sub(pos, pos)
        pos = pos + 1
        return char
    end

    local function skipWhitespace()
        while pos <= len do
            local c = str:sub(pos, pos)
            if c ~= " " and c ~= "\n" and c ~= "\r" and c ~= "\t" then
                break
            end
            pos = pos + 1
        end
    end

    local function parseNumber()
        local startPos = pos
        if peek() == "-" then
            pos = pos + 1
        end

        while peek():match("%d") do
            pos = pos + 1
        end

        if peek() == "." then
            pos = pos + 1
            while peek():match("%d") do
                pos = pos + 1
            end
        end

        local c = peek()
        if c == "e" or c == "E" then
            pos = pos + 1
            c = peek()
            if c == "+" or c == "-" then
                pos = pos + 1
            end
            while peek():match("%d") do
                pos = pos + 1
            end
        end

        local numberStr = str:sub(startPos, pos - 1)
        local number = tonumber(numberStr)
        if not number then
            error("Invalid number")
        end
        return number
    end

    local function parseUnicodeEscape()
        local hex = str:sub(pos, pos + 3)
        if not hex:match("%x%x%x%x") then
            error("Invalid unicode escape")
        end
        pos = pos + 4
        local codepoint = tonumber(hex, 16)
        if codepoint <= 0x7F then
            return string.char(codepoint)
        elseif codepoint <= 0x7FF then
            local b1 = 0xC0 + math.floor(codepoint / 0x40)
            local b2 = 0x80 + (codepoint % 0x40)
            return string.char(b1, b2)
        elseif codepoint <= 0xFFFF then
            local b1 = 0xE0 + math.floor(codepoint / 0x1000)
            local b2 = 0x80 + (math.floor(codepoint / 0x40) % 0x40)
            local b3 = 0x80 + (codepoint % 0x40)
            return string.char(b1, b2, b3)
        else
            error("Unicode escape out of range")
        end
    end

    local function parseString()
        local quote = nextChar()
        if quote ~= '"' then
            error("Expected '\"' to start string")
        end
        local buffer = {}
        while pos <= len do
            local c = nextChar()
            if c == '"' then
                return table.concat(buffer)
            elseif c == "\\" then
                local esc = nextChar()
                if esc == "u" then
                    buffer[#buffer + 1] = parseUnicodeEscape()
                elseif UNESCAPE_MAP[esc] then
                    buffer[#buffer + 1] = UNESCAPE_MAP[esc]
                else
                    error("Invalid escape sequence: \\" .. tostring(esc))
                end
            else
                buffer[#buffer + 1] = c
            end
        end
        error("Unterminated string")
    end

    local function parseLiteral(literal, value)
        if str:sub(pos, pos + #literal - 1) == literal then
            pos = pos + #literal
            return value
        end
        error("Unexpected literal while parsing JSON")
    end

    local parseValue

    local function parseArray()
        pos = pos + 1 -- skip [
        local array = {}
        skipWhitespace()
        if peek() == "]" then
            pos = pos + 1
            return array
        end
        while true do
            array[#array + 1] = parseValue()
            skipWhitespace()
            local c = nextChar()
            if c == "]" then
                break
            elseif c ~= "," then
                error("Expected ',' or ']' in array")
            end
            skipWhitespace()
        end
        return array
    end

    local function parseObject()
        pos = pos + 1 -- skip {
        local object = {}
        skipWhitespace()
        if peek() == "}" then
            pos = pos + 1
            return object
        end
        while true do
            skipWhitespace()
            local key = parseString()
            skipWhitespace()
            if nextChar() ~= ":" then
                error("Expected ':' after object key")
            end
            skipWhitespace()
            object[key] = parseValue()
            skipWhitespace()
            local c = nextChar()
            if c == "}" then
                break
            elseif c ~= "," then
                error("Expected ',' or '}' in object")
            end
            skipWhitespace()
        end
        return object
    end

    function parseValue()
        skipWhitespace()
        local c = peek()
        if c == "{" then
            return parseObject()
        elseif c == "[" then
            return parseArray()
        elseif c == '"' then
            return parseString()
        elseif c == "-" or c:match("%d") then
            return parseNumber()
        elseif c == "t" then
            return parseLiteral("true", true)
        elseif c == "f" then
            return parseLiteral("false", false)
        elseif c == "n" then
            return parseLiteral("null", nil)
        end
        error("Unexpected character while parsing JSON: " .. tostring(c))
    end

    local function parse()
        local result = parseValue()
        skipWhitespace()
        if pos <= len then
            local leftover = str:sub(pos):match("^%s*$")
            if not leftover then
                error("Unexpected trailing characters in JSON")
            end
        end
        return result
    end

    return parse
end

function M.decode(str)
    if type(str) ~= "string" or str == "" then
        return nil
    end
    local parser = createParser(str)
    local ok, result = pcall(parser)
    if ok then
        return result
    end
    return nil
end

return M
