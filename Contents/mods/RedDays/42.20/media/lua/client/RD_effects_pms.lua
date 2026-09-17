RD_EffectsPMS = RD_EffectsPMS or {}
RDEffectsPMS = RD_EffectsPMS -- Alias for backward compatibility
require "RD_game_api"

-- FullType -> percent PMS reduction (doubled from the original design values per user request).
-- Sourced from vanilla item scripts (media/scripts/generated/items/{food,normal}.txt) -- note the
-- mod's real names differ from common usage: Yoghurt (not Yogurt), no "Bowl of Oatmeal"/"Chocolate2"/"PeanutButter2".
local FOOD_PMS_REDUCTIONS = {
    ["Base.Milk"] = 10, ["Base.MilkBottle"] = 10, ["Base.Milk_Personalsized"] = 10,  -- drunk, not eaten -- see ISDrinkFluidAction hook
    ["Base.Yoghurt"] = 10,
    ["Base.Cheese"] = 8, ["Base.Processedcheese"] = 8,
    ["Base.Oatmeal"] = 6,
    ["Base.PeanutButter"] = 4,
    ["Base.Peanuts"] = 4,
    ["Base.Banana"] = 4,

    -- Chocolate-flavored (10%, same tier as plain Chocolate). Raw/dough/prep variants
    -- (CakeRaw, CakePrep, *Dough, PieWholeRaw*, Muffintray_Biscuit) aren't eaten as-is, so they're
    -- excluded on purpose.
    ["Base.Chocolate"] = 10,
    ["Base.CakeChocolate"] = 10, ["Base.CakeBlackForest"] = 10,  -- black forest = chocolate + cherry
    ["Base.CookieChocolateChip"] = 10, ["Base.CookiesChocolate"] = 10,
    ["Base.DoughnutChocolate"] = 10, ["Base.ChocolateChips"] = 10,
    ["Base.ChocolateCoveredCoffeeBeans"] = 10,
    ["Base.Chocolate_Butterchunkers"] = 10, ["Base.Chocolate_Candy"] = 10,
    ["Base.Chocolate_Crackle"] = 10, ["Base.Chocolate_Deux"] = 10,
    ["Base.Chocolate_GalacticDairy"] = 10, ["Base.Chocolate_HeartBox"] = 10,
    ["Base.Chocolate_RoysPBPucks"] = 10, ["Base.Chocolate_Smirkers"] = 10,
    ["Base.Chocolate_SnikSnak"] = 10, ["Base.FudgeePop"] = 10, ["Base.FudgeePop_Melted"] = 10,

    -- Other sweets/desserts (6%, same tier as Oatmeal -- comfort food, less indulgent than chocolate).
    ["Base.CakeCarrot"] = 6, ["Base.CakeCheeseCake"] = 6, ["Base.CakeRedVelvet"] = 6,
    ["Base.CakeSlice"] = 6, ["Base.CakeStrawberryShortcake"] = 6,
    ["Base.CookieJelly"] = 6, ["Base.CookiesOatmeal"] = 6, ["Base.CookiesShortbread"] = 6,
    ["Base.CookiesSugar"] = 6,
    ["Base.DoughnutFrosted"] = 6, ["Base.DoughnutJelly"] = 6, ["Base.DoughnutPlain"] = 6,
    ["Base.MuffinFruit"] = 6, ["Base.MuffinGeneric"] = 6,
    ["Base.Pie"] = 6, ["Base.PieApple"] = 6, ["Base.PieBlueberry"] = 6, ["Base.PieKeyLime"] = 6,
    ["Base.PieLemonMeringue"] = 6, ["Base.PiePumpkin"] = 6,
    ["Base.CandyCaramels"] = 6, ["Base.CandyGummyfish"] = 6, ["Base.CandyMolasses"] = 6,
    ["Base.CandyNovapops"] = 6, ["Base.Candycane"] = 6, ["Base.CandyCorn"] = 6,
    ["Base.CandyFruitSlices"] = 6, ["Base.CandyPackage"] = 6,
    ["Base.Icecream"] = 6, ["Base.IcecreamMelted"] = 6,
    ["Base.IcecreamSandwich"] = 6, ["Base.IcecreamSandwich_Melted"] = 6,
    ["Base.Marshmallows"] = 6,
}
local FISH_TAG_REDUCTION_PCT = 4  -- fish items are inconsistent on FoodType but consistently tagged base:fishmeat

