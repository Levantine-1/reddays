RD_TSSManager = RD_TSSManager or {}
RDTSSManager = RD_TSSManager -- Alias for backward compatibility
RD_TSSManager._debugSpeedMult = nil  -- set via rd.debug.speedMult.set(N) from debugger

require "RD_game_api"
require "RD_hygiene_manager"

local MINUTES_PER_HOUR = 60
local MINUTES_PER_DAY = 1440

local SICKNESS_DECAY_BASE = 0.0002              -- safety decay for residual sickness in stages 0-3
local SICKNESS_RECOVERY_COMPLETE = 0.02
local TSS_SICKNESS_STAGE4_START = 0.26          -- SICKNESS set to this when Stage 4 triggers
local TSS_SICKNESS_RAMP_PER_MIN = (1.0 - 0.26) / (12.0 * 60)   -- 0.26→1.0 over 12 in-game hours (~0.001028/min)
local SICKNESS_RECOVERY_DECAY_PER_MIN = 1.0 / (12.0 * 60)      -- fixed decay rate; 12h from 1.0, shorter if treated early
local BLUR_STAGE3_TARGET = 0.35
local BLUR_RAMP_UP = 0.01
local BLUR_RAMP_DOWN = 0.008
local NORMAL_BODY_TEMP_C = 37.0
local TSS_FEVER_TARGET_C = 42.0
local TSS_FEVER_NUDGE_MIN_SICKNESS = 0.91              -- only nudge after vanilla stage-4 sickness is active
local TSS_FEVER_NUDGE_START_TEMP_C = 37.8              -- wait until vanilla fever reaches plateau band
local TSS_FEVER_NUDGE_FULL_TEMP_C = 38.2               -- full nudge strength by this temp
-- Fever pressure knobs — units are CharacterStat.TEMPERATURE stat units per in-game minute.
-- The game uses stats:add(CharacterStat.TEMPERATURE, gain) to push real body temp each minute;
-- the vanilla thermoregulator fights back naturally (homeostasis = tug-of-war).
-- This is intentionally a nudge layer: vanilla sickness should do most of the heating up to ~38C.
local TSS_FEVER_PRESSURE_BASE_GAIN_PER_MIN = 0.0015
local TSS_FEVER_PRESSURE_CATCHUP_PER_DEG_PER_MIN = 0.01
local TSS_FEVER_PRESSURE_MAX_GAIN_PER_MIN = 0.06
local TSS_FEVER_PRESSURE_MIN_GAIN_PER_MIN = 0.0
local TSS_FEVER_HIGH_TEMP_START_C = 38.0                   -- begin high-temp bonus here
local TSS_FEVER_HIGH_TEMP_BONUS_MULT = 0.0                 -- disable extra high-temp boost in nudge mode
local TSS_FEVER_INTEGRATOR_GAIN_PER_DEG_PER_MIN = 0.02
local TSS_FEVER_INTEGRATOR_MAX_GAIN_PER_MIN = 0.05
local TSS_FEVER_INTEGRATOR_DECAY_PER_MIN = 0.08

-- Stage 4 HP-drain temperature scaling knobs.
-- Two-segment linear: 37.0C=1x → 38.5C=2x → 40.0C=3x (cap; game body temp rarely exceeds ~40C).
local TSS_FEVER_DRAIN_HOT_BREAK_C    = 38.5   -- 2x multiplier at this temperature
local TSS_FEVER_DRAIN_HOT_BREAK_MULT = 2.0
local TSS_FEVER_DRAIN_HOT_CAP_C      = 39.0   -- 3x cap; game core temp plateaus near here
local TSS_FEVER_DRAIN_HOT_CAP_MULT   = 3.0
local TSS_COLD_STAGE1_TEMP_C = 36.1
local TSS_COLD_STAGE2_TEMP_C = 34.9
local TSS_COLD_STAGE3_TEMP_C = 29.9
local TSS_COLD_STAGE4_TEMP_C = 24.9
local TSS_COLD_MIN_TEMP_C = 20.0
local TSS_COLD_STAGE1_MULT = 1.10
local TSS_COLD_STAGE2_MULT = 1.25
local TSS_COLD_STAGE3_MULT = 1.70
local TSS_COLD_STAGE4_MULT = 2.20
local TSS_COLD_MIN_MULT = 2.40
local TSS_STAGE4_BASE_HP_DRAIN = 0.15
local FEVER_TICK_INTERVAL_S = 3.0 -- Apply fever pressure every N in-game seconds

local function getSandbox()
    return SandboxVars.RedDays or {}
end

local function isEnabled()
    local sb = getSandbox()
    if sb.tss_enabled == nil then return true end
    return sb.tss_enabled
end

local function isLethalEnabled()
    local sb = getSandbox()
    if sb.tss_lethal_enabled == nil then return true end
    return sb.tss_lethal_enabled
end

local function getWarningIntervalMinutes()
    local sb = getSandbox()
    return sb.tss_warning_interval_mins or 180
end

local function getTamponGraceMinutes()
    local sb = getSandbox()
    return (sb.tss_tampon_grace_hours or 8) * MINUTES_PER_HOUR
end

