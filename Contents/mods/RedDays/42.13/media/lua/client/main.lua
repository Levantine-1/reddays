require "RedDays/game_api"
require "RedDays/cycle_manager"
require "RedDays/cycle_tracker_logic"
require "RedDays/effects_manager"
require "RedDays/hygiene_manager"
require "RedDays/effects_pms"
require "RedDays/moodles"

-- ================= GLOBAL EVENT HOOKS =================

local function OnGameStart()
    CycleManager.LoadPlayerData()
    CycleTrackerLogic.LoadPlayerData()
    EffectsPMS.LoadPlayerData()
    HygieneManager.LoadPlayerData()
    moodles.LoadPlayerData()
end
Events.OnGameStart.Add(OnGameStart)

local function EveryHours()
    if not zapi.getPlayer() then return end
    return -- Disable debug prints for release
    CycleDebugger.printWrapper()
end
Events.EveryHours.Add(EveryHours)

local function EveryTenMinutes()
    if not zapi.getPlayer() then return end
    local cycle = CycleManager.tick()
    EffectsManager.determineEffects(cycle)
    CycleDebugger.printWrapper()
end
Events.EveryTenMinutes.Add(EveryTenMinutes)

local function EveryOneMinute()
    if not zapi.getPlayer() then return end
    EffectsPMS.applyPMSEffectsMain()
    moodles.mainLoop()
end
Events.EveryOneMinute.Add(EveryOneMinute)

-- ================= INTERCEPT FUNCTIONS =================

-- If player unequips the hygiene item
local o_ISUnequipAction_perform = ISUnequipAction.perform
function ISUnequipAction:perform()
    moodles.ISUnequipAction_perform(self)
    CycleTrackerLogic.ISUnequipAction_perform(self)
    o_ISUnequipAction_perform(self)
end

-- If the player replaces a hygiene item
local o_ISWearClothing_perform = ISWearClothing.perform
function ISWearClothing:perform()
    moodles.ISWearClothing_perform(self)
    CycleTrackerLogic.ISWearClothing_perform(self)
    o_ISWearClothing_perform(self)
end

-- If the player washes themselves, reset the leak moodle
local o_ISWashYourself_perform = ISWashYourself.perform
function ISWashYourself:perform()
    moodles.ISWashYourself_perform()
    o_ISWashYourself_perform(self)
end

-- If the player takes painkillers, reduce PMS symptoms
local o_ISTakePillAction_perform = ISTakePillAction.perform
function ISTakePillAction:perform()
    EffectsPMS.ISTakePillAction_perform(self)
    o_ISTakePillAction_perform(self)
end
