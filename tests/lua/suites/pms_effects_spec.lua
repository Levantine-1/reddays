-- RD_effects_pms.lua: the individual PMS symptom effects.

local T = require "runner"
local H = require "harness.init"

local function stat(w, name) return w.t.player.stats:get(w.env.CharacterStat[name]) end
local function setStat(w, name, v) w.t.player.stats:__seed(w.env.CharacterStat[name], v) end
local function stiffness(w, partName)
    return w.t.player.bodyDamage:getBodyPart(w.env.BodyPartType[partName]):getStiffness()
end
local function setStiffness(w, partName, v)
    w.t.player.bodyDamage:getBodyPart(w.env.BodyPartType[partName]).stiffness = v
end

local function statsWorld(isClient)
    local w = H.newWorld({ isClient = isClient })
    setStat(w, "ENDURANCE", 0.5)
    setStat(w, "FATIGUE", 0.2)
    setStat(w, "UNHAPPINESS", 10)
    return w, w.t.player.stats, w.env.RD_EffectsPMS
end

-- Luteal cycle pinned at maximum PMS severity, with only the listed symptoms on.
local function peakWorld(symptoms)
    local w = H.newWorld()
    local cycle = w.cycle()
    cycle.current_phase = "lutealPhase"
    cycle.pms_duration_mins = 7 * 1440
    cycle.phase_minutes_remaining = 0
    cycle.healthEffectSeverity = 100
    for _, key in ipairs({ "pms_agitation", "pms_cramps", "pms_fatigue", "pms_tenderBreasts",
                           "pms_craveFood", "pms_Sadness" }) do
        cycle[key] = symptoms[key] == true
    end
    return w
end

T.describe("PMS agitation", function()

    T.it("raises anger in steps up to the severity, and boosts endurance", function()
        local w, stats, PMS = statsWorld()
        PMS.setAngerMoodle(stats, 50, 1)
        T.near(stat(w, "ANGER"), 0.02, 1e-12)
        T.near(stat(w, "ENDURANCE"), 0.5 + 0.0053 * 0.5, 1e-12)

        for _ = 1, 40 do PMS.setAngerMoodle(stats, 50, 1) end
        T.near(stat(w, "ANGER"), 0.5, 1e-12, "held at the severity")
    end)

    T.it("drops anger to the severity when it is above it", function()
        local w, stats, PMS = statsWorld()
        setStat(w, "ANGER", 0.9)
        PMS.setAngerMoodle(stats, 50, 1)
        T.near(stat(w, "ANGER"), 0.5, 1e-12)
    end)

    T.it("never pushes endurance past 1", function()
        local w, stats, PMS = statsWorld()
        setStat(w, "ENDURANCE", 1)
        PMS.setAngerMoodle(stats, 100, 1)
        T.near(stat(w, "ENDURANCE"), 1, 1e-12)
    end)

end)

T.describe("PMS fatigue", function()

    T.it("adds fatigue and drains endurance, scaled by severity", function()
        local w, stats, PMS = statsWorld()
        PMS.setFatigueEffect(stats, 100, 1)
        T.near(stat(w, "FATIGUE"), 0.2 + 0.00034, 1e-12)
        T.near(stat(w, "ENDURANCE"), 0.5 - 0.00134, 1e-12)

        -- Each world has its own CharacterStat handles, so use that world's module too.
        local h, hstats, hPMS = statsWorld()
        hPMS.setFatigueEffect(hstats, 50, 1)
        T.near(stat(h, "FATIGUE"), 0.2 + 0.00017, 1e-12)
    end)

    T.it("stays within 0..1", function()
        local w, stats, PMS = statsWorld()
        setStat(w, "FATIGUE", 1)
        setStat(w, "ENDURANCE", 0)
        PMS.setFatigueEffect(stats, 100, 1)
        T.near(stat(w, "FATIGUE"), 1, 1e-12)
        T.near(stat(w, "ENDURANCE"), 0, 1e-12)
    end)

end)

T.describe("PMS sadness", function()

    T.it("moves unhappiness one point toward the target, either way", function()
        local w, stats, PMS = statsWorld()
        PMS.setSadnessMoodle(stats, 50, 1)
        T.near(stat(w, "UNHAPPINESS"), 11, 1e-12)

        setStat(w, "UNHAPPINESS", 60)
        PMS.setSadnessMoodle(stats, 50, 1)
        T.near(stat(w, "UNHAPPINESS"), 59, 1e-12)

        setStat(w, "UNHAPPINESS", 50)
        PMS.setSadnessMoodle(stats, 50, 1)
        T.near(stat(w, "UNHAPPINESS"), 50, 1e-12)
    end)

end)

T.describe("PMS food cravings", function()

    T.it("jumps hunger to peckish once, until the player eats", function()
        local w, stats, PMS = statsWorld()
        setStat(w, "HUNGER", 0.05)
        PMS.setFoodCravingEffect(stats, 100, 1)
        T.near(stat(w, "HUNGER"), 0.16, 1e-12)

        setStat(w, "HUNGER", 0.2)
        PMS.setFoodCravingEffect(stats, 100, 1)
        T.near(stat(w, "HUNGER"), 0.2, 1e-12, "already past peckish")

        setStat(w, "HUNGER", 0.05)  -- ate, so hunger dropped
        PMS.setFoodCravingEffect(stats, 100, 1)
        T.near(stat(w, "HUNGER"), 0.16, 1e-12, "the craving comes back")
    end)

    T.it("does not trigger below the severity's hunger threshold", function()
        local w, stats, PMS = statsWorld()
        setStat(w, "HUNGER", 0.05)
        PMS.setFoodCravingEffect(stats, 0, 1)  -- threshold 0.1
        T.near(stat(w, "HUNGER"), 0.05, 1e-12)
    end)

end)

T.describe("PMS cramps and tender breasts", function()

    T.it("cramps stiffen the groin and lower torso in steps of 2 up to the target", function()
        local w, stats, PMS = statsWorld()
        PMS.setCrampsEffect(stats, 50, 1)
        T.eq(stiffness(w, "Groin"), 2)
        T.eq(stiffness(w, "Torso_Lower"), 2)
        for _ = 1, 40 do PMS.setCrampsEffect(stats, 50, 1) end
        T.eq(stiffness(w, "Groin"), 50)
    end)

    T.it("on an MP client, cramps go to the server instead of being set locally", function()
        local w, stats, PMS = statsWorld(true)
        PMS.setCrampsEffect(stats, 50, 1)
        T.eq(stiffness(w, "Groin"), 0)
        local sent = w.t.sentCommands[#w.t.sentCommands]
        T.eq(sent.command, "applyBodyStiffness")
        T.eq(sent.args.Groin, 2)
        T.eq(sent.args.Torso_Lower, 2)
    end)

    T.it("tender breasts stiffen the upper torso, at half strength alongside cramps", function()
        local w, stats, PMS = statsWorld()
        for _ = 1, 40 do PMS.setTenderBreastsEffect(stats, 50, 1, false) end
        T.eq(stiffness(w, "Torso_Upper"), 50)

        local c, cstats, cPMS = statsWorld()
        for _ = 1, 40 do cPMS.setTenderBreastsEffect(cstats, 50, 1, true) end
        T.eq(stiffness(c, "Torso_Upper"), 26, "target 25, reached in steps of 2")
    end)

end)

T.describe("PMS effects main loop", function()

    T.it("a fresh painkiller relaxes active stiffness once", function()
        local w = peakWorld({ pms_tenderBreasts = true })
        setStiffness(w, "Torso_Upper", 40)
        setStiffness(w, "Groin", 40)
        w.icdata().pill_recently_taken = true

        w.env.RD_EffectsPMS.applyPMSEffectsMain()
        T.eq(stiffness(w, "Torso_Upper"), 24.5, "reset to 22.5, then this minute's +2")
        T.eq(stiffness(w, "Groin"), 40, "cramps are off, so the groin is untouched")
        T.falsy(w.icdata().pill_recently_taken)

        w.env.RD_EffectsPMS.applyPMSEffectsMain()
        T.eq(stiffness(w, "Torso_Upper"), 26.5, "no second reset")
    end)

    T.it("does nothing outside the PMS window", function()
        local w = peakWorld({ pms_agitation = true, pms_Sadness = true })
        w.cycle().current_phase = "follicularPhase"
        setStat(w, "UNHAPPINESS", 10)
        w.env.RD_EffectsPMS.applyPMSEffectsMain()
        T.eq(stat(w, "ANGER"), 0)
        T.near(stat(w, "UNHAPPINESS"), 10, 1e-12)
    end)

end)
