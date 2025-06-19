EffectsManager = {}

local counter = 0
local pill_effect_active = false
local pill_recently_taken = false
local function takePillsStiffness()
    -- print("takePillsStiffness called, current counter: " .. counter)
	if counter < 36 then -- Pills are effective for 6 hours (36 * 10 = 360 minutes)
		counter = counter + 1
        -- print("Pills counter: " .. counter)
	else
		Events.EveryTenMinutes.Remove(takePillsStiffness) -- Pills are no longer effective
        pill_effect_active = false
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
        pill_recently_taken = true
		Events.EveryTenMinutes.Add(takePillsStiffness)
        print("Just took a pill, painkiller effect is now active.")
	end
	o_ISTakePillAction_perform(self)
end

local stat_Adjustment_isEnabled = false
local function stat_Adjustment()
    local player = getPlayer()

    if not player:isFemale() then
        -- todo: add sandbox option to enable the mod for all players if desired
        print("Player is not female, skipping stat adjustment.")
        return
    end
    stat_Adjustment_isEnabled = true

    local stats = player:getStats()
    local bodyDamage = player:getBodyDamage()
    local lowerTorso = bodyDamage:getBodyPart(BodyPartType.Torso_Lower)
    local groin = bodyDamage:getBodyPart(BodyPartType.Groin)

    local cycle = modData.ICdata.currentCycle -- The event system calls the function with no arguments, so cycle is nil, so that's why it's set here

    groin:setBleeding(true)
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

function EffectsManager.determineEffects(cycle)
    local player = getPlayer()
    if not player:isFemale() then
        -- Todo: Add a sandbox option to enable the mod for non female players
        if stat_Adjustment_isEnabled then
            Events.EveryOneMinute.Remove(stat_Adjustment)
            print("Disabling stat adjustment for non female player")
        end
        print("YOU ARE NOT A WOMAN!")
        return
    end

    local current_phase = CycleManager.getCurrentCyclePhase(cycle)

    if current_phase == "redPhase" then
        if not stat_Adjustment_isEnabled then
            print("Red phase has begun, applying debuffs")
            Events.EveryOneMinute.Add(stat_Adjustment)
        end
    else
        if stat_Adjustment_isEnabled then
            Events.EveryOneMinute.Remove(stat_Adjustment)
            print("Red phase has ended, removing debuffs")
        end
        stat_Adjustment_isEnabled = false
    end
end

function EffectsManager.resetEffects()
    stat_Adjustment_isEnabled = false
end

return EffectsManager
