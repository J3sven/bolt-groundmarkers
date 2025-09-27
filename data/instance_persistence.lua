-- instance_persistence.lua
local M = {}

local SAVE_FILE  = "instance_profiles.json"
local DEBUG_FILE = "instance_debug.txt"

local function now(b)
  if b and type(b.time) == "function" then
    local ok, t = pcall(b.time)
    if ok and type(t) == "number" then return t end
  end
  return 0
end

local function pad(n)
  n = tonumber(n) or 0
  if n < 10 then return "000" .. n
  elseif n < 100 then return "00" .. n
  elseif n < 1000 then return "0" .. n
  else return tostring(n) end
end

local function ensureReverseIndex(state)
  state.byFp = state.byFp or {}
end

local function rebuildReverseIndex(state)
  state.byFp = {}
  for _, inst in ipairs(state.instances or {}) do
    for fp, _ in pairs(inst.fingerprints or {}) do
      state.byFp[fp] = inst.id
    end
  end
end

local function calculateConfidence(inst)
  if not inst or not inst.fingerprints then return 0 end
  
  local totalObservations = 0
  local uniqueFingerprints = 0
  
  for fp, count in pairs(inst.fingerprints) do
    totalObservations = totalObservations + count
    uniqueFingerprints = uniqueFingerprints + 1
  end
  
  local confidence = math.min(10, (totalObservations * 0.5) + (uniqueFingerprints * 1.5))
  return math.floor(confidence * 10) / 10 -- Round to 1 decimal
end

local function emptyState()
  local s = { version = 1, nextId = 1, instances = {}, byFp = {} }
  rebuildReverseIndex(s)
  return s
end

local function fromDecodedTable(t)
  local state = emptyState()
  if type(t) ~= "table" then return state end
  state.version   = tonumber(t.version) or 1
  state.nextId    = tonumber(t.nextId) or 1
  state.instances = {}

  if type(t.instances) == "table" then
    for _, inst in ipairs(t.instances) do
      if type(inst) == "table" and type(inst.id) == "string" then
        local ctx = inst.context or {}
        local newInst = {
          id    = inst.id,
          label = type(inst.label) == "string" and inst.label or nil,
          firstSeen = tonumber(inst.firstSeen), -- may be nil; fixed in load()
          lastSeen  = tonumber(inst.lastSeen),  -- may be nil; fixed in load()
          context = {
            floor  = tonumber(ctx.floor) or 0,
          },
          fingerprints = type(inst.fingerprints) == "table" and inst.fingerprints or {},
          confidence = tonumber(inst.confidence) or 0
        }
        
        -- Recalculate confidence if not present
        if not inst.confidence then
          newInst.confidence = calculateConfidence(newInst)
        end
        
        table.insert(state.instances, newInst)
      end
    end
  end

  rebuildReverseIndex(state)
  return state
end

local function manualDecode(jsonStr)
  local ok, data = pcall(function()
    local out = { version = 1, nextId = 1, instances = {} }
    out.version = tonumber(jsonStr:match('%"version%":%s*(%d+)')) or 1
    out.nextId  = tonumber(jsonStr:match('%"nextId%":%s*(%d+)')) or 1

    local instancesBlock = jsonStr:match('%"instances%":%s*%[(.*)%]%s*}')
    if instancesBlock then
      for instStr in instancesBlock:gmatch('{(.-)}') do
        local id = instStr:match('%"id%":%s*%"(.-)%"')
        if id then
          local floor   = tonumber(instStr:match('%"floor%":%s*(-?%d+)')) or 0
          local firstSeen = tonumber(instStr:match('%"firstSeen%":%s*(%d+)'))
          local lastSeen  = tonumber(instStr:match('%"lastSeen%":%s*(%d+)'))
          local confidence = tonumber(instStr:match('%"confidence%":%s*([%d%.]+)')) or 0

          local fps = {}
          local fpsBlock = instStr:match('%"fingerprints%":%s*{(.-)}')
          if fpsBlock then
            for k, v in fpsBlock:gmatch('%"([^"]+)%":%s*(%d+)') do
              fps[k] = tonumber(v)
            end
          end

          local newInst = {
            id = id,
            label = instStr:match('%"label%":%s*%"(.-)%"'),
            firstSeen = firstSeen,
            lastSeen  = lastSeen,
            context = { floor = floor },
            fingerprints = fps,
            confidence = confidence
          }
          
          -- Recalculate confidence if missing
          if confidence == 0 then
            newInst.confidence = calculateConfidence(newInst)
          end

          table.insert(out.instances, newInst)
        end
      end
    end
    return out
  end)
  if ok then return data else return emptyState() end
end

local function toJsonTable(state)
  local t = { version = 1, nextId = state.nextId or 1, instances = {} }
  for _, inst in ipairs(state.instances or {}) do
    table.insert(t.instances, {
      id = inst.id,
      label = inst.label,
      firstSeen = inst.firstSeen,
      lastSeen  = inst.lastSeen,
      context = {
        floor  = inst.context and inst.context.floor  or 0,
      },
      fingerprints = inst.fingerprints or {},
      confidence = calculateConfidence(inst)
    })
  end
  return t
end


