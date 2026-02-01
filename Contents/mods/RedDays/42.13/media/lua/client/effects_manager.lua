require "hygiene_manager"
require "moodles"
require "game_api"

EffectsManager = {}

local stat_Adjustment_isEnabled = false
local function stat_Adjustment()
    stat_Adjustment_isEnabled = true
    local cycle = modData.ICdata.currentCycle -- The event system calls the function with no arguments, so cycle is nil, so that's why it's set here

    if HygieneManager:consumeHygieneProduct() then
        modData.ICdata.LeakSwitchState = false
    elseif not HygieneManager:consumeHygieneProduct() then
        modData.ICdata.LeakSwitchState = true
    end

    -- local current_discomfort = bodyDamage:getDiscomfortLevel()
    -- local discomfort_target = cycle.discomfort_target
    -- if current_discomfort < discomfort_target then
    --     bodyDamage:setDiscomfortLevel(math.max(0, current_discomfort + 35))
    -- end
    -- I couldn't find the discomfort stat gets and sets in the API docuementation, but I found it in this mod:
    -- Nepenthe's Slower Discomfort, Credit to Nepenthe for that
end

local consumingDischargeItem = false
local function consumeDischargeProduct()
    consumingDischargeItem = true
    return HygieneManager:consumeDischargeProduct()
end

local function stopGroinBleeding()
    local groin = zapi.getBodyPart(BodyPartType.Groin)
    local bleedingTime = groin:getBleedingTime()
    if bleedingTime == 0 then -- Clear bleeding if no wounds. Cycle generates bleeding time of 0, so assumed no wounds.
        -- groin:setBleeding(false)
        modData.ICdata.LeakSwitchState = false
    end
end

function EffectsManager.determineEffects(cycle)
    local current_phase = CycleManager.getCurrentCyclePhase(cycle)

    if current_phase == "redPhase" then
        if not stat_Adjustment_isEnabled then
            Events.EveryOneMinute.Add(stat_Adjustment)
        end
        if consumingDischargeItem then
            Events.EveryDays.Remove(consumeDischargeProduct)
            consumingDischargeItem = false
        end
    else
        if stat_Adjustment_isEnabled then
            Events.EveryOneMinute.Remove(stat_Adjustment)
            stopGroinBleeding() -- Stop bleeding if it was caused by the red phase
        end
        stat_Adjustment_isEnabled = false

        if not consumingDischargeItem then
            Events.EveryDays.Add(consumeDischargeProduct)
            consumingDischargeItem = true
        end
    end
end

return EffectsManager