local function getSandboxStageBounds(stage)
    local sb = getSandbox()
    if stage == 0 then
        return (sb.tss_stage0_duration_lowerBound or 12) * MINUTES_PER_HOUR,
               (sb.tss_stage0_duration_upperBound or 48) * MINUTES_PER_HOUR
    elseif stage == 1 then
        return (sb.tss_stage1_duration_lowerBound or 48) * MINUTES_PER_HOUR,
               (sb.tss_stage1_duration_upperBound or 120) * MINUTES_PER_HOUR
    elseif stage == 2 then
        return (sb.tss_stage2_duration_lowerBound or 120) * MINUTES_PER_HOUR,
               (sb.tss_stage2_duration_upperBound or 240) * MINUTES_PER_HOUR
    end
    return 0, 0
end

local function getRiskMultiplier()
    local sb = getSandbox()
    local mult = math.max(1, sb.tss_risk_multiplier_pct or 100)
    local debugMult = RD_TSSManager._debugSpeedMult or 1
    if debugMult > 1 then return mult * debugMult end
    return mult
end

local function rollNextStageThreshold(stage)
    local lowerMins, upperMins = getSandboxStageBounds(stage)
    if upperMins <= 0 then return 0 end
    local range = math.max(0, upperMins - lowerMins)
    local base = lowerMins + (range > 0 and ZombRand(range + 1) or 0)
    local debugMult = RD_TSSManager._debugSpeedMult or 1
    return math.floor(base / debugMult)
end

local function getModData()
    local md = RD_zapi.getModData()
    if not md then return nil end
    md.ICdata = md.ICdata or {}
    md.ICdata.tss = md.ICdata.tss or {
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
        disinfectant_recently = false,
        alcohol_recently = false,
        recovery_mode = "none",
        baseline_blur_effect = 0,
        tss_rolls = 0,
        treatment_attempts = 0,
        tss_risk = 0,
        stage_threshold = 0,
        stage3_minutes = 0,
        complication_cooldown = 60,
        abx_toxin_level = 0,
        abx_cooldown_mins = 0,
        abx_suppress_mins = 0,
        abx_dose_count = 0,
        tss_fever_induced = 0,
    }
    return md
end

local function getPlayer()
    return RD_zapi.getPlayer()
end

local function notifyPlayer(msg)
    if not msg then return end
    print("[RedDays][TSS] " .. msg)
end

local function transmitNow()
    if isClient() then
        local player = getPlayer()
        if player then
            player:transmitModData()
        end
    end
end

local function lowerText(s)
    if not s then return "" end
    return string.lower(s)
end

local function isTampon(item)
    local t = lowerText(item and item:getType())
    return string.find(t, "tampon", 1, true) ~= nil
end

local function isPadOrLiner(item)
    local t = lowerText(item and item:getType())
    return string.find(t, "pad", 1, true) ~= nil or string.find(t, "pantyliner", 1, true) ~= nil or string.find(t, "liner", 1, true) ~= nil
end

local function isDirtyOrSaturated(item)
    if not item then return false end
    local itemName = lowerText(item:getName())
    local condition = item:getCondition() or 0
    if condition <= 2 then return true end
    if string.find(itemName, "dirty", 1, true) then return true end
    if string.find(itemName, "saturated", 1, true) then return true end
    if string.find(itemName, "nearly saturated", 1, true) then return true end
    return false
end

local function hasGroinWoundOrInfection()
    local groin = RD_zapi.getBodyPart(BodyPartType.Groin)
    if not groin then return false end
    return groin:isInfectedWound()
        or groin:IsInfected()
        or groin:getWoundInfectionLevel() > 0
        or groin:bleeding()
        or groin:scratched()
        or groin:isCut()
        or groin:isDeepWounded()
end

local function clampStage(stage)
    if stage < 0 then return 0 end
    if stage > 4 then return 4 end
    return stage
end

local function resetTreatmentFlags(tss)
    tss.antibiotics_taken_recently = false
    tss.disinfectant_recently = false
    tss.alcohol_recently = false
end

local function cureTSS(tss)
    tss.stage = 1
    tss.severity = 0
    tss.stage3_minutes = 0
    tss.stage_threshold = rollNextStageThreshold(1)
    tss.warning_cooldown = getWarningIntervalMinutes()
    tss.cured = true
    tss.stabilized_until = 0
    tss.recovery_mode = "antibiotics"
    resetTreatmentFlags(tss)
    notifyPlayer("Treatment started. TSS symptoms should gradually improve.")
    transmitNow()
end

local function applyBlurEffect(player, tss)
    if not player then return end

    local baseline = tss.baseline_blur_effect or 0
    local currentBlur = player:getSleepingTabletEffect()
    local target = baseline

    if tss.stage >= 3 then
        target = math.max(baseline, BLUR_STAGE3_TARGET)
    end

    if currentBlur < target then
        player:setSleepingTabletEffect(math.min(target, currentBlur + BLUR_RAMP_UP))
    elseif currentBlur > target then
        player:setSleepingTabletEffect(math.max(target, currentBlur - BLUR_RAMP_DOWN))
    end
end

