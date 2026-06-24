RD_TSSManager = RD_TSSManager or {}
RDTSSManager = RD_TSSManager -- Alias for backward compatibility

require "RD_game_api"
require "RD_hygiene_manager"

local MINUTES_PER_HOUR = 60
local MINUTES_PER_DAY = 1440

local SICKNESS_RAMP_STAGE1 = 0.00035
local SICKNESS_RAMP_STAGE2 = 0.0008
local SICKNESS_RAMP_STAGE3 = 0.0014
local SICKNESS_DECAY_BASE = 0.0002
local SICKNESS_DECAY_FALLBACK = 0.0011
local SICKNESS_DECAY_ANTIBIOTICS = 0.0018
local SICKNESS_RECOVERY_COMPLETE = 0.02
local BLUR_STAGE3_TARGET = 0.35
local BLUR_RAMP_UP = 0.01
local BLUR_RAMP_DOWN = 0.008

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

local function getProgressionSpeedPct()
    local sb = getSandbox()
    return math.max(10, math.min(200, sb.tss_progression_speed_pct or 100))
end

local function getRiskMultiplier()
    local sb = getSandbox()
    return math.max(1, sb.tss_risk_multiplier_pct or 100)
end

local function getDisinfectBaseChance()
    local sb = getSandbox()
    return math.max(5, math.min(95, sb.tss_disinfectant_success_pct or 65))
end

local function rollNextStageThreshold(stage)
    local base = 0
    if stage == 0 then
        base = 2880 + ZombRand(4321)
    elseif stage == 1 then
        base = 7200 + ZombRand(23041)
    elseif stage == 2 then
        base = 30240 + ZombRand(50401)
    else
        return 0
    end
    return math.floor(base * (getProgressionSpeedPct() / 100))
end

local function getModData()
    local md = RD_zapi.getModData()
    if not md then return nil end
    md.ICdata = md.ICdata or {}
    md.ICdata.tss = md.ICdata.tss or {
        stage = 0,
        exposure_minutes = 0,
        untreated_minutes = 0,
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
    }
    return md
end

local function getPlayer()
    return RD_zapi.getPlayer()
end

local function notifyPlayer(msg)
    if not msg then return end
    local player = getPlayer()
    if player then
        player:Say(msg)
    end
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
    tss.untreated_minutes = 0
    tss.stage_threshold = rollNextStageThreshold(1)
    tss.warning_cooldown = getWarningIntervalMinutes()
    tss.cured = true
    tss.stabilized_until = 0
    tss.recovery_mode = "antibiotics"
    resetTreatmentFlags(tss)
    notifyPlayer("Treatment started. TSS symptoms should gradually improve.")
    transmitNow()
end

local function treatmentStageChance(stage)
    local base = getDisinfectBaseChance()
    if stage <= 1 then return base end
    if stage == 2 then return math.max(10, base - 20) end
    return math.max(5, base - 40)
end

local function applyDisinfectFallback(tss)
    if not tss.source_removed then
        notifyPlayer("Remove or replace the offending hygiene item first.")
        return
    end

    local chance = treatmentStageChance(tss.stage)
    local roll = ZombRand(1, 101)
    tss.treatment_attempts = (tss.treatment_attempts or 0) + 1

    if roll <= chance then
        if tss.stage <= 1 then
            cureTSS(tss)
            return
        end

        -- Disinfectant/alcohol can stabilize and step severity down, but is less reliable than antibiotics.
        tss.stage = clampStage(tss.stage - 1)
        tss.untreated_minutes = math.max(0, tss.untreated_minutes - (8 * MINUTES_PER_HOUR))
        tss.stabilized_until = 12 * MINUTES_PER_HOUR
        tss.recovery_mode = "fallback"
        notifyPlayer("You temporarily stabilized TSS symptoms. Keep monitoring and seek antibiotics.")
        transmitNow()
    else
        notifyPlayer("Disinfectant/alcohol treatment did not fully control symptoms.")
    end
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

    local currentSickness = player:getCorpseSicknessRate()
    local newSickness = currentSickness

    if tss.recovery_mode ~= "none" then
        local decayRate = SICKNESS_DECAY_BASE
        if tss.recovery_mode == "antibiotics" then
            decayRate = SICKNESS_DECAY_ANTIBIOTICS
        elseif tss.recovery_mode == "fallback" then
            decayRate = SICKNESS_DECAY_FALLBACK
        end

        newSickness = math.max(0, currentSickness - decayRate)

        if newSickness <= SICKNESS_RECOVERY_COMPLETE then
            tss.stage = 0
            tss.exposure_minutes = 0
            tss.untreated_minutes = 0
            tss.first_symptom_minutes = 0
            tss.warning_cooldown = 0
            tss.tss_risk = 0
            tss.stage_threshold = 0
            tss.cured = false
            tss.recovery_mode = "none"
            notifyPlayer("TSS symptoms have resolved.")
            transmitNow()
        end
    elseif tss.stage >= 1 then
        local rampRate = SICKNESS_RAMP_STAGE1
        if tss.stage == 2 then
            rampRate = SICKNESS_RAMP_STAGE2
        elseif tss.stage >= 3 then
            rampRate = SICKNESS_RAMP_STAGE3
        end

        if not tss.source_active then
            rampRate = rampRate * 0.35
        end
        if tss.stabilized_until and tss.stabilized_until > 0 then
            rampRate = rampRate * 0.5
        end

        newSickness = math.min(1, currentSickness + rampRate)
    else
        newSickness = math.max(0, currentSickness - SICKNESS_DECAY_BASE)
    end

    player:setCorpseSicknessRate(newSickness)
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
        notifyPlayer("Your body is in toxic shock. Immediate treatment is required.")
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
            local bd = player:getBodyDamage()
            if bd then bd:ReduceGeneralHealth(0.004) end
        end
    end
