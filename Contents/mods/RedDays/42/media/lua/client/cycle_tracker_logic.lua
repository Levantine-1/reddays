CycleTrackerLogic = {}
require "RedDays/cycle_tracker_text"

local function LoadPlayerData()
    local player = getPlayer()
    modData = player:getModData()
    modData.ICdata = modData.ICdata or {}
    modData.ICdata.calendar = modData.ICdata.calendar or CycleTrackerText.newCalendar()
    modData.ICdata.calendarMonth = modData.ICdata.calendarMonth or getGameTime():getMonth() + 1
end
Events.OnGameStart.Add(LoadPlayerData)


function CycleTrackerLogic.getJournal(player)
    local inv = player:getInventory()
    for i = 0, inv:getItems():size() - 1 do
        local item = inv:getItems():get(i)
        if string.find(item:getDisplayName(), "Period Tracker") then -- Match substring because the appended year may vary
            return item
        end
    end
    return nil
end

function CycleTrackerLogic.readJournal(journal)
    if not journal then 
        print("No journal found.")
        return
    end

    local pages = journal:getCustomPages()
    if not pages or not pages.size then
        print("No pages or invalid page data in journal.")
        return
    end

    local pageCount = pages:size()
    print("Journal has " .. pageCount .. " pages.")
    for i = 1, pageCount do
        local text = journal:seePage(i)
        print("Page " .. i .. ": " .. tostring(text))
    end
end

function CycleTrackerLogic.writeToJournal(journal, pageNum, data)
    journal:addPage(pageNum, data)
end

local function updateCalendar(calendar, day, value)
    for lineIndex, line in ipairs(calendar) do
        if line.days[day] then
            line.days[day] = value
            modData.ICdata.calendar = calendar
            return true
        end
    end
    return false
end

local function cycleTrackerMainLogic()
    print("Player has unequipped/replaced a hygiene item, updating the cycle tracker.")
    return
end


-- If player unequips the hygiene item, inspect the item and update the cycle tracker
local o_ISUnequipAction_perform = ISUnequipAction.perform
function ISUnequipAction:perform()
    if self.item:getBodyLocation() == "HygieneItem" then
        cycleTrackerMainLogic()
    end
    o_ISUnequipAction_perform(self)
end

-- If the player replaces a hygiene item, inspect the item and update the cycle tracker
local o_ISWearClothing_perform = ISWearClothing.perform
function ISWearClothing:perform()
    if self.item:getBodyLocation() == "HygieneItem" then
        hygieneItem = HygieneManager.getCurrentlyWornSanitaryItem()
        if hygieneItem then
            cycleTrackerMainLogic()
        end
    end
    o_ISWearClothing_perform(self)
end

return CycleTrackerLogic