-- Returns the PMS-reduction percent for one full type, or 0 if it doesn't qualify.
--
-- Evolved-recipe ingredient lists (getExtraItems / getSpices) hold full-type STRINGS, not
-- items -- confirmed via bytecode: both return ArrayList<String>. Tags are checked with the
-- global hasItemTag(String, ItemTag), the same idiom vanilla uses on these exact elements
-- (ISAddItemInRecipe.lua). This one path serves both the eaten item and its ingredients.
local function getFoodPMSReductionForType(fullType)
    if type(fullType) ~= "string" or fullType == "" then return 0 end
    -- Tolerate an unqualified name, so the table lookup doesn't depend on which form
    -- the engine stored.
    if not string.find(fullType, ".", 1, true) then fullType = "Base." .. fullType end
    if FOOD_PMS_REDUCTIONS[fullType] then return FOOD_PMS_REDUCTIONS[fullType] end
    -- The tag must be an ItemTag object -- a raw string throws "No implementation found".
    if hasItemTag(fullType, ItemTag.FISH_MEAT) then return FISH_TAG_REDUCTION_PCT end
    return 0
end

-- Sums the eaten item's own reduction plus every qualifying ingredient folded into it via the
-- evolved-recipe system (stew/soup/pizza/etc.), so a home-cooked meal gets credit for its
-- matching ingredients even though the meal's own FullType is a fixed Base.PotOfStew/etc.
-- Bowls served from a pot inherit the same lists (InheritFood -> Food.copyExtraItems).
local function getTotalFoodPMSReduction(item)
    if not item then return 0 end
    local total = getFoodPMSReductionForType(item:getFullType())
    if instanceof(item, "Food") and item:haveExtraItems() then
        local extras = item:getExtraItems()
        if extras then
            for i = 0, extras:size() - 1 do
                total = total + getFoodPMSReductionForType(extras:get(i))
            end
        end
        local spices = item:getSpices()
        if spices then
            for i = 0, spices:size() - 1 do
                total = total + getFoodPMSReductionForType(spices:get(i))
            end
        end
    end
    return total
end

-- In MP the server owns character stats: a client's direct stats:set() is reverted (proven in
-- game by rd.mptest's stat check). The stat effects below still apply locally for instant
-- feedback, and also record the same STEP in `pending`, which applyEnabledSymptomEffects sends
-- once per tick to Commands.applyPMSStats. Steps rather than final values, because the server
-- keeps changing these stats itself and a value computed from the client's copy would clobber that.
local function addPending(pending, field, delta)
    if pending then pending[field] = (pending[field] or 0) + delta end
end

function RD_EffectsPMS.setAngerMoodle(stats, target_value, rate_multiplier, pending)
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

        if pending then
            pending.angerTarget = severity
            pending.angerStep = angerLevel_change_rate
        end
        addPending(pending, "enduranceDelta", endurance_change_rate)
end

function RD_EffectsPMS.setCrampsEffect(stats, target_value, rate_multiplier)
        -- Begins a few hours before menstruation or with its onset due to uterine contractions (prostaglandins).
        -- Peaks during the first 1–2 days of bleeding, then fades by day 3.
        -- Intensity varies; typically moderate in healthy individuals.
        -- May cause mild lower back or thigh ache.
        local change_rate = 2 * rate_multiplier

        local lowerTorso = RD_zapi.getBodyPart(BodyPartType.Torso_Lower)
        local groin = RD_zapi.getBodyPart(BodyPartType.Groin)

        local new_lower = lowerTorso:getStiffness()
        if new_lower < target_value then
            new_lower = math.max(0, new_lower + change_rate)
        end

        local new_groin = groin:getStiffness()
        if new_groin < target_value then
            new_groin = math.max(0, new_groin + change_rate)
        end

        if isClient() then
            sendClientCommand(getPlayer(), 'RedDays', 'applyBodyStiffness', { Torso_Lower = new_lower, Groin = new_groin })
        else
            lowerTorso:setStiffness(new_lower)
            groin:setStiffness(new_groin)
        end
