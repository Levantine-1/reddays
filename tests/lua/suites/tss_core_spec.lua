-- RD_tss_manager.lua: the toxic shock syndrome state machine.
--
-- TSS can kill a player, so every rule that moves a stage, drains health, or ends an
-- infection is pinned here. The tick is driven directly (RD_TSSManager.EveryOneMinute) so the
-- cycle clock never moves, with the cycle parked outside the red phase so hygiene wear-down
-- never touches the items under test.

local T = require "runner"
local H = require "harness.init"
local MP = require "harness.mp"

local HYGIENE = "RedDays:HygieneItem"
local SICKNESS_RAMP = (1.0 - 0.26) / (12 * 60)
local SICKNESS_RECOVERY = 1.0 / (12 * 60)

local function merge(a, b)
    local out = {}
    for k, v in pairs(a or {}) do out[k] = v end
    for k, v in pairs(b or {}) do out[k] = v end
    return out
end

-- Complications are off unless a test turns them on, so nothing random happens by default.
local function tssWorld(sandbox, opts)
    opts = opts or {}
    local w = H.newWorld({
        sandbox = merge({ tss_complication_chance_pct = 0 }, sandbox),
        seed = opts.seed,
        isClient = opts.isClient,
        verboseLog = opts.verboseLog,
    })
    local cycle = w.cycle()
    cycle.current_phase = "follicularPhase"
    cycle.phase_minutes_remaining = 100000
    return w
end

local function tssOf(w) return w.icdata().tss end
local function setTSS(w, fields)
    local tss = tssOf(w)
    for k, v in pairs(fields) do tss[k] = v end
    return tss
end
local function tick(w, n)
    for _ = 1, (n or 1) do w.env.RD_TSSManager.EveryOneMinute() end
end
local function stat(w, name) return w.t.player.stats:get(w.env.CharacterStat[name]) end
local function setStat(w, name, v) w.t.player.stats:__seed(w.env.CharacterStat[name], v) end
local function health(w) return w.t.player.bodyDamage.health end
local function setHealth(w, v) w.t.player.bodyDamage.health = v end
local function groin(w) return w.t.player.bodyDamage:getBodyPart(w.env.BodyPartType.Groin) end

local function wear(w, typeName, opts)
    opts = opts or {}
    local item = w.t.newItem({
        type = typeName, bodyLocation = HYGIENE, condition = opts.condition, name = opts.name,
    })
    w.t.player.worn:add(item, HYGIENE)
    return item
end

local function dose(w)
    local pill = w.t.newItem({ type = "Antibiotics", fullType = "Base.Antibiotics", isFood = true })
    w.env.RD_TSSManager.registerTreatmentFromItem(pill, "test")
end

local function stage3(w, fields)
    return setTSS(w, merge({ stage = 3, stage_threshold = 0, stage3_minutes = 58, tss_risk = 120 * 50 }, fields))
end

local function stage4(w, fields)
    return setTSS(w, merge({
        stage = 4, stage_threshold = 0, abx_toxin_level = 100, abx_dose_count = 0,
        abx_suppress_mins = 0, abx_bank_points = 0,
    }, fields))
end

-- ================= SOURCE =================

