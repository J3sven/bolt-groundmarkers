local M = {}

local VERSION_FILE = "plugin_version.ini"
local CURRENT_VERSION = "1.10"
local MIGRATION_THRESHOLD = 1.10

function M.needsInstanceLayoutMigration(bolt)
    local saved = bolt.loadconfig(VERSION_FILE)

    if not saved or saved == "" then
        local layoutPersist = require("data.layout_persistence")
        local layouts = layoutPersist.getAllLayouts(bolt)

        local hasInstanceLayouts = false
        for _, layout in ipairs(layouts) do
            if layout.layoutType == "instance" then
                hasInstanceLayouts = true
                break
            end
        end

        if hasInstanceLayouts then
            return true
        else
            M.saveVersion(bolt)
            return false
        end
    end

    local savedVersion = saved:match("version=([%d%.]+)")
    if not savedVersion then
        local layoutPersist = require("data.layout_persistence")
        local layouts = layoutPersist.getAllLayouts(bolt)

        for _, layout in ipairs(layouts) do
            if layout.layoutType == "instance" then
                return true
            end
        end

        M.saveVersion(bolt)
        return false
    end

    local savedVer = tonumber(savedVersion)
    local currentVer = tonumber(CURRENT_VERSION)

    if not savedVer or not currentVer then
        M.saveVersion(bolt)
        return false
    end

    if savedVer < currentVer and savedVer < MIGRATION_THRESHOLD then
        return true
    end

    return false
end

function M.saveVersion(bolt)
    bolt.saveconfig(VERSION_FILE, "version=" .. CURRENT_VERSION)
end

function M.markMigrationShown(bolt)
    bolt.saveconfig(VERSION_FILE, "version=" .. CURRENT_VERSION .. "\nmigration_shown=true")
end

function M.migrationAlreadyShown(bolt)
    local saved = bolt.loadconfig(VERSION_FILE)
    if not saved then
        return false
    end
    return saved:match("migration_shown=true") ~= nil
end

return M
