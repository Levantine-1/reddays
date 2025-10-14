require "MF_ISMoodle"

require "RedDays/hygiene_manager"
require "RedDays/cycle_manager"

local moodles = {}

local function LoadPlayerData()
    local player = getPlayer()
    modData = player:getModData()
    modData.ICdata = modData.ICdata or {}
    modData.ICdata.LeakSwitchState = modData.ICdata.LeakSwitchState or false -- This value is updated by effects_manager methods
    modData.ICdata.LeakLevel = modData.ICdata.LeakLevel or 0.42 -- 0.42 is an arbitrary value that clears the moodle, but is low enough to quickly trigger a moodle when needed.
end
Events.OnGameStart.Add(LoadPlayerData)

MF.createMoodle("DirtyPantyLiner");
MF.createMoodle("BloodyPantyLiner");

MF.createMoodle("DirtySanitaryPad");
MF.createMoodle("BloodySanitaryPad");

MF.createMoodle("DirtyTampon");
MF.createMoodle("BloodyTampon");

MF.createMoodle("Leak");


-- Determine if player bathed based on clothes/body dirtiness/bloody
local function getMoodleLevel(hygieneItemCondition)
    local moodleLevel = 0.5
    if hygieneItemCondition == 4 then
        moodleLevel = 0.4
    elseif hygieneItemCondition == 3 then
        moodleLevel = 0.3
    elseif hygieneItemCondition == 2 then
        moodleLevel = 0.2
    elseif hygieneItemCondition < 2 then
        moodleLevel = 0
    end
    return moodleLevel
end


function getHygieneItemName(hygieneItem)
    local hygieneItemName = hygieneItem:getType()
    hygieneItemName = string.gsub(hygieneItemName, "_", "") -- Remove all underscores
    return hygieneItemName
end


local function getCurrentPlayerNum()
    return getPlayer():getPlayerNum()
end

local function getCurrentHygieneItem()
    return HygieneManager.getCurrentlyWornSanitaryItem()
end

local function getCurrentPhaseData()
    return CycleManager.getPhaseStatus(modData.ICdata.currentCycle)
end

local function getMoodleType(phase)
    return (phase == "redPhase") and "Bloody" or "Dirty"
end

local function getMoodleLevelForItem(moodletype, condition)
    if moodletype == "Dirty" and condition <= 1 then
        return 0.4 -- Only show level 1 moodle for dirty from discharge
    else
        return getMoodleLevel(condition)
    end
end

local function getLeakDecrementValue(phase_percent_complete)
    if (phase_percent_complete >= 0 and phase_percent_complete < 10) or (phase_percent_complete >= 85 and phase_percent_complete <= 100) then
        return 0.001 -- Spotting
    elseif (phase_percent_complete >= 10 and phase_percent_complete < 25) or (phase_percent_complete >= 70 and phase_percent_complete < 85) then
        return 0.002 -- Light
    elseif (phase_percent_complete >= 25 and phase_percent_complete < 35) or (phase_percent_complete >= 55 and phase_percent_complete < 70) then
        return 0.003 -- Medium
    elseif (phase_percent_complete >= 35 and phase_percent_complete < 55) then
        return 0.007 -- Heavy
    else
        return 0.002 -- Fallback
    end
end

local function updateLeakState(phaseData) -- This is expected to run in the main loop which runs every in game minute
    if modData.ICdata.LeakSwitchState then
        modData.ICdata.LeakLevel = modData.ICdata.LeakLevel - getLeakDecrementValue(phaseData.percent_complete)
    end
    MF.getMoodle("Leak", getCurrentPlayerNum()):setValue(modData.ICdata.LeakLevel)
end

local function resetMoodles()
    local playerNum = getCurrentPlayerNum()
    local moodleNames = {
        "DirtyPantyLiner",
        "BloodyPantyLiner",
        "DirtySanitaryPad",
        "BloodySanitaryPad",
        "DirtyTampon",
        "BloodyTampon"
    }
    for _, name in ipairs(moodleNames) do
        MF.getMoodle(name, playerNum):setValue(0.42)
    end
end

local function setHygieneMoodle(hygieneItem, phaseData)
    local hygieneItemName = getHygieneItemName(hygieneItem)
    local hygieneItemCondition = hygieneItem:getCondition()
    local moodletype = getMoodleType(phaseData.phase)
    local moodleLevel = getMoodleLevelForItem(moodletype, hygieneItemCondition)
    local moodleName = moodletype .. hygieneItemName
    MF.getMoodle(moodleName, getCurrentPlayerNum()):setValue(moodleLevel)
end

function mainLoop()
    local hygieneItem = getCurrentHygieneItem()
    local phaseData = getCurrentPhaseData()

    if hygieneItem then
        if phaseData.phase == "redPhase" then
            setHygieneMoodle(hygieneItem, phaseData)

        elseif hygieneItem:getCondition() == 1 then
            setHygieneMoodle(hygieneItem, phaseData)
        end
    end

    updateLeakState(phaseData)
end
Events.EveryOneMinute.Add(mainLoop)


-- Below are intercept functions that are triggered when the player interacts with hygiene items.

-- If player unequips the hygiene item, inspect the item and update the cycle tracker
local o_ISUnequipAction_perform = ISUnequipAction.perform
function ISUnequipAction:perform()
    if self.item:getBodyLocation() == "HygieneItem" then
        resetMoodles()
    end
    o_ISUnequipAction_perform(self)
end

-- If the player replaces a hygiene item, inspect the item and update the cycle tracker
local o_ISWearClothing_perform = ISWearClothing.perform
function ISWearClothing:perform()
    if self.item:getBodyLocation() == "HygieneItem" then
        resetMoodles()
    end
    o_ISWearClothing_perform(self)
end


-- If the player washes themselves, reset the leak moodle
local o_ISWashYourself_perform = ISWashYourself.perform
function ISWashYourself:perform()
    modData.ICdata.LeakLevel = 0.42 -- 0.42 is an arbitrary value that clears the moodle, but is low enough to quickly trigger a moodle when needed.
    o_ISWashYourself_perform(self)
end

return moodles
