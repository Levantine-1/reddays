EffectsPMS = {}

        -- pms_agitation = false, -- Set Anger moodle, boost endurance recovery
        -- pms_cramps = true, --  Set stiffness effects lower torso
        -- pms_fatigue = true, -- Set fatigue effects
        -- pms_tenderBreasts = false, --  set chest stiffness
        -- pms_craveFood = false, -- No need for moodle, just more hungry
        -- pms_Sadness = false -- Set Sadness moodle, reduce endurance recovery

    function EffectsPMS.setAngerMoodle(target_value, increment_multiplier)
        -- Anger or irritability tends to rise during the late luteal phase (about 1 week before period).
        -- Often linked to progesterone dominance and serotonin fluctuations.
        -- Peaks just before menstruation and resolves quickly once bleeding begins.
        -- Typically short-lived bursts of frustration or low patience.
        print("Setting Anger Moodle to target - " .. tostring(target_value))

        local player = getPlayer()
        if not player then
            print("No player found for setting Anger Moodle")
            return
        end
        local stats = player:getStats()
        local angerLevel = stats:getAnger()
        print("Current Anger Level - " .. tostring(angerLevel))

        local randomInt = ZombRand(1, 100)
        local randomFloat = randomInt / 100

        print("Setting Random Float for Anger Moodle - " .. tostring(randomFloat))
        stats:setAnger(randomFloat)
        print("New Anger Level - " .. tostring(stats:getAnger()))
    end

    function EffectsPMS.setCrampsEffect(target_value, increment_multiplier)
        -- Begins a few hours before menstruation or with its onset due to uterine contractions (prostaglandins).
        -- Peaks during the first 1–2 days of bleeding, then fades by day 3.
        -- Intensity varies; typically moderate in healthy individuals.
        -- May cause mild lower back or thigh ache.
        print("Setting Cramps Effect to target - " .. tostring(target_value))
    end

    function EffectsPMS.setFatigueEffect(target_value, increment_multiplier)
        -- Fatigue builds gradually during the luteal phase (about 5–7 days pre-period).
        -- Peaks right before or at the start of menstruation due to hormonal shifts and poor sleep quality.
        -- Resolves around day 2–3 of the period.
        -- May mildly return mid-cycle if ovulation symptoms are tracked, but less intense.
        print("Setting Fatigue Effect to target - " .. tostring(target_value))
    end

    function EffectsPMS.setTenderBreastsEffect(target_value, increment_multiplier)
        -- Typically begins 3–5 days before menstruation due to rising progesterone levels.
        -- Peaks right before the period starts, then subsides by about day 2–3 of menstruation.
        -- Intensity ranges from mild tenderness to noticeable soreness when touched.
        -- Often correlates with hormonal water retention.
        print("Setting Tender Breasts Effect to target - " .. tostring(target_value))
    end

    function EffectsPMS.setFoodCravingEffect(target_value, increment_multiplier)
        -- Starts about 5–7 days before menstruation.
        -- Common cravings: carbs, sweets, salty or fatty foods due to serotonin and blood sugar changes.
        -- Peaks just before menstruation and fades within the first day of bleeding.
        -- Can be reduced by stable blood sugar or exercise in simulation.
        print("Setting Food Craving Effect to target - " .. tostring(target_value))

        -- Hunger moodle pops up at 0.15 to 0.25 severity
        -- Pop this moodle up as soon as Eaten food timer is below 3200
    end

    function EffectsPMS.setSadnessMoodle(target_value, increment_multiplier)
        -- Mild sadness or mood dips commonly appear in the days leading up to menstruation.
        -- May involve lower energy, sensitivity, or tearfulness.
        -- Often starts 3–5 days before menstruation and resolves within 1–2 days of bleeding onset.
        -- Related to serotonin and estrogen drops.
        print("Setting Sadness Moodle to target - " .. tostring(target_value))

        -- Level 1 mooodle at 20
        -- Level 2 moodle at 40
        -- Level 3 moodle at 60
        -- Level 4 moodle at 80
    end

    function EffectsPMS.applyPMSEffects()
        local pms_severity = CycleManager.getPMSseverity()
        if pms_severity < 0.1 then
            print("Not PMSing")
            return
        end
        print("Applying PMS Effects with severity - " .. tostring(pms_severity))
        local currentCycle = modData.ICdata.currentCycle
        if not currentCycle then return 0 end

        if currentCycle.pms_agitation then
            EffectsPMS.setAngerMoodle(pms_severity, 1)
        end
        if currentCycle.pms_cramps then
            EffectsPMS.setCrampsEffect(pms_severity, 1)
        end
        if currentCycle.pms_fatigue then
            EffectsPMS.setFatigueEffect(pms_severity, 1)
        end
        if currentCycle.pms_tenderBreasts then
            EffectsPMS.setTenderBreastsEffect(pms_severity, 1)
        end
        if currentCycle.pms_craveFood then
            EffectsPMS.setFoodCravingEffect(pms_severity, 1)
        end
        if currentCycle.pms_Sadness then
            EffectsPMS.setSadnessMoodle(pms_severity, 1)
        end

    end
    Events.EveryOneMinute.Add(EffectsPMS.applyPMSEffects)

return EffectsPMS