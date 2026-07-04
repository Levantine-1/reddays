RD_CycleDebugger = RD_CycleDebugger or {}
RDCycleDebugger = RD_CycleDebugger -- Alias for backward compatibility
require "RD_cycle_tracker_logic"
require "RD_cycle_manager"
require "RD_hygiene_manager"
require "RD_game_api"

local MINUTES_PER_DAY = 1440
local MINUTES_PER_HOUR = 60

rd = rd or {}
rd.tss = rd.tss or {}
rd.cycle = rd.cycle or {}
rd.hygiene = rd.hygiene or {}
rd.pms = rd.pms or {}
rd.status = rd.status or {}
rd.debug = rd.debug or {}

local TSS_DEFAULTS = {
    stage = 0,
    exposure_minutes = 0,
    severity = 0,
    first_symptom_minutes = 0,
    wear_minutes = 0,
    source_active = false,
    source_removed = false,
    source_type = "",
    source_item_id = -1,
    warning_cooldown = 0,
    cured = false,
    stabilized_until = 0,
    antibiotics_taken_recently = false,
    recovery_mode = "none",
    baseline_blur_effect = 0,
    tss_risk = 0,
    stage_threshold = 0,
    stage3_minutes = 0,
    complication_cooldown = 60,
    abx_toxin_level = 0,
    abx_cooldown_mins = 0,
    abx_suppress_mins = 0,
    abx_dose_count = 0,
    abx_bank_points = 0,
    abx_bank_cap = 0,
    abx_bank_drain_per_min = 0,
    abx_toxin_clear_per_point = 1,
}

local CYCLE_DEFAULTS = {
    current_phase = "redPhase",
    phase_minutes_remaining = 0,
    healthEffectSeverity = 50,
    reason_for_cycle = "debug_override",
}

local function transmitDebugData()
    if not isClient() then return end
    local player = RD_zapi.getPlayer()
    if player then
        player:transmitModData()
    end
end

local function getICData(create)
    local md = RD_zapi.getModData()
    if not md then return nil end
    if create then
        md.ICdata = md.ICdata or {}
    end
    return md.ICdata
end

local function getTSS(create)
    local ic = getICData(create)
    if not ic then return nil end
    if create then
        ic.tss = ic.tss or {}
    elseif not ic.tss then
        return nil
    end

    local tss = ic.tss
    for key, defaultValue in pairs(TSS_DEFAULTS) do
        if tss[key] == nil then
            tss[key] = defaultValue
        end
    end
    return tss
end

local function getCycle(create)
    local ic = getICData(create)
    if not ic then return nil end
    if create then
        ic.currentCycle = ic.currentCycle or {}
    elseif not ic.currentCycle then
        return nil
    end

    local cycle = ic.currentCycle
    for key, defaultValue in pairs(CYCLE_DEFAULTS) do
        if cycle[key] == nil then
            cycle[key] = defaultValue
        end
    end
    return cycle
end

local function clampNumber(value, minValue, maxValue, defaultValue)
    local n = tonumber(value)
    if n == nil then n = defaultValue end
    if minValue ~= nil and n < minValue then n = minValue end
    if maxValue ~= nil and n > maxValue then n = maxValue end
    return n
end

local function clampBoolean(value)
    if type(value) == "boolean" then return value end
    if type(value) == "number" then return value ~= 0 end
    if type(value) == "string" then
        local l = string.lower(value)
        if l == "true" or l == "1" or l == "yes" or l == "on" then return true end
        if l == "false" or l == "0" or l == "no" or l == "off" then return false end
    end
    return false
end

local function asString(value, defaultValue)
    if value == nil then return defaultValue end
    return tostring(value)
end

local function defineAccessor(namespace, name, rootGetter, fieldName, normalizer)
    namespace[name] = namespace[name] or {}

    namespace[name].get = function()
        local root = rootGetter(false)
        if not root then return nil end
        return root[fieldName]
    end

    namespace[name].set = function(value)
        local root = rootGetter(true)
        if not root then return nil end
        local finalValue = normalizer and normalizer(value, root) or value
        root[fieldName] = finalValue
        transmitDebugData()
        return root[fieldName]
    end
end

