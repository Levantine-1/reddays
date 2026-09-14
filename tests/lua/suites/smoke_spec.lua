-- Proves the harness itself works: the real mod files load unmodified into a
-- sandboxed environment, register their hooks, and initialise player data.

local T = require "runner"
local H = require "harness.init"

T.describe("harness smoke", function()

    T.it("loads every client module without error", function()
        local w = H.newWorld({ autoStart = false })
        T.notNil(w.env.RD_zapi, "RD_zapi should be defined")
        T.notNil(w.env.RD_CycleManager, "RD_CycleManager should be defined")
        T.notNil(w.env.RD_CycleIrregularity)
        T.notNil(w.env.RD_HygieneManager)
        T.notNil(w.env.RD_TSSManager)
        T.notNil(w.env.RD_moodles)
        T.notNil(w.env.RD_EffectsPMS)
        T.notNil(w.env.RD_EffectsManager)
        T.notNil(w.env.RD_CycleTrackerLogic)
        T.notNil(w.env.RD_CycleDebugger)
    end)

    T.it("registers the event hooks RD_main.lua wires up", function()
        local w = H.newWorld({ autoStart = false })
        local events = w.t.events
        for _, name in ipairs({ "OnGameStart", "OnCreatePlayer", "EveryHours",
                                "EveryTenMinutes", "EveryOneMinute", "EveryDays",
                                "OnPlayerUpdate" }) do
            T.truthy(#events.handlersFor(name) > 0, "no handler registered for " .. name)
        end
    end)

    T.it("creates player data on game start", function()
        local w = H.newWorld()
        local ic = w.icdata()
        T.notNil(ic, "ICdata should exist after OnGameStart")
        T.notNil(ic.currentCycle, "a cycle should be generated")
        T.truthy(w.env.RD_CycleManager.isCycleValid(ic.currentCycle),
                 "the generated cycle should pass the mod's own validity check")
    end)

    T.it("isolates state between worlds", function()
        local a = H.newWorld({ seed = 1 })
        local b = H.newWorld({ seed = 2 })
        a.icdata().marker = "a"
        T.isNil(b.icdata().marker, "worlds must not share modData")
    end)

    T.it("advances in-game time through the real registered handlers", function()
        local w = H.newWorld()
        local before = w.cycle().phase_minutes_remaining
        w.advanceMinutes(30)
        local after = w.cycle().phase_minutes_remaining
        T.neq(after, before, "30 minutes of ticks should move the cycle countdown")
    end)

    T.it("produces identical results for identical seeds", function()
        local a = H.newWorld({ seed = 12345 })
        local b = H.newWorld({ seed = 12345 })
        T.eq(a.cycle().cycle_duration_mins, b.cycle().cycle_duration_mins)
        T.eq(a.cycle().current_phase, b.cycle().current_phase)
    end)

end)
