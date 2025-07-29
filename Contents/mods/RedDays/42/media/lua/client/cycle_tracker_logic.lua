CycleTrackerLogic = {}
require "RedDays/cycle_tracker_text"

local function LoadPlayerData()
    local player = getPlayer()
    modData = player:getModData()
    modData.ICdata = modData.ICdata or {}
    cycleDelayed = modData.ICdata.cycleDelayed or false
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

function CycleTrackerLogic.writeToJournal(journal, pageNum, text)
    return
end

local function testFunction()
    local player = getPlayer()
    local journal = CycleTrackerLogic.getJournal(player)
    -- CycleTracker.readJournal(journal)
    if journal then
        print("Adding frontPage to journal.")
        local frontPage = CycleTrackerText.getFrontPage(player)
        journal:addPage(1, frontPage)
        print("Adding page template to journal.")
        local newCalendar = CycleTrackerText.newCalendar()
        local calendarText = CycleTrackerText.getCalendarText(newCalendar)
        journal:addPage(2, calendarText)
        print("Adding backpage to journal.")
        local backPage = CycleTrackerText.getBackPage()
        journal:addPage(14, backPage)
    end
    local year = getGameTime():getYear()
    local month = getGameTime():getMonth() + 1
    local day = getGameTime():getDay() + 1
    print("DATE: " .. month .. "/" .. day .. "/" .. year)
end
Events.EveryTenMinutes.Add(testFunction)

return CycleTrackerLogic