defineAccessor(rd.tss, "stage", getTSS, "stage", function(v)
    return clampNumber(v, 0, 4, 0)
end)
defineAccessor(rd.tss, "exposure_minutes", getTSS, "exposure_minutes", function(v)
    return clampNumber(v, 0, nil, 0)
end)
defineAccessor(rd.tss, "severity", getTSS, "severity", function(v)
    return clampNumber(v, 0, nil, 0)
end)
defineAccessor(rd.tss, "stage3_minutes", getTSS, "stage3_minutes", function(v)
    return clampNumber(v, 0, nil, 0)
end)
defineAccessor(rd.tss, "stage_threshold", getTSS, "stage_threshold", function(v)
    return clampNumber(v, 0, nil, 0)
end)
defineAccessor(rd.tss, "tss_risk", getTSS, "tss_risk", function(v)
    return clampNumber(v, 0, nil, 0)
end)
defineAccessor(rd.tss, "source_active", getTSS, "source_active", function(v)
    return clampBoolean(v)
end)
defineAccessor(rd.tss, "source_removed", getTSS, "source_removed", function(v)
    return clampBoolean(v)
end)
defineAccessor(rd.tss, "source_type", getTSS, "source_type", function(v)
    return asString(v, "")
end)
defineAccessor(rd.tss, "warning_cooldown", getTSS, "warning_cooldown", function(v)
    return clampNumber(v, 0, nil, 0)
end)
defineAccessor(rd.tss, "stabilized_until", getTSS, "stabilized_until", function(v)
    return clampNumber(v, 0, nil, 0)
end)
defineAccessor(rd.tss, "recovery_mode", getTSS, "recovery_mode", function(v)
    local m = asString(v, "none")
    if m ~= "none" and m ~= "antibiotics" and m ~= "fallback" then
        return "none"
    end
    return m
end)
defineAccessor(rd.tss, "antibiotics_taken_recently", getTSS, "antibiotics_taken_recently", function(v)
    return clampBoolean(v)
end)
defineAccessor(rd.tss, "baseline_blur_effect", getTSS, "baseline_blur_effect", function(v)
    return clampNumber(v, 0, nil, 0)
end)
defineAccessor(rd.tss, "abx_toxin_level", getTSS, "abx_toxin_level", function(v)
    return clampNumber(v, 0, 100, 0)
end)
defineAccessor(rd.tss, "abx_cooldown_mins", getTSS, "abx_cooldown_mins", function(v)
    return clampNumber(v, 0, nil, 0)
end)
defineAccessor(rd.tss, "abx_suppress_mins", getTSS, "abx_suppress_mins", function(v)
    return clampNumber(v, 0, nil, 0)
end)
defineAccessor(rd.tss, "abx_dose_count", getTSS, "abx_dose_count", function(v)
    return clampNumber(v, 0, nil, 0)
end)
defineAccessor(rd.tss, "abx_bank_points", getTSS, "abx_bank_points", function(v)
    return clampNumber(v, 0, nil, 0)
end)
defineAccessor(rd.tss, "abx_bank_cap", getTSS, "abx_bank_cap", function(v)
    return clampNumber(v, 0, nil, 0)
end)
defineAccessor(rd.tss, "abx_bank_drain_per_min", getTSS, "abx_bank_drain_per_min", function(v)
    return clampNumber(v, 0, nil, 0)
end)
defineAccessor(rd.tss, "abx_toxin_clear_per_point", getTSS, "abx_toxin_clear_per_point", function(v)
    return clampNumber(v, 0, nil, 1)
end)

rd.tss.reset_progression = rd.tss.reset_progression or {}
rd.tss.reset_progression.get = function()
    return "Call rd.tss.reset_progression.set(true)"
end
rd.tss.reset_progression.set = function(value)
    if not clampBoolean(value) then return false end
    local tss = getTSS(true)
    if not tss then return false end
    tss.stage = 0
    tss.exposure_minutes = 0
    tss.severity = 0
    tss.stage3_minutes = 0
    tss.stage_threshold = 0
    tss.tss_risk = 0
    tss.warning_cooldown = 0
    tss.abx_toxin_level = 0
    tss.abx_cooldown_mins = 0
    tss.abx_suppress_mins = 0
    tss.abx_dose_count = 0
    tss.abx_bank_points = 0
    tss.abx_bank_cap = 0
    tss.abx_bank_drain_per_min = 0
    tss._feverDrive = 0
    tss._feverAccum = 0
    tss._tempDiagPrinted = nil

    local player = RD_zapi.getPlayer()
    if player then
        local stats = player:getStats()
        if stats then
            stats:set(CharacterStat.SICKNESS, 0)
        end
    end
    transmitDebugData()
    return true
end

rd.debug.speedMult = rd.debug.speedMult or {}

-- rd.debug.speedMult.set(10)  -- compress all time values 10x for fast testing
-- rd.debug.speedMult.set(1)   -- clear override (normal speed on next rolls)
rd.debug.speedMult.get = function()
    return (RD_TSSManager and RD_TSSManager._debugSpeedMult) or 1
end

rd.debug.speedMult.set = function(value)
    local mult = clampNumber(value, 1, 1000, 1)
    local isReset = mult <= 1

    -- Apply or clear TSS speed override
    if RD_TSSManager then
        RD_TSSManager._debugSpeedMult = isReset and nil or mult
    end

    -- Compress current TSS stage_threshold so the active stage advances faster
    local tss = getTSS(false)
    if tss and not isReset and mult > 1 then
        local threshold = tss.stage_threshold or 0
        if threshold > 0 then
            local current = (tss.stage == 0) and (tss.exposure_minutes or 0) or (tss.severity or 0)
            tss.stage_threshold = math.max(math.floor(current) + 5, math.floor(threshold / mult))
        end
    end

    -- Compress current cycle phase_minutes_remaining and all phase duration fields
    local cycle = getCycle(false)
    if cycle and not isReset and mult > 1 then
        cycle.phase_minutes_remaining = math.max(1, math.floor((cycle.phase_minutes_remaining or 1440) / mult))
        for _, phaseName in ipairs({"redPhase", "follicularPhase", "ovulationPhase", "lutealPhase"}) do
            local key = phaseName .. "_duration_mins"
            if cycle[key] then
                cycle[key] = math.max(10, math.floor(cycle[key] / mult))
            end
        end
    end

    transmitDebugData()
    if isReset then
        print("[rd.debug.speedMult] cleared -- normal speed on next threshold/cycle roll")
    else
        print("[rd.debug.speedMult] " .. mult .. "x -- TSS thresholds and cycle durations compressed")
    end
    return mult
end


-- Enable: rd.debug.hunger_thirst_zero.set(true)
-- Disable: rd.debug.hunger_thirst_zero.set(false)
-- Check state: rd.debug.hunger_thirst_zero.get()

rd.debug.hunger_thirst_zero = rd.debug.hunger_thirst_zero or {}

rd.debug.hunger_thirst_zero.get = function()
    return RD_CycleDebugger._debugClampHungerThirst == true
end

rd.debug.hunger_thirst_zero.set = function(value)
    local enabled = clampBoolean(value)
    RD_CycleDebugger._debugClampHungerThirst = enabled
    print("[rd.debug.hunger_thirst_zero] " .. (enabled and "enabled" or "disabled"))
    return enabled
end