local function applySicknessProgression(player, tss)
    if not player then return end
    local stats = player:getStats()
    if not stats then return end

    -- CharacterStat.SICKNESS is the primary fever driver (separate from corpse-proximity sickness).
    -- Stages 0-3: held at 0 (SICKNESS only active in Stage 4 and during recovery decay).
    -- Stage 4:    ramps 0.26 → 1.0 over 12 in-game hours; game natively holds body temp at ~38C
    --             once SICKNESS ≥ 0.91 (~10.4h in). ApplyFeverPressure pushes further toward 42C.
    -- Recovery:   fixed decay rate; reaches 0 in 12h from 1.0, faster if treated early.
    local currentSickness = stats:get(CharacterStat.SICKNESS) or 0
    local newSickness = currentSickness

    if tss.recovery_mode ~= "none" then
        newSickness = math.max(0, currentSickness - SICKNESS_RECOVERY_DECAY_PER_MIN)

        if newSickness <= SICKNESS_RECOVERY_COMPLETE then
            stats:set(CharacterStat.SICKNESS, 0)
            tss.stage = 0
            tss.exposure_minutes = 0
            tss.severity = 0
            tss.stage3_minutes = 0
            tss.first_symptom_minutes = 0
            tss.warning_cooldown = 0
            tss.tss_risk = 0
            tss.stage_threshold = 0
            tss.cured = false
            tss.recovery_mode = "none"
            notifyPlayer("TSS symptoms have resolved.")
            transmitNow()
            applyBlurEffect(player, tss)
            return
        end
    elseif tss.stage == 4 then
        if (tss.abx_suppress_mins or 0) > 0 then
            -- Antibiotic suppression window active: freeze sickness, no fever ramp
        else
            newSickness = math.min(1.0, currentSickness + TSS_SICKNESS_RAMP_PER_MIN)
        end
    else
        -- Stages 0-3: decay any residual sickness to zero as a safety measure
        newSickness = math.max(0, currentSickness - SICKNESS_DECAY_BASE)
    end

    stats:set(CharacterStat.SICKNESS, newSickness)
    applyBlurEffect(player, tss)
end

local function getProgressionMultiplier(player)
    if not player then return 1.0 end
    local stats = player:getStats()
    local bd = player:getBodyDamage()
    if not stats or not bd then return 1.0 end

    local mult = 0.0

    local fatigue = stats:get(CharacterStat.FATIGUE) or 0
    if fatigue > 0.90 then mult = mult + 0.5
    elseif fatigue > 0.80 then mult = mult + 0.3
    elseif fatigue > 0.70 then mult = mult + 0.1
    end

    local thirst = stats:get(CharacterStat.THIRST) or 0
    if thirst > 0.85 then mult = mult + 0.5
    elseif thirst > 0.70 then mult = mult + 0.3
    elseif thirst > 0.25 then mult = mult + 0.1
    end

    local hunger = stats:get(CharacterStat.HUNGER) or 0
    if hunger > 0.70 then mult = mult + 0.3
    elseif hunger > 0.45 then mult = mult + 0.15
    elseif hunger > 0.25 then mult = mult + 0.05
    end

    local thermoregulator = bd:getThermoregulator()
    if thermoregulator then
        local temp = thermoregulator:getCoreCelcius()
        if temp then
            if temp > 40.0 then mult = mult + 0.5
            elseif temp > 39.0 then mult = mult + 0.3
            elseif temp > 37.5 then mult = mult + 0.1
            elseif temp < 30.0 then mult = mult + 0.2
            elseif temp < 35.0 then mult = mult + 0.1
            elseif temp < 36.5 then mult = mult + 0.05
            end
        end
    end

    if bd:isHasACold() then mult = mult + 0.3 end
    local sickness = stats:get(CharacterStat.SICKNESS) or 0
    if sickness > 0.5 then mult = mult + 0.2 end

    return math.min(3.0, 1.0 + mult)
end

local function getTSSRiskGain(player)
    if not player then return 0 end
    local stats = player:getStats()
    local bd = player:getBodyDamage()
    if not stats or not bd then return 0 end

    local gain = 0

    local fatigue = stats:get(CharacterStat.FATIGUE) or 0
    if fatigue > 0.90 then gain = gain + 3
    elseif fatigue > 0.80 then gain = gain + 1
    end

    local thirst = stats:get(CharacterStat.THIRST) or 0
    if thirst > 0.85 then gain = gain + 3
    elseif thirst > 0.70 then gain = gain + 1
    end

    local thermoregulator = bd:getThermoregulator()
    if thermoregulator then
        local temp = thermoregulator:getCoreCelcius()
        if temp then
            if temp > 40.0 then gain = gain + 3
            elseif temp > 39.0 then gain = gain + 2
            elseif temp > 37.5 then gain = gain + 1
            end
        end
    end

    local sickness = stats:get(CharacterStat.SICKNESS) or 0
    if bd:isHasACold() or sickness > 0.4 then gain = gain + 2 end

    if gain <= 0 then return 0 end
    return math.floor(gain * (getRiskMultiplier() / 100))
end