T.describe("TSS source detection", function()

    T.it("a tampon becomes the source only once the grace period has passed", function()
        local w = tssWorld({ tss_tampon_grace_hours = 1 })
        wear(w, "Tampon")

        tick(w, 1)
        T.eq(tssOf(w).wear_minutes, 0, "the first tick only records the item")
        T.falsy(tssOf(w).source_active)

        tick(w, 59)
        T.eq(tssOf(w).wear_minutes, 59)
        T.falsy(tssOf(w).source_active)

        tick(w, 1)
        T.truthy(tssOf(w).source_active, "60 minutes worn is the 1 hour grace")
        T.eq(tssOf(w).source_type, "tampon")
    end)

    T.it("swapping to another item restarts the wear clock", function()
        local w = tssWorld({ tss_tampon_grace_hours = 1 })
        local first = wear(w, "Tampon")
        tick(w, 30)
        T.eq(tssOf(w).wear_minutes, 29)

        w.t.player.worn:remove(first)
        wear(w, "Tampon")
        tick(w, 1)
        T.eq(tssOf(w).wear_minutes, 0)
    end)

    T.it("taking the item off clears the source", function()
        local w = tssWorld({ tss_tampon_grace_hours = 0 })
        local tampon = wear(w, "Tampon")
        tick(w, 1)
        T.truthy(tssOf(w).source_active)

        w.t.player.worn:remove(tampon)
        tick(w, 1)
        T.falsy(tssOf(w).source_active)
        T.eq(tssOf(w).source_item_id, -1)
        T.eq(tssOf(w).wear_minutes, 0)
        T.eq(tssOf(w).source_type, "")
    end)

    T.it("a pad or liner is a source only when dirty and the groin is wounded", function()
        local w = tssWorld()
        local pad = wear(w, "Sanitary_Pad", { condition = 2 })

        tick(w, 1)
        T.falsy(tssOf(w).source_active, "dirty, but no wound")

        groin(w).cut = true
        tick(w, 1)
        T.truthy(tssOf(w).source_active)
        T.eq(tssOf(w).source_type, "pad_or_liner")

        pad.condition = 8
        tick(w, 1)
        T.falsy(tssOf(w).source_active, "wounded, but the pad is clean")

        pad.name = "Sanitary_Pad (Dirty)"
        tick(w, 1)
        T.truthy(tssOf(w).source_active, "a Dirty name counts as dirty")
    end)

end)

-- ================= PROGRESSION =================

T.describe("TSS progression", function()

    T.it("reaches stage 1 when exposure reaches the rolled threshold", function()
        local w = tssWorld({
            tss_tampon_grace_hours = 0,
            tss_stage0_duration_lowerBound = 1, tss_stage0_duration_upperBound = 1,
            tss_stage1_duration_lowerBound = 2, tss_stage1_duration_upperBound = 2,
        })
        wear(w, "Tampon")

        tick(w, 59)
        T.eq(tssOf(w).stage, 0)
        T.eq(tssOf(w).stage_threshold, 60)
        T.eq(tssOf(w).exposure_minutes, 59)

        tick(w, 1)
        T.eq(tssOf(w).stage, 1)
        T.eq(tssOf(w).stage_threshold, 120, "the next threshold comes from the stage 1 bounds")
        T.eq(tssOf(w).severity, 1, "severity starts building in the same minute")
    end)

    T.it("stress speeds up exposure", function()
        local w = tssWorld({ tss_tampon_grace_hours = 0 })
        setStat(w, "THIRST", 0.9)  -- +0.5 -> 1.5x
        wear(w, "Tampon")
        tick(w, 2)
        T.near(tssOf(w).exposure_minutes, 3, 1e-9)
    end)

    T.it("exposure fades by 2 a minute with no source", function()
        local w = tssWorld()
        setTSS(w, { exposure_minutes = 10 })
        tick(w, 3)
        T.eq(tssOf(w).exposure_minutes, 4)
        tick(w, 3)
        T.eq(tssOf(w).exposure_minutes, 0, "never below zero")
    end)

    T.it("worsens a stage each time severity reaches the threshold", function()
        local w = tssWorld({
            tss_tampon_grace_hours = 0,
            tss_stage2_duration_lowerBound = 3, tss_stage2_duration_upperBound = 3,
        })
        wear(w, "Tampon")
        setTSS(w, { stage = 1, severity = 0, stage_threshold = 5 })

        tick(w, 4)
        T.eq(tssOf(w).stage, 1)
        T.eq(tssOf(w).severity, 4)

        tick(w, 1)
        T.eq(tssOf(w).stage, 2)
        T.eq(tssOf(w).severity, 0)
        T.eq(tssOf(w).stage_threshold, 180)

        setTSS(w, { stage_threshold = 2 })
        tick(w, 2)
        T.eq(tssOf(w).stage, 3)
        T.eq(tssOf(w).stage_threshold, 0, "stage 3 has no severity threshold")

        tick(w, 500)
        T.eq(tssOf(w).stage, 3, "only the toxic-shock roll moves past stage 3")
    end)

end)

-- ================= RECOVERY =================