function RD_CycleDebugger.ApplyDebugStatClamps(player)
    if RD_CycleDebugger._debugClampHungerThirst ~= true then return end
    if not player then return end
    local stats = player:getStats()
    if not stats then return end
    stats:set(CharacterStat.HUNGER, 0)
    stats:set(CharacterStat.THIRST, 0)
end

defineAccessor(rd.cycle, "current_phase", getCycle, "current_phase", function(v)
    local p = asString(v, "redPhase")
    if p ~= "redPhase" and p ~= "follicularPhase" and p ~= "ovulationPhase" and p ~= "lutealPhase" then
        return "redPhase"
    end
    return p
end)
defineAccessor(rd.cycle, "phase_minutes_remaining", getCycle, "phase_minutes_remaining", function(v)
    return clampNumber(v, 0, nil, 0)
end)
defineAccessor(rd.cycle, "healthEffectSeverity", getCycle, "healthEffectSeverity", function(v)
    return clampNumber(v, 0, 100, 50)
end)
defineAccessor(rd.cycle, "reason_for_cycle", getCycle, "reason_for_cycle", function(v)
    return asString(v, "debug_override")
end)

defineAccessor(rd.hygiene, "cSIHDC_counter", function(create)
    local ic = getICData(create)
    if not ic then return nil end
    if ic.cSIHDC_counter == nil then ic.cSIHDC_counter = 0 end
    return ic
end, "cSIHDC_counter", function(v)
    return clampNumber(v, 0, nil, 0)
end)
defineAccessor(rd.hygiene, "leak_level", function(create)
    local ic = getICData(create)
    if not ic then return nil end
    if ic.LeakLevel == nil then ic.LeakLevel = 0.42 end
    return ic
end, "LeakLevel", function(v)
    return clampNumber(v, 0, 0.42, 0.42)
end)
defineAccessor(rd.hygiene, "leak_switch", function(create)
    local ic = getICData(create)
    if not ic then return nil end
    if ic.LeakSwitchState == nil then ic.LeakSwitchState = false end
    return ic
end, "LeakSwitchState", function(v)
    return clampBoolean(v)
end)

defineAccessor(rd.pms, "pill_recently_taken", function(create)
    local ic = getICData(create)
    if not ic then return nil end
    if ic.pill_recently_taken == nil then ic.pill_recently_taken = false end
    return ic
end, "pill_recently_taken", function(v)
    return clampBoolean(v)
end)
defineAccessor(rd.pms, "pill_effect_active", function(create)
    local ic = getICData(create)
    if not ic then return nil end
    if ic.pill_effect_active == nil then ic.pill_effect_active = false end
    return ic
end, "pill_effect_active", function(v)
    return clampBoolean(v)
end)
defineAccessor(rd.pms, "pill_effect_counter", function(create)
    local ic = getICData(create)
    if not ic then return nil end
    if ic.pill_effect_counter == nil then ic.pill_effect_counter = 0 end
    return ic
end, "pill_effect_counter", function(v)
    return clampNumber(v, 0, nil, 0)
end)

rd.status.get = function()
    local tss = getTSS(false)
    local cycle = getCycle(false)
    local ic = getICData(false)
    return {
        tss = tss and {
            stage = tss.stage,
            stage_threshold = tss.stage_threshold,
            exposure_minutes = tss.exposure_minutes,
            severity = tss.severity,
            stage3_minutes = tss.stage3_minutes,
            tss_risk = tss.tss_risk,
            source_active = tss.source_active,
            source_removed = tss.source_removed,
            recovery_mode = tss.recovery_mode,
            abx_toxin_level = tss.abx_toxin_level,
            abx_cooldown_mins = tss.abx_cooldown_mins,
            abx_suppress_mins = tss.abx_suppress_mins,
            abx_dose_count = tss.abx_dose_count,
            abx_bank_points = tss.abx_bank_points,
            abx_bank_cap = tss.abx_bank_cap,
            abx_bank_drain_per_min = tss.abx_bank_drain_per_min,
        } or nil,
        cycle = cycle and {
            current_phase = cycle.current_phase,
            phase_minutes_remaining = cycle.phase_minutes_remaining,
            healthEffectSeverity = cycle.healthEffectSeverity,
        } or nil,
        hygiene = ic and {
            cSIHDC_counter = ic.cSIHDC_counter,
            LeakLevel = ic.LeakLevel,
            LeakSwitchState = ic.LeakSwitchState,
        } or nil,
        pms = ic and {
            pill_recently_taken = ic.pill_recently_taken,
            pill_effect_active = ic.pill_effect_active,
            pill_effect_counter = ic.pill_effect_counter,
        } or nil,
    }
end

rd.status.print = function()
    local s = rd.status.get()
    if not s then
        print("[RedDays][rd.status] unavailable")
        return nil
    end

    local t = s.tss or {}
    local c = s.cycle or {}
    local player = RD_zapi.getPlayer()
    local isSleeping = player and player.isAsleep and player:isAsleep() or false
    local efSleepGate = isSleeping and ((t.stage or 0) >= 1)
    print("[RedDays][rd.status] tss.stage=" .. tostring(t.stage)
        .. " tss.risk=" .. tostring(t.tss_risk)
        .. " tss.severity=" .. tostring(t.severity)
        .. " abx.toxin=" .. tostring(t.abx_toxin_level)
        .. " abx.bank=" .. string.format("%.2f", t.abx_bank_points or 0)
        .. "/" .. string.format("%.2f", t.abx_bank_cap or 0)
        .. " abx.cdEta=" .. tostring(t.abx_cooldown_mins)
        .. " abx.sup=" .. tostring(t.abx_suppress_mins)
        .. " cycle.phase=" .. tostring(c.current_phase)
        .. " cycle.remaining=" .. tostring(c.phase_minutes_remaining))
    print("[RedDays][rd.status] sleep=" .. tostring(isSleeping) .. " ef_sleep_gate=" .. tostring(efSleepGate))
    return s
