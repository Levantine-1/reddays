require "RD_game_api"
require "RD_cycle_manager"
require "RD_cycle_tracker_logic"
require "RD_effects_manager"
require "RD_hygiene_manager"
require "RD_effects_pms"
require "RD_moodles"
require "RD_debugger"

-- Gender check
local function isValidGenderCheck()
    if not SandboxVars.RedDays.affectsAllGenders then
        if not RD_zapi.isFemale() then
            return false
        end
    end
    return true
end

-- ================= GLOBAL EVENT HOOKS =================
local function initializePlayerData()
    RD_CycleManager.LoadPlayerData()
    RD_CycleTrackerLogic.LoadPlayerData()
    RD_EffectsPMS.LoadPlayerData()
    RD_HygieneManager.LoadPlayerData()
    RD_moodles.LoadPlayerData()
end

local function OnGameStart()
    if not isValidGenderCheck() then return end
    initializePlayerData()
end
Events.OnGameStart.Add(OnGameStart)

local function OnCreatePlayer(playerIndex, player) -- When player is created or respawned
    if playerIndex ~= 0 then return end
    if not isValidGenderCheck() then return end
    initializePlayerData()
end
Events.OnCreatePlayer.Add(OnCreatePlayer)

-- ================= TIMED EVENT HOOKS =================
local function EveryHours()
    if not isValidGenderCheck() then return end
    RD_CycleDebugger.printWrapper()
end
Events.EveryHours.Add(EveryHours)

local function EveryTenMinutes()
    if not isValidGenderCheck() then return end
    -- RD_CycleDebugger.printWrapper()
end
Events.EveryTenMinutes.Add(EveryTenMinutes)

local function EveryOneMinute()
    if not isValidGenderCheck() then return end
    local cycle = RD_CycleManager.tick(1)
    RD_EffectsManager.determineEffects(cycle)
    RD_EffectsPMS.applyPMSEffectsMain()
    RD_moodles.mainLoop()
end
Events.EveryOneMinute.Add(EveryOneMinute)

-- ================= INTERCEPT FUNCTIONS =================
local o_ISUnequipAction_perform = ISUnequipAction.perform
function ISUnequipAction:perform()
    if isValidGenderCheck() then
        RD_moodles.ISUnequipAction_perform(self)
        RD_CycleTrackerLogic.ISUnequipAction_perform(self)
    end
    o_ISUnequipAction_perform(self)
end

local o_ISWearClothing_perform = ISWearClothing.perform
function ISWearClothing:perform()
    if isValidGenderCheck() then
        RD_moodles.ISWearClothing_perform(self)
        RD_CycleTrackerLogic.ISWearClothing_perform(self)
    end
    o_ISWearClothing_perform(self)
end

local o_ISWashYourself_perform = ISWashYourself.perform
function ISWashYourself:perform()
    if isValidGenderCheck() then
        RD_moodles.ISWashYourself_perform()
    end
    o_ISWashYourself_perform(self)
end

local o_ISTakePillAction_perform = ISTakePillAction.perform
function ISTakePillAction:perform()
    if isValidGenderCheck() then
        RD_EffectsPMS.ISTakePillAction_perform(self)
    end
    o_ISTakePillAction_perform(self)
end