local function rollTSSTransition(player, tss)
    if not isLethalEnabled() then return end
    if tss.stage ~= 3 then return end
    local sb = getSandbox()
    local minStage3Hours = sb.tss_min_stage3_hours or 48
    if (tss.stage3_minutes or 0) < minStage3Hours * MINUTES_PER_HOUR then return end

    local gain = getTSSRiskGain(player)
    if tss.stabilized_until and tss.stabilized_until > 0 then
        gain = math.floor(gain * 0.5)
    end
    tss.tss_risk = (tss.tss_risk or 0) + gain
    if tss.tss_risk <= 0 then return end

    local riskPoints = math.min(50, math.floor(tss.tss_risk / 120))
    if riskPoints > 0 and ZombRand(10000) < riskPoints then
        tss.stage = 4
        tss.tss_risk = 0
        tss.stage_threshold = 0
        tss.abx_toxin_level = 100
        tss.abx_dose_count = 0
        tss._tempDiagPrinted = nil  -- ensure calibration print fires on first Stage 4 tick
        tss._feverDrive = 0
        tss._feverAccum = 0
        local s4Stats = player:getStats()
        if s4Stats then s4Stats:set(CharacterStat.SICKNESS, TSS_SICKNESS_STAGE4_START) end
        print("[RedDays][TSS] Toxic shock triggered. Toxin score set to 100. Take antibiotics repeatedly.")
        transmitNow()
    end
end

local function applyStageStatEffects(player, tss)
    if not player then return end
    local stats = player:getStats()
    if not stats then return end

    if tss.stage == 1 then
        stats:set(CharacterStat.ENDURANCE, math.max(0, stats:get(CharacterStat.ENDURANCE) - 0.00005))
        stats:set(CharacterStat.FATIGUE, math.min(1, stats:get(CharacterStat.FATIGUE) + 0.0002))
        stats:set(CharacterStat.UNHAPPINESS, math.min(100, stats:get(CharacterStat.UNHAPPINESS) + 0.05))
    elseif tss.stage == 2 then
        stats:set(CharacterStat.ENDURANCE, math.max(0, stats:get(CharacterStat.ENDURANCE) - 0.0002))
        stats:set(CharacterStat.FATIGUE, math.min(1, stats:get(CharacterStat.FATIGUE) + 0.0004))
        stats:set(CharacterStat.THIRST, math.min(1, stats:get(CharacterStat.THIRST) + 0.001))
        stats:set(CharacterStat.UNHAPPINESS, math.min(100, stats:get(CharacterStat.UNHAPPINESS) + 0.1))
    elseif tss.stage >= 3 then
        stats:set(CharacterStat.ENDURANCE, math.max(0, stats:get(CharacterStat.ENDURANCE) - 0.0007))
        stats:set(CharacterStat.FATIGUE, math.min(1, stats:get(CharacterStat.FATIGUE) + 0.001))
        stats:set(CharacterStat.THIRST, math.min(1, stats:get(CharacterStat.THIRST) + 0.002))
        stats:set(CharacterStat.UNHAPPINESS, math.min(100, stats:get(CharacterStat.UNHAPPINESS) + 0.2))
        if tss.stage == 4 then
            -- Clamp endurance and fatigue at the sickness Stage 4 plateau (clamp only, no ramp)
            local currentSickness = stats:get(CharacterStat.SICKNESS) or 0
            if currentSickness >= TSS_FEVER_NUDGE_MIN_SICKNESS then
                local endurance = stats:get(CharacterStat.ENDURANCE) or 1
                if endurance > 0.8 then stats:set(CharacterStat.ENDURANCE, 0.8) end
                local fatigue = stats:get(CharacterStat.FATIGUE) or 0
                if fatigue < 0.4 then stats:set(CharacterStat.FATIGUE, 0.4) end
            end
            -- HP drain only when antibiotic suppression window has expired
            if (tss.abx_suppress_mins or 0) <= 0 then
                local bd = player:getBodyDamage()
                if bd then
                    local sbDrainPct = getSandbox().tss_stage4_hp_drain_pct or 100
                    local baseDrain = TSS_STAGE4_BASE_HP_DRAIN * (sbDrainPct / 100)
                    local drain = baseDrain
                    local thermo = bd:getThermoregulator()
                    if thermo then
                        local bodyTemp = thermo:getCoreCelcius()
                        if bodyTemp then
                            -- Two-segment linear drain curve, asymmetric around 37C.
                            -- Hot: 37.0C=1x → 38.5C=2x → 40.0C=3x (cap; game body temp rarely exceeds ~40C).
                            -- Cold: forgiving curve down to 20C.
                            local mult
                            if bodyTemp >= TSS_FEVER_DRAIN_HOT_CAP_C then
                                mult = TSS_FEVER_DRAIN_HOT_CAP_MULT
                            elseif bodyTemp >= TSS_FEVER_DRAIN_HOT_BREAK_C then
                                local t = (bodyTemp - TSS_FEVER_DRAIN_HOT_BREAK_C) / (TSS_FEVER_DRAIN_HOT_CAP_C - TSS_FEVER_DRAIN_HOT_BREAK_C)
                                mult = TSS_FEVER_DRAIN_HOT_BREAK_MULT + t * (TSS_FEVER_DRAIN_HOT_CAP_MULT - TSS_FEVER_DRAIN_HOT_BREAK_MULT)
                            elseif bodyTemp >= NORMAL_BODY_TEMP_C then
                                local t = (bodyTemp - NORMAL_BODY_TEMP_C) / (TSS_FEVER_DRAIN_HOT_BREAK_C - NORMAL_BODY_TEMP_C)
                                mult = 1.0 + t * (TSS_FEVER_DRAIN_HOT_BREAK_MULT - 1.0)
                            elseif bodyTemp >= TSS_COLD_STAGE1_TEMP_C then
                                local t = (NORMAL_BODY_TEMP_C - bodyTemp) / (NORMAL_BODY_TEMP_C - TSS_COLD_STAGE1_TEMP_C)
                                mult = 1.0 + t * (TSS_COLD_STAGE1_MULT - 1.0)
                            elseif bodyTemp >= TSS_COLD_STAGE2_TEMP_C then
                                local t = (TSS_COLD_STAGE1_TEMP_C - bodyTemp) / (TSS_COLD_STAGE1_TEMP_C - TSS_COLD_STAGE2_TEMP_C)
                                mult = TSS_COLD_STAGE1_MULT + t * (TSS_COLD_STAGE2_MULT - TSS_COLD_STAGE1_MULT)
                            elseif bodyTemp >= TSS_COLD_STAGE3_TEMP_C then
                                local t = (TSS_COLD_STAGE2_TEMP_C - bodyTemp) / (TSS_COLD_STAGE2_TEMP_C - TSS_COLD_STAGE3_TEMP_C)
                                mult = TSS_COLD_STAGE2_MULT + t * (TSS_COLD_STAGE3_MULT - TSS_COLD_STAGE2_MULT)
                            elseif bodyTemp >= TSS_COLD_STAGE4_TEMP_C then
                                local t = (TSS_COLD_STAGE3_TEMP_C - bodyTemp) / (TSS_COLD_STAGE3_TEMP_C - TSS_COLD_STAGE4_TEMP_C)
                                mult = TSS_COLD_STAGE3_MULT + t * (TSS_COLD_STAGE4_MULT - TSS_COLD_STAGE3_MULT)
                            elseif bodyTemp >= TSS_COLD_MIN_TEMP_C then
                                local t = (TSS_COLD_STAGE4_TEMP_C - bodyTemp) / (TSS_COLD_STAGE4_TEMP_C - TSS_COLD_MIN_TEMP_C)
                                mult = TSS_COLD_STAGE4_MULT + t * (TSS_COLD_MIN_MULT - TSS_COLD_STAGE4_MULT)
                            else
                                mult = TSS_COLD_MIN_MULT
                            end
                            drain = baseDrain * mult
                        end
                    end
                    bd:ReduceGeneralHealth(drain)
                end
            end
        end
    end