end

-- Phase name aliases accepted by rd.goToPhase
local PHASE_ALIASES = {
    red         = "redPhase",
    period      = "redPhase",
    menstrual   = "redPhase",
    redphase    = "redPhase",
    follicular  = "follicularPhase",
    follicularphase = "follicularPhase",
    ovulation   = "ovulationPhase",
    ovulationphase = "ovulationPhase",
    luteal      = "lutealPhase",
    lutealphase = "lutealPhase",
}

-- rd.goToPhase("red")                     -- jump to red phase, use existing duration
-- rd.goToPhase("luteal", 1440)            -- jump to luteal with 1 day remaining
-- rd.goToPhase("follicular", 2880, 80)    -- jump to follicular, 2 days remaining, severity 80
rd.goToPhase = function(phase, minutesRemaining, severity)
    local cycle = getCycle(true)
    if not cycle then
        print("[rd.goToPhase] no cycle data available")
        return false
    end

    local resolved = PHASE_ALIASES[string.lower(tostring(phase or ""))] or tostring(phase or "")
    local valid = { redPhase=true, follicularPhase=true, ovulationPhase=true, lutealPhase=true }
    if not valid[resolved] then
        print("[rd.goToPhase] unknown phase '" .. tostring(phase) .. "'. use: red, follicular, ovulation, luteal")
        return false
    end

    local durationKey = resolved .. "_duration_mins"
    local defaultDuration = cycle[durationKey] or MINUTES_PER_DAY
    local remaining = clampNumber(minutesRemaining, 1, nil, defaultDuration)

    cycle.current_phase = resolved
    cycle.phase_minutes_remaining = remaining
    cycle.reason_for_cycle = "debug_goToPhase_" .. resolved
    if severity ~= nil then
        cycle.healthEffectSeverity = clampNumber(severity, 0, 100, 50)
    end

    transmitDebugData()
    print("[rd.goToPhase] -> " .. resolved .. " | " .. tostring(remaining) .. " mins remaining | severity=" .. tostring(cycle.healthEffectSeverity))
    return true
end

-- TSS state profiles used by rd.goToTSSStage and rd.tss.preset
-- source_active=false/source_removed=true means tampon removed but stage active (recovery-ready)
-- source_active=true/source_removed=false means tampon still worn (actively worsening)
local TSS_STAGE_PROFILES = {
    stage0_clean = {
        stage = 0, exposure_minutes = 0, severity = 0,
        stage_threshold = 0, tss_risk = 0,
        source_active = false, source_removed = false, source_type = "",
        recovery_mode = "none", warning_cooldown = 0, stabilized_until = 0,
        first_symptom_minutes = 0, cured = false,
        _note = "Clean slate. No TSS exposure.",
    },
    stage1_early = {
        stage = 1, exposure_minutes = 3500, severity = 0,
        stage_threshold = 10080,   -- mid range stage1to2 (7 days)
        tss_risk = 0,
        source_active = true, source_removed = false, source_type = "tampon",
        recovery_mode = "none", warning_cooldown = 0, stabilized_until = 0,
        first_symptom_minutes = 60, cured = false,
        _note = "Stage 1 warning. Tampon still worn. Symptoms just started.",
    },
    stage2_progressing = {
        stage = 2, exposure_minutes = 5760, severity = 0,
        stage_threshold = 14400,   -- mid range stage2to3 (10 days)
        tss_risk = 0,
        source_active = true, source_removed = false, source_type = "tampon",
        recovery_mode = "none", warning_cooldown = 0, stabilized_until = 0,
        first_symptom_minutes = 1440, cured = false,
        _note = "Stage 2 worsening. Tampon worn. Needs treatment soon.",
    },
    stage3_stable = {
        stage = 3, exposure_minutes = 8640, severity = 0,
        tss_risk = 0,
        source_active = false, source_removed = true, source_type = "tampon",
        recovery_mode = "none", warning_cooldown = 0, stabilized_until = 720,
        first_symptom_minutes = 4320, cured = false,
        _note = "Stage 3 critical but stabilized. Source removed. Risk not yet accumulating.",
    },
    stage3_risky = {
        stage = 3, exposure_minutes = 8640, severity = 0,
        stage_threshold = 0,
        tss_risk = 360,            -- high enough to trigger stage4 quickly under stress
        source_active = true, source_removed = false, source_type = "tampon",
        recovery_mode = "none", warning_cooldown = 0, stabilized_until = 0,
        first_symptom_minutes = 5760, cured = false,
        _note = "Stage 3 with elevated risk. Stage 4 likely within minutes under stress.",
    },
    stage4_critical = {
        stage = 4, exposure_minutes = 8640, severity = 0,
        stage_threshold = 0,
        tss_risk = 0,
        abx_toxin_level = 100, abx_cooldown_mins = 0, abx_suppress_mins = 0, abx_dose_count = 0,
        source_active = true, source_removed = false, source_type = "tampon",
        recovery_mode = "none", warning_cooldown = 0, stabilized_until = 0,
        first_symptom_minutes = 7200, cured = false,
        _note = "Stage 4 toxic shock. Fever just starting. HP draining. Take antibiotics repeatedly.",
    },
    treatment_abx_ready = {
        stage = 4, exposure_minutes = 8640, severity = 0,
        stage_threshold = 0,
        tss_risk = 0,
        abx_toxin_level = 65, abx_cooldown_mins = 0, abx_suppress_mins = 480, abx_dose_count = 1,
        source_active = true, source_removed = false, source_type = "tampon",
        recovery_mode = "antibiotics", warning_cooldown = 0, stabilized_until = 0,
        first_symptom_minutes = 7200, cured = false,
        _note = "Stage 4 after 1st dose. HP suppressed (8h window). Fever at 1.5C. Cooldown ready — take next dose now.",
    },
    abx_dose_ready = {
        stage = 4, exposure_minutes = 8640, severity = 0,
        stage_threshold = 0,
        tss_risk = 0,
        abx_toxin_level = 44, abx_cooldown_mins = 0, abx_suppress_mins = 0, abx_dose_count = 4,
        source_active = true, source_removed = false, source_type = "tampon",
        recovery_mode = "antibiotics", warning_cooldown = 0, stabilized_until = 0,
        first_symptom_minutes = 7200, cured = false,
        _note = "Stage 4 mid-course. Suppression expired, HP draining. Fever at 40C. Next dose ready — take now or die.",
    },
    abx_near_recovery = {
        stage = 4, exposure_minutes = 8640, severity = 0,
        stage_threshold = 0,
        tss_risk = 0,
        abx_toxin_level = 0, abx_cooldown_mins = 0, abx_suppress_mins = 0, abx_dose_count = 15,
        source_active = false, source_removed = true, source_type = "tampon",
        recovery_mode = "antibiotics", warning_cooldown = 0, stabilized_until = 0,
        first_symptom_minutes = 7200, cured = false,
        _note = "Stage 4 toxin cleared. Fever broken. Should drop to stage 3 recovery on next tick.",
    },
    stage4_peak_fever = {
        stage = 4, exposure_minutes = 8640, severity = 0,
        stage_threshold = 0,
        tss_risk = 0,
        abx_toxin_level = 100, abx_cooldown_mins = 0, abx_suppress_mins = 0, abx_dose_count = 0,
        source_active = true, source_removed = false, source_type = "tampon",
        recovery_mode = "none", warning_cooldown = 0, stabilized_until = 0,
        first_symptom_minutes = 7200, cured = false,
        _note = "Stage 4 worst case. Fever maxed (5C offset, ~42C effective). HP melting. Antibiotics urgently needed.",
    },
    recovery_flow = {
        stage = 1, exposure_minutes = 4320, severity = 0,
        stage_threshold = 0,
        tss_risk = 0,
        source_active = false, source_removed = true, source_type = "tampon",
        recovery_mode = "antibiotics", warning_cooldown = 60, stabilized_until = 0,
        first_symptom_minutes = 2160, cured = true,
        _note = "In recovery. Sickness should be decaying. Watch CharacterStat.SICKNESS.",
    },
}

