-- RD_cycle_manager.lua -- the phase/duration engine.

local T = require "runner"
local H = require "harness.init"

local DAY = 1440

-- Sandbox values chosen so every ZombRand(lo, hi) range has exactly one legal
-- result, making cycle generation deterministic regardless of seed.
-- ZombRand(a, b) is max-EXCLUSIVE, so {3,4} always yields 3.
local FIXED = {
    red_phase_duration_lowerBound = 3,        red_phase_duration_upperBound = 4,
    follicular_phase_duration_lowerBound = 12, follicular_phase_duration_upperBound = 13,
    ovulation_phase_duration_lowerBound = 1,  ovulation_phase_duration_upperBound = 2,
    luteal_phase_duration_lowerBound = 11,    luteal_phase_duration_upperBound = 12,
    menstrual_cycle_duration_lowerBound = 27, menstrual_cycle_duration_upperBound = 27,
    PMS_duration_lowerbound = 7,              PMS_duration_upperbound = 8,
    healthEffectLowerBound = 50,              healthEffectUpperBound = 51,
    phase_start_delay_enabled = false,
}

-- A complete, valid cycle table for tests that drive tick()/getPhaseStatus directly.
local function makeCycle(overrides)
    local cycle = {
        current_phase = "redPhase",
        phase_minutes_remaining = 3 * DAY,
        redPhase_duration_mins = 3 * DAY,
        follicularPhase_duration_mins = 12 * DAY,
        ovulationPhase_duration_mins = 1 * DAY,
        lutealPhase_duration_mins = 11 * DAY,
        cycle_duration_mins = 27 * DAY,
        stiffness_target = 50,
        stiffness_increment = 2,
        discomfort_target = 50,
        endurance_decrement = 0.001,
        fatigue_increment = 0.0002,
        healthEffectSeverity = 50,
        pms_duration_mins = 7 * DAY,
        pms_agitation = false, pms_cramps = true, pms_fatigue = true,
        pms_tenderBreasts = false, pms_craveFood = false, pms_Sadness = false,
        reason_for_cycle = "test",
        traumaDelayAppliedThisCycle = false,
    }
    for k, v in pairs(overrides or {}) do cycle[k] = v end
    return cycle
end

-- Builds a world and installs `cycle` as the active one.
local function worldWith(cycle, sandbox)
    local w = H.newWorld({ sandbox = sandbox or FIXED })
    w.env.RD_modData.ICdata.currentCycle = cycle
    return w
end

T.describe("RD_CycleManager.tick", function()

    T.it("decrements the countdown by the tick size", function()
        local w = worldWith(makeCycle({ phase_minutes_remaining = 500 }))
        w.env.RD_CycleManager.tick(1)
        T.eq(w.cycle().phase_minutes_remaining, 499)
        w.env.RD_CycleManager.tick(10)
        T.eq(w.cycle().phase_minutes_remaining, 489)
    end)

    T.it("rejects a non-positive tick without altering the cycle", function()
        local w = worldWith(makeCycle({ phase_minutes_remaining = 500 }))
        w.env.RD_CycleManager.tick(0)
        w.env.RD_CycleManager.tick(-5)
        T.eq(w.cycle().phase_minutes_remaining, 500)
    end)

    T.it("advances through the phases in order", function()
        local order = { "redPhase", "follicularPhase", "ovulationPhase", "lutealPhase" }
        for i = 1, #order - 1 do
            local w = worldWith(makeCycle({
                current_phase = order[i],
                phase_minutes_remaining = 1,
            }))
            w.env.RD_CycleManager.tick(1)
            T.eq(w.cycle().current_phase, order[i + 1],
                 order[i] .. " should advance to " .. order[i + 1])
        end
    end)

    T.it("carries overflow minutes into the next phase", function()
        -- 30 minutes past the end of red phase: follicular starts 30 minutes in.
        local w = worldWith(makeCycle({
            current_phase = "redPhase",
            phase_minutes_remaining = 10,
        }))
        w.env.RD_CycleManager.tick(40)
        T.eq(w.cycle().current_phase, "follicularPhase")
        T.eq(w.cycle().phase_minutes_remaining, (12 * DAY) - 30)
    end)

    T.it("generates a fresh cycle when luteal phase ends", function()
        local w = worldWith(makeCycle({
            current_phase = "lutealPhase",
            phase_minutes_remaining = 1,
            reason_for_cycle = "the_old_one",
        }))
        w.env.RD_CycleManager.tick(1)
        local cycle = w.cycle()
        T.eq(cycle.current_phase, "redPhase", "a new cycle starts in red phase")
        T.contains(cycle.reason_for_cycle, "tick_endOfCycle")
        T.neq(cycle.reason_for_cycle, "the_old_one")
    end)

    T.it("regenerates rather than crashing on a structurally broken cycle", function()
        local w = worldWith({ current_phase = nil })
        local cycle = w.env.RD_CycleManager.tick(1)
        T.notNil(cycle)
        T.truthy(w.env.RD_CycleManager.isCycleValid(cycle))
    end)

    T.it("walks multiple phase boundaries in a single large tick", function()
        -- One tick longer than red + follicular + ovulation: should land in luteal.
        local w = worldWith(makeCycle({
            current_phase = "redPhase",
            phase_minutes_remaining = 3 * DAY,
        }))
        w.env.RD_CycleManager.tick((3 * DAY) + (12 * DAY) + (1 * DAY) + 60)
        T.eq(w.cycle().current_phase, "lutealPhase")
        T.eq(w.cycle().phase_minutes_remaining, (11 * DAY) - 60)
    end)

end)