end

function RD_EffectsPMS.setFatigueEffect(stats, target_value, rate_multiplier, pending)
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

        addPending(pending, "fatigueDelta", fatigue_change_rate)
        addPending(pending, "enduranceDelta", -endurance_change_rate)
end

function RD_EffectsPMS.setTenderBreastsEffect(stats, target_value, rate_multiplier, alsoHasCramps)
        -- Typically begins 3–5 days before menstruation due to rising progesterone levels.
        -- Peaks right before the period starts, then subsides by about day 2–3 of menstruation.
        -- Intensity ranges from mild tenderness to noticeable soreness when touched.
        -- Often correlates with hormonal water retention.

        if alsoHasCramps then
            target_value = target_value * 0.5 -- Reduce breast tenderness severity by 50% if cramps are also active as too much pain is unrealistic
        end

        local change_rate = 2 * rate_multiplier

        local upperTorso = RD_zapi.getBodyPart(BodyPartType.Torso_Upper)

        local new_upper = upperTorso:getStiffness()
        if new_upper < target_value then
            new_upper = math.max(0, new_upper + change_rate)
        end

        if isClient() then
            sendClientCommand(getPlayer(), 'RedDays', 'applyBodyStiffness', { Torso_Upper = new_upper })
        else
            upperTorso:setStiffness(new_upper)
        end
end

local setFoodCravingEffect_lastHunger = 0
    local setFoodCravingEffect_jumpedToHungry = false
    function RD_EffectsPMS.setFoodCravingEffect(stats, target_value, rate_multiplier, pending)
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
            if pending then pending.hungerFloor = 0.16 end
        end
        setFoodCravingEffect_lastHunger = currentHunger
end

function RD_EffectsPMS.setSadnessMoodle(stats, target_value, rate_multiplier, pending)
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

        -- Sent even when the client is already at the target: the server's copy may not be.
        if pending then
            pending.unhappinessTarget = target_value
            pending.unhappinessStep = change_rate
        end
end

local function clearStiffness(currentCycle)
        local resetValue = 22.5
        local updates = {}
    local hasUpdates = false

        if currentCycle.pms_cramps then
            local groin = RD_zapi.getBodyPart(BodyPartType.Groin)
            local lowerTorso = RD_zapi.getBodyPart(BodyPartType.Torso_Lower)

            local new_groin = groin:getStiffness() > resetValue and resetValue or groin:getStiffness()
            local new_lower = lowerTorso:getStiffness() > resetValue and resetValue or lowerTorso:getStiffness()

            if isClient() then
                updates.Groin = new_groin
                updates.Torso_Lower = new_lower
                hasUpdates = true
            else
                groin:setStiffness(new_groin)
                lowerTorso:setStiffness(new_lower)
            end
        end

        if currentCycle.pms_tenderBreasts then
            local upperTorso = RD_zapi.getBodyPart(BodyPartType.Torso_Upper)

            local new_upper = upperTorso:getStiffness() > resetValue and resetValue or upperTorso:getStiffness()

            if isClient() then
                updates.Torso_Upper = new_upper
                hasUpdates = true
            else
                upperTorso:setStiffness(new_upper)
            end
        end

        if isClient() and hasUpdates then
            sendClientCommand(getPlayer(), 'RedDays', 'applyBodyStiffness', updates)
        end

        RD_modData.ICdata.pill_recently_taken = false
end

