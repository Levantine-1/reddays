EffectsPMS = {}
require "RedDays/game_api"

    function EffectsPMS.setAngerMoodle(stats, target_value, rate_multiplier)
        -- Anger or irritability tends to rise during the late luteal phase (about 1 week before period).
        -- Often linked to progesterone dominance and serotonin fluctuations.
        -- Peaks just before menstruation and resolves quickly once bleeding begins.
        -- Typically short-lived bursts of frustration or low patience.

        -- Anger moodle is a float from 0 to 1 where 1 is max anger
        -- By default, anger decrements at a rate of 0.35 per ingame hour

        local severity = target_value / 100

        -- Default Anger decrement is -0.35 per ingame hour
        local angerLevel_change_rate = .02 -- This is an arbitrary value to gradually ramp anger up
        local currentAngerLevel = stats:get(CharacterStat.ANGER)
        stats:set(CharacterStat.ANGER, math.min(severity, currentAngerLevel + angerLevel_change_rate))

        -- Default Endurance Recovery is +0.160 per ingame hour or +0.0268/min, so +0.0053/min is a 100% buff rate at max PMS Severity
        local endurance_change_rate = (0.0053 * severity) * rate_multiplier
        local current_endurance = stats:get(CharacterStat.ENDURANCE)
        stats:set(CharacterStat.ENDURANCE, math.min(1, current_endurance + endurance_change_rate))
    end

    function EffectsPMS.setCrampsEffect(stats, target_value, rate_multiplier)
        -- Begins a few hours before menstruation or with its onset due to uterine contractions (prostaglandins).
        -- Peaks during the first 1–2 days of bleeding, then fades by day 3.
        -- Intensity varies; typically moderate in healthy individuals.
        -- May cause mild lower back or thigh ache.
        local change_rate = 2 * rate_multiplier

        local lowerTorso = zapi.getBodyPart(BodyPartType.Torso_Lower)
        local groin = zapi.getBodyPart(BodyPartType.Groin)

        local current_lower_torso_stiffness = lowerTorso:getStiffness()
        if current_lower_torso_stiffness < target_value then
            lowerTorso:setStiffness(math.max(0, current_lower_torso_stiffness + change_rate))
        end
        
        local current_groin_stiffness = groin:getStiffness()
        if current_groin_stiffness < target_value then
            groin:setStiffness(math.max(0, current_groin_stiffness + change_rate))
        end
    end

    function EffectsPMS.setFatigueEffect(stats, target_value, rate_multiplier)
        -- Fatigue builds gradually during the luteal phase (about 5–7 days pre-period).
        -- Peaks right before or at the start of menstruation due to hormonal shifts and poor sleep quality.
        -- Resolves around day 2–3 of the period.
        -- May mildly return mid-cycle if ovulation symptoms are tracked, but less intense.

        local severity = target_value / 100

        -- Default Fatigue decrement is -0.04 per ingame hour, so 0.00034 is a 50% debuff rate at max PMS Severity
        local fatigue_change_rate = (0.00034 * severity) * rate_multiplier
        local current_fatigue = stats:get(CharacterStat.FATIGUE)
        stats:set(CharacterStat.FATIGUE, math.min(1, current_fatigue + fatigue_change_rate))

        -- Default Endurance Recovery is +0.160 per ingame hour, so 0.00134 is a 50% debuff rate at max PMS Severity
        local endurance_change_rate = (0.00134 * severity) * rate_multiplier
        local current_endurance = stats:get(CharacterStat.ENDURANCE)
        stats:set(CharacterStat.ENDURANCE, math.max(0, current_endurance - endurance_change_rate))
    end

    function EffectsPMS.setTenderBreastsEffect(stats, target_value, rate_multiplier, alsoHasCramps)
        -- Typically begins 3–5 days before menstruation due to rising progesterone levels.
        -- Peaks right before the period starts, then subsides by about day 2–3 of menstruation.
        -- Intensity ranges from mild tenderness to noticeable soreness when touched.
        -- Often correlates with hormonal water retention.

        if alsoHasCramps then
            target_value = target_value * 0.5 -- Reduce breast tenderness severity by 50% if cramps are also active as too much pain is unrealistic
        end

        local change_rate = 2 * rate_multiplier

        local upperTorso = zapi.getBodyPart(BodyPartType.Torso_Upper)

        local current_upper_torso_stiffness = upperTorso:getStiffness()
        if current_upper_torso_stiffness < target_value then
            upperTorso:setStiffness(math.max(0, current_upper_torso_stiffness + change_rate))
        end
    end

    local setFoodCravingEffect_lastHunger = 0
    local setFoodCravingEffect_jumpedToHungry = false
    function EffectsPMS.setFoodCravingEffect(stats, target_value, rate_multiplier)
        -- Starts about 5–7 days before menstruation.
        -- Common cravings: carbs, sweets, salty or fatty foods due to serotonin and blood sugar changes.
        -- Peaks just before menstruation and fades within the first day of bleeding.
        -- Can be reduced by stable blood sugar or exercise in simulation.

        -- Pop this moodle up as soon as Eaten food timer is below 3200
        -- However, if food eaten timer is counting down, hunger does not decrement
        -- So we should be able to safely assume if hunger is above 0.01, hunger satiety timer is over.

        -- Hunger is a float from 0 to 1 where 1 is max hunger
        -- Hunger increments by +0.035 per ingame hour or +0.000583/min by default
        -- local increment_rate = 0.000583

        -- Since hunger has a real negative effect, we'll only pop the peckish moodle and hold it there
        -- until enough time passed to make up for how much red days deducts

        local currentHunger = stats:get(CharacterStat.HUNGER)

        if currentHunger < setFoodCravingEffect_lastHunger then
            setFoodCravingEffect_jumpedToHungry = false
        end

        -- Linear mapping: input 0 → 0.1, input 100 → 0.001
        local target_trigger_hunger_value = 0.1 - (target_value * 0.00099)

        if currentHunger > target_trigger_hunger_value and currentHunger < 0.16 and not setFoodCravingEffect_jumpedToHungry then
            stats:set(CharacterStat.HUNGER, 0.16)  -- Jump to peckish threshold
            setFoodCravingEffect_jumpedToHungry = true
        end
        setFoodCravingEffect_lastHunger = currentHunger
    end

    function EffectsPMS.setSadnessMoodle(stats, target_value, rate_multiplier)
        -- Mild sadness or mood dips commonly appear in the days leading up to menstruation.
        -- May involve lower energy, sensitivity, or tearfulness.
        -- Often starts 3–5 days before menstruation and resolves within 1–2 days of bleeding onset.
        -- Related to serotonin and estrogen drops.

        -- Depression moodle is an int from 0 - 100 where 100 is max sadness
        -- Moodles level up from 1-4 at these respective thresholds: 20, 40, 60, 80

        local currentUnhappynessLevel = stats:get(CharacterStat.UNHAPPINESS)
        local change_rate = 1  -- Adjust unhappiness by 1 per minute toward target

        -- Gradually move toward target value
        if currentUnhappynessLevel < target_value then
            -- Increase unhappiness toward target
            stats:set(CharacterStat.UNHAPPINESS, math.min(100, currentUnhappynessLevel + change_rate))
        elseif currentUnhappynessLevel > target_value then
            -- Decrease unhappiness toward target
            stats:set(CharacterStat.UNHAPPINESS, math.max(0, currentUnhappynessLevel - change_rate))
        end
    end

    local function clearStiffness(currentCycle)
        local resetValue = 22.5

        if currentCycle.pms_cramps then
            local groin = zapi.getBodyPart(BodyPartType.Groin)
            local lowerTorso = zapi.getBodyPart(BodyPartType.Torso_Lower)

            if groin:getStiffness() > resetValue then
                groin:setStiffness(resetValue)
            end
            if lowerTorso:getStiffness() > resetValue then
                lowerTorso:setStiffness(resetValue)
            end
        end

        if currentCycle.pms_tenderBreasts then
            local upperTorso = zapi.getBodyPart(BodyPartType.Torso_Upper)

            if upperTorso:getStiffness() > resetValue then
                upperTorso:setStiffness(resetValue)
            end
        end

        modData.ICdata.pill_recently_taken = false
    end

    local function applyEnabledSymptomEffects(currentCycle, pms_severity, rate_multiplier)
        local player = zapi.getPlayer()
        if not player then return end

        local stats = player:getStats()

        local target_value = (pms_severity / 100) * currentCycle.healthEffectSeverity

        if modData.ICdata.pill_recently_taken then
            clearStiffness(currentCycle)
        end

        if modData.ICdata.pill_effect_active then
            target_value = target_value * 0.25 -- Reduce severity by 75% if pills are active
        end

        if currentCycle.pms_agitation then
            EffectsPMS.setAngerMoodle(stats, target_value, rate_multiplier)
        end
        if currentCycle.pms_cramps then
            EffectsPMS.setCrampsEffect(stats, target_value, rate_multiplier)
        end
        if currentCycle.pms_fatigue then
            EffectsPMS.setFatigueEffect(stats, target_value, rate_multiplier)
        end
        if currentCycle.pms_tenderBreasts then
            EffectsPMS.setTenderBreastsEffect(stats, target_value, rate_multiplier, currentCycle.pms_cramps)
        end
        if currentCycle.pms_craveFood then
            EffectsPMS.setFoodCravingEffect(stats, target_value, rate_multiplier)
        end
        if currentCycle.pms_Sadness then
            EffectsPMS.setSadnessMoodle(stats, target_value, rate_multiplier)
        end
    end



    local pill_effect_counter_max = SandboxVars.RedDays.painkillerEffectDuration or 36 -- Pills are effective for 6 hours (36 * 10 = 360 minutes)
    local function takePillsStiffness()
        if not modData.ICdata.pill_effect_counter then return end -- Safety check incase player dies and respawns
        if modData.ICdata.pill_effect_counter < pill_effect_counter_max then
            modData.ICdata.pill_effect_counter = modData.ICdata.pill_effect_counter + 1
        else
            print("PMS Painkiller Effect Ended")
            Events.EveryTenMinutes.Remove(takePillsStiffness) -- Pills are no longer effective
            modData.ICdata.pill_effect_active = false
            modData.ICdata.pill_effect_counter = 0
            return
        end
    end

    function EffectsPMS.ISTakePillAction_perform(self)
        if self.item:getFullType() == "Base.Pills" then
            print("Painkillers Taken, Reducing PMS Symptoms")
            modData.ICdata.pill_recently_taken = true
            modData.ICdata.pill_effect_active = true
            modData.ICdata.pill_effect_counter = 0
            Events.EveryTenMinutes.Add(takePillsStiffness)
        end
    end
    -- 2026-01-23 Moved to events_intercepts.lua


    function EffectsPMS.LoadPlayerData()
        modData.ICdata.pill_recently_taken = modData.ICdata.pill_recently_taken or false
        modData.ICdata.pill_effect_counter = modData.ICdata.pill_effect_counter or 0
        modData.ICdata.pill_effect_active = modData.ICdata.pill_effect_active or false
        if modData.ICdata.pill_effect_active then
            Events.EveryTenMinutes.Add(takePillsStiffness) -- Start the timer if the effect is active
        end
    end
    -- Events.OnGameStart.Add(EffectsPMS.LoadPlayerData)
    -- Event hook moved to events_intercepts.lua 2026-01-22

    function EffectsPMS.applyPMSEffectsMain()
        local pms_severity = CycleManager.getPMSseverity()
        if pms_severity < 0.1 then return end
        local currentCycle = modData.ICdata.currentCycle
        if not currentCycle then return end
        if not currentCycle.healthEffectSeverity then return end -- If mod existed before PMS update, some values after this may be nil until a new cycle is generated.
        
        local rate_multiplier = 1 -- Placeholder for future use if needed
        applyEnabledSymptomEffects(currentCycle, pms_severity, rate_multiplier)

    end
    -- Events.EveryOneMinute.Add(EffectsPMS.applyPMSEffectsMain)
    -- Event hook moved to events_intercepts.lua 2026-01-22

return EffectsPMS