T.describe("RD_CycleManager.getPhaseStatus", function()

    T.it("reports progress through the current phase", function()
        local w = worldWith(makeCycle())
        local status = w.env.RD_CycleManager.getPhaseStatus(makeCycle({
            current_phase = "follicularPhase",
            phase_minutes_remaining = 6 * DAY,   -- half of a 12-day follicular phase
        }))
        T.eq(status.phase, "follicularPhase")
        T.near(status.percent_complete, 50)
        T.near(status.time_remaining, 6)          -- days, for display compatibility
        T.eq(status.time_remaining_mins, 6 * DAY)
    end)

    T.it("clamps percentage into 0-100 when time has overrun", function()
        local w = worldWith(makeCycle())
        local over = w.env.RD_CycleManager.getPhaseStatus(makeCycle({
            current_phase = "redPhase",
            phase_minutes_remaining = -500,
        }))
        T.between(over.percent_complete, 0, 100)

        local under = w.env.RD_CycleManager.getPhaseStatus(makeCycle({
            current_phase = "redPhase",
            phase_minutes_remaining = 99 * DAY,
        }))
        T.between(under.percent_complete, 0, 100)
    end)

    T.it("returns false for a cycle with no phase", function()
        local w = worldWith(makeCycle())
        T.falsy(w.env.RD_CycleManager.getPhaseStatus({}))
        T.falsy(w.env.RD_CycleManager.getPhaseStatus(nil))
    end)

end)

T.describe("RD_CycleManager.isCycleValid", function()

    local REQUIRED = {
        "current_phase", "phase_minutes_remaining",
        "redPhase_duration_mins", "follicularPhase_duration_mins",
        "ovulationPhase_duration_mins", "lutealPhase_duration_mins",
        "cycle_duration_mins", "healthEffectSeverity",
        "pms_duration_mins", "reason_for_cycle",
    }

    T.it("accepts a well-formed cycle", function()
        local w = worldWith(makeCycle())
        T.truthy(w.env.RD_CycleManager.isCycleValid(makeCycle()))
    end)

    T.it("rejects a cycle missing any required field", function()
        local w = worldWith(makeCycle())
        for _, field in ipairs(REQUIRED) do
            local broken = makeCycle()
            broken[field] = nil
            T.falsy(w.env.RD_CycleManager.isCycleValid(broken),
                    "should reject a cycle missing '" .. field .. "'")
        end
    end)

    T.it("rejects an unknown phase name", function()
        local w = worldWith(makeCycle())
        T.falsy(w.env.RD_CycleManager.isCycleValid(makeCycle({ current_phase = "menopause" })))
    end)

end)

T.describe("RD_CycleManager.getPMSseverity", function()

    T.it("is zero outside luteal and red phases", function()
        for _, phase in ipairs({ "follicularPhase", "ovulationPhase" }) do
            local w = worldWith(makeCycle({ current_phase = phase }))
            T.eq(w.env.RD_CycleManager.getPMSseverity(), 0, "expected 0 during " .. phase)
        end
    end)

    T.it("ramps from 0 to 100 across the PMS window at the end of luteal", function()
        local pms = 7 * DAY
        local cases = {
            { remaining = pms,       expected = 0 },    -- PMS just beginning
            { remaining = pms / 2,   expected = 50 },
            { remaining = 0,         expected = 100 },  -- period about to start
        }
        for _, case in ipairs(cases) do
            local w = worldWith(makeCycle({
                current_phase = "lutealPhase",
                pms_duration_mins = pms,
                phase_minutes_remaining = case.remaining,
            }))
            T.near(w.env.RD_CycleManager.getPMSseverity(), case.expected, 0.001)
        end
    end)

    T.it("stays at zero earlier in luteal, before the PMS window opens", function()
        local w = worldWith(makeCycle({
            current_phase = "lutealPhase",
            pms_duration_mins = 7 * DAY,
            phase_minutes_remaining = 10 * DAY,
        }))
        T.eq(w.env.RD_CycleManager.getPMSseverity(), 0)
    end)

    T.it("drains from 100 to 0 over the first day of red phase", function()
        local red = 3 * DAY
        local cases = {
            { intoRed = 0,      expected = 100 },
            { intoRed = 720,    expected = 50 },
            { intoRed = DAY,    expected = 0 },
            { intoRed = 2 * DAY, expected = 0 },   -- past the first day
        }
        for _, case in ipairs(cases) do
            local w = worldWith(makeCycle({
                current_phase = "redPhase",
                redPhase_duration_mins = red,
                phase_minutes_remaining = red - case.intoRed,
            }))
            T.near(w.env.RD_CycleManager.getPMSseverity(), case.expected, 0.001,
                   "at " .. case.intoRed .. " minutes into red phase")
        end
    end)

end)