local function applyEnabledSymptomEffects(currentCycle, pms_severity, rate_multiplier)
        local player = RD_zapi.getPlayer()
        if not player then return end

        local stats = player:getStats()

        local target_value = (pms_severity / 100) * currentCycle.healthEffectSeverity

        if RD_modData.ICdata.pill_recently_taken then
            clearStiffness(currentCycle)
        end

        if RD_modData.ICdata.pill_effect_active then
            local pillReductionPct = SandboxVars.RedDays.painkillerEffectReductionPct or 50
            target_value = target_value * (1 - (pillReductionPct / 100))
        end

        if (RD_modData.ICdata.food_pms_reduction_pct or 0) > 0 then
            target_value = target_value * (1 - (RD_modData.ICdata.food_pms_reduction_pct / 100))
        end

        local pending = {}
        if currentCycle.pms_agitation then
            RD_EffectsPMS.setAngerMoodle(stats, target_value, rate_multiplier, pending)
        end
        if currentCycle.pms_cramps then
            RD_EffectsPMS.setCrampsEffect(stats, target_value, rate_multiplier)
        end
        if currentCycle.pms_fatigue then
            RD_EffectsPMS.setFatigueEffect(stats, target_value, rate_multiplier, pending)
        end
        if currentCycle.pms_tenderBreasts then
            RD_EffectsPMS.setTenderBreastsEffect(stats, target_value, rate_multiplier, currentCycle.pms_cramps)
        end
        if currentCycle.pms_craveFood then
            RD_EffectsPMS.setFoodCravingEffect(stats, target_value, rate_multiplier, pending)
        end
        if currentCycle.pms_Sadness then
            RD_EffectsPMS.setSadnessMoodle(stats, target_value, rate_multiplier, pending)
        end

        -- One command per tick for all stat effects; stiffness keeps applyBodyStiffness.
        -- Kahlua has no next(), so test for an empty table with pairs().
        if isClient() then
            local hasAny = false
            for _ in pairs(pending) do
                hasAny = true
                break
            end
            if hasAny then
                sendClientCommand(player, 'RedDays', 'applyPMSStats', pending)
            end
        end
end

local pill_effect_counter_max = SandboxVars.RedDays.painkillerEffectDuration or 36
local function takePillsStiffness()
    if not RD_modData.ICdata.pill_effect_active then
        -- Self-heals an orphaned duplicate registration (see ISTakePillAction_perform below)
        -- or a save already affected by that bug -- unregister THIS copy and stop.
        Events.EveryTenMinutes.Remove(takePillsStiffness)
        return
    end
    if RD_modData.ICdata.pill_effect_counter < pill_effect_counter_max then
        RD_modData.ICdata.pill_effect_counter = RD_modData.ICdata.pill_effect_counter + 1
    else
        RD_zapi.log("PMS Painkiller Effect Ended")
        Events.EveryTenMinutes.Remove(takePillsStiffness)
        RD_modData.ICdata.pill_effect_active = false
        RD_modData.ICdata.pill_effect_counter = 0
        return
    end
end

function RD_EffectsPMS.ISTakePillAction_perform(self)
    if not self.item then return end
    local fullType = self.item:getFullType()

    if fullType == "Base.Pills" then
        RD_zapi.log("Painkillers Taken, Reducing PMS Symptoms")
        RD_modData.ICdata.pill_recently_taken = true
        local wasActive = RD_modData.ICdata.pill_effect_active
        RD_modData.ICdata.pill_effect_active = true
        RD_modData.ICdata.pill_effect_counter = 0
        if not wasActive then
            -- Events.Add never dedupes (confirmed via bytecode: plain ArrayList.add with no
            -- contains() check) -- registering again while already active would double the
            -- countdown speed and orphan a copy in the handler list forever after expiry.
            Events.EveryTenMinutes.Add(takePillsStiffness)
        end
    end

end

