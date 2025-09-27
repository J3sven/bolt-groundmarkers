-- core/instances.lua - Fixed Drop-In Replacement with Conservative Matching
local M = {}

local instancePersist = require('data.instance_persistence')

-- Recognition confidence levels for JIT decision making
local CONFIDENCE_LEVELS = {
    UNKNOWN = 0,        -- New instance, no matches yet
    WEAK = 1,           -- Few fingerprint matches, could be coincidence  
    MODERATE = 2,       -- Some fingerprint matches, likely correct
    STRONG = 3,         -- Many fingerprint matches, very confident
    CERTAIN = 4         -- Overwhelming matches + validation, definitely correct
}

-- AGGRESSIVE COLLECTION SETTINGS (unchanged)
local ANALYSIS_INTERVAL = 25        -- Much more frequent sampling
local FINGERPRINT_INTERVAL = 60     -- Generate fingerprints every 60 swaps  
local MIN_ANALYSIS_SAMPLES = 8     -- Lower threshold for fingerprint generation
local MIN_FINGERPRINTS_PER_SESSION = 8  -- Collect many more fingerprints
local EXTENDED_SESSION_TIME = 1200   -- Collect for longer (20 minutes worth)

-- MUCH MORE CONSERVATIVE MATCHING THRESHOLDS
local PROGRESSIVE_THRESHOLDS = {
    MIN_FINGERPRINTS_FOR_WEAK = 3,        -- Increased from 2
    MIN_FINGERPRINTS_FOR_MODERATE = 5,    -- Increased from 3  
    MIN_FINGERPRINTS_FOR_STRONG = 8,      -- Increased from 5
    MIN_OVERLAP_FOR_WEAK = 2,             -- Increased from 1
    MIN_OVERLAP_FOR_MODERATE = 3,         -- Increased from 2
    MIN_OVERLAP_FOR_STRONG = 5,           -- Increased from 3
    MIN_OVERLAP_PERCENTAGE_WEAK = 0.40,   -- Much higher - 40%
    MIN_OVERLAP_PERCENTAGE_MODERATE = 0.60, -- 60%
    MIN_OVERLAP_PERCENTAGE_STRONG = 0.75    -- 75%
}

-- Minimum fingerprints required before attempting any matching
local MIN_FINGERPRINTS_FOR_MATCHING = 3

-- Internal state
local state = {
    instanceDb = nil,
    currentInstance = nil,
    sessionStartCoords = nil,
    wasInInstance = false,
    swapBufferCount = 0,
    render3dCount = 0,
    renderFrequency = {},
    sessionFingerprints = {},
    sessionStartTime = 0,
    captureAttempts = 0,
    captureSuccesses = 0,
    isRecognized = false,
    initialized = false,
    -- Progressive recognition state
    recognitionConfidence = 0, -- CONFIDENCE_LEVELS.UNKNOWN
    matchCandidates = {},
    lastConfidenceUpdate = 0,
    tempInstanceCreated = false,
    switchHistory = {},
    -- Debug state
    lastRenderInfo = nil,
    debugEnabled = true
}

-- Enhanced debug logging
local function debugLog(bolt, message, level)
    if not state.debugEnabled then return end
    
    level = level or "INFO"
    local timestamp = state.swapBufferCount or 0
    local logMessage = string.format("[%d] %s: %s", timestamp, level, message)
    
    if bolt and bolt.saveconfig then
        bolt.saveconfig("instances_debug.txt", logMessage)
        if level == "ERROR" then
            bolt.saveconfig("instances_error.txt", logMessage)
        end
    end
end

-- Coordinate functions
local function worldToTileCoords(worldX, worldZ)
    return math.floor(worldX / 512), math.floor(worldZ / 512)
end

local function tileToRS(tileX, tileZ, worldY)
    local floor = 0  -- Hardcoded since Y coordinates aren't reliable
    local chunkX = math.floor(tileX / 64)
    local chunkZ = math.floor(tileZ / 64)
    return floor, chunkX, chunkZ
end

local function isInInstanceChunk(chunkX, chunkZ)
    return chunkX > 100 or chunkX < -100
end