T.describe("TSS recovery", function()

    T.it("drops one stage per recovery period once the source is removed", function()
        local w = tssWorld({ tss_recovery_hours_per_stage = 1 })
        setTSS(w, { stage = 2, severity = 30, stage_threshold = 500, exposure_minutes = 900 })

        tick(w, 59)
        T.eq(tssOf(w).stage, 2)
        T.eq(tssOf(w).recovery_timer, 59)
        T.eq(tssOf(w).severity, 30, "severity is frozen while recovering")

        tick(w, 1)
        T.eq(tssOf(w).stage, 1)
        T.eq(tssOf(w).recovery_timer, 0)

        tick(w, 60)
        T.eq(tssOf(w).stage, 0)
        T.eq(tssOf(w).exposure_minutes, 0)
        T.eq(tssOf(w).stage_threshold, 0)
    end)

    T.it("recovers twice as fast while the antibiotic bank is active", function()
        local w = tssWorld({ tss_recovery_hours_per_stage = 1 })
        setTSS(w, { stage = 2, stage_threshold = 500, abx_bank_points = 10, abx_bank_drain_per_min = 0.001 })
        tick(w, 30)
        T.eq(tssOf(w).stage, 1)
    end)

    T.it("loses recovery progress if the source comes back", function()
        local w = tssWorld({ tss_recovery_hours_per_stage = 1, tss_tampon_grace_hours = 0 })
        setTSS(w, { stage = 2, stage_threshold = 500 })
        tick(w, 30)
        T.eq(tssOf(w).recovery_timer, 30)

        wear(w, "Tampon")
        tick(w, 1)
        T.eq(tssOf(w).recovery_timer, 0)
        T.eq(tssOf(w).severity, 1)
    end)

end)

-- ================= TOXIC SHOCK =================

T.describe("TSS stage 3 to toxic shock", function()

    T.it("never rolls toxic shock before tss_min_stage3_hours", function()
        local w = tssWorld({ tss_min_stage3_hours = 1 })
        stage3(w)
        w.t.rng.script({ 0 })  -- a guaranteed hit, whenever a roll happens

        tick(w, 1)  -- 59 of the 60 minutes
        T.eq(tssOf(w).stage, 3)

        tick(w, 1)  -- 60: the roll happens and hits
        T.eq(tssOf(w).stage, 4)
    end)

    T.it("never rolls toxic shock when lethal TSS is disabled", function()
        local w = tssWorld({ tss_min_stage3_hours = 1, tss_lethal_enabled = false })
        stage3(w, { stage3_minutes = 600 })
        w.t.rng.script({ 0 })
        tick(w, 5)
        T.eq(tssOf(w).stage, 3)
    end)

    T.it("REGRESSION: earlier antibiotics do not let toxic shock cure itself", function()
        -- A player who took antibiotics at stages 1-3 keeps recovery_mode = "antibiotics".
        -- Toxic shock used to start without resetting it, so sickness DECAYED, and within
        -- hours TSS reset itself to stage 0 without any antibiotic course.
        local w = tssWorld({ tss_min_stage3_hours = 1 })
        stage3(w, { stage3_minutes = 59, recovery_mode = "antibiotics" })
        w.t.rng.script({ 0 })

        tick(w, 1)
        T.eq(tssOf(w).stage, 4)
        T.eq(tssOf(w).recovery_mode, "none")

        tick(w, 600)  -- ten hours, no antibiotics
        T.eq(tssOf(w).stage, 4, "toxic shock needs the antibiotic course to end")
        T.truthy(stat(w, "SICKNESS") > 0.26, "sickness rises during toxic shock")
    end)

    T.it("REGRESSION: enters stage 4 with a full toxin score and rising sickness", function()
        local w = tssWorld({ tss_min_stage3_hours = 1 })
        stage3(w, { stage3_minutes = 59, abx_dose_count = 3, abx_bank_points = 5 })
        w.t.rng.script({ 0 })

        tick(w, 1)

        local tss = tssOf(w)
        T.eq(tss.stage, 4)
        T.eq(tss.abx_toxin_level, 100)
        T.eq(tss.abx_dose_count, 0, "earlier doses do not count toward the stage 4 course")
        T.eq(tss.abx_bank_points, 0)
        T.eq(tss.tss_risk, 0)
        T.near(stat(w, "SICKNESS"), 0.26 + SICKNESS_RAMP, 1e-9)
    end)

    T.it("halves the toxic-shock risk gain while stabilized", function()
        local w = tssWorld({ tss_min_stage3_hours = 0 })
        setStat(w, "FATIGUE", 0.95)  -- +3 risk a minute
        stage3(w, { tss_risk = 0, stage3_minutes = 0 })

        tick(w, 1)
        T.eq(tssOf(w).tss_risk, 3)

        setTSS(w, { tss_risk = 0, stabilized_until = 100 })
        tick(w, 1)
        T.eq(tssOf(w).tss_risk, 1, "floor(3 * 0.5)")
    end)

end)

