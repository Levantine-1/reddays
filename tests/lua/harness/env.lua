-- Builds a fresh sandboxed global environment per test.
--
-- Mod files are loaded into this table with setfenv(), so each test gets its own
-- RD_* globals, its own RD_modData, and its own event registrations. Nothing
-- leaks between tests.

local M = {}

local rngLib = require "harness.rng"
local eventsLib = require "harness.events"
local enumsLib = require "harness.doubles.enums"
local playerLib = require "harness.doubles.player"
local itemLib = require "harness.doubles.item"
local gameTimeLib = require "harness.doubles.gametime"
local mfLib = require "harness.doubles.moodleframework"
local actionsLib = require "harness.doubles.actions"

-- Standard library exposed to mod code. Deliberately narrow:
--
--  * `next` is OMITTED because PZ's Kahlua VM does not provide it. The mod has a
--    comment at RD_tss_manager.lua:975 working around exactly that. Leaving it
--    out means a test fails here rather than the player crashing in game.
--  * io / os / dofile / loadfile are omitted; mod code has no business there.
local STDLIB = {
    "assert", "error", "ipairs", "pairs", "pcall", "xpcall", "select",
    "setmetatable", "getmetatable", "rawget", "rawset", "rawequal", "rawlen",
    "tonumber", "tostring", "type", "unpack", "loadstring", "setfenv", "getfenv",
    "table", "string", "math",
}