end

local function updateStageByUntreated(tss)
    if tss.stage == 0 or tss.stage >= 4 then return end

    local prev = tss.stage
    if tss.stage_threshold > 0 and (tss.severity or 0) >= tss.stage_threshold then
        if tss.stage == 1 then
            tss.stage = 2
        elseif tss.stage == 2 then
            tss.stage = 3
        end
    end

    if tss.stage ~= prev then
        tss.severity = 0
        tss.stage3_minutes = 0
        tss.stage_threshold = rollNextStageThreshold(tss.stage)
        if tss.stage == 2 then
            notifyPlayer("TSS symptoms are worsening. Replace hygiene item and treat immediately.")
        elseif tss.stage == 3 then
            notifyPlayer("Critical TSS symptoms. Risk of toxic shock if left untreated.")
        end
        transmitNow()
    end
end

local function maybeWarn(tss)
    if tss.stage < 1 then return end
    tss.warning_cooldown = (tss.warning_cooldown or 0) - 1
    if tss.warning_cooldown > 0 then return end

    if tss.stage == 1 then
        notifyPlayer("Possible TSS warning: replace hygiene item and take antibiotics if available.")
    elseif tss.stage == 2 then
        notifyPlayer("TSS warning: condition worsening. Treat now.")
    elseif tss.stage == 3 then
        notifyPlayer("Critical TSS: risk of toxic shock. Remove hygiene item and take antibiotics.")
    else
        notifyPlayer("Toxic shock warning: your body is failing. Antibiotics required immediately.")
    end
    tss.warning_cooldown = getWarningIntervalMinutes()
end

local function updateSourceState(tss)
    local item = RD_HygieneManager.getCurrentlyWornSanitaryItem()
    local sourceActive = false
    local sourceType = ""

    if item then
        local itemId = item:getID() or -1
        if tss.source_item_id ~= itemId then
            tss.source_item_id = itemId
            tss.wear_minutes = 0
        else
            tss.wear_minutes = (tss.wear_minutes or 0) + 1
        end

        if isTampon(item) then
            sourceType = "tampon"
            if tss.wear_minutes >= getTamponGraceMinutes() then
                sourceActive = true
            end
        elseif isPadOrLiner(item) then
            sourceType = "pad_or_liner"
            if isDirtyOrSaturated(item) and hasGroinWoundOrInfection() then
                sourceActive = true
            end
        end
    else
        tss.source_item_id = -1
        tss.wear_minutes = 0
    end

    tss.source_type = sourceType
    tss.source_removed = (tss.stage >= 1) and (not sourceActive)
    tss.source_active = sourceActive
end