-- ================= ANTIBIOTICS =================

T.describe("TSS antibiotics", function()

    T.it("ignores antibiotics when there is no infection", function()
        local w = tssWorld()
        dose(w)
        T.eq(tssOf(w).abx_dose_count, 0)
        T.eq(tssOf(w).abx_bank_points, 0)
    end)

    T.it("a dose fills the bank and starts the suppression window", function()
        local w = tssWorld({ tss_abx_dose_cooldown_hours = 12, tss_abx_suppress_window_hours = 12 })
        setTSS(w, { stage = 2 })
        dose(w)

        local tss = tssOf(w)
        T.eq(tss.abx_dose_count, 1)
        T.eq(tss.abx_bank_points, 10)
        T.eq(tss.abx_bank_cap, 10)
        T.eq(tss.abx_suppress_mins, 720)
        T.truthy(tss.stabilized_until >= 720)
        T.eq(tss.recovery_mode, "antibiotics")
        T.near(tss.abx_bank_drain_per_min, 10 / 720, 1e-12)
    end)

    T.it("the bank drains at bank / cooldown minutes", function()
        local w = tssWorld({ tss_abx_dose_cooldown_hours = 12 })
        setTSS(w, { stage = 2, stage_threshold = 100000 })
        dose(w)
        tick(w, 60)
        T.near(tssOf(w).abx_bank_points, 10 - 60 * (10 / 720), 1e-9)
    end)

    T.it("at stage 4 draining the bank clears toxin at the pills-to-cure rate", function()
        local w = tssWorld({ tss_abx_pills_to_cure = 5, tss_abx_dose_cooldown_hours = 12 })
        stage4(w)
        dose(w)
        tick(w, 36)  -- drains 0.5 bank points
        T.near(tssOf(w).abx_toxin_level, 99, 1e-9, "5 pills to cure = 2 toxin per bank point")
    end)

    T.it("toxin at zero with at least one dose ends toxic shock", function()
        local w = tssWorld()
        stage4(w, { abx_toxin_level = 0, abx_dose_count = 1, recovery_timer = 50 })
        tick(w, 1)
        local tss = tssOf(w)
        T.eq(tss.stage, 3)
        T.eq(tss.recovery_mode, "antibiotics")
        T.eq(tss.recovery_timer, 0)
        T.eq(tss.stage3_minutes, 0)
    end)

    T.it("toxin at zero without any dose does not end toxic shock", function()
        local w = tssWorld()
        stage4(w, { abx_toxin_level = 0, abx_dose_count = 0 })
        tick(w, 1)
        T.eq(tssOf(w).stage, 4)
    end)

    T.it("a full default course, taken as the bank empties, ends toxic shock", function()
        -- Defaults: 10 pills to cure, 12 h cooldown. The player takes the next pill as soon as
        -- the bank runs dry, which is what the cooldown ETA tells them to do.
        local w = tssWorld()
        stage4(w)
        local ticks = 0
        for doseNumber = 1, 10 do
            dose(w)
            while (tssOf(w).abx_bank_points or 0) > 0 and tssOf(w).stage == 4 and ticks < 20000 do
                tick(w, 1)
                ticks = ticks + 1
            end
            if tssOf(w).stage ~= 4 then
                T.eq(doseNumber, 10, "toxic shock ended before the full course")
                break
            end
        end
        if tssOf(w).stage == 4 then tick(w, 1) end
        T.eq(tssOf(w).stage, 3, "a full course must end toxic shock; toxin left: "
            .. tostring(tssOf(w).abx_toxin_level))
        T.eq(tssOf(w).abx_dose_count, 10)
        T.truthy(health(w) > 0, "the player survived the course")
    end)

end)

-- ================= STAGE 4 HEALTH =================