local function syncRuntimeTSSStatsForDebugPreset(tss, profile)
    if not tss then return end

    -- Reset fever controller runtime fields so test presets always start from known controller state.
    tss._feverDrive = 0
    tss._feverAccum = 0
    tss._tempDiagPrinted = nil

    local player = RD_zapi.getPlayer()
    if not player then return end
    local stats = player:getStats()
    if not stats then return end

    local stage = clampNumber(tss.stage, 0, 4, 0)
    local override = profile and profile._sickness
    if override ~= nil then
        stats:set(CharacterStat.SICKNESS, clampNumber(override, 0, 1, 0))
    elseif stage >= 4 then
        stats:set(CharacterStat.SICKNESS, 0.26)
    else
        stats:set(CharacterStat.SICKNESS, 0)
    end
end

-- rd.goToTSSStage(3)               -- jump to stage 3 using stage3_stable profile
-- rd.goToTSSStage(4)               -- jump to stage 4 using stage4_critical profile
-- rd.goToTSSStage(3, "risky")      -- jump to stage 3 using stage3_risky profile
rd.goToTSSStage = function(stage, variant)
    local tss = getTSS(true)
    if not tss then
        print("[rd.goToTSSStage] no TSS data available")
        return false
    end

    stage = clampNumber(stage, 0, 4, 0)

    -- Auto-pick profile name from stage and variant
    local profileKey
    if variant then
        profileKey = "stage" .. tostring(stage) .. "_" .. string.lower(tostring(variant))
    else
        local defaults = { [0]="stage0_clean", [1]="stage1_early", [2]="stage2_progressing",
                           [3]="stage3_stable", [4]="stage4_critical" }
        profileKey = defaults[stage] or "stage0_clean"
    end

    local profile = TSS_STAGE_PROFILES[profileKey]
    if not profile then
        print("[rd.goToTSSStage] no profile '" .. profileKey .. "'. see rd.tss.preset.list()")
        return false
    end

    for k, v in pairs(profile) do
        if k ~= "_note" then
            tss[k] = v
        end
    end

    syncRuntimeTSSStatsForDebugPreset(tss, profile)

    transmitDebugData()
    print("[rd.goToTSSStage] stage=" .. tostring(tss.stage) .. " profile=" .. profileKey)
    print("[rd.goToTSSStage] note: " .. tostring(profile._note))
    return true
end

-- rd.tss.preset.apply("stage3_risky")   -- apply a named preset directly
-- rd.tss.preset.list()                   -- print all available preset names and notes
rd.tss.preset = {
    apply = function(name)
        local tss = getTSS(true)
        if not tss then
            print("[rd.tss.preset] no TSS data available")
            return false
        end
        local profile = TSS_STAGE_PROFILES[tostring(name or "")]
        if not profile then
            print("[rd.tss.preset] unknown preset '" .. tostring(name) .. "'. call rd.tss.preset.list()")
            return false
        end
        for k, v in pairs(profile) do
            if k ~= "_note" then
                tss[k] = v
            end
        end
        syncRuntimeTSSStatsForDebugPreset(tss, profile)
        transmitDebugData()
        print("[rd.tss.preset] applied '" .. name .. "': " .. tostring(profile._note))
        return true
    end,
    list = function()
        print("[rd.tss.preset] available presets:")
        for name, profile in pairs(TSS_STAGE_PROFILES) do
            print("  " .. name .. " -- " .. tostring(profile._note))
        end
    end,
}

