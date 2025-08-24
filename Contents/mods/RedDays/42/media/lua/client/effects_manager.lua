require "RedDays/hygiene_manager"

EffectsManager = {}

local pill_effect_counter_max = SandboxVars.RedDays.painkillerEffectDuration or 36
local pill_recently_taken = false
local function takePillsStiffness()
    print("Current pill effect counter: " .. pill_effect_counter)
	if pill_effect_counter < pill_effect_counter_max then -- Pills are effective for 6 hours (36 * 10 = 360 minutes)
		print("Incrementing pill effect counter")
        pill_effect_counter = pill_effect_counter + 1
        modData.ICdata.pill_effect_counter = pill_effect_counter -- Saving the counter here is fine because it only saves every 10 minutes``
	else
		Events.EveryTenMinutes.Remove(takePillsStiffness) -- Pills are no longer effective
        pill_effect_active = false
        modData.ICdata.pill_effect_active = pill_effect_active -- Save the pill effect state
        pill_effect_counter = 0
        modData.ICdata.pill_effect_counter = pill_effect_counter -- Reset the counter
        print("Painkiller effect has worn off.")
		return
	end
end

-- takePillsStiffness and o_o_ISTakePillAction_perform is originally from [B42] Painkillers Remove Arm Muscle Strain created by lect 
-- Slightly modified to fit the RedDays mod
local o_ISTakePillAction_perform = ISTakePillAction.perform
function ISTakePillAction:perform()
	if self.item:getFullType() == "Base.Pills" then
		counter = 0
        pill_effect_active = true
        modData.ICdata.pill_effect_active = pill_effect_active -- Save the pill effect state
        pill_recently_taken = true
		Events.EveryTenMinutes.Add(takePillsStiffness)
        print("Just took a pill, painkiller effect is now active.")
	end
	o_ISTakePillAction_perform(self)
end

local stat_Adjustment_isEnabled = false
local function stat_Adjustment()
    local player = getPlayer()

    stat_Adjustment_isEnabled = true

    local stats = player:getStats()
    local bodyDamage = player:getBodyDamage()
    local lowerTorso = bodyDamage:getBodyPart(BodyPartType.Torso_Lower)
    local groin = bodyDamage:getBodyPart(BodyPartType.Groin)

    local cycle = modData.ICdata.currentCycle -- The event system calls the function with no arguments, so cycle is nil, so that's why it's set here

    if not HygieneManager:consumeHygieneProduct() then
        groin:setBleeding(true)
    end

    if pill_effect_active then
        if pill_recently_taken then
            if groin:getStiffness() > 22.5 then
                groin:setStiffness(22.5)
            end
            if lowerTorso:getStiffness() > 22.5 then
                lowerTorso:setStiffness(22.5)
            end
            pill_recently_taken = false
        end
        return
    end

    local current_groin_stiffness = groin:getStiffness()
    if current_groin_stiffness < cycle.stiffness_target then
        groin:setStiffness(math.max(0, current_groin_stiffness + cycle.stiffness_increment))
    end
    
    local current_lower_torso_stiffness = lowerTorso:getStiffness()
    if current_lower_torso_stiffness < cycle.stiffness_target then
        lowerTorso:setStiffness(math.max(0, current_lower_torso_stiffness + cycle.stiffness_increment))
    end

    local current_fatigue = stats:getFatigue()
    stats:setFatigue(math.min(1, current_fatigue + cycle.fatigue_increment))

    local current_endurance = stats:getEndurance()
    stats:setEndurance(math.min(1, current_endurance - cycle.endurance_decrement))

    local current_discomfort = bodyDamage:getDiscomfortLevel()
    bodyDamage:setDiscomfortLevel(math.max(0, current_discomfort + 20))
    -- I couldn't find the discomfort stat gets and sets in the API docuementation, but I found it in this mod:
    -- Nepenthe's Slower Discomfort, Credit to Nepenthe for that
end

local consumingDischargeItem = false
local function consumeDischargeProduct()
    consumingDischargeItem = true
    return HygieneManager:consumeDischargeProduct()
end

local function stopGroinBleeding()
    local player = getPlayer()
    local bodyDamage = player:getBodyDamage()
    local groin = bodyDamage:getBodyPart(BodyPartType.Groin)
    local bleedingTime = groin:getBleedingTime()
    if bleedingTime == 0 then -- Clear bleeding if no wounds. Cycle generates bleeding time of 0, so assumed no wounds.
        groin:setBleeding(false)
    end
end

function EffectsManager.determineEffects(cycle)
    if not SandboxVars.RedDays.affectsAllGenders then
        local player = getPlayer()
        if not player:isFemale() then
            if stat_Adjustment_isEnabled then
                Events.EveryOneMinute.Remove(stat_Adjustment)
                print("Disabling stat adjustment for non female player")
            end
            return
        end
    end

    local current_phase = CycleManager.getCurrentCyclePhase(cycle)

    if current_phase == "redPhase" then
        if not stat_Adjustment_isEnabled then
            print("Red phase has begun, applying debuffs")
            Events.EveryOneMinute.Add(stat_Adjustment)
        end
        if consumingDischargeItem then
            print("Stopping to consume hygiene product for discharge")
            Events.EveryDays.Remove(consumeDischargeProduct)
            consumingDischargeItem = false
        end
    else
        if stat_Adjustment_isEnabled then
            Events.EveryOneMinute.Remove(stat_Adjustment)
            print("Red phase has ended, removing debuffs")
            stopGroinBleeding() -- Stop bleeding if it was caused by the red phase
        end
        stat_Adjustment_isEnabled = false

        if not consumingDischargeItem then
            print("Starting to consume hygiene product for discharge")
            Events.EveryDays.Add(consumeDischargeProduct)
            consumingDischargeItem = true
        end
    end
end

local function LoadPlayerData()
    local player = getPlayer()
    modData = player:getModData()
    modData.ICdata = modData.ICdata or {}
    pill_effect_counter = modData.ICdata.pill_effect_counter or 0
    pill_effect_active = modData.ICdata.pill_effect_active or false
    if pill_effect_active then
        Events.EveryTenMinutes.Add(takePillsStiffness) -- Start the timer if the effect is active
    end
end
Events.OnGameStart.Add(LoadPlayerData)

-- NOTE: 2025-07-24 Disabled because this gets run on every load which means you always start on the first day of the cycle.
-- function EffectsManager.resetEffects()
--     local player = getPlayer()
--     modData = player:getModData()
--     modData.ICdata = modData.ICdata or {}
--     stat_Adjustment_isEnabled = false
--     modData.ICdata.pill_effect_counter = 0
--     modData.ICdata.pill_effect_active = false
--     Events.EveryDays.Remove(consumeDischargeProduct)
--     Events.EveryOneMinute.Remove(stat_Adjustment)
--     Events.EveryTenMinutes.Remove(takePillsStiffness)
-- end

return EffectsManager