-- Enhanced render analysis with debugging
local function analyzeRender(event)
    local success, analysis = pcall(function()
        local vertexCount = event:vertexcount()
        local textureId = event:textureid()
        
        if not vertexCount or not textureId or vertexCount == 0 then
            return nil
        end
        
        -- Store debug info about what we're analyzing
        state.lastRenderInfo = {
            vertexCount = vertexCount,
            textureId = textureId,
            timestamp = state.swapBufferCount
        }
        
        local patterns = {}
        
        -- 1. BROAD size categories (less sensitive to exact vertex counts)
        local sizeCategory = "unknown"
        if vertexCount < 50 then 
            sizeCategory = "tiny"
        elseif vertexCount < 200 then 
            sizeCategory = "small"
        elseif vertexCount < 1000 then 
            sizeCategory = "medium"
        elseif vertexCount < 5000 then 
            sizeCategory = "large"
        else 
            sizeCategory = "huge"
        end
        
        -- 2. TEXTURE-based patterns (most stable)
        local textureCategory = math.floor(textureId / 100) * 100 -- Group textures by hundreds
        table.insert(patterns, string.format("tex_%d", textureCategory))
        
        -- 3. COMBINED size + texture signature
        table.insert(patterns, string.format("model_%s_tex%d", sizeCategory, textureCategory))
        
        -- 4. DOMINANT COLOR analysis (more stable than precise hues)
        local colorCounts = {red = 0, green = 0, blue = 0, warm = 0, cool = 0, neutral = 0}
        local sampleSize = math.min(vertexCount, 12)
        
        for i = 1, sampleSize do
            local vertexIndex = math.floor((i - 1) * vertexCount / sampleSize) + 1
            local r, g, b, a = event:vertexcolour(vertexIndex)
            
            if r and g and b and a and a > 0.1 then
                -- Broad color categories
                if r > g and r > b then
                    if r > 0.6 then colorCounts.red = colorCounts.red + 1 end
                    colorCounts.warm = colorCounts.warm + 1
                elseif g > r and g > b then
                    if g > 0.6 then colorCounts.green = colorCounts.green + 1 end
                    if b > 0.4 then colorCounts.cool = colorCounts.cool + 1
                    else colorCounts.warm = colorCounts.warm + 1 end
                elseif b > r and b > g then
                    if b > 0.6 then colorCounts.blue = colorCounts.blue + 1 end
                    colorCounts.cool = colorCounts.cool + 1
                else
                    colorCounts.neutral = colorCounts.neutral + 1
                end
            end
        end
        
        -- Add dominant color patterns
        for color, count in pairs(colorCounts) do
            if count >= 2 then  -- At least 2 samples
                table.insert(patterns, string.format("color_%s", color))
            end
        end
        
        -- 5. GEOMETRIC complexity patterns
        if vertexCount > 0 then
            local complexity = "simple"
            if vertexCount > 100 then complexity = "moderate" end
            if vertexCount > 500 then complexity = "complex" end
            if vertexCount > 2000 then complexity = "very_complex" end
            
            table.insert(patterns, string.format("geo_%s", complexity))
        end
        
        return patterns
    end)
    
    if not success then
        local bolt = require("bolt")
        debugLog(bolt, string.format("Render analysis failed: %s", tostring(analysis)), "ERROR")
    end
    
    return success and analysis or nil
end

local function updatePatterns(patterns)
    for _, pattern in ipairs(patterns or {}) do
        state.renderFrequency[pattern] = (state.renderFrequency[pattern] or 0) + 1
    end
end