T.describe("RD_CycleManager.newCycle", function()

    T.it("builds phase durations from the sandbox ranges", function()
        local w = H.newWorld({ sandbox = FIXED })
        local cycle = w.env.RD_CycleManager.newCycle("test")
        T.eq(cycle.redPhase_duration_mins, 3 * DAY)
        T.eq(cycle.follicularPhase_duration_mins, 12 * DAY)
        T.eq(cycle.ovulationPhase_duration_mins, 1 * DAY)
        T.eq(cycle.lutealPhase_duration_mins, 11 * DAY)
        T.eq(cycle.cycle_duration_mins, 27 * DAY)
    end)

    T.it("records who asked for the cycle", function()
        local w = H.newWorld({ sandbox = FIXED })
        T.eq(w.env.RD_CycleManager.newCycle("someCaller").reason_for_cycle, "someCaller")
    end)

    T.it("falls back to the default cycle when the ranges cannot be satisfied", function()
        -- Phase ranges sum to 27 days but the total is required to be 100.
        local impossible = {}
        for k, v in pairs(FIXED) do impossible[k] = v end
        impossible.menstrual_cycle_duration_lowerBound = 100
        impossible.menstrual_cycle_duration_upperBound = 100

        local w = H.newWorld({ sandbox = impossible })
        local cycle = w.env.RD_CycleManager.newCycle("caller")
        T.contains(cycle.reason_for_cycle, "_fallbackDefault")
        T.eq(cycle.cycle_duration_mins, 28 * DAY, "the default cycle is 28 days")
        T.truthy(w.env.RD_CycleManager.isCycleValid(cycle))
        T.contains(w.t.log(), "Failed to generate valid cycle after 10 attempts")
    end)

    T.it("produces a cycle that always passes its own validity check", function()
        local w = H.newWorld({ sandbox = FIXED })
        for seed = 1, 25 do
            w.t.rng.reseed(seed)
            local cycle = w.env.RD_CycleManager.newCycle("seed" .. seed)
            T.truthy(w.env.RD_CycleManager.isCycleValid(cycle), "invalid cycle at seed " .. seed)
        end
    end)

end)

T.describe("first-cycle start delay", function()

    T.it("starts in luteal for the delay period and latches cycleDelayed", function()
        local sandbox = {}
        for k, v in pairs(FIXED) do sandbox[k] = v end
        sandbox.phase_start_delay_enabled = true
        sandbox.phase_start_delay_lowerBound = 5
        sandbox.phase_start_delay_upperBound = 6   -- max-exclusive, so always 5

        local w = H.newWorld({ sandbox = sandbox })
        local cycle = w.cycle()
        T.eq(cycle.current_phase, "lutealPhase",
             "the first cycle should wait out the delay in luteal phase")
        T.eq(cycle.phase_minutes_remaining, 5 * DAY)
        T.truthy(w.env.RD_modData.ICdata.cycleDelayed, "cycleDelayed should latch")
    end)

    T.it("starts directly in red phase once the delay has been used", function()
        local sandbox = {}
        for k, v in pairs(FIXED) do sandbox[k] = v end
        sandbox.phase_start_delay_enabled = true
        sandbox.phase_start_delay_lowerBound = 5
        sandbox.phase_start_delay_upperBound = 6

        local w = H.newWorld({ sandbox = sandbox })
        -- Second cycle: the latch is set, so no further delay is applied.
        local cycle = w.env.RD_CycleManager.newCycle("second")
        T.eq(cycle.current_phase, "redPhase")
        T.eq(cycle.phase_minutes_remaining, 3 * DAY)
    end)

    T.it("starts in red phase when the delay option is off", function()
        local w = H.newWorld({ sandbox = FIXED })   -- phase_start_delay_enabled = false
        T.eq(w.cycle().current_phase, "redPhase")
    end)

end)
