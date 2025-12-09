EffectsPMS = {}

        -- pms_agitation = false, -- Set Anger moodle, boost endurance recovery
        -- pms_cramps = true, --  Set stiffness effects lower torso
        -- pms_fatigue = true, -- Set fatigue effects
        -- pms_tenderBreasts = false, --  set chest stiffness
        -- pms_craveFood = false, -- No need for moodle, just more hungry
        -- pms_Sadness = false -- Set Sadness moodle, reduce endurance recovery

    function EffectsPMS.setAngerMoodle(player, stats, target_value, rate_multiplier)
        -- Anger or irritability tends to rise during the late luteal phase (about 1 week before period).
        -- Often linked to progesterone dominance and serotonin fluctuations.
        -- Peaks just before menstruation and resolves quickly once bleeding begins.
        -- Typically short-lived bursts of frustration or low patience.

        -- Anger moodle is a float from 0 to 1 where 1 is max anger
        -- By default, anger decrements at a rate of 0.35 per ingame hour

        local severity = target_value / 100

        -- Default Anger decrement is -0.35 per ingame hour
        local angerLevel_change_rate = .02 -- This is an arbitrary value to gradually ramp anger up
        local currentAngerLevel = stats:getAnger()
        stats:setAnger(math.min(severity, currentAngerLevel + angerLevel_change_rate))

        -- Default Endurance Recovery is +0.160 per ingame hour or +0.0268/min, so +0.0053/min is a 100% buff rate at max PMS Severity
        local endurance_change_rate = (0.0053 * severity) * rate_multiplier
        local current_endurance = stats:getEndurance()
        stats:setEndurance(math.min(1, current_endurance + endurance_change_rate))
    end

    function EffectsPMS.setCrampsEffect(player, stats, target_value, rate_multiplier)
        -- Begins a few hours before menstruation or with its onset due to uterine contractions (prostaglandins).
        -- Peaks during the first 1–2 days of bleeding, then fades by day 3.
        -- Intensity varies; typically moderate in healthy individuals.
        -- May cause mild lower back or thigh ache.
        local change_rate = 2 * rate_multiplier

        local bodyDamage = player:getBodyDamage()
        local lowerTorso = bodyDamage:getBodyPart(BodyPartType.Torso_Lower)
        local groin = bodyDamage:getBodyPart(BodyPartType.Groin)

        local current_lower_torso_stiffness = lowerTorso:getStiffness()
        if current_lower_torso_stiffness < target_value then
            lowerTorso:setStiffness(math.max(0, current_lower_torso_stiffness + change_rate))
        end
        
        local current_groin_stiffness = groin:getStiffness()
        if current_groin_stiffness < target_value then
            groin:setStiffness(math.max(0, current_groin_stiffness + change_rate))
        end
    end

    function EffectsPMS.setFatigueEffect(player, stats, target_value, rate_multiplier)
        -- Fatigue builds gradually during the luteal phase (about 5–7 days pre-period).
        -- Peaks right before or at the start of menstruation due to hormonal shifts and poor sleep quality.
        -- Resolves around day 2–3 of the period.
        -- May mildly return mid-cycle if ovulation symptoms are tracked, but less intense.

        local severity = target_value / 100

        -- Default Fatigue decrement is -0.04 per ingame hour, so 0.00034 is a 50% debuff rate at max PMS Severity
        local fatigue_change_rate = (0.00034 * severity) * rate_multiplier
        local current_fatigue = stats:getFatigue()
        stats:setFatigue(math.min(1, current_fatigue + fatigue_change_rate))

        -- Default Endurance Recovery is +0.160 per ingame hour, so 0.00134 is a 50% debuff rate at max PMS Severity
        local endurance_change_rate = (0.00134 * severity) * rate_multiplier
        local current_endurance = stats:getEndurance()
        stats:setEndurance(math.max(0, current_endurance - endurance_change_rate))
    end

    function EffectsPMS.setTenderBreastsEffect(player, stats, target_value, rate_multiplier)
        -- Typically begins 3–5 days before menstruation due to rising progesterone levels.
        -- Peaks right before the period starts, then subsides by about day 2–3 of menstruation.
        -- Intensity ranges from mild tenderness to noticeable soreness when touched.
        -- Often correlates with hormonal water retention.

        local change_rate = 2 * rate_multiplier

        local bodyDamage = player:getBodyDamage()
        local upperTorso = bodyDamage:getBodyPart(BodyPartType.Torso_Upper)

        local current_upper_torso_stiffness = upperTorso:getStiffness()
        if current_upper_torso_stiffness < target_value then
            upperTorso:setStiffness(math.max(0, current_upper_torso_stiffness + change_rate))
        end
    end

    function EffectsPMS.setFoodCravingEffect(player, stats, target_value, rate_multiplier)
        -- Starts about 5–7 days before menstruation.
        -- Common cravings: carbs, sweets, salty or fatty foods due to serotonin and blood sugar changes.
        -- Peaks just before menstruation and fades within the first day of bleeding.
        -- Can be reduced by stable blood sugar or exercise in simulation.
        print("Setting Food Craving Effect to target - " .. tostring(target_value))

        -- Hunger moodle pops up at 0.15 to 0.25 severity
        -- Pop this moodle up as soon as Eaten food timer is below 3200
    end

    function EffectsPMS.setSadnessMoodle(player, stats, target_value, rate_multiplier)
        -- Mild sadness or mood dips commonly appear in the days leading up to menstruation.
        -- May involve lower energy, sensitivity, or tearfulness.
        -- Often starts 3–5 days before menstruation and resolves within 1–2 days of bleeding onset.
        -- Related to serotonin and estrogen drops.

        -- Depression moodle is an int from 0 - 100 where 100 is max sadness
        -- Moodles level up from 1-4 at these respective thresholds: 20, 40, 60, 80

        print("Pushing Sadness Moodle to target - " .. tostring(target_value))
        local bodyDamage = player:getBodyDamage()
        local currentUnhappynessLevel = bodyDamage:getUnhappynessLevel()
        local change_rate = 1  -- Adjust unhappiness by 1 per minute toward target

        -- Gradually move toward target value
        if currentUnhappynessLevel < target_value then
            -- Increase unhappiness toward target
            print("Increasing Unhappyness Level")
            bodyDamage:setUnhappynessLevel(math.min(100, currentUnhappynessLevel + change_rate))
        elseif currentUnhappynessLevel > target_value then
            -- Decrease unhappiness toward target
            print("Decreasing Unhappyness Level")
            bodyDamage:setUnhappynessLevel(math.max(0, currentUnhappynessLevel - change_rate))
        end
    end

    local function applyEnabledSymptomEffects(currentCycle, pms_severity, rate_multiplier)
        local player = getPlayer()
        if not player then return end

        local stats = player:getStats()

        local target_value = (pms_severity / 100) * currentCycle.healthEffectSeverity

        if currentCycle.pms_agitation then
            EffectsPMS.setAngerMoodle(player, stats, target_value, rate_multiplier)
        end
        if currentCycle.pms_cramps then
            EffectsPMS.setCrampsEffect(player, stats, target_value, rate_multiplier)
        end
        if currentCycle.pms_fatigue then
            EffectsPMS.setFatigueEffect(player, stats, target_value, rate_multiplier)
        end
        if currentCycle.pms_tenderBreasts then
            EffectsPMS.setTenderBreastsEffect(player, stats, target_value, rate_multiplier)
        end
        if currentCycle.pms_craveFood then
            EffectsPMS.setFoodCravingEffect(player, stats, target_value, rate_multiplier)
        end
        if currentCycle.pms_Sadness then
            -- Small buffer to make sure these are clear values before condition to run method stops running this
            -- as depression moodle does not decrement naturally
            if pms_severity <= 2 then
                modData.ICdata.pmsUnhappyAdded = nil
                modData.ICdata.pmsPreviousTarget = nil
                return
            end
            EffectsPMS.setSadnessMoodle(player, stats, target_value, rate_multiplier)
        end
    end

    function EffectsPMS.applyPMSEffectsMain()
        local pms_severity = CycleManager.getPMSseverity()
        if pms_severity < 0.1 then return end

        -- print("Applying PMS Effects with severity - " .. tostring(pms_severity))
        local currentCycle = modData.ICdata.currentCycle
        if not currentCycle then return end
        
        local rate_multiplier = 1 -- Placeholder for future use if needed
        applyEnabledSymptomEffects(currentCycle, pms_severity, rate_multiplier)

    end
    Events.EveryOneMinute.Add(EffectsPMS.applyPMSEffectsMain)

return EffectsPMS
