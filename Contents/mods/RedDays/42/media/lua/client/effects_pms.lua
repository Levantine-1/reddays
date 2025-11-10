EffectsPMS = {}

        -- pms_agitation = false, -- Set Anger moodle, boost endurance recovery
        -- pms_cramps = true, --  Set stiffness effects lower torso
        -- pms_fatigue = true, -- Set fatigue effects
        -- pms_tenderBreasts = false, --  set chest stiffness
        -- pms_craveFood = false, -- No need for moodle, just more hungry
        -- pms_Sadness = false -- Set Sadness moodle, reduce endurance recovery

    function EffectsPMS.setAngerMoodle(target)
        -- Anger or irritability tends to rise during the late luteal phase (about 1 week before period).
        -- Often linked to progesterone dominance and serotonin fluctuations.
        -- Peaks just before menstruation and resolves quickly once bleeding begins.
        -- Typically short-lived bursts of frustration or low patience.
        print("Setting Anger Moodle to target: " .. tostring(target))

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

    function EffectsPMS.setCrampsEffect(target)
        -- Begins a few hours before menstruation or with its onset due to uterine contractions (prostaglandins).
        -- Peaks during the first 1–2 days of bleeding, then fades by day 3.
        -- Intensity varies; typically moderate in healthy individuals.
        -- May cause mild lower back or thigh ache.
        print("Setting Cramps Effect to target: " .. tostring(target))
    end

    function EffectsPMS.setFatigueEffect(target)
        -- Fatigue builds gradually during the luteal phase (about 5–7 days pre-period).
        -- Peaks right before or at the start of menstruation due to hormonal shifts and poor sleep quality.
        -- Resolves around day 2–3 of the period.
        -- May mildly return mid-cycle if ovulation symptoms are tracked, but less intense.
        print("Setting Fatigue Effect to target: " .. tostring(target))
    end

    function EffectsPMS.setTenderBreastsEffect(target)
        -- Typically begins 3–5 days before menstruation due to rising progesterone levels.
        -- Peaks right before the period starts, then subsides by about day 2–3 of menstruation.
        -- Intensity ranges from mild tenderness to noticeable soreness when touched.
        -- Often correlates with hormonal water retention.
        print("Setting Tender Breasts Effect to target: " .. tostring(target))
    end

    function EffectsPMS.setFoodCravingEffect(target)
        -- Starts about 5–7 days before menstruation.
        -- Common cravings: carbs, sweets, salty or fatty foods due to serotonin and blood sugar changes.
        -- Peaks just before menstruation and fades within the first day of bleeding.
        -- Can be reduced by stable blood sugar or exercise in simulation.
        print("Setting Food Craving Effect to target: " .. tostring(target))
    end

    function EffectsPMS.setSadnessMoodle(target)
        -- Mild sadness or mood dips commonly appear in the days leading up to menstruation.
        -- May involve lower energy, sensitivity, or tearfulness.
        -- Often starts 3–5 days before menstruation and resolves within 1–2 days of bleeding onset.
        -- Related to serotonin and estrogen drops.
        print("Setting Sadness Moodle to target: " .. tostring(target))
    end

    function EffectsPMS.applyPMSEffects()
        local pms_severity = CycleManager.getPMSseverity()
        if pms_severity < 0.1 then
            print("Not PMSing")
            return
        end
        print("Applying PMS Effects with severity - " .. tostring(pms_severity))
    end
    Events.EveryOneMinute.Add(EffectsPMS.applyPMSEffects)

return EffectsPMS