local food_effect_counter_max = SandboxVars.RedDays.foodPMSEffectDuration or 36
local function takeFoodPMSCountdown()
    if not RD_modData.ICdata.food_pms_effect_active then
        -- Self-heals an orphaned duplicate registration (see registerFoodPMSEffect below) or
        -- a save already affected by that bug -- unregister THIS copy and stop.
        Events.EveryTenMinutes.Remove(takeFoodPMSCountdown)
        return
    end
    if RD_modData.ICdata.food_pms_effect_counter < food_effect_counter_max then
        RD_modData.ICdata.food_pms_effect_counter = RD_modData.ICdata.food_pms_effect_counter + 1
    else
        RD_zapi.log("PMS Food Effect Ended")
        Events.EveryTenMinutes.Remove(takeFoodPMSCountdown)
        RD_modData.ICdata.food_pms_effect_active = false
        RD_modData.ICdata.food_pms_effect_counter = 0
        RD_modData.ICdata.food_pms_reduction_pct = 0
        return
    end
end

-- Called whenever a food or drink item finishes being consumed. Tops up the shared food-PMS
-- reduction (capped) and resets the shared countdown to full duration -- same reset-on-redose
-- behavior as taking another painkiller, just tracking a variable magnitude instead of a fixed one.
function RD_EffectsPMS.registerFoodPMSEffect(item)
    local reduction = getTotalFoodPMSReduction(item)
    if reduction <= 0 then return end

    local cap = SandboxVars.RedDays.foodPMSReductionCapPct or 20
    local newTotal = math.min(cap, (RD_modData.ICdata.food_pms_reduction_pct or 0) + reduction)
    local wasActive = RD_modData.ICdata.food_pms_effect_active

    RD_zapi.log("PMS-reducing food eaten (+" .. reduction .. "%, total " .. newTotal .. "%)")
    RD_modData.ICdata.food_pms_reduction_pct = newTotal
    RD_modData.ICdata.food_pms_effect_active = true
    RD_modData.ICdata.food_pms_effect_counter = 0  -- reset, exactly like re-taking a pill
    if not wasActive then
        -- Events.Add never dedupes (confirmed via bytecode: plain ArrayList.add with no
        -- contains() check) -- registering again while already active would double the
        -- countdown speed and orphan a copy in the handler list forever after expiry.
        Events.EveryTenMinutes.Add(takeFoodPMSCountdown)
    end
end

-- Called from the perform() hooks in RD_main.lua -- complete() never runs client-side in MP.
function RD_EffectsPMS.ISEatFoodAction_perform(self)
    if not self.item then return end
    RD_EffectsPMS.registerFoodPMSEffect(self.item)
end

function RD_EffectsPMS.ISDrinkFluidAction_perform(self)
    if not self.item then return end
    RD_EffectsPMS.registerFoodPMSEffect(self.item)
end

function RD_EffectsPMS.LoadPlayerData()
    RD_modData.ICdata.pill_recently_taken = RD_modData.ICdata.pill_recently_taken or false
    RD_modData.ICdata.pill_effect_counter = RD_modData.ICdata.pill_effect_counter or 0
    RD_modData.ICdata.pill_effect_active = RD_modData.ICdata.pill_effect_active or false
    if RD_modData.ICdata.pill_effect_active then
        Events.EveryTenMinutes.Add(takePillsStiffness)
    end

    RD_modData.ICdata.food_pms_reduction_pct = RD_modData.ICdata.food_pms_reduction_pct or 0
    RD_modData.ICdata.food_pms_effect_counter = RD_modData.ICdata.food_pms_effect_counter or 0
    RD_modData.ICdata.food_pms_effect_active = RD_modData.ICdata.food_pms_effect_active or false
    if RD_modData.ICdata.food_pms_effect_active then
        Events.EveryTenMinutes.Add(takeFoodPMSCountdown)
    end
end

function RD_EffectsPMS.applyPMSEffectsMain()
    local pms_severity = RD_CycleManager.getPMSseverity()
    if pms_severity < 0.1 then return end
    local currentCycle = RD_modData.ICdata.currentCycle
    if not currentCycle then return end
    if not currentCycle.healthEffectSeverity then return end
    
    local rate_multiplier = 1
    applyEnabledSymptomEffects(currentCycle, pms_severity, rate_multiplier)
end
return RD_EffectsPMS