local function rollComplication(player, tss)
    tss.complication_cooldown = (tss.complication_cooldown or 60) - 1
    if tss.complication_cooldown > 0 then return end
    tss.complication_cooldown = 60

    local sb = getSandbox()
    local baseChance = sb.tss_complication_chance_pct or 5
    local bonus = 0
    local stats = player and player:getStats()
    local bd = player and player:getBodyDamage()
    if stats then
        local fatigue = stats:get(CharacterStat.FATIGUE) or 0
        if fatigue > 0.80 then bonus = bonus + 10 end
        local thirst = stats:get(CharacterStat.THIRST) or 0
        if thirst > 0.70 then bonus = bonus + 10 end
    end
    if bd then
        local thermoregulator = bd:getThermoregulator()
        if thermoregulator then
            local temp = thermoregulator:getCoreCelcius()
            if temp and temp > 39.0 then bonus = bonus + 15 end
        end
        if bd:isHasACold() then bonus = bonus + 10 end
    end

    local totalChance = math.min(60, baseChance + bonus)
    if ZombRand(100) >= totalChance then return end

    local roll = ZombRand(100)
    if roll < 60 then
        if stats then
            stats:set(CharacterStat.FATIGUE, math.min(1, stats:get(CharacterStat.FATIGUE) + 0.1))
            stats:set(CharacterStat.ENDURANCE, math.max(0, stats:get(CharacterStat.ENDURANCE) - 0.05))
            stats:set(CharacterStat.UNHAPPINESS, math.min(100, stats:get(CharacterStat.UNHAPPINESS) + 5))
        end
        print("[RedDays][TSS] Complication: mild symptom flare.")
    elseif roll < 85 then
        local spike = 30 + ZombRand(91)
        tss.severity = (tss.severity or 0) + spike
        print("[RedDays][TSS] Complication: infection flare, +" .. spike .. " severity mins.")
    elseif roll < 97 then
        if tss.stage >= 2 then
            local spike = 120 + ZombRand(361)
            tss.severity = (tss.severity or 0) + spike
            print("[RedDays][TSS] Complication: severe infection spike, +" .. spike .. " severity mins.")
        end
    else
        if tss.stage >= 3 then
            local riskGain = 20 + ZombRand(31)
            tss.tss_risk = (tss.tss_risk or 0) + riskGain
            print("[RedDays][TSS] Complication: systemic stress spike, +" .. riskGain .. " TSS risk.")
        end
    end
end

-- ===== FEVER PRESSURE (OnPlayerUpdate, throttled by in-game time) =====
-- Called from OnPlayerUpdate in main.lua every frame.
-- Accumulates in-game seconds via getGameWorldSecondsSinceLastUpdate() and fires every
-- FEVER_TICK_INTERVAL_S game-seconds, which is frame-rate independent and scales correctly
-- with game speed (4x speed = fires 4x more often in real-time, matching thermoregulator pace).
-- Per-frame cost when Stage 4 is inactive: ~2-3 field reads then return.
-- local FEVER_TICK_INTERVAL_S = 3.0 -- This is moved to the top

function RD_TSSManager.ApplyFeverPressure(player)
    if not isEnabled() then return end

    local md = getModData()
    if not md then return end
    local tss = md.ICdata.tss

    -- Cheapest possible exit: not in Stage 4 or under antibiotic suppression
    if tss.stage ~= 4 or (tss.abx_suppress_mins or 0) > 0 then
        tss._feverAccum = 0
        tss._feverDrive = 0
        return
    end

    -- Accumulate in-game seconds; only do real work once the interval is reached
    local dt = getGameTime():getGameWorldSecondsSinceLastUpdate()
    tss._feverAccum = (tss._feverAccum or 0) + dt
    if tss._feverAccum < FEVER_TICK_INTERVAL_S then return end
    local elapsedGameSecs = tss._feverAccum
    tss._feverAccum = 0

    local bd = player:getBodyDamage()
    if not bd then return end
    local thermo = bd:getThermoregulator()
    local feverStats = player:getStats()
    if not thermo or not feverStats then return end
    local currentTempC = thermo:getCoreCelcius()
    if not currentTempC then return end
    local sickness = feverStats:get(CharacterStat.SICKNESS) or 0

    -- Let vanilla stage-4 sickness establish fever first; this controller only nudges on top.
    if sickness < TSS_FEVER_NUDGE_MIN_SICKNESS or currentTempC < TSS_FEVER_NUDGE_START_TEMP_C then
        tss._feverDrive = 0
        return
    end

    -- One-time calibration print when Stage 4 first fires so knob values can be verified
    if not tss._tempDiagPrinted then
        tss._tempDiagPrinted = true
        local statVal = feverStats:get(CharacterStat.TEMPERATURE)
        print(string.format(
            "[RedDays][TEMP] Scale calibration: getCoreCelcius()=%.4f  stats:get(TEMPERATURE)=%.4f  min=%.4f  max=%.4f  default=%.4f",
            currentTempC, statVal or 0,
            CharacterStat.TEMPERATURE:getMinimumValue(),
            CharacterStat.TEMPERATURE:getMaximumValue(),
            CharacterStat.TEMPERATURE:getDefaultValue()))
    end

    local elapsedGameMins = elapsedGameSecs / 60.0
    local gapC = math.max(0, TSS_FEVER_TARGET_C - currentTempC)

    -- Integrator stores persistent fever drive so pressure does not stall in upper temperatures.
    local drive = tss._feverDrive or 0
    if gapC > 0 then
        drive = math.min(
            TSS_FEVER_INTEGRATOR_MAX_GAIN_PER_MIN,
            drive + gapC * TSS_FEVER_INTEGRATOR_GAIN_PER_DEG_PER_MIN * elapsedGameMins)
    else
        drive = math.max(0, drive - TSS_FEVER_INTEGRATOR_DECAY_PER_MIN * elapsedGameMins)
    end
    tss._feverDrive = drive

    if gapC > 0 then
        local proportionalGain = TSS_FEVER_PRESSURE_BASE_GAIN_PER_MIN
            + gapC * TSS_FEVER_PRESSURE_CATCHUP_PER_DEG_PER_MIN

        local sicknessReadiness = math.max(0, math.min(1, (sickness - TSS_FEVER_NUDGE_MIN_SICKNESS) / (1.0 - TSS_FEVER_NUDGE_MIN_SICKNESS)))
        local plateauReadiness = math.max(0, math.min(1, (currentTempC - TSS_FEVER_NUDGE_START_TEMP_C) / (TSS_FEVER_NUDGE_FULL_TEMP_C - TSS_FEVER_NUDGE_START_TEMP_C)))
        local nudgeReadiness = math.min(sicknessReadiness, plateauReadiness)
        if nudgeReadiness <= 0 then
            tss._feverDrive = 0
            return
        end

        -- As core temp rises, vanilla pushes harder; add a controlled high-temp bonus to compensate.
        local highTempSpan = math.max(0.1, TSS_FEVER_TARGET_C - TSS_FEVER_HIGH_TEMP_START_C)
        local highBand = math.max(0, math.min(1, (currentTempC - TSS_FEVER_HIGH_TEMP_START_C) / highTempSpan))
        local highTempMult = 1.0 + highBand * TSS_FEVER_HIGH_TEMP_BONUS_MULT

        local rawGain = (proportionalGain * highTempMult + drive) * nudgeReadiness
        local gainPerMin = math.max(
            TSS_FEVER_PRESSURE_MIN_GAIN_PER_MIN,
            math.min(TSS_FEVER_PRESSURE_MAX_GAIN_PER_MIN, rawGain))

        local nudgePct = getSandbox().tss_fever_nudge_strength_pct or 100
        local debugMult = RD_TSSManager._debugSpeedMult or 1
        feverStats:add(CharacterStat.TEMPERATURE, gainPerMin * elapsedGameMins * debugMult * (nudgePct / 100))
    end
