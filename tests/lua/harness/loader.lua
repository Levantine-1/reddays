-- Loads the real, unmodified mod files into a sandboxed environment.
--
-- PZ's require() takes a flat module name and searches its own lua roots; this
-- shim reproduces that against media/lua/{client,server,shared}. Because
-- everything lands in one shared env, the implicit cross-module globals the mod
-- relies on (RD_effects_manager calls RD_CycleManager.* without requiring it)
-- resolve exactly as they do in game.

local M = {}

local SEARCH_DIRS = { "client", "server", "shared", "shared/definitions", "server/items", "" }

-- Modules that live in OTHER mods. The environment already provides their
-- globals, so requiring them is a no-op rather than a failure.
local EXTERNAL = {
    MF_ISMoodle = true,
    ISBaseObject = true,
}

local function fileExists(path)
    local f = io.open(path, "r")
    if f then f:close() return true end
    return false
end

-- Loads one file into `env` and runs it. Returns whatever the chunk returned.
function M.loadFile(env, path)
    local chunk, err = loadfile(path)
    if not chunk then
        error("failed to parse " .. path .. ": " .. tostring(err), 0)
    end
    setfenv(chunk, env)
    local ok, result = pcall(chunk)
    if not ok then
        error("error while loading " .. path .. ": " .. tostring(result), 0)
    end
    return result
end

-- Installs the require shim. `luaRoot` is the absolute path to media/lua.
function M.install(env, luaRoot)
    env.__loaded = {}
    env.__luaRoot = luaRoot

    local function resolve(name)
        -- PZ module names are flat, but tolerate dotted names just in case.
        local relative = string.gsub(name, "%.", "/")
        for _, dir in ipairs(SEARCH_DIRS) do
            local path = luaRoot .. "/" .. (dir == "" and "" or (dir .. "/")) .. relative .. ".lua"
            if fileExists(path) then return path end
        end
        return nil
    end

    env.require = function(name)
        if EXTERNAL[name] then return true end
        if env.__loaded[name] ~= nil then return env.__loaded[name] end

        local path = resolve(name)
        if not path then
            error("harness require: cannot find module '" .. tostring(name)
                .. "' under " .. luaRoot, 0)
        end

        -- Mark before running so a circular require doesn't recurse forever;
        -- the mod's modules publish themselves as globals anyway.
        env.__loaded[name] = true
        local result = M.loadFile(env, path)
        if result ~= nil then env.__loaded[name] = result end
        return env.__loaded[name]
    end

    env.__test.resolve = resolve
    return env
end

-- Loads the full client-side mod exactly as the game would: RD_main.lua pulls in
-- every other client module and registers all event hooks.
function M.loadClient(env)
    return env.require("RD_main")
end

-- Loads the server side (command handlers). Separate environment in MP tests.
function M.loadServer(env)
    return env.require("RD_server_commands")
end

return M
