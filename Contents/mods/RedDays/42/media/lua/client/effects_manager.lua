EffectsManager = {}

local counter = 0
local pill_effect_active = false
local pill_recently_taken = false
local function takePillsStiffness()
    print("takePillsStiffness called, current counter: " .. counter)
	if counter < 36 then -- Pills are effective for 6 hours (36 * 10 = 360 minutes)
		counter = counter + 1
        print("Pills counter: " .. counter)
	else
		Events.EveryTenMinutes.Remove(takePillsStiffness) -- Pills are no longer effective
        pill_effect_active = false
        print("Pills effect has worn off after 6 hours.")
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
        print("Pills taken, stiffness effect will last for 6 hours.")
	end
	o_ISTakePillAction_perform(self)
end

local stat_Adjustment_isEnabled = false
local function stat_Adjustment(cycle)
    stat_Adjustment_isEnabled = true
    print("Stat adjustment is enabled, applying effects...")

    local player = getPlayer()
    local stats = player:getStats()
    local bodyDamage = player:getBodyDamage()
    local lowerTorso = bodyDamage:getBodyPart(BodyPartType.Torso_Lower)
    local groin = bodyDamage:getBodyPart(BodyPartType.Groin)

    groin:setBleeding(true)
    print("Pill Status: " .. tostring(pill_effect_active))
    print("Pill recently taken: " .. tostring(pill_recently_taken))
    if pill_effect_active then
        if pill_recently_taken then
            print("Groin Stiffness:" .. groin:getStiffness())
            print("Lower Torso Stiffness:" .. lowerTorso:getStiffness())
            if groin:getStiffness() > 22.5 then
                groin:setStiffness(22.5)
            end
            if lowerTorso:getStiffness() > 22.5 then
                lowerTorso:setStiffness(22.5)
            end
            pill_recently_taken = false
        end
        print("Pill effect is active, skipping stat adjustment. Just bleeding...")
        return
    end

    local current_groin_stiffness = groin:getStiffness()
    groin:setStiffness(math.max(0, current_groin_stiffness + 2))

    local current_lower_torso_stiffness = lowerTorso:getStiffness()
    lowerTorso:setStiffness(math.max(0, current_lower_torso_stiffness + 2))

    local current_fatigue = stats:getFatigue()
    stats:setFatigue(math.min(1, current_fatigue + 0.0001))

    local current_endurance = stats:getEndurance()
    stats:setEndurance(math.min(1, current_endurance - 0.0005))

    local current_discomfort = bodyDamage:getDiscomfortLevel()
    bodyDamage:setDiscomfortLevel(math.max(0, current_discomfort + 20))
    -- I couldn't find the discomfort stat gets and sets in the API docuementation, but I found it in this mod:
    -- Nepenthe's Slower Discomfort, Credit to Nepenthe for that
end

function EffectsManager.determineEffects(cycle)
    local current_phase = CycleManager.getCurrentCyclePhase(cycle)

    local player = getPlayer()
    local bodyDamage = player:getBodyDamage()
    local lowerTorso = bodyDamage:getBodyPart(BodyPartType.Torso_Lower)
    local groin = bodyDamage:getBodyPart(BodyPartType.Groin)

    local stats = player:getStats()


    if current_phase == "redPhase" then
        if not stat_Adjustment_isEnabled then
            print("Red phase and stat_Adjustment is not enabled, enabling it now.")
            Events.EveryOneMinute.Add(stat_Adjustment)
        end
    else
        if stat_Adjustment_isEnabled then
            print("Current phase is not redPhase and stat_Adjustment is enabled, disabling it.")
            Events.EveryOneMinute.Remove(stat_Adjustment)
        end
        stat_Adjustment_isEnabled = false
    end
end

return EffectsManager
