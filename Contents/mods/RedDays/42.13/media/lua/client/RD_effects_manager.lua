require "RD_hygiene_manager"
require "RD_moodles"
require "RD_game_api"

RD_EffectsManager = RD_EffectsManager or {}
RDEffectsManager = RD_EffectsManager -- Alias for backward compatibility

local stat_Adjustment_isEnabled = false
local function stat_Adjustment()
    stat_Adjustment_isEnabled = true
    local cycle = RD_modData.ICdata.currentCycle -- The event system calls the function with no arguments, so cycle is nil, so that's why it's set here

    if RD_HygieneManager:consumeHygieneProduct() then
        RD_modData.ICdata.LeakSwitchState = false
    elseif not RD_HygieneManager:consumeHygieneProduct() then
        RD_modData.ICdata.LeakSwitchState = true
    end
end

local consumingDischargeItem = false
local function consumeDischargeProduct()
    consumingDischargeItem = true
    return RD_HygieneManager:consumeDischargeProduct()
end

local function stopGroinBleeding()
    local groin = RD_zapi.getBodyPart(BodyPartType.Groin)
    local bleedingTime = groin:getBleedingTime()
    if bleedingTime == 0 then -- Clear bleeding if no wounds. Cycle generates bleeding time of 0, so assumed no wounds.
        -- groin:setBleeding(false)
        RD_modData.ICdata.LeakSwitchState = false
    end
end

function RD_EffectsManager.determineEffects(cycle)
    local current_phase = RD_CycleManager.getCurrentCyclePhase(cycle)

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

return RD_EffectsManager