end

function RD_TSSManager.LoadPlayerData()
    local md = getModData()
    if not md then return end
    local tss = md.ICdata.tss

    tss.stage = clampStage(tss.stage or 0)
    tss.exposure_minutes = tss.exposure_minutes or 0
    -- Migrate untreated_minutes -> severity (v2 architecture rename)
    if tss.untreated_minutes ~= nil and tss.severity == nil then
        tss.severity = tss.untreated_minutes
    end
    tss.untreated_minutes = nil
    tss.severity = tss.severity or 0
    tss.stage3_minutes = tss.stage3_minutes or 0
    tss.complication_cooldown = tss.complication_cooldown or 60
    tss.first_symptom_minutes = tss.first_symptom_minutes or 0
    tss.wear_minutes = tss.wear_minutes or 0
    tss.source_active = tss.source_active or false
    tss.source_removed = tss.source_removed or false
    tss.source_type = tss.source_type or ""
    tss.source_item_id = tss.source_item_id or -1
    tss.warning_cooldown = tss.warning_cooldown or 0
    tss.cured = tss.cured or false
    tss.stabilized_until = tss.stabilized_until or 0
    tss.antibiotics_taken_recently = tss.antibiotics_taken_recently or false
    tss.disinfectant_recently = tss.disinfectant_recently or false
    tss.alcohol_recently = tss.alcohol_recently or false
    tss.recovery_mode = tss.recovery_mode or "none"
    tss.baseline_blur_effect = tss.baseline_blur_effect or tss.baseline_drunkenness or 0
    tss.baseline_drunkenness = nil
    tss.tss_rolls = tss.tss_rolls or 0
    tss.treatment_attempts = tss.treatment_attempts or 0
    tss.tss_risk = tss.tss_risk or 0
    tss.abx_toxin_level = tss.abx_toxin_level or 0
    tss.abx_cooldown_mins = tss.abx_cooldown_mins or 0
    tss.abx_suppress_mins = tss.abx_suppress_mins or 0
    tss.abx_dose_count = tss.abx_dose_count or 0
    tss.tss_fever_induced = tss.tss_fever_induced or 0
    tss._feverDrive = tss._feverDrive or 0
    tss._feverAccum = tss._feverAccum or 0
    tss.stage_threshold = tss.stage_threshold or rollNextStageThreshold(tss.stage)

    local player = getPlayer()
    if player then
        tss.baseline_blur_effect = player:getSleepingTabletEffect()
    end
end

