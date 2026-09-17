-- PMS stat effects in multiplayer.
--
-- The hosted-MP self-test proved character stats are server-authoritative: a client's direct
-- stats:set() is reverted by the server. Agitation, fatigue, food cravings and sadness used to
-- change stats only on the client, so in MP they did nothing. They now also send the server
-- the same STEP (applyPMSStats), which it applies to its own live value.

local T = require "runner"
local H = require "harness.init"
local MP = require "harness.mp"

-- Pins a luteal cycle at maximum PMS severity without advancing the cycle clock, with the
-- four stat-based symptoms on and the two stiffness-based ones off.
local function pinPeakPMS(world)
    local cycle = world.cycle()
    cycle.current_phase = "lutealPhase"
    cycle.pms_duration_mins = 7 * 1440
    cycle.phase_minutes_remaining = 0
    cycle.healthEffectSeverity = 100
    cycle.pms_agitation = true
    cycle.pms_cramps = false
    cycle.pms_fatigue = true
    cycle.pms_tenderBreasts = false
    cycle.pms_craveFood = true
    cycle.pms_Sadness = true
end

local START = { ANGER = 0, ENDURANCE = 0.5, FATIGUE = 0.2, HUNGER = 0.05, UNHAPPINESS = 10 }
local SYNCED = { "ANGER", "ENDURANCE", "FATIGUE", "HUNGER", "UNHAPPINESS" }

local function seed(world, values)
    for name, v in pairs(values) do
        world.t.player.stats:__seed(world.env.CharacterStat[name], v)
    end
end

local function statOf(world, name)
    return world.t.player.stats:get(world.env.CharacterStat[name])
end

local function tick(world, n)
    for _ = 1, n do world.env.RD_EffectsPMS.applyPMSEffectsMain() end
end

T.describe("PMS stat effects on a multiplayer client", function()

    T.it("REGRESSION: sends its PMS stat effects to the server, which converges", function()
        local pair = MP.newPair()
        pinPeakPMS(pair.client)
        seed(pair.client, START)
        seed(pair.server, START)

        tick(pair.client, 5)

        T.eq(#pair.commandsNamed("applyPMSStats"), 5, "one command per effects tick")
        for _, name in ipairs(SYNCED) do
            T.near(statOf(pair.server, name), statOf(pair.client, name), 1e-9,
                name .. " on the server must match the client")
        end
        T.near(statOf(pair.server, "ANGER"), 0.10, 1e-9, "5 steps of 0.02")
        T.near(statOf(pair.server, "UNHAPPINESS"), 15, 1e-9, "5 steps of 1")
        T.near(statOf(pair.server, "HUNGER"), 0.16, 1e-9, "the craving jump")
    end)

    T.it("applies each step to the server's own value, not the client's", function()
        -- The server keeps changing stats on its own (vanilla anger decay etc.), so the command
        -- carries a step and a target, never a final value computed from the client's copy.
        local pair = MP.newPair()
        pinPeakPMS(pair.client)
        seed(pair.client, START)
        seed(pair.server, { ANGER = 0.3, ENDURANCE = 0.5, FATIGUE = 0.2, HUNGER = 0.05, UNHAPPINESS = 40 })

        tick(pair.client, 1)

        T.near(statOf(pair.server, "ANGER"), 0.32, 1e-9)
        T.near(statOf(pair.server, "UNHAPPINESS"), 41, 1e-9)
        T.near(statOf(pair.client, "ANGER"), 0.02, 1e-9, "the client moved its own copy")
    end)

    T.it("scales the anger target by an active painkiller", function()
        local pair = MP.newPair()
        pinPeakPMS(pair.client)
        pair.client.icdata().pill_effect_active = true

        tick(pair.client, 1)

        local record = pair.lastCommand("applyPMSStats")
        T.notNil(record)
        T.near(record.payload.angerTarget, 0.5, 1e-9, "default painkiller halves the target")
        T.near(record.payload.unhappinessTarget, 50, 1e-9)
    end)

    T.it("sends nothing when PMS is not active", function()
        local pair = MP.newPair()
        pinPeakPMS(pair.client)
        pair.client.cycle().current_phase = "follicularPhase"

        tick(pair.client, 3)

        T.eq(#pair.commandsNamed("applyPMSStats"), 0)
    end)

    T.it("sends nothing for stiffness-only symptoms, which keep their own command", function()
        local pair = MP.newPair()
        pinPeakPMS(pair.client)
        local cycle = pair.client.cycle()
        cycle.pms_agitation, cycle.pms_fatigue, cycle.pms_craveFood, cycle.pms_Sadness = false, false, false, false
        cycle.pms_cramps = true

        tick(pair.client, 1)

        T.eq(#pair.commandsNamed("applyPMSStats"), 0)
        T.eq(#pair.commandsNamed("applyBodyStiffness"), 1)
    end)

end)

T.describe("PMS stat effects in single player", function()

    T.it("changes stats locally with no network traffic", function()
        local w = H.newWorld({ isClient = false })
        pinPeakPMS(w)
        seed(w, START)

        tick(w, 5)

        T.eq(#w.t.sentCommands, 0)
        T.near(statOf(w, "ANGER"), 0.10, 1e-9)
        T.near(statOf(w, "UNHAPPINESS"), 15, 1e-9)
        T.near(statOf(w, "HUNGER"), 0.16, 1e-9)
    end)

end)