T.describe("TSS stage 4 health drain", function()

    T.it("without antibiotics the drain can kill, awake", function()
        local w = tssWorld()
        stage4(w)
        setHealth(w, 0.1)
        tick(w, 1)
        T.eq(health(w), 0)
        T.eq(tssOf(w)._lastHPDrainMode, "stage4_sickness_drain")
    end)

    T.it("the awake drain scales with tss_stage4_hp_drain_pct", function()
        local w = tssWorld({ tss_stage4_hp_drain_pct = 200 })
        stage4(w)
        tick(w, 1)
        T.near(health(w), 100 - 0.30, 1e-9)
    end)

    T.it("asleep, the drain uses tss_stage4_sleep_hp_drain_pct", function()
        local w = tssWorld({ tss_stage4_sleep_hp_drain_pct = 50 })
        stage4(w)
        w.t.player.asleep = true
        tick(w, 1)
        T.near(health(w), 100 - 0.075, 1e-9)
        T.eq(tssOf(w)._lastHPDrainMode, "stage4_sleep_drain")
    end)

    T.it("with antibiotics above the cap it drains, but never below the cap", function()
        local w = tssWorld({ tss_abx_sleep_health_cap_pct = 50 })
        stage4(w, { abx_suppress_mins = 100 })
        setHealth(w, 60)
        tick(w, 1)
        T.near(health(w), 59.85, 1e-9)
        T.eq(tssOf(w)._lastHPDrainMode, "abx_cap_sickness_drain")

        setHealth(w, 50.05)
        tick(w, 1)
        T.eq(health(w), 50)
    end)

    T.it("with antibiotics at the cap and awake, the trickle is floored at the cap", function()
        local w = tssWorld({ tss_abx_sleep_health_cap_pct = 50 })
        stage4(w, { abx_suppress_mins = 100 })
        setHealth(w, 50)
        tick(w, 1)
        T.eq(health(w), 50)
        T.eq(tssOf(w)._lastHPDrainMode, "abx_flat_drain")
    end)

    T.it("with antibiotics below the cap and asleep, health recovers toward the cap", function()
        local w = tssWorld({ tss_abx_sleep_health_cap_pct = 50 })
        stage4(w, { abx_suppress_mins = 100 })
        w.t.player.asleep = true
        setHealth(w, 40)
        tick(w, 1)
        T.near(health(w), 40.05, 1e-9)
        T.eq(tssOf(w)._lastHPDrainMode, "abx_sleep_regen")

        setHealth(w, 49.99)
        tick(w, 1)
        T.eq(health(w), 50, "never above the cap")
    end)

    T.it("never lets the player die while antibiotics are active", function()
        local w = tssWorld({ tss_abx_sleep_health_cap_pct = 50 })
        stage4(w, { abx_suppress_mins = 100000 })
        w.t.player.thermo.core = 39.5  -- 3x drain
        setHealth(w, 55)
        local lowest = 100
        for minute = 1, 3000 do
            w.t.player.asleep = (minute % 400) < 200
            tick(w, 1)
            if health(w) < lowest then lowest = health(w) end
        end
        T.truthy(lowest >= 50, "health dropped to " .. lowest)
    end)

    T.it("scales the drain with body temperature", function()
        local cases = {
            { 37.0, 1.0 }, { 37.75, 1.5 }, { 38.5, 2.0 }, { 38.75, 2.5 }, { 39.0, 3.0 }, { 41.0, 3.0 },
            { 36.55, 1.05 }, { 36.1, 1.10 }, { 34.9, 1.25 }, { 29.9, 1.70 }, { 24.9, 2.20 },
            { 20.0, 2.40 }, { 10.0, 2.40 },
        }
        for _, case in ipairs(cases) do
            local w = tssWorld()
            stage4(w)
            w.t.player.thermo.core = case[1]
            tick(w, 1)
            T.near(tssOf(w)._lastHPDrainMult, case[2], 1e-9, "at " .. case[1] .. "C")
        end
    end)

end)

-- ================= SICKNESS AND BLUR =================