function RD_TSSManager.registerTreatmentFromItem(item, actionName)
    if not item then return end
    local md = getModData()
    if not md then return end
    local tss = md.ICdata.tss

    local fullType = item:getFullType() or ""
    if fullType ~= "Base.Antibiotics" then return end
    if tss.stage < 1 then
        print("[RedDays][TSS] Antibiotics taken but no active TSS infection.")
        return
    end

    if (tss.abx_cooldown_mins or 0) > 0 then
        local hoursLeft = math.ceil(tss.abx_cooldown_mins / MINUTES_PER_HOUR)
        print("[RedDays][TSS] Antibiotic dose not ready. Next effective dose in ~" .. hoursLeft .. " hours.")
        return
    end

    local sb = getSandbox()
    local cooldownMins = (sb.tss_abx_dose_cooldown_hours or 6) * MINUTES_PER_HOUR
    local suppressMins = (sb.tss_abx_suppress_window_hours or 8) * MINUTES_PER_HOUR
    local toxinReduction = sb.tss_abx_toxin_per_dose or 7

    tss.abx_cooldown_mins = cooldownMins
    tss.abx_suppress_mins = suppressMins
    tss.abx_dose_count = (tss.abx_dose_count or 0) + 1

    if tss.stage == 4 then
        tss.abx_toxin_level = math.max(0, (tss.abx_toxin_level or 100) - toxinReduction)
        print("[RedDays][TSS] Dose " .. tss.abx_dose_count .. ". Toxin: " .. tss.abx_toxin_level .. "/100. HP drain suppressed for " .. math.floor(suppressMins / MINUTES_PER_HOUR) .. "h.")
    else
        -- Stages 1-3: slow progression and suppress sickness ramp
        local severityReduction = toxinReduction * MINUTES_PER_HOUR
        tss.severity = math.max(0, (tss.severity or 0) - severityReduction)
        tss.stabilized_until = math.max(tss.stabilized_until or 0, suppressMins)
        tss.recovery_mode = "antibiotics"
        print("[RedDays][TSS] Dose " .. tss.abx_dose_count .. ". Severity reduced by " .. severityReduction .. " mins. Symptoms eased for " .. math.floor(suppressMins / MINUTES_PER_HOUR) .. "h.")
    end
    transmitNow()
end

function RD_TSSManager.EveryOneMinute(cycle)
    if not isEnabled() then return end

    local md = getModData()
    if not md then return end
    local player = getPlayer()
    if not player or player:isDead() then return end

    local tss = md.ICdata.tss
    if tss.stage == 0 and tss.recovery_mode == "none" then
        tss.baseline_blur_effect = player:getSleepingTabletEffect()
    end
    updateSourceState(tss)

    local stressMult = getProgressionMultiplier(player)

    if tss.stabilized_until and tss.stabilized_until > 0 then
        tss.stabilized_until = tss.stabilized_until - 1
    end

    if tss.source_active then
        if tss.stage == 0 and tss.stage_threshold == 0 then
            tss.stage_threshold = rollNextStageThreshold(0)
        end
        tss.exposure_minutes = tss.exposure_minutes + stressMult
    elseif tss.stage == 0 then
        tss.exposure_minutes = math.max(0, tss.exposure_minutes - 2)
    end

    if tss.stage == 0 and tss.source_active and tss.stage_threshold > 0 and tss.exposure_minutes >= tss.stage_threshold then
        tss.stage = 1
        tss.severity = 0
        tss.stage3_minutes = 0
        tss.stage_threshold = rollNextStageThreshold(1)
        tss.first_symptom_minutes = 0
        tss.warning_cooldown = 0
        notifyPlayer("You feel sudden fever, weakness, and nausea. This may be TSS.")
        transmitNow()
    end

    if tss.stage >= 1 then
        tss.first_symptom_minutes = tss.first_symptom_minutes + 1

        if tss.stage == 3 then
            tss.stage3_minutes = (tss.stage3_minutes or 0) + 1
        end

        if tss.source_active then
            tss.severity = (tss.severity or 0) + stressMult
        else
            tss.severity = (tss.severity or 0) + (0.25 * stressMult)
        end

        -- Tick antibiotic treatment timers
        if (tss.abx_cooldown_mins or 0) > 0 then
            tss.abx_cooldown_mins = tss.abx_cooldown_mins - 1
        end
        if (tss.abx_suppress_mins or 0) > 0 then
            tss.abx_suppress_mins = tss.abx_suppress_mins - 1
        end

        -- Fever pressure is applied via ApplyFeverPressure() in OnPlayerUpdate (main.lua),
        -- throttled to every 6 in-game seconds for smooth, frame-rate-independent pressure.

        -- Check if Stage 4 toxin has been cleared by antibiotic course
        if tss.stage == 4 and (tss.abx_toxin_level or 0) <= 0 and (tss.abx_dose_count or 0) > 0 then
            tss.stage = 3
            tss.severity = 0
            tss.stage3_minutes = 0
            tss.stage_threshold = 0
            tss.tss_risk = 0
            tss._tempDiagPrinted = nil  -- reset so calibration prints if Stage 4 recurs
            tss._feverDrive = 0
            tss._feverAccum = 0
            -- ApplyFeverPressure stops immediately (stage ≠ 4). CharacterStat.SICKNESS remains
            -- elevated and the game's thermoregulator keeps body temp near 38C until SICKNESS
            -- decays below ~0.91 via applySicknessProgression (recovery_mode = "antibiotics").
            -- Fever breaks gradually as the player recovers — no manual TEMPERATURE reset needed.
            tss.recovery_mode = "antibiotics"
            print("[RedDays][TSS] Toxin cleared by antibiotics. Fever breaking. Transitioning to Stage 3 recovery.")
            transmitNow()
            return
        end

        rollComplication(player, tss)
        updateStageByUntreated(tss)
        rollTSSTransition(player, tss)
        maybeWarn(tss)
        applySicknessProgression(player, tss)
        applyStageStatEffects(player, tss)
    else
        applySicknessProgression(player, tss)
    end
end

return RD_TSSManager