function M.load(bolt)
  local ok, stateOrErr = pcall(function()
    local saved = nil
    if bolt and type(bolt.loadconfig) == "function" then
      saved = bolt.loadconfig(SAVE_FILE)
    end
    local state

    if saved and saved ~= "" then
      local success, decoded = false, nil

      if bolt and bolt.json and bolt.json.decode then
        success, decoded = pcall(bolt.json.decode, saved)
      end
      if not success and bolt and type(bolt.loadjson) == "function" then
        success, decoded = pcall(bolt.loadjson, SAVE_FILE)
      end
      if success and type(decoded) == "table" then
        state = fromDecodedTable(decoded)
      else
        state = fromDecodedTable(manualDecode(saved))
      end
    else
      state = emptyState()
    end

    ensureReverseIndex(state)
    rebuildReverseIndex(state)

    local tnow = now(bolt)
    for _, inst in ipairs(state.instances or {}) do
      if type(inst.firstSeen) ~= "number" then inst.firstSeen = tnow end
      if type(inst.lastSeen)  ~= "number" then inst.lastSeen  = tnow end
    end

    return state
  end)

  if not ok then
    if bolt and type(bolt.saveconfig) == "function" then
      bolt.saveconfig(DEBUG_FILE, "LOAD ERROR: " .. tostring(stateOrErr))
    end
    return emptyState()
  end

  local state = stateOrErr
  if bolt and type(bolt.saveconfig) == "function" then
    bolt.saveconfig(DEBUG_FILE, ("Loaded %d instances; nextId=%d"):format(#(state.instances or {}), state.nextId or 1))
  end
  return state
end

function M.save(bolt, state)
  local ok, err = pcall(function()
    ensureReverseIndex(state)
    local asTable = toJsonTable(state)

    if bolt and bolt.json and bolt.json.encode then
      local success, jsonString = pcall(bolt.json.encode, asTable)
      if success and jsonString and type(bolt.saveconfig) == "function" then
        bolt.saveconfig(SAVE_FILE, jsonString)
        bolt.saveconfig(DEBUG_FILE, "Saved instances (" .. #asTable.instances .. ")")
        return
      end
    elseif bolt and type(bolt.savejson) == "function" then
      pcall(bolt.savejson, SAVE_FILE, asTable)
      if type(bolt.saveconfig) == "function" then
        bolt.saveconfig(DEBUG_FILE, "Saved instances (via bolt.savejson)")
      end
      return
    end

    -- Manual encoder fallback
    local lines = {'{'}
    table.insert(lines, '  "version": 1,')
    table.insert(lines, '  "nextId": ' .. (asTable.nextId or 1) .. ',')
    table.insert(lines, '  "instances": [')
    for i, inst in ipairs(asTable.instances) do
      local fpsLines = {}
      for fp, cnt in pairs(inst.fingerprints or {}) do
        table.insert(fpsLines, string.format('"%s": %d', fp, cnt))
      end
      local fpsJson = "{" .. table.concat(fpsLines, ", ") .. "}"
      local comma = i < #asTable.instances and ',' or ''
      table.insert(lines, string.format(
        '    {"id": "%s", "label": %s, "firstSeen": %d, "lastSeen": %d, "context": {"floor": %d}, "fingerprints": %s, "confidence": %.1f}%s',
        tostring(inst.id or ""),
        inst.label and string.format('"%s"', inst.label) or 'null',
        tonumber(inst.firstSeen) or 0,
        tonumber(inst.lastSeen)  or 0,
        tonumber(inst.context and inst.context.floor) or 0,
        fpsJson,
        tonumber(inst.confidence) or 0,
        comma
      ))
    end
    table.insert(lines, '  ]')
    table.insert(lines, '}')

    if bolt and type(bolt.saveconfig) == "function" then
      bolt.saveconfig(SAVE_FILE, table.concat(lines, '\n'))
      bolt.saveconfig(DEBUG_FILE, "Saved instances (" .. #asTable.instances .. ") [manual]")
    end
  end)
  if not ok and bolt and type(bolt.saveconfig) == "function" then
    bolt.saveconfig(DEBUG_FILE, "SAVE ERROR: " .. tostring(err))
  end
end

-- Exact fingerprint match
function M.findByFingerprint(state, fp)
  if not state or not fp then return nil end
  ensureReverseIndex(state)
  local id = state.byFp[fp]
  if not id then return nil end
  for _, inst in ipairs(state.instances or {}) do
    if inst.id == id then return inst end
  end
  return nil
end

function M.createInstance(state, context, bolt)
  ensureReverseIndex(state)
  state.nextId = (tonumber(state.nextId) or 1)
  local id = ("inst_%04d"):format(state.nextId)
  state.nextId = state.nextId + 1

  local inst = {
    id = id,
    label = nil,
    firstSeen = now(bolt),
    lastSeen  = now(bolt),
    context = {
      floor  = tonumber(context and context.floor) or 0,
    },
    fingerprints = {},
    confidence = 0
  }
  state.instances = state.instances or {}
  table.insert(state.instances, inst)
  return inst
end

function M.addFingerprint(state, inst, fp, bolt)
  if not (state and inst and fp) then return end
  ensureReverseIndex(state)
  inst.fingerprints = inst.fingerprints or {}
  inst.fingerprints[fp] = (tonumber(inst.fingerprints[fp]) or 0) + 1
  inst.lastSeen = now(bolt)
  inst.confidence = calculateConfidence(inst)
  state.byFp[fp] = inst.id
end

function M.describe(inst)
  if not inst then return "unknown" end
  local ctx = inst.context or {}
  return string.format("%s (floor=%d, confidence=%.1f, fps=%d)",
    tostring(inst.id or "inst_????"),
    tonumber(ctx.floor) or 0,
    inst.confidence or 0,
    inst.fingerprints and table.getn and table.getn(inst.fingerprints) or 0
  )
end

function M.getInstancesByConfidence(state)
  if not state or not state.instances then return {} end
  
  local sorted = {}
  for _, inst in ipairs(state.instances) do
    inst.confidence = calculateConfidence(inst)
    table.insert(sorted, inst)
  end
  
  table.sort(sorted, function(a, b) return a.confidence > b.confidence end)
  return sorted
end

return M