T.describe("TSS sickness and blurred vision", function()

    T.it("stage 4 ramps sickness at the 12-hour rate", function()
        local w = tssWorld()
        stage4(w)
        setStat(w, "SICKNESS", 0.5)
        tick(w, 1)
        T.near(stat(w, "SICKNESS"), 0.5 + SICKNESS_RAMP, 1e-9)
    end)

    T.it("the suppression window freezes sickness", function()
        local w = tssWorld()
        stage4(w, { abx_suppress_mins = 100 })
        setStat(w, "SICKNESS", 0.5)
        tick(w, 1)
        T.near(stat(w, "SICKNESS"), 0.5, 1e-9)
    end)

    T.it("sickness never passes 1.0", function()
        local w = tssWorld()
        stage4(w)
        setStat(w, "SICKNESS", 0.9995)
        tick(w, 1)
        T.near(stat(w, "SICKNESS"), 1.0, 1e-9)
    end)

    T.it("after toxic shock, sickness decays and a near-zero value resets TSS", function()
        local w = tssWorld()
        stage3(w, { stage3_minutes = 0, tss_risk = 0, recovery_mode = "antibiotics", exposure_minutes = 900 })
        setStat(w, "SICKNESS", 0.5)
        tick(w, 1)
        T.near(stat(w, "SICKNESS"), 0.5 - SICKNESS_RECOVERY, 1e-9)

        setStat(w, "SICKNESS", 0.021)
        tick(w, 1)
        local tss = tssOf(w)
        T.eq(stat(w, "SICKNESS"), 0)
        T.eq(tss.stage, 0)
        T.eq(tss.recovery_mode, "none")
        T.eq(tss.exposure_minutes, 0)
    end)

    T.it("stages 0-3 slowly clear stray sickness", function()
        local w = tssWorld()
        setStat(w, "SICKNESS", 0.1)
        tick(w, 1)
        T.near(stat(w, "SICKNESS"), 0.1 - 0.0002, 1e-12)
    end)

    T.it("blurs vision at stage 3 and clears it when the stage drops", function()
        local w = tssWorld({ tss_recovery_hours_per_stage = 100 })
        stage3(w, { stage3_minutes = 0, tss_risk = 0 })
        tick(w, 35)
        T.near(w.t.player.sleepingTabletEffect, 0.35, 1e-9)
        tick(w, 5)
        T.near(w.t.player.sleepingTabletEffect, 0.35, 1e-9, "holds at the stage 3 target")

        setTSS(w, { stage = 2, stage_threshold = 100000 })
        tick(w, 44)
        T.near(w.t.player.sleepingTabletEffect, 0, 1e-9)
    end)

    -- The game fades the sleeping-tablet effect on its own every frame, and clears it during
    -- sleep (IsoGameCharacter.updateInternal, confirmed via bytecode). The harness has no such
    -- fade, so these tests apply one between ticks.
    local function fadeAndTick(w, minutes, fadePerMinute)
        local p = w.t.player
        for _ = 1, minutes do
            p.sleepingTabletEffect = math.max(0, p.sleepingTabletEffect - fadePerMinute)
            tick(w, 1)
        end
    end

    T.it("once toxic shock resolves straight to stage 0, TSS lets the blur fade", function()
        -- Sickness can finish decaying while TSS is still at stage 3 (treated early), which
        -- resets straight to stage 0 while vision is still blurred.
        local w = tssWorld()
        stage3(w, { stage3_minutes = 0, tss_risk = 0, recovery_mode = "antibiotics", baseline_blur_effect = 0 })
        w.t.player.sleepingTabletEffect = 0.35
        setStat(w, "SICKNESS", 0.021)

        tick(w, 1)
        T.eq(tssOf(w).stage, 0, "sanity: the reset happened")

        fadeAndTick(w, 60, 0.01)
        T.near(w.t.player.sleepingTabletEffect, 0, 1e-9, "TSS must not keep pushing the blur back up")
    end)

    T.it("at stage 3, TSS holds vision blurred against the game's fade", function()
        local w = tssWorld({ tss_recovery_hours_per_stage = 100 })
        stage3(w, { stage3_minutes = 0, tss_risk = 0 })
        w.t.player.sleepingTabletEffect = 0.35
        fadeAndTick(w, 60, 0.005)
        T.near(w.t.player.sleepingTabletEffect, 0.35, 1e-9)
    end)

end)

-- ================= STAT EFFECTS =================

