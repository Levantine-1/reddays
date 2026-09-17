-- shared/RD_config.lua's verboseLog switch and the client/server RD_zapi.log / rdLog helpers
-- that gate non-debugger diagnostic prints (see CLAUDE.md's "verboseLog" note).

local T = require "runner"
local H = require "harness.init"

T.describe("RD_Config.verboseLog", function()

    T.it("defaults to false", function()
        local w = H.newWorld()
        T.falsy(w.env.RD_Config.verboseLog)
    end)

    T.it("RD_zapi.log stays silent by default", function()
        local w = H.newWorld()
        w.env.RD_zapi.log("should not appear")
        T.eq(#w.t.printed, 0)
    end)

    T.it("RD_zapi.log prints once verboseLog is on", function()
        -- autoStart off: OnGameStart's own initializePlayerData prints plenty when verboseLog is
        -- on (new cycle, etc), which would pollute this count -- not what's under test here.
        local w = H.newWorld({ verboseLog = true, autoStart = false })
        local before = #w.t.printed
        w.env.RD_zapi.log("should appear")
        T.eq(#w.t.printed, before + 1)
        T.eq(w.t.printed[#w.t.printed], "should appear")
    end)

    T.it("gates the diagnostic prints from a real code path (cycle regeneration on invalid data)", function()
        local w = H.newWorld({ verboseLog = true })
        w.icdata().currentCycle = { current_phase = "not_a_real_phase" }  -- fails isCycleValid
        w.env.RD_CycleManager.LoadPlayerData()
        local sawRegenMessage = false
        for _, line in ipairs(w.t.printed) do
            if line:find("Regenerating cycle", 1, true) then sawRegenMessage = true end
        end
        T.truthy(sawRegenMessage, "expected the regenerate-cycle diagnostic once verboseLog is on")
    end)

    T.it("stays silent for that same code path when verboseLog is off (the release default)", function()
        local w = H.newWorld()
        w.icdata().currentCycle = { current_phase = "not_a_real_phase" }
        w.env.RD_CycleManager.LoadPlayerData()
        T.eq(#w.t.printed, 0, "no diagnostic noise expected with verboseLog off")
    end)

end)