end

local function updateStageByUntreated(tss)
    if tss.stage == 0 or tss.stage >= 4 then return end

    local prev = tss.stage
    if tss.stage_threshold > 0 and tss.untreated_minutes >= tss.stage_threshold then
        if tss.stage == 1 then
            tss.stage = 2
        elseif tss.stage == 2 then
            tss.stage = 3
        end
    end

    if tss.stage ~= prev then
        tss.untreated_minutes = 0
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

function RD_TSSManager.LoadPlayerData()
    local md = getModData()
    if not md then return end
    local tss = md.ICdata.tss

    tss.stage = clampStage(tss.stage or 0)
    tss.exposure_minutes = tss.exposure_minutes or 0
    tss.untreated_minutes = tss.untreated_minutes or 0
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
    if fullType == "Base.Antibiotics" then
        tss.antibiotics_taken_recently = true
        notifyPlayer("Antibiotics taken.")
        return
    end

    local lower = lowerText(fullType)
    if string.find(lower, "disinfect", 1, true) or string.find(lower, "alcohol", 1, true) or string.find(lower, "whiskey", 1, true) then
        if actionName == "ISApplyDisinfectant" or actionName == "ISTakePillAction" then
            if string.find(lower, "alcohol", 1, true) or string.find(lower, "whiskey", 1, true) then
                tss.alcohol_recently = true
            else
                tss.disinfectant_recently = true
            end
            notifyPlayer("Disinfectant treatment used.")
        end
    end
end

function RD_TSSManager.ISTakePillAction_perform(self)
    if not self or not self.item then return end
    RD_TSSManager.registerTreatmentFromItem(self.item, "ISTakePillAction")
end

function RD_TSSManager.ISApplyDisinfectant_perform(self)
    if not self then return end
    local item = self.item or self.disinfectant or self.alcohol
    if not item then return end
    RD_TSSManager.registerTreatmentFromItem(item, "ISApplyDisinfectant")
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
        tss.untreated_minutes = 0
        tss.stage_threshold = rollNextStageThreshold(1)
        tss.first_symptom_minutes = 0
        tss.warning_cooldown = 0
        notifyPlayer("You feel sudden fever, weakness, and nausea. This may be TSS.")
        transmitNow()
    end

    if tss.stage >= 1 then
        tss.first_symptom_minutes = tss.first_symptom_minutes + 1

        if tss.source_active then
            tss.untreated_minutes = tss.untreated_minutes + stressMult
        else
            tss.untreated_minutes = tss.untreated_minutes + (0.25 * stressMult)
        end

        if tss.antibiotics_taken_recently then
            if tss.stage == 4 and tss.source_removed then
                tss.stage = 3
                tss.untreated_minutes = 0
                tss.stage_threshold = 0
                tss.tss_risk = 0
                tss.recovery_mode = "antibiotics"
                tss.antibiotics_taken_recently = false
                notifyPlayer("Antibiotics are slowing TSS. You are no longer in Stage 4, but continue treatment.")
                transmitNow()
                return
            elseif tss.source_removed then
                cureTSS(tss)
                return
            else
                tss.stabilized_until = math.max(tss.stabilized_until or 0, 8 * MINUTES_PER_HOUR)
                tss.recovery_mode = "fallback"
                notifyPlayer("Antibiotics help, but remove or replace the offending hygiene item to recover.")
            end
            tss.antibiotics_taken_recently = false
        end

        if tss.disinfectant_recently or tss.alcohol_recently then
            if hasGroinWoundOrInfection() then
                applyDisinfectFallback(tss)
            else
                notifyPlayer("Disinfectant/alcohol treatment requires a treatable groin wound or infection context.")
            end
            tss.disinfectant_recently = false
            tss.alcohol_recently = false
        end

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