T.describe("TSS per-stage stat effects", function()

    local function seeded(stageFields, asleep)
        local w = tssWorld({ tss_recovery_hours_per_stage = 100 })
        setTSS(w, merge({ stage_threshold = 100000 }, stageFields))
        setStat(w, "ENDURANCE", 0.5)
        setStat(w, "FATIGUE", 0.2)
        setStat(w, "THIRST", 0.1)
        setStat(w, "UNHAPPINESS", 10)
        w.t.player.asleep = asleep == true
        tick(w, 1)
        return w
    end

    T.it("stage 1: mild fatigue, and sadness even while asleep", function()
        local w = seeded({ stage = 1 })
        T.near(stat(w, "ENDURANCE"), 0.5 - 0.00005, 1e-12)
        T.near(stat(w, "FATIGUE"), 0.2 + 0.0002, 1e-12)
        T.near(stat(w, "UNHAPPINESS"), 10.05, 1e-12)

        local s = seeded({ stage = 1 }, true)
        T.near(stat(s, "ENDURANCE"), 0.5, 1e-12)
        T.near(stat(s, "FATIGUE"), 0.2, 1e-12)
        T.near(stat(s, "UNHAPPINESS"), 10.05, 1e-12)
    end)

    T.it("stage 2: more fatigue and thirst while awake", function()
        local w = seeded({ stage = 2 })
        T.near(stat(w, "ENDURANCE"), 0.5 - 0.0002, 1e-12)
        T.near(stat(w, "FATIGUE"), 0.2 + 0.0004, 1e-12)
        T.near(stat(w, "THIRST"), 0.1 + 0.001, 1e-12)
        T.near(stat(w, "UNHAPPINESS"), 10.1, 1e-12)

        local s = seeded({ stage = 2 }, true)
        T.near(stat(s, "THIRST"), 0.1, 1e-12)
        T.near(stat(s, "UNHAPPINESS"), 10.1, 1e-12)
    end)

    T.it("stage 3: the heaviest fatigue and thirst", function()
        local w = seeded({ stage = 3, stage3_minutes = 0, tss_risk = 0 })
        T.near(stat(w, "ENDURANCE"), 0.5 - 0.0007, 1e-12)
        T.near(stat(w, "FATIGUE"), 0.2 + 0.001, 1e-12)
        T.near(stat(w, "THIRST"), 0.1 + 0.002, 1e-12)
        T.near(stat(w, "UNHAPPINESS"), 10.2, 1e-12)
    end)

    T.it("stage 4 at the sickness plateau pins endurance down and fatigue up, awake", function()
        local w = tssWorld()
        stage4(w, { abx_suppress_mins = 100 })
        setStat(w, "SICKNESS", 0.95)
        setStat(w, "ENDURANCE", 0.95)
        setStat(w, "FATIGUE", 0.1)
        tick(w, 1)
        T.near(stat(w, "ENDURANCE"), 0.8, 1e-12)
        T.near(stat(w, "FATIGUE"), 0.4, 1e-12)
    end)

end)

-- ================= FEVER =================

T.describe("TSS fever pressure", function()

    local function feverWorld(fields, sickness, core)
        local w = tssWorld()
        stage4(w, fields)
        setStat(w, "SICKNESS", sickness)
        w.t.player.thermo.core = core
        return w
    end
    local function nudges(w) return #w.t.player:callsOf("stats:add") end

    T.it("only runs at stage 4 outside the suppression window", function()
        local w = feverWorld({ stage = 3 }, 1.0, 38.5)
        w.env.RD_TSSManager.ApplyFeverPressure(w.t.player)
        T.eq(nudges(w), 0)

        local s = feverWorld({ abx_suppress_mins = 100 }, 1.0, 38.5)
        s.env.RD_TSSManager.ApplyFeverPressure(s.t.player)
        T.eq(nudges(s), 0)
    end)

    T.it("waits for the game's own fever to set in first", function()
        local w = feverWorld({}, 0.5, 38.5)
        w.env.RD_TSSManager.ApplyFeverPressure(w.t.player)
        T.eq(nudges(w), 0, "sickness below 0.91")

        local c = feverWorld({}, 1.0, 37.5)
        c.env.RD_TSSManager.ApplyFeverPressure(c.t.player)
        T.eq(nudges(c), 0, "core temperature below 37.8C")
    end)

    T.it("nudges temperature once enough game time has passed", function()
        local w = feverWorld({}, 1.0, 38.5)
        w.t.gameTime.secondsSinceLastUpdate = 1
        local before = stat(w, "TEMPERATURE")
        w.env.RD_TSSManager.ApplyFeverPressure(w.t.player)
        w.env.RD_TSSManager.ApplyFeverPressure(w.t.player)
        T.eq(nudges(w), 0, "2 of the 3 game-seconds")

        w.env.RD_TSSManager.ApplyFeverPressure(w.t.player)
        T.eq(nudges(w), 1)
        T.truthy(stat(w, "TEMPERATURE") > before, "temperature went up")
        T.truthy(tssOf(w)._pendingTemperatureAdd > 0, "and is banked for the server")
    end)

    T.it("an MP client hands the banked temperature to the server on the minute tick", function()
        local pair = MP.newPair({ sandbox = { tss_complication_chance_pct = 0 } })
        local w = pair.client
        w.cycle().current_phase = "follicularPhase"
        w.cycle().phase_minutes_remaining = 100000
        stage4(w)
        setStat(w, "SICKNESS", 1.0)
        w.t.player.thermo.core = 38.5
        w.env.RD_TSSManager.ApplyFeverPressure(w.t.player)
        local banked = tssOf(w)._pendingTemperatureAdd
        T.truthy(banked > 0)

        tick(w, 1)

        T.near(pair.lastCommand("applyTSSStats").payload.temperatureAdd, banked, 1e-12)
        T.eq(tssOf(w)._pendingTemperatureAdd, 0)
    end)

end)

