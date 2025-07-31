CycleTrackerLogic = {}
require "RedDays/cycle_tracker_text"

local function LoadPlayerData()
    local player = getPlayer()
    modData = player:getModData()
    modData.ICdata = modData.ICdata or {}
    modData.ICdata.calendar = modData.ICdata.calendar or CycleTrackerText.newCalendar()
    modData.ICdata.calendarMonth = modData.ICdata.calendarMonth or getGameTime():getMonth() + 1
    modData.ICdata.journalID = modData.ICdata.journalID or CycleTrackerText.generateUID()
end
Events.OnGameStart.Add(LoadPlayerData)

local function checkIfJournalisBlank(journal)
    local allBlank = true
    for pageNum = 1, 14 do
        local pageData = CycleTrackerLogic.readJournal(journal, pageNum)
        if pageData and pageData:match("%S") then -- if any non-whitespace found
            allBlank = false
            break
        end
    end
    if allBlank then
        return journal
    end
end

function CycleTrackerLogic.getJournal(player, idSubstring, returnBlank)
    local function search(container)
        for i = 0, container:getItems():size() - 1 do
            local item = container:getItems():get(i)

            if item:getType() == "Period_Tracker" then
                local pageData = CycleTrackerLogic.readJournal(item, 14)
                if pageData and string.find(pageData, idSubstring) and not returnBlank then
                    return item
                end

                if returnBlank then
                    local blank_journal = checkIfJournalisBlank(item)
                    if blank_journal then
                        return blank_journal
                    end
                end
            end

            -- Recurse into subcontainers like bags
            if item:IsInventoryContainer() then
                local found = search(item:getInventory())
                if found then return found end
            end
        end
        return nil
    end
    return search(player:getInventory())
end

function CycleTrackerLogic.RegisterNewJournal(player, idSubstring)
    journal = CycleTrackerLogic.getJournal(player, idSubstring, true)
    if journal then
        frontCoverData = CycleTrackerText.getFrontPage(player)
        CycleTrackerLogic.writeToJournal(journal, 1, frontCoverData)

        -- Write monthly data for pages 2-13 for each month
        for month = 1, 12 do
            local calendarData = CycleTrackerText.newCalendar()
            local monthText = CycleTrackerText.getCalendarText(calendarData, month)
            CycleTrackerLogic.writeToJournal(journal, month + 1, monthText) -- Pages 2-13 for months
        end

        idPageData = CycleTrackerText.getBackPage()
        CycleTrackerLogic.writeToJournal(journal, 14, idPageData)
        return journal
    end
end

function CycleTrackerLogic.readJournal(journal, pageNum)
    -- There used to be a lot of logic here, but keeping this to keep it consistent.
    return journal:seePage(pageNum)
end

function CycleTrackerLogic.writeToJournal(journal, pageNum, data)
    -- There used to be a lot of logic here, but keeping this to keep it consistent.
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

    local player = getPlayer()
    local day = getGameTime():getDayPlusOne()
    local month = getGameTime():getMonth() + 1
    local year = getGameTime():getYear()

    if modData.ICdata.calendarMonth ~= month then
        modData.ICdata.calendarMonth = month
        modData.ICdata.calendar = CycleTrackerText.newCalendar() -- Reset calendar for the new month
        print("Cycle Tracker Logic: New month detected, resetting calendar.")
    end

    local journal = CycleTrackerLogic.getJournal(player, modData.ICdata.journalID, false)
    if not journal then
        journal = CycleTrackerLogic.RegisterNewJournal(player, modData.ICdata.journalID)
        if not journal then
            print("No valid journal found or registered. Cycle tracking data not saved.")
            return
        end
    end

    -- Front cover should exist, but this mainly refreshes the inspirational quotes
    frontCoverData = CycleTrackerText.getFrontPage(player)
    CycleTrackerLogic.writeToJournal(journal, 1, frontCoverData)

    -- local pageMonthNumber = month + 1 -- Adjusted for front cover page
    -- local calendarData = CycleTrackerText.getCalendarText(calendar)
    -- CycleTrackerLogic.writeToJournal(journal, pageMonthNumber, calendarData)
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
        local hygieneItem = HygieneManager.getCurrentlyWornSanitaryItem()
        if hygieneItem then
            cycleTrackerMainLogic()
        end
    end
    o_ISWearClothing_perform(self)
end

return CycleTrackerLogic

-- Notes:
-- Add writing tool requirements
-- 	item 1 [Base.Pen;Base.BluePen;Base.GreenPen;Base.RedPen;Base.PenFancy;Base.PenMultiColor;Base.PenSpiffo;Base.Pencil;Base.PencilSpiffo;Base.MarkerBlack;Base.MarkerBlue;Base.MarkerGreen;Base.MarkerRed],