local function printTSSStatus()
    local sb = SandboxVars.RedDays or {}
    local tss = RD_modData and RD_modData.ICdata and RD_modData.ICdata.tss or nil

    print("--- TSS Diagnostics ---------------------")
    print("TSS enabled ----------------------------- " .. tostring(sb.tss_enabled ~= false))
    print("TSS lethal enabled ---------------------- " .. tostring(sb.tss_lethal_enabled ~= false))
    print("TSS risk multiplier pct ----------------- " .. tostring(sb.tss_risk_multiplier_pct or 100))

    if not tss then
        print("TSS state ------------------------------- unavailable")
        return
    end

    local stage = tss.stage or 0
    local stageLabel = "none"
    if stage == 1 then stageLabel = "warning"
    elseif stage == 2 then stageLabel = "worsening"
    elseif stage == 3 then stageLabel = "critical"
    elseif stage >= 4 then stageLabel = "toxic_shock" end

    local threshold = tss.stage_threshold or 0
    local thresholdDays = threshold / MINUTES_PER_DAY

    print("TSS stage ------------------------------- " .. tostring(stage) .. " (" .. stageLabel .. ")")
    print("TSS stage threshold --------------------- " .. tostring(threshold) .. " mins (" .. string.format("%.2f", thresholdDays) .. " days)")
    local severity = tss.severity or 0
    if stage >= 1 and stage < 3 and threshold > 0 then
        local minsLeft = math.max(0, threshold - severity)
        print("TSS progression remaining --------------- " .. tostring(math.floor(minsLeft)) .. " mins (~" .. string.format("%.2f", minsLeft / MINUTES_PER_DAY) .. " days at 1x stress)")
    end
    if stage == 3 then
        local minStage3Hours = (SandboxVars.RedDays or {}).tss_min_stage3_hours or 48
        local stage3Mins = tss.stage3_minutes or 0
        local eligibleIn = math.max(0, (minStage3Hours * MINUTES_PER_HOUR) - stage3Mins)
        if eligibleIn > 0 then
            print("TSS (Stage 4) eligible in -------------- " .. math.ceil(eligibleIn / MINUTES_PER_HOUR) .. " hours (Stage 3 minimum not yet met)")
        else
            print("TSS (Stage 4) eligibility -------------- ELIGIBLE -- risk accumulating")
        end
    end
    print("TSS tss_risk ---------------------------- " .. tostring(tss.tss_risk or 0))
    print("TSS recovery mode ----------------------- " .. tostring(tss.recovery_mode or "none"))
    print("TSS cured flag -------------------------- " .. tostring(tss.cured or false))
    print("TSS source active ----------------------- " .. tostring(tss.source_active or false))
    print("TSS source removed ---------------------- " .. tostring(tss.source_removed or false))
    print("TSS wear minutes ------------------------ " .. tostring(tss.wear_minutes or 0) .. " mins (" .. tostring((tss.wear_minutes or 0) / MINUTES_PER_HOUR) .. " hours)")
    local expMin = tss.exposure_minutes or 0
    print("TSS exposure minutes -------------------- " .. tostring(expMin) .. " mins (" .. string.format("%.2f", expMin / MINUTES_PER_HOUR) .. " hours / " .. string.format("%.2f", expMin / MINUTES_PER_DAY) .. " days)")
    print("TSS severity ---------------------------- " .. tostring(severity) .. " mins (" .. string.format("%.2f", severity / MINUTES_PER_HOUR) .. " hours / " .. string.format("%.2f", severity / MINUTES_PER_DAY) .. " days)")
    print("TSS stage3 minutes ---------------------- " .. tostring(tss.stage3_minutes or 0) .. " mins")
    print("TSS first symptom minutes --------------- " .. tostring(tss.first_symptom_minutes or 0))
    print("TSS warning cooldown -------------------- " .. tostring(tss.warning_cooldown or 0))
    print("TSS stabilized until -------------------- " .. tostring(tss.stabilized_until or 0))
    -- Antibiotic (ABX) treatment state -- all ABX fields grouped here.
    local abxSuppress = tss.abx_suppress_mins or 0
    local abxCooldown = tss.abx_cooldown_mins or 0
    local abxDoses = tss.abx_dose_count or 0
    local abxBank = tss.abx_bank_points or 0
    local abxBankCap = tss.abx_bank_cap or 0
    local abxBankDrain = tss.abx_bank_drain_per_min or 0
    local abxToxin = tss.abx_toxin_level or 0
    local abxEffective = (abxSuppress > 0) and (abxBank > 0)
    local pillsToCure = math.max(1, sb.tss_abx_pills_to_cure or 10)
    print("TSS ABX effective ----------------------- " .. tostring(abxEffective))
    print("TSS ABX doses taken --------------------- " .. tostring(abxDoses))
    print("TSS ABX toxin score --------------------- " .. tostring(abxToxin) .. "/100")
    print("TSS ABX bank ---------------------------- " .. string.format("%.2f", abxBank) .. "/" .. string.format("%.2f", abxBankCap) .. " (drain=" .. string.format("%.4f", abxBankDrain) .. "/min)")
    print("TSS ABX cooldown ETA -------------------- " .. tostring(abxCooldown) .. " mins")
    print("TSS ABX suppression remaining ----------- " .. tostring(abxSuppress) .. " mins")
    print("TSS ABX cure plan ----------------------- pillsToCure=" .. tostring(pillsToCure) .. ", toxinClearPerPoint=" .. string.format("%.3f", tss.abx_toxin_clear_per_point or 1))

    local player = RD_zapi.getPlayer()
    if player then
        local stats = player:getStats()
        local sickness = stats and stats:get(CharacterStat.SICKNESS) or "unavailable"
        print("TSS current CharacterStat.SICKNESS ------ " .. tostring(sickness))
        print("TSS current blur effect ----------------- " .. tostring(player:getSleepingTabletEffect()))
        print("TSS baseline blur effect ---------------- " .. tostring(tss.baseline_blur_effect or 0))
        -- Body temp + fever controller state
        local bd = player:getBodyDamage()
        local thermo = bd and bd:getThermoregulator()
        local coreTemp = thermo and thermo:getCoreCelcius()
        if coreTemp then
            print("TSS core body temp (C) ------------------ " .. string.format("%.2f", coreTemp))
        else
            print("TSS core body temp (C) ------------------ unavailable")
        end
        -- Fever gate state (mirrors gate logic in ApplyFeverPressure: SICKNESS>=0.91 AND temp>=37.8)
        local sickNum = type(sickness) == "number" and sickness or 0
        local gateState
        if stage ~= 4 then
            gateState = "not Stage 4"
        elseif sickNum < 0.91 then
            gateState = "below sickness gate (" .. string.format("%.3f", sickNum) .. " < 0.91)"
        elseif coreTemp and coreTemp < 37.8 then
            gateState = "below temp gate (" .. string.format("%.2f", coreTemp) .. "C < 37.8C)"
        else
            gateState = "ACTIVE"
        end
        print("TSS fever gate state -------------------- " .. gateState)
        print("TSS fever drive (_feverDrive) ----------- " .. string.format("%.6f", tss._feverDrive or 0))
        print("TSS fever frame accum (_feverAccum) ----- " .. string.format("%.3f", tss._feverAccum or 0))
        -- Drain multiplier at current core temp (mirrors two-segment curve in applyStageStatEffects)
        if coreTemp then
            local mult
            local hotBreakC = 38.5
            local hotBreakMult = 2.0
            local hotCapC = 39.0
            local hotCapMult = 3.0
            if coreTemp >= hotCapC then
                mult = 3.0
            elseif coreTemp >= hotBreakC then
                local t = (coreTemp - hotBreakC) / (hotCapC - hotBreakC)
                mult = hotBreakMult + t * (hotCapMult - hotBreakMult)
            elseif coreTemp >= 37.0 then
                local t = (coreTemp - 37.0) / (hotBreakC - 37.0)
                mult = 1.0 + t * (hotBreakMult - 1.0)
            elseif coreTemp >= 36.1 then
                local t = (37.0 - coreTemp) / (37.0 - 36.1)
                mult = 1.0 + t * (1.10 - 1.0)
            elseif coreTemp >= 34.9 then
                local t = (36.1 - coreTemp) / (36.1 - 34.9)
                mult = 1.10 + t * (1.25 - 1.10)
            elseif coreTemp >= 29.9 then
                local t = (34.9 - coreTemp) / (34.9 - 29.9)
                mult = 1.25 + t * (1.70 - 1.25)
            elseif coreTemp >= 24.9 then
                local t = (29.9 - coreTemp) / (29.9 - 24.9)
                mult = 1.70 + t * (2.20 - 1.70)
            elseif coreTemp >= 20.0 then
                local t = (24.9 - coreTemp) / (24.9 - 20.0)
                mult = 2.20 + t * (2.40 - 2.20)
            else
                mult = 2.40
            end
            local sbDrainPct = (SandboxVars.RedDays or {}).tss_stage4_hp_drain_pct or 100
            local baseDrain = 0.15 * (sbDrainPct / 100)
            local sicknessDrainPerMin = baseDrain * mult
            local activeDrainPerMin = tss._lastHPDrainPerMin or sicknessDrainPerMin
            local activeMode = tostring(tss._lastHPDrainMode or "none")
            print("TSS drain mult at " .. string.format("%.2f", coreTemp) .. "C ------------ " .. string.format("%.3f", mult) .. "x")
            print("TSS sickness drain per minute ----------- " .. string.format("%.4f", sicknessDrainPerMin))
            print("TSS HP drain mode ----------------------- " .. activeMode)
            if stage == 4 then
                local abxCap = (SandboxVars.RedDays or {}).tss_abx_sleep_health_cap_pct or 50
                print("TSS HP drain per minute ----------------- " .. string.format("%.4f", activeDrainPerMin) .. " (Stage 4 active)")
                print("TSS ABX HP cap -------------------------- " .. string.format("%.1f", abxCap) .. " (current=" .. string.format("%.2f", tss._lastHealthAtTick or (bd:getHealth() or 0)) .. ")")
            else
                print("TSS HP drain per minute ----------------- " .. string.format("%.4f", activeDrainPerMin) .. " (not Stage 4)")
            end
        else
            print("TSS drain mult / HP drain per min ------- unavailable (no core temp)")
        end
        -- Endurance/fatigue + Stage 4 sickness clamp status
        if stats then
            local endurance = stats:get(CharacterStat.ENDURANCE) or 0
            local fatigue = stats:get(CharacterStat.FATIGUE) or 0
            local clampActive = stage == 4 and sickNum >= 0.91
            local clampStr = clampActive and " (clamped: END<=0.8, FAT>=0.4)" or ""
            print("TSS endurance / fatigue ----------------- END=" .. string.format("%.3f", endurance) .. "  FAT=" .. string.format("%.3f", fatigue) .. clampStr)
        end
    else
        print("TSS current CharacterStat.SICKNESS ------ unavailable")
        print("TSS current blur effect ----------------- unavailable")
        print("TSS baseline blur effect ---------------- " .. tostring(tss.baseline_blur_effect or 0))
        print("TSS core body temp (C) ------------------ unavailable (no player)")
    end