-- config:
--   sandbox      table of SandboxVars.RedDays values (from the real .txt)
--   seed         RNG seed (default 1)
--   isClient     bool (default false)
--   isServer     bool (default false)
--   player       opts forwarded to the player double
--   activatedMods list of mod names (default includes MoodleFramework)
--   selftest     RD_Config.selftest (default false, whatever shared/RD_config.lua ships)
--   verboseLog   RD_Config.verboseLog (default false, whatever shared/RD_config.lua ships)
--   debug        isDebugEnabled() (default false)
function M.new(config)
    config = config or {}

    local env = {}
    for _, name in ipairs(STDLIB) do env[name] = _G[name] end
    env._G = env

    -- ---- build switches ----
    -- Pre-seeded so tests never depend on the value the real file currently ships with.
    env.RD_Config = { selftest = config.selftest == true, verboseLog = config.verboseLog == true }

    -- ---- captured output ----
    local printed = {}
    env.print = function(...)
        local parts = {}
        for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
        printed[#printed + 1] = table.concat(parts, "\t")
    end

    -- ---- deterministic randomness ----
    local rng = rngLib.new(config.seed or 1)
    env.ZombRand = rng.ZombRand
    env.ZombRandFloat = rng.ZombRandFloat

    -- ---- events ----
    local events = eventsLib.new()
    env.Events = events

    -- ---- enums / registries ----
    local enums = enumsLib.build()
    for k, v in pairs(enums) do env[k] = v end

    -- ---- sandbox options ----
    local sandbox = {}
    for k, v in pairs(config.sandbox or {}) do sandbox[k] = v end
    env.SandboxVars = { RedDays = sandbox }

    -- ---- world objects ----
    local player = playerLib.new(enums, config.player)
    local gameTime = gameTimeLib.new(config.gameTime)
    local mf = mfLib.new()
    local actions = actionsLib.new()
    actions.character = player

    env.MF = mf
    for _, className in ipairs({ "ISUnequipAction", "ISWearClothing", "ISWashYourself",
                                "ISTakePillAction", "ISEatFoodAction", "ISDrinkFluidAction" }) do
        env[className] = actions[className]
    end

    env.getPlayer = function() return player end
    env.getSpecificPlayer = function() return player end
    env.getGameTime = function() return gameTime end

    -- ---- real-time clock (getTimestampMs), advanced by __test.tick ----
    local realMs = 1000000
    env.getTimestampMs = function() return realMs end

    -- ---- multiplayer role ----
    local isClient = config.isClient == true
    local isServer = config.isServer == true
    local debugEnabled = config.debug == true
    env.isClient = function() return isClient end
    env.isServer = function() return isServer end
    env.isDebugEnabled = function() return debugEnabled end

    local function singlePlayer() return not isClient and not isServer end

    -- Outbound client->server traffic. mp.lua replaces this with a live bus. In single
    -- player the engine loops it back locally (SinglePlayerClient -> SinglePlayerServer ->
    -- OnClientCommand), so this does the same -- a no-op unless the world also loaded
    -- RD_server_commands.lua.
    local sentCommands = {}
    env.sendClientCommand = function(sender, module, command, args)
        sentCommands[#sentCommands + 1] = {
            player = sender, module = module, command = command, args = args,
        }
        if singlePlayer() then
            events.fire("OnClientCommand", module, command, sender, args)
        end
    end

    -- Server->client traffic: (player, module, command, args) or (module, command, args).
    -- NOT looped back in single player: both real overloads return immediately unless
    -- GameServer.serverZ (confirmed via bytecode), so in SP a reply sent this way is simply
    -- lost. Only client->server loops back. Routed by mp.lua in a pair.
    local serverCommands = {}
    env.sendServerCommand = function(a, b, c, d)
        local module, command, args
        if type(a) == "string" then module, command, args = a, b, c else module, command, args = b, c, d end
        serverCommands[#serverCommands + 1] = { module = module, command = command, args = args }
    end

    local syncedItems = {}
    env.syncItemFields = function(p, item)
        syncedItems[#syncedItems + 1] = { player = p, item = item }
    end

    -- syncVisuals(player) / sendHumanVisual(player): how vanilla pushes body and worn-clothing
    -- visuals (blood, dirt) from the server (ISWashClothing / ISWashYourself).
    local visualSyncs = {}
    env.syncVisuals = function(p)
        visualSyncs[#visualSyncs + 1] = { what = "syncVisuals", player = p }
    end
    env.sendHumanVisual = function(p)
        visualSyncs[#visualSyncs + 1] = { what = "sendHumanVisual", player = p }
    end

    local addedToContainer = {}
    env.sendAddItemToContainer = function(container, item)
        addedToContainer[#addedToContainer + 1] = { container = container, item = item }
    end

    -- ---- misc engine globals ----
    env.instanceof = function(obj, className)
        if type(obj) ~= "table" then return false end
        if className == "Clothing" then return obj.__isClothing == true end
        if className == "InventoryItem" then return obj.__item == true end
        if className == "IsoPlayer" then return obj.__player == true end
        if className == "Food" then return obj.__isFood == true end
        return false
    end

    local triggered = {}
    env.triggerEvent = function(name, ...)
        triggered[#triggered + 1] = name
        events.fire(name, ...)
    end

    local bloodSplats = {}
    env.addBloodSplat = function(square, count, x, z)
        bloodSplats[#bloodSplats + 1] = { square = square, count = count, x = x, z = z }
    end

    local activatedMods = config.activatedMods or { "MoodleFramework" }
    env.getActivatedMods = function()
        return {
            contains = function(_, name)
                for _, m in ipairs(activatedMods) do
                    if m == name then return true end
                end
                return false
            end,
        }
    end

    env.getText = function(key, ...) return key end

    -- getFileWriter / getFileReader (files in the Zomboid/Lua folder), kept in memory per world.
    -- Vanilla usage: getFileWriter(name, createIfNull, append) -> write/close,
    -- getFileReader(name, createIfNull) -> readLine/close.
    local files = {}
    env.getFileWriter = function(name, createIfNull, append)
        local buffer = (append and files[name]) or ""
        return {
            write = function(_, s) buffer = buffer .. tostring(s) end,
            close = function() files[name] = buffer end,
        }
    end
    env.getFileReader = function(name, createIfNull)
        local content = files[name]
        if content == nil then
            if not createIfNull then return nil end
            content = ""
            files[name] = content
        end
        local lines = {}
        for line in string.gmatch(content, "([^\n]*)\n") do lines[#lines + 1] = line end
        local i = 0
        return {
            readLine = function() i = i + 1; return lines[i] end,
            close = function() end,
        }
    end

    -- Script-item tag registry behind the global hasItemTag(String, ItemTag). The real
    -- signature is (String, ItemTag) -- confirmed in LuaManager$GlobalObject -- so a string
    -- tag errors here exactly like the item-level hasTag double does.
    local scriptItemTags = {}
    env.hasItemTag = function(fullType, tag)
        if type(tag) ~= "table" then
            error("No implementation found for function: hasItemTag(string, " .. type(tag)
                .. ") -- the tag must be an ItemTag object, never a raw string", 0)
        end
        local tags = scriptItemTags[fullType]
        return tags ~= nil and tags[tag] == true
    end

    -- RedDays_ProceduralDistributions.lua indexes this at load time and will
    -- error on a nil list entry, so every distribution it names must exist.
    env.ProceduralDistributions = { list = setmetatable({}, {
        __index = function(t, k)
            local entry = { items = {} }
            rawset(t, k, entry)
            return entry
        end,
    }) }

    -- ---- test-facing handles ----
    env.__test = {
        rng = rng,
        events = events,
        enums = enums,
        player = player,
        gameTime = gameTime,
        mf = mf,
        actions = actions,
        sandbox = sandbox,
        printed = printed,
        sentCommands = sentCommands,
        serverCommands = serverCommands,
        syncedItems = syncedItems,
        addedToContainer = addedToContainer,
        visualSyncs = visualSyncs,
        files = files,
        bloodSplats = bloodSplats,
        triggered = triggered,
        newItem = itemLib.new,
        -- Declare script-level tags for a full type, as read by the global hasItemTag.
        setScriptItemTags = function(fullType, tagList)
            local set = {}
            for _, tag in ipairs(tagList) do set[tag] = true end
            scriptItemTags[fullType] = set
        end,
        setRole = function(client, server) isClient = client; isServer = server end,
        setDebug = function(on) debugEnabled = on == true end,
        -- Advances real time by `ms` and fires one OnTick.
        tick = function(ms)
            realMs = realMs + (ms or 0)
            events.fire("OnTick")
        end,
        -- Concatenated print output, for asserting on log lines the mod emits.
        log = function() return table.concat(printed, "\n") end,
    }

    return env
end

return M