-- ================= WARNINGS AND COMPLICATIONS =================

T.describe("TSS warnings and complications", function()

    T.it("repeats the warning once per warning interval", function()
        local w = tssWorld({ tss_recovery_hours_per_stage = 100, tss_warning_interval_mins = 180 }, { verboseLog = true })
        setTSS(w, { stage = 1, stage_threshold = 100000 })
        tick(w, 360)
        local count = 0
        for _ in string.gmatch(w.t.log(), "Possible TSS warning") do count = count + 1 end
        T.eq(count, 2)
    end)

    local function complicationWorld(stageFields, script)
        local w = tssWorld({ tss_complication_chance_pct = 5, tss_recovery_hours_per_stage = 100 })
        setTSS(w, merge({ stage_threshold = 100000, complication_cooldown = 1 }, stageFields))
        setStat(w, "ENDURANCE", 0.5)
        setStat(w, "FATIGUE", 0.2)
        setStat(w, "UNHAPPINESS", 10)
        w.t.rng.script(script)
        tick(w, 1)
        return w
    end

    T.it("an infection flare adds severity", function()
        local w = complicationWorld({ stage = 1 }, { 0, 70, 10 })
        T.eq(tssOf(w).severity, 40)
    end)

    T.it("a severe infection spike needs stage 2", function()
        T.eq(tssOf(complicationWorld({ stage = 1 }, { 0, 90 })).severity, 0)
        T.eq(tssOf(complicationWorld({ stage = 2 }, { 0, 90, 30 })).severity, 150)
    end)

    T.it("a systemic stress spike needs stage 3", function()
        T.eq(tssOf(complicationWorld({ stage = 2 }, { 0, 98 })).tss_risk, 0)
        local w = complicationWorld({ stage = 3, stage3_minutes = 0, tss_risk = 0 }, { 0, 98, 10 })
        T.eq(tssOf(w).tss_risk, 30)
    end)

    T.it("a mild flare saps energy and mood, sparing energy while asleep", function()
        local w = complicationWorld({ stage = 1 }, { 0, 10 })
        T.near(stat(w, "FATIGUE"), 0.2 + 0.1 + 0.0002, 1e-12)
        T.near(stat(w, "ENDURANCE"), 0.5 - 0.05 - 0.00005, 1e-12)
        T.near(stat(w, "UNHAPPINESS"), 10 + 5 + 0.05, 1e-12)
    end)

    T.it("the complication chance is capped at 60%", function()
        local w = tssWorld({ tss_complication_chance_pct = 100, tss_recovery_hours_per_stage = 100 })
        setTSS(w, { stage = 1, stage_threshold = 100000, complication_cooldown = 1 })
        w.t.rng.script({ 60, 70, 10 })
        tick(w, 1)
        T.eq(tssOf(w).severity, 0, "a roll of 60 misses a 60% cap")
    end)

end)