end

-- Don't use colons in strings here because the game won't print the whole string before a colon
local function PrintStatus(cycle)
    print("=========================== Generated menstrual cycle details ==============================")
    print("Mod version ----------------------------- 42.18")
    local mpMode = "singleplayer"
    if isClient() then mpMode = "client (multiplayer)"
    elseif isServer() then mpMode = "server (multiplayer)" end
    print("Session mode ---------------------------- " .. mpMode)
    print("MoodleFramework loaded ------------------ " .. tostring(getActivatedMods():contains("MoodleFramework")))
    local currentDay = RD_zapi.getGameTime("getWorldAgeHours") / 24
    print("Current time in days -------------------- " .. currentDay)
    local gt = getGameTime()
    print("In-game date ---------------------------- Day " .. tostring(gt:getDay()) .. ", Month " .. tostring(gt:getMonth()) .. ", Year " .. tostring(gt:getYear()))

    print("The reason for last cycle generation ---- " .. cycle.reason_for_cycle)
    print("Cycle delayed (first spawn delay used) -- " .. tostring(RD_modData.ICdata.cycleDelayed or false))
    print("Current phase --------------------------- " .. cycle.current_phase)
    print("Phase minutes remaining ----------------- " .. cycle.phase_minutes_remaining .. " mins (" .. (cycle.phase_minutes_remaining / MINUTES_PER_DAY) .. " days)")
    print("Total cycle duration -------------------- " .. (cycle.cycle_duration_mins / MINUTES_PER_DAY) .. " days (" .. cycle.cycle_duration_mins .. " mins)")

    print("Red phase duration ---------------------- " .. (cycle.redPhase_duration_mins / MINUTES_PER_DAY) .. " days (" .. cycle.redPhase_duration_mins .. " mins)")
    print("Follicular phase duration --------------- " .. (cycle.follicularPhase_duration_mins / MINUTES_PER_DAY) .. " days (" .. cycle.follicularPhase_duration_mins .. " mins)")
    print("Ovulation phase duration ---------------- " .. (cycle.ovulationPhase_duration_mins / MINUTES_PER_DAY) .. " days (" .. cycle.ovulationPhase_duration_mins .. " mins)")
    print("Luteal phase duration ------------------- " .. (cycle.lutealPhase_duration_mins / MINUTES_PER_DAY) .. " days (" .. cycle.lutealPhase_duration_mins .. " mins)")

    local currentPhase = RD_CycleManager.getCurrentCyclePhase(cycle)
    print("Current cycle phase (from func) --------- " .. currentPhase)
    if not cycle.healthEffectSeverity then return end
    print("Target Health Effect Severity ----------- " .. cycle.healthEffectSeverity)

    local sanitaryItem = RD_HygieneManager.getCurrentlyWornSanitaryItem()
    if sanitaryItem then
        print("Currently worn sanitary item ------------ " .. sanitaryItem:getName())
        print("Sanitary item condition ----------------- " .. sanitaryItem:getCondition())
    else
        print("Currently worn sanitary item ------------ None")
    end
    print("Hygiene saturation counter (cSIHDC) ----- " .. tostring(RD_modData.ICdata.cSIHDC_counter or 0))
    print("Leak level ------------------------------ " .. tostring(RD_modData.ICdata.LeakLevel or 0))
    print("Leak switch state ----------------------- " .. tostring(RD_modData.ICdata.LeakSwitchState or false))
    printTSSStatus()

    local phaseStatus = RD_CycleManager.getPhaseStatus(cycle)
    if phaseStatus then
        print("Phase Status ---------------------------- " .. phaseStatus.phase)
        print("Time remaining in current phase --------- " .. phaseStatus.time_remaining .. " days (" .. phaseStatus.time_remaining_mins .. " mins)")
        print("Phase percent complete ------------------ " .. phaseStatus.percent_complete .. "%")
    else
        print("No valid phase status found for the current cycle.")
    end

    local dataCodes = RD_CycleTrackerLogic.getDataCodes(cycle)
    if dataCodes then
        print("Data codes for the current phase -------- " .. table.concat(dataCodes, ", "))
    else
        print("No data codes available for the current cycle phase.")
    end
    print("PMS Duration ---------------------------- " .. tostring(cycle.pms_duration_mins / MINUTES_PER_DAY) .. " days (" .. tostring(cycle.pms_duration_mins) .. " mins)")
    print("PMS Severity ---------------------------- " .. tostring(RD_CycleManager.getPMSseverity()))
    print("PMS Symptom - Agitation ----------------- " .. tostring(cycle.pms_agitation))
    print("PMS Symptom - Cramps -------------------- " .. tostring(cycle.pms_cramps))
    print("PMS Symptom - Fatigue ------------------- " .. tostring(cycle.pms_fatigue))
    print("PMS Symptom - Tender Breasts ------------ " .. tostring(cycle.pms_tenderBreasts))
    print("PMS Symptom - Crave Food ---------------- " .. tostring(cycle.pms_craveFood))
    print("PMS Symptom - Sadness ------------------- " .. tostring(cycle.pms_Sadness))
    print("Painkiller active ----------------------- " .. tostring(RD_modData.ICdata.pill_effect_active))
    print("Painkiller counter/max ------------------ " .. tostring(RD_modData.ICdata.pill_effect_counter or 0) .. " / " .. tostring(SandboxVars.RedDays.painkillerEffectDuration or 36))
    print("This log output was formatted to be read in a separate terminal window with a monospace font, not the in-game console.")
    print("==========================================================================================")
end
-- Events.OnGameStart.Add(PrintStatus(RD_modData.ICdata.currentCycle)) Sometimes this prints before the cycle is generated, so we call it in main() instead.


function RD_CycleDebugger.printWrapper() -- Wrapper to control printing frequency when running from main function
    if not RD_modData or not RD_modData.ICdata then return end
    local cycle = RD_modData.ICdata.currentCycle
    if not cycle then return end
    PrintStatus(cycle)
    -- There used to be a lot more logic here, but keeping this to keep it consistent.
end

return RD_CycleDebugger
