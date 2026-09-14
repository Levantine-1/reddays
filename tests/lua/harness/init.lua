-- Convenience entry point: build a ready-to-use world in one call.
--
--   local H = require "harness.init"
--   local w = H.newWorld{ sandbox = { follicular_phase_max_days = 45 } }
--   w.sim.advanceDays(w.env, 30)

local M = {}

local envLib = require "harness.env"
local loaderLib = require "harness.loader"
local simLib = require "harness.sim"

M.env = envLib
M.loader = loaderLib
M.sim = simLib

-- Config injected by run.py before any suite loads.
local function hostConfig()
    return rawget(_G, "RD_TEST_CONFIG") or
        error("RD_TEST_CONFIG not set -- run the suite through tests/run.py", 0)
end

M.hostConfig = hostConfig

-- Sandbox defaults parsed from the real sandbox-options.txt, merged with overrides.
local function buildSandbox(overrides)
    local sandbox = {}
    for k, v in pairs(hostConfig().sandbox) do sandbox[k] = v end
    for k, v in pairs(overrides or {}) do sandbox[k] = v end
    return sandbox
end
M.buildSandbox = buildSandbox

-- opts:
--   sandbox     table of SandboxVars.RedDays overrides
--   seed        RNG seed (default 1)
--   player      opts for the player double (female, health, traits, ...)
--   isClient / isServer
--   autoStart   fire OnGameStart to initialise player data (default true)
--   load        "client" (default) | "server" | "none"
function M.newWorld(opts)
    opts = opts or {}
    local config = hostConfig()

    local env = envLib.new({
        sandbox = buildSandbox(opts.sandbox),
        seed = opts.seed or 1,
        isClient = opts.isClient,
        isServer = opts.isServer,
        player = opts.player,
        gameTime = opts.gameTime,
        activatedMods = opts.activatedMods,
    })
    loaderLib.install(env, config.luaRoot)

    local what = opts.load or "client"
    if what == "client" then
        loaderLib.loadClient(env)
    elseif what == "server" then
        loaderLib.loadServer(env)
    end

    local world = {
        env = env,
        sim = simLib,
        loader = loaderLib,
        t = env.__test,
    }

    -- Shorthands used constantly in suites.
    function world.advanceMinutes(n, o) return simLib.advanceMinutes(env, n, o) end
    function world.advanceHours(n, o) return simLib.advanceHours(env, n, o) end
    function world.advanceDays(n, o) return simLib.advanceDays(env, n, o) end
    function world.advanceUntil(p, limit, o) return simLib.advanceUntil(env, p, limit, o) end

    function world.start()
        env.__test.events.fire("OnGameStart")
        return world
    end

    -- The mod's per-player state root: player:getModData().ICdata
    function world.icdata()
        return env.__test.player.modData.ICdata
    end

    function world.cycle()
        local ic = world.icdata()
        return ic and ic.currentCycle
    end

    if what == "client" and opts.autoStart ~= false then
        world.start()
    end

    return world
end

return M