-- Enhanced createStableFingerprint with extensive debugging
local function createStableFingerprint(bolt)
    debugLog(bolt, "=== FINGERPRINT GENERATION ATTEMPT ===")
    
    if next(state.renderFrequency) == nil then
        debugLog(bolt, "FAILED: renderFrequency is empty", "ERROR")
        return nil
    end
    
    local totalSamples = 0
    local patternCount = 0
    for pattern, count in pairs(state.renderFrequency) do
        totalSamples = totalSamples + count
        patternCount = patternCount + 1
    end
    
    debugLog(bolt, string.format("Render patterns: %d, Total samples: %d, Required: %d", 
              patternCount, totalSamples, MIN_ANALYSIS_SAMPLES))
    
    if totalSamples < MIN_ANALYSIS_SAMPLES then
        debugLog(bolt, string.format("FAILED: Insufficient samples (%d < %d)", 
                  totalSamples, MIN_ANALYSIS_SAMPLES), "ERROR")
        return nil
    end
    
    -- Debug pattern breakdown
    local patternsByType = {}
    for pattern, count in pairs(state.renderFrequency) do
        local patternType = string.match(pattern, "^([^_]+)_") or "unknown"
        patternsByType[patternType] = (patternsByType[patternType] or 0) + 1
        
        if count >= 2 then
            debugLog(bolt, string.format("  Pattern: %s (count: %d)", pattern, count))
        end
    end
    
    for pType, pCount in pairs(patternsByType) do
        debugLog(bolt, string.format("  Type '%s': %d patterns", pType, pCount))
    end
    
    local fingerprints = {}
    
    -- 1. TEXTURE fingerprint with detailed logging
    local texturePatterns = {}
    for pattern, count in pairs(state.renderFrequency) do
        if string.match(pattern, "^tex_") and count >= 2 then
            table.insert(texturePatterns, pattern)
        end
    end
    
    debugLog(bolt, string.format("Texture patterns found: %d", #texturePatterns))
    
    if #texturePatterns >= 2 then
        table.sort(texturePatterns)
        local texHash = 0
        local texStr = table.concat(texturePatterns, "|")
        for i = 1, #texStr do
            texHash = (texHash * 17 + string.byte(texStr, i)) % 100000000
        end
        local texFingerprint = string.format("texture_%08d", texHash)
        table.insert(fingerprints, texFingerprint)
        debugLog(bolt, string.format("Generated texture fingerprint: %s", texFingerprint))
    else
        debugLog(bolt, "Skipped texture fingerprint: insufficient patterns")
    end
    
    -- 2. COLOR fingerprint with detailed logging
    local colorPatterns = {}
    for pattern, count in pairs(state.renderFrequency) do
        if string.match(pattern, "^color_") and count >= 2 then
            table.insert(colorPatterns, pattern)
        end
    end
    
    debugLog(bolt, string.format("Color patterns found: %d", #colorPatterns))
    
    if #colorPatterns >= 2 then
        table.sort(colorPatterns)
        local colorHash = 0
        local colorStr = table.concat(colorPatterns, "|")
        for i = 1, #colorStr do
            colorHash = (colorHash * 13 + string.byte(colorStr, i)) % 100000000
        end
        local colorFingerprint = string.format("color_%08d", colorHash)
        table.insert(fingerprints, colorFingerprint)
        debugLog(bolt, string.format("Generated color fingerprint: %s", colorFingerprint))
    else
        debugLog(bolt, "Skipped color fingerprint: insufficient patterns")
    end
    
    -- 3. GEOMETRY fingerprint with detailed logging
    local geoPatterns = {}
    for pattern, count in pairs(state.renderFrequency) do
        if string.match(pattern, "^geo_") and count >= 1 then
            table.insert(geoPatterns, pattern)
        end
    end
    
    debugLog(bolt, string.format("Geometry patterns found: %d", #geoPatterns))
    
    if #geoPatterns >= 1 then
        table.sort(geoPatterns)
        local geoHash = 0
        local geoStr = table.concat(geoPatterns, "|")
        for i = 1, #geoStr do
            geoHash = (geoHash * 19 + string.byte(geoStr, i)) % 100000000
        end
        local geoFingerprint = string.format("geometry_%08d", geoHash)
        table.insert(fingerprints, geoFingerprint)
        debugLog(bolt, string.format("Generated geometry fingerprint: %s", geoFingerprint))
    else
        debugLog(bolt, "Skipped geometry fingerprint: insufficient patterns")
    end
    
    -- 4. MODEL fingerprint with detailed logging
    local modelPatterns = {}
    for pattern, count in pairs(state.renderFrequency) do
        if string.match(pattern, "^model_") and count >= 2 then
            table.insert(modelPatterns, pattern)
        end
    end
    
    debugLog(bolt, string.format("Model patterns found: %d", #modelPatterns))
    
    if #modelPatterns >= 1 then
        table.sort(modelPatterns)
        local modelHash = 0
        local modelStr = table.concat(modelPatterns, "|")
        for i = 1, #modelStr do
            modelHash = (modelHash * 23 + string.byte(modelStr, i)) % 100000000
        end
        local modelFingerprint = string.format("model_%08d", modelHash)
        table.insert(fingerprints, modelFingerprint)
        debugLog(bolt, string.format("Generated model fingerprint: %s", modelFingerprint))
    else
        debugLog(bolt, "Skipped model fingerprint: insufficient patterns")
    end
    
    debugLog(bolt, string.format("FINGERPRINT GENERATION RESULT: %d fingerprints generated", #fingerprints))
    
    if #fingerprints == 0 then
        debugLog(bolt, "CRITICAL: No fingerprints generated despite having render data!", "ERROR")
        -- Emergency fallback - create a basic fingerprint
        local fallbackHash = totalSamples % 100000000
        local fallbackFp = string.format("fallback_%08d", fallbackHash)
        table.insert(fingerprints, fallbackFp)
        debugLog(bolt, string.format("Generated fallback fingerprint: %s", fallbackFp))
    end
    
    return fingerprints
end

-- Calculate recognition confidence for current session
local function calculateRecognitionConfidence(sessionFingerprints, matchedInstance, overlapCount)
    if not matchedInstance or overlapCount == 0 then
        return CONFIDENCE_LEVELS.UNKNOWN
    end
    
    local fpCount = #sessionFingerprints
    local overlapPercentage = fpCount > 0 and (overlapCount / fpCount) or 0
    
    -- Progressive confidence based on evidence strength
    if fpCount >= PROGRESSIVE_THRESHOLDS.MIN_FINGERPRINTS_FOR_STRONG and 
       overlapCount >= PROGRESSIVE_THRESHOLDS.MIN_OVERLAP_FOR_STRONG and 
       overlapPercentage >= PROGRESSIVE_THRESHOLDS.MIN_OVERLAP_PERCENTAGE_STRONG then
        return CONFIDENCE_LEVELS.STRONG
        
    elseif fpCount >= PROGRESSIVE_THRESHOLDS.MIN_FINGERPRINTS_FOR_MODERATE and 
           overlapCount >= PROGRESSIVE_THRESHOLDS.MIN_OVERLAP_FOR_MODERATE and 
           overlapPercentage >= PROGRESSIVE_THRESHOLDS.MIN_OVERLAP_PERCENTAGE_MODERATE then
        return CONFIDENCE_LEVELS.MODERATE
        
    elseif fpCount >= PROGRESSIVE_THRESHOLDS.MIN_FINGERPRINTS_FOR_WEAK and 
           overlapCount >= PROGRESSIVE_THRESHOLDS.MIN_OVERLAP_FOR_WEAK and 
           overlapPercentage >= PROGRESSIVE_THRESHOLDS.MIN_OVERLAP_PERCENTAGE_WEAK then
        return CONFIDENCE_LEVELS.WEAK
        
    else
        return CONFIDENCE_LEVELS.UNKNOWN
    end
end

-- FIXED: Much more conservative matching with minimal fuzzy matching
local function findBestMatchWithScore(sessionFingerprints)
    if #sessionFingerprints == 0 then
        return nil, 0, CONFIDENCE_LEVELS.UNKNOWN
    end
    
    local bestMatch = nil
    local bestOverlap = 0
    local bestScore = 0
    
    for _, instance in ipairs(state.instanceDb.instances or {}) do
        if not instance.fingerprints or next(instance.fingerprints) == nil then
            goto continue
        end
        
        -- Skip temporary instances
        if state.tempInstanceCreated and state.currentInstance and 
           instance.id == state.currentInstance.id then
            goto continue
        end
        
        local overlapCount = 0
        
        -- ONLY exact fingerprint matches
        for _, sessionFp in ipairs(sessionFingerprints) do
            if instance.fingerprints[sessionFp] then
                overlapCount = overlapCount + 1
            end
        end
        
        -- VERY LIMITED fuzzy matching - only if we already have solid exact matches
        local fuzzyScore = 0
        if overlapCount >= 2 then  -- Only apply fuzzy if we already have exact matches
            local sessionTypeCount = {}
            local instanceTypeCount = {}
            
            -- Count fingerprint types in session
            for _, sessionFp in ipairs(sessionFingerprints) do
                local sessionType = string.match(sessionFp, "^([^_]+)_")
                if sessionType then
                    sessionTypeCount[sessionType] = (sessionTypeCount[sessionType] or 0) + 1
                end
            end
            
            -- Count fingerprint types in instance
            for instanceFp, _ in pairs(instance.fingerprints) do
                local instanceType = string.match(instanceFp, "^([^_]+)_")
                if instanceType then
                    instanceTypeCount[instanceType] = (instanceTypeCount[instanceType] or 0) + 1
                end
            end
            
            -- Only give fuzzy credit if both have multiple fingerprints of same type
            for fpType, sessionCount in pairs(sessionTypeCount) do
                local instanceCount = instanceTypeCount[fpType] or 0
                if sessionCount >= 2 and instanceCount >= 2 then
                    fuzzyScore = fuzzyScore + 0.1  -- Very small fuzzy bonus
                end
            end
        end
        
        local totalScore = overlapCount + fuzzyScore
        
        if totalScore > bestScore then
            bestMatch = instance
            bestOverlap = overlapCount
            bestScore = totalScore
        end
        
        ::continue::
    end
    
    local confidence = calculateRecognitionConfidence(sessionFingerprints, bestMatch, bestOverlap)
    return bestMatch, bestOverlap, confidence
end

-- FIXED: Much more conservative instance recognition
local function updateInstanceRecognition(bolt)
    -- Require minimum fingerprints before attempting any matching
    if #state.sessionFingerprints < MIN_FINGERPRINTS_FOR_MATCHING then 
        debugLog(bolt, string.format("Skipping recognition: only %d/%d fingerprints", 
                  #state.sessionFingerprints, MIN_FINGERPRINTS_FOR_MATCHING))
        return 
    end
    
    local bestMatch, overlapCount, confidence = findBestMatchWithScore(state.sessionFingerprints)
    local previousConfidence = state.recognitionConfidence
    state.recognitionConfidence = confidence
    state.lastConfidenceUpdate = state.swapBufferCount
    
    -- MUCH more conservative decision logic for switching
    local shouldSwitch = false
    local switchReason = ""
    
    if bestMatch and confidence >= CONFIDENCE_LEVELS.MODERATE then
        if not state.currentInstance then
            shouldSwitch = true
            switchReason = "No current instance"
            
        elseif state.tempInstanceCreated then
            -- Only switch from temporary if we have STRONG confidence
            if confidence >= CONFIDENCE_LEVELS.STRONG then
                shouldSwitch = true
                switchReason = "Strong match from temporary instance"
            end
            
        elseif state.currentInstance.id ~= bestMatch.id then
            -- Only switch between instances with CERTAIN evidence (highest level)
            if confidence >= CONFIDENCE_LEVELS.CERTAIN then
                shouldSwitch = true
                switchReason = "Certain evidence for different instance"
            end
        end
    end
    
    -- Additional safety check: require absolute minimum overlaps
    if shouldSwitch and overlapCount < 3 then
        shouldSwitch = false
        switchReason = "Insufficient absolute overlap count"
        debugLog(bolt, string.format("Blocked switch due to low overlap: %d < 3", overlapCount))
    end
    
    -- Additional safety check: require minimum percentage
    if shouldSwitch and bestMatch then
        local overlapPercentage = overlapCount / #state.sessionFingerprints
        if overlapPercentage < 0.5 then  -- Must have at least 50% overlap
            shouldSwitch = false
            switchReason = "Insufficient overlap percentage"
            debugLog(bolt, string.format("Blocked switch due to low percentage: %.1f%% < 50%%", 
                      overlapPercentage * 100))
        end
    end
    
    -- Perform the switch if warranted
    if shouldSwitch and bestMatch then
        local oldInstance = state.currentInstance
        state.currentInstance = bestMatch
        state.tempInstanceCreated = false
        state.isRecognized = true
        
        -- Log the switch
        table.insert(state.switchHistory, {
            swapCount = state.swapBufferCount,
            from = oldInstance and oldInstance.id or "none",
            to = bestMatch.id,
            reason = switchReason,
            confidence = confidence,
            overlap = overlapCount,
            fingerprints = #state.sessionFingerprints
        })
        
        debugLog(bolt, string.format(
            "=== INSTANCE SWITCH ===\nFrom: %s\nTo: %s\nReason: %s\nConfidence: %d\nOverlap: %d/%d (%.1f%%)\nSwap: %d",
            oldInstance and instancePersist.describe(oldInstance) or "none",
            instancePersist.describe(bestMatch),
            switchReason,
            confidence,
            overlapCount, #state.sessionFingerprints,
            (overlapCount / #state.sessionFingerprints) * 100,
            state.swapBufferCount
        ))
        
        -- Clean up temporary instance if we created one
        if oldInstance and state.tempInstanceCreated then
            for i, inst in ipairs(state.instanceDb.instances) do
                if inst.id == oldInstance.id then
                    table.remove(state.instanceDb.instances, i)
                    debugLog(bolt, "Removed temporary instance from database")
                    break
                end
            end
        end
    else
        -- Log why we didn't switch
        if bestMatch and confidence > CONFIDENCE_LEVELS.UNKNOWN then
            debugLog(bolt, string.format(
                "No switch: match=%s, confidence=%d, overlap=%d/%d (%.1f%%), reason=%s",
                bestMatch.id, confidence, overlapCount, #state.sessionFingerprints,
                (overlapCount / #state.sessionFingerprints) * 100,
                switchReason ~= "" and switchReason or "insufficient confidence"
            ))
        end
    end
    
    -- Log confidence changes
    if confidence ~= previousConfidence then
        debugLog(bolt, string.format(
            "Confidence changed: %d → %d (fingerprints: %d, best overlap: %d)",
            previousConfidence, confidence, #state.sessionFingerprints, overlapCount
        ))
    end
end

-- Enhanced updateInstanceState with debugging and cleanup
local function updateInstanceState(bolt)
    state.swapBufferCount = state.swapBufferCount + 1
    
    local playerPos = bolt.playerposition()
    if not playerPos then return end
    
    local px, py, pz = playerPos:get()
    local tileX, tileZ = worldToTileCoords(px, pz)
    local floor, chunkX, chunkZ = tileToRS(tileX, tileZ, py)
    local inInstance = isInInstanceChunk(chunkX, chunkZ)

    -- Handle session changes
    if inInstance and not state.wasInInstance then
        -- Entering instance
        debugLog(bolt, "=== ENTERING INSTANCE ===")
        
        state.sessionFingerprints = {}
        state.sessionStartTime = state.swapBufferCount
        state.sessionStartCoords = {worldX = px, worldZ = pz, worldY = py}
        state.renderFrequency = {}
        state.recognitionConfidence = CONFIDENCE_LEVELS.UNKNOWN
        state.matchCandidates = {}
        state.switchHistory = {}
        
        -- Create temporary instance
        local tempInstance = instancePersist.createInstance(state.instanceDb, {floor = floor}, bolt)
        state.currentInstance = tempInstance
        state.isRecognized = false
        state.tempInstanceCreated = true
        
        debugLog(bolt, string.format(
            "Created temporary instance: %s\nChunk coordinates: (%d,%d) [DYNAMIC - NOT USED FOR MATCHING]\nUsing visual fingerprints only",
            tempInstance.id, chunkX, chunkZ
        ))
        
    elseif not inInstance and state.wasInInstance then
        -- Leaving instance - finalize with enhanced cleanup
        debugLog(bolt, "=== LEAVING INSTANCE ===")
        
        if state.currentInstance then
            debugLog(bolt, string.format("Finalizing instance: %s", state.currentInstance.id))
            debugLog(bolt, string.format("Session fingerprints collected: %d", #state.sessionFingerprints))
            
            if #state.sessionFingerprints > 0 then
                -- Add fingerprints to the final instance
                for _, fp in ipairs(state.sessionFingerprints) do
                    instancePersist.addFingerprint(state.instanceDb, state.currentInstance, fp, bolt)
                end
                debugLog(bolt, string.format("Added %d fingerprints to instance", #state.sessionFingerprints))
            else
                debugLog(bolt, "WARNING: No fingerprints collected during session!", "ERROR")
                
                -- CLEANUP: Remove empty temporary instances
                if state.tempInstanceCreated then
                    debugLog(bolt, string.format("Removing empty temporary instance: %s", state.currentInstance.id))
                    
                    for i, inst in ipairs(state.instanceDb.instances) do
                        if inst.id == state.currentInstance.id then
                            table.remove(state.instanceDb.instances, i)
                            debugLog(bolt, "Empty temporary instance removed from database")
                            break
                        end
                    end
                else
                    debugLog(bolt, "Empty session on existing instance - keeping instance")
                end
            end
            
            instancePersist.save(bolt, state.instanceDb)
        end
        
        -- Clear session data
        state.sessionFingerprints = {}
        state.currentInstance = nil
        state.isRecognized = false
        state.recognitionConfidence = CONFIDENCE_LEVELS.UNKNOWN
        state.tempInstanceCreated = false
        state.switchHistory = {}
    end

    state.wasInInstance = inInstance

    -- Enhanced fingerprint generation with debugging
    if inInstance and state.swapBufferCount % FINGERPRINT_INTERVAL == 0 then
        state.captureAttempts = state.captureAttempts + 1
        debugLog(bolt, string.format("Fingerprint capture attempt #%d", state.captureAttempts))
        
        local fingerprints = createStableFingerprint(bolt)
        
        if fingerprints and #fingerprints > 0 then
            local newFingerprintsAdded = 0
            
            for _, fingerprint in ipairs(fingerprints) do
                local isDuplicate = false
                for _, existingFp in ipairs(state.sessionFingerprints) do
                    if existingFp == fingerprint then
                        isDuplicate = true
                        break
                    end
                end
                
                if not isDuplicate then
                    table.insert(state.sessionFingerprints, fingerprint)
                    newFingerprintsAdded = newFingerprintsAdded + 1
                    state.captureSuccesses = state.captureSuccesses + 1
                end
            end
            
            debugLog(bolt, string.format("Added %d new fingerprints (total session: %d)", 
                      newFingerprintsAdded, #state.sessionFingerprints))
            
            if newFingerprintsAdded > 0 then
                updateInstanceRecognition(bolt)
            end
        else
            debugLog(bolt, "Fingerprint generation returned nil or empty array", "ERROR")
        end
    end
    
    -- Extended collection with better logging
    if inInstance and #state.sessionFingerprints < MIN_FINGERPRINTS_PER_SESSION and
       (state.swapBufferCount - state.sessionStartTime) < EXTENDED_SESSION_TIME and
       state.swapBufferCount % (FINGERPRINT_INTERVAL / 3) == 0 then
        
        debugLog(bolt, string.format("Extended fingerprint collection attempt (have %d/%d)", 
                  #state.sessionFingerprints, MIN_FINGERPRINTS_PER_SESSION))
        
        local fingerprints = createStableFingerprint(bolt)
        if fingerprints and #fingerprints > 0 then
            local added = 0
            for _, fingerprint in ipairs(fingerprints) do
                local isDuplicate = false
                for _, existingFp in ipairs(state.sessionFingerprints) do
                    if existingFp == fingerprint then
                        isDuplicate = true
                        break
                    end
                end
                
                if not isDuplicate then
                    table.insert(state.sessionFingerprints, fingerprint)
                    added = added + 1
                end
            end
            
            if added > 0 then
                debugLog(bolt, string.format("Extended collection added %d fingerprints", added))
                updateInstanceRecognition(bolt)
            end
        end
    end
end

-- Public API Functions

function M.init(bolt, hooks)
    if not bolt then return false end
    
    state.instanceDb = instancePersist.load(bolt)

    if hooks then
        hooks.addRender3DHandler("fingerprinting", function(event)
            state.render3dCount = state.render3dCount + 1
            
            if state.render3dCount % ANALYSIS_INTERVAL ~= 0 then
                return
            end
            
            local patterns = analyzeRender(event)
            if patterns then
                updatePatterns(patterns)
            end
        end)
        
        hooks.addSwapBufferHandler("instance_detection", function(event)
            local success = pcall(updateInstanceState, bolt)
            if not success then
                debugLog(bolt, "Error in instance update", "ERROR")
            end
        end)
    end
    
    state.initialized = true
    debugLog(bolt, "Fixed visual-only instance recognition initialized with conservative matching")
    return true
end

function M.isInInstance()
    local bolt = require("bolt")
    local playerPos = bolt.playerposition()
    if not playerPos then return false end
    
    local px, py, pz = playerPos:get()
    local tileX, tileZ = worldToTileCoords(px, pz)
    local floor, chunkX, chunkZ = tileToRS(tileX, tileZ, py)
    
    return isInInstanceChunk(chunkX, chunkZ)
end

function M.isInstanceRecognized()
    return state.isRecognized
end

function M.getCurrentInstanceId()
    return state.currentInstance and state.currentInstance.id or nil
end

function M.getCurrentInstance()
    return state.currentInstance
end

function M.getSessionEntryCoords()
    return state.sessionStartCoords
end

function M.getStats()
    return {
        swapBufferCount = state.swapBufferCount,
        render3dCount = state.render3dCount,
        captureAttempts = state.captureAttempts,
        captureSuccesses = state.captureSuccesses,
        sessionFingerprints = #state.sessionFingerprints,
        isInInstance = state.wasInInstance,
        currentInstanceId = state.currentInstance and state.currentInstance.id or nil,
        isRecognized = state.isRecognized
    }
end

function M.save(bolt)
    if state.instanceDb then
        instancePersist.save(bolt, state.instanceDb)
    end
end

-- Progressive recognition API for JIT decision making

function M.getRecognitionConfidence()
    return state.recognitionConfidence
end

function M.isConfidentEnough(minimumConfidence)
    return state.recognitionConfidence >= (minimumConfidence or CONFIDENCE_LEVELS.MODERATE)
end

function M.getCurrentInstanceWithConfidence()
    return state.currentInstance, state.recognitionConfidence
end

function M.shouldTriggerAction(requiredConfidence)
    requiredConfidence = requiredConfidence or CONFIDENCE_LEVELS.MODERATE
    return M.isInInstance() and state.recognitionConfidence >= requiredConfidence
end

function M.getActionRecommendation()
    local instance, confidence = M.getCurrentInstanceWithConfidence()
    
    if not instance then
        return "none", "Not in instance"
    end
    
    if confidence >= CONFIDENCE_LEVELS.STRONG then
        return "full_automation", string.format("Strong recognition of %s", instance.id)
    elseif confidence >= CONFIDENCE_LEVELS.MODERATE then
        return "assisted_actions", string.format("Moderate recognition of %s", instance.id)
    elseif confidence >= CONFIDENCE_LEVELS.WEAK then
        return "basic_assistance", string.format("Weak recognition of %s", instance.id)
    else
        return "manual_only", "Unknown instance, manual actions only"
    end
end

function M.getRecognitionState()
    return {
        currentInstance = state.currentInstance and state.currentInstance.id or nil,
        confidence = state.recognitionConfidence,
        sessionFingerprints = #state.sessionFingerprints,
        isTemporary = state.tempInstanceCreated,
        switchHistory = state.switchHistory,
        lastUpdate = state.lastConfidenceUpdate
    }
end

-- FIXED: Enhanced debug functions with matching analysis

function M.debugFingerprints()
    if not state.currentInstance then return "Not in instance" end
    
    local info = {}
    table.insert(info, string.format("Current: %s (temp: %s)", 
                 state.currentInstance.id, tostring(state.tempInstanceCreated)))
    table.insert(info, string.format("Session fingerprints: %d", #state.sessionFingerprints))
    
    -- Group fingerprints by type
    local byType = {}
    for i, fp in ipairs(state.sessionFingerprints) do
        local fpType = string.match(fp, "^([^_]+)_") or "unknown"
        byType[fpType] = byType[fpType] or {}
        table.insert(byType[fpType], fp)
    end
    
    for fpType, fps in pairs(byType) do
        table.insert(info, string.format("  %s: %d fingerprints", fpType, #fps))
        for _, fp in ipairs(fps) do
            table.insert(info, string.format("    %s", fp))
        end
    end
    
    table.insert(info, string.format("Confidence: %d", state.recognitionConfidence))
    
    local patternCount = 0
    for k, v in pairs(state.renderFrequency) do
        patternCount = patternCount + 1
    end
    table.insert(info, string.format("Render patterns: %d", patternCount))
    
    return table.concat(info, "\n")
end

function M.debugMatchingDecision()
    if #state.sessionFingerprints == 0 then 
        return "No session fingerprints to analyze" 
    end
    
    if #state.sessionFingerprints < MIN_FINGERPRINTS_FOR_MATCHING then
        return string.format("Not enough fingerprints for matching: %d/%d", 
                           #state.sessionFingerprints, MIN_FINGERPRINTS_FOR_MATCHING)
    end
    
    local bestMatch, overlapCount, confidence = findBestMatchWithScore(state.sessionFingerprints)
    
    local overlapPercentage = overlapCount / #state.sessionFingerprints
    local wouldSwitch = false
    
    if bestMatch and confidence >= CONFIDENCE_LEVELS.MODERATE then
        if not state.currentInstance or state.tempInstanceCreated then
            wouldSwitch = (confidence >= CONFIDENCE_LEVELS.STRONG)
        elseif state.currentInstance.id ~= bestMatch.id then
            wouldSwitch = (confidence >= CONFIDENCE_LEVELS.CERTAIN)
        end
        
        -- Apply safety checks
        if wouldSwitch and (overlapCount < 3 or overlapPercentage < 0.5) then
            wouldSwitch = false
        end
    end
    
    return string.format(
        "Session FPs: %d | Best match: %s | Overlap: %d (%.1f%%) | Confidence: %d | Would switch: %s",
        #state.sessionFingerprints,
        bestMatch and bestMatch.id or "none",
        overlapCount,
        overlapPercentage * 100,
        confidence,
        tostring(wouldSwitch)
    )
end

function M.debugPotentialMatches()
    if #state.sessionFingerprints == 0 then
        return "No session fingerprints to analyze"
    end
    
    local results = {}
    table.insert(results, string.format("Session fingerprints: %d", #state.sessionFingerprints))
    table.insert(results, string.format("Matching threshold: %d fingerprints minimum", MIN_FINGERPRINTS_FOR_MATCHING))
    
    if #state.sessionFingerprints < MIN_FINGERPRINTS_FOR_MATCHING then
        table.insert(results, "*** NOT ENOUGH FINGERPRINTS FOR MATCHING ***")
    end
    
    for _, instance in ipairs(state.instanceDb.instances or {}) do
        if not instance.fingerprints or next(instance.fingerprints) == nil then
            table.insert(results, string.format("Instance %s: EMPTY (no fingerprints)", instance.id))
            goto continue
        end
        
        local exactMatches = 0
        local matchedFingerprints = {}
        
        for _, sessionFp in ipairs(state.sessionFingerprints) do
            if instance.fingerprints[sessionFp] then
                exactMatches = exactMatches + 1
                table.insert(matchedFingerprints, sessionFp)
            end
        end
        
        local percentage = #state.sessionFingerprints > 0 and 
                          (exactMatches / #state.sessionFingerprints) or 0
        
        local confidence = calculateRecognitionConfidence(state.sessionFingerprints, instance, exactMatches)
        
        table.insert(results, string.format("Instance %s: %d/%d exact matches (%.1f%%) - Confidence: %d", 
                     instance.id, exactMatches, #state.sessionFingerprints, percentage * 100, confidence))
        
        if exactMatches > 0 then
            table.insert(results, "  Matched fingerprints:")
            for _, fp in ipairs(matchedFingerprints) do
                table.insert(results, string.format("    %s", fp))
            end
        end
        
        ::continue::
    end
    
    return table.concat(results, "\n")
end

function M.debugRenderCollection()
    local info = {}
    table.insert(info, string.format("Render3D count: %d", state.render3dCount))
    table.insert(info, string.format("Analysis interval: %d", ANALYSIS_INTERVAL))
    
    local patternCount = 0
    for k, v in pairs(state.renderFrequency) do
        patternCount = patternCount + 1
    end
    table.insert(info, string.format("Pattern types collected: %d", patternCount))
    
    if state.lastRenderInfo then
        table.insert(info, string.format("Last render: vertices=%d, texture=%d, swap=%d",
                     state.lastRenderInfo.vertexCount,
                     state.lastRenderInfo.textureId,
                     state.lastRenderInfo.timestamp))
    else
        table.insert(info, "No render data captured yet")
    end
    
    local patternsByType = {}
    for pattern, count in pairs(state.renderFrequency) do
        local pType = string.match(pattern, "^([^_]+)_") or "unknown"
        patternsByType[pType] = (patternsByType[pType] or 0) + count
    end
    
    for pType, count in pairs(patternsByType) do
        table.insert(info, string.format("  %s patterns: %d total samples", pType, count))
    end
    
    return table.concat(info, "\n")
end

function M.debugFullState()
    local bolt = require("bolt")
    
    local info = {}
    table.insert(info, "=== COMPLETE INSTANCE DEBUG STATE (FIXED VERSION) ===")
    table.insert(info, string.format("Swap count: %d", state.swapBufferCount))
    table.insert(info, string.format("In instance: %s", tostring(state.wasInInstance)))
    table.insert(info, string.format("Current instance: %s", 
                 state.currentInstance and state.currentInstance.id or "none"))
    table.insert(info, string.format("Is temporary: %s", tostring(state.tempInstanceCreated)))
    table.insert(info, string.format("Session fingerprints: %d", #state.sessionFingerprints))
    table.insert(info, string.format("Confidence: %d", state.recognitionConfidence))
    table.insert(info, string.format("Matching threshold: %d fingerprints", MIN_FINGERPRINTS_FOR_MATCHING))
    
    -- Render analysis state
    table.insert(info, string.format("Render3D events: %d", state.render3dCount))
    
    local patternCount = 0
    for k, v in pairs(state.renderFrequency) do
        patternCount = patternCount + 1
    end
    table.insert(info, string.format("Patterns collected: %d", patternCount))
    
    -- Show current patterns (first 10)
    local count = 0
    for pattern, freq in pairs(state.renderFrequency) do
        count = count + 1
        if count <= 10 then
            table.insert(info, string.format("  %s: %d", pattern, freq))
        end
    end
    
    if count > 10 then
        table.insert(info, string.format("  ... and %d more patterns", count - 10))
    end
    
    -- Database state
    local dbInstanceCount = state.instanceDb and #(state.instanceDb.instances or {}) or 0
    table.insert(info, string.format("Database instances: %d", dbInstanceCount))
    
    -- Show switch history
    if #state.switchHistory > 0 then
        table.insert(info, "Switch history:")
        for _, switch in ipairs(state.switchHistory) do
            table.insert(info, string.format("  Swap %d: %s -> %s (%s, conf=%d)", 
                         switch.swapCount, switch.from, switch.to, switch.reason, switch.confidence))
        end
    end
    
    bolt.saveconfig("full_debug_state.txt", table.concat(info, "\n"))
    return table.concat(info, "\n")
end

function M.enableDebug(enabled)
    state.debugEnabled = enabled or true
end

-- Export confidence levels for external use
M.CONFIDENCE_LEVELS = CONFIDENCE_LEVELS

return M