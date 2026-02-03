RD_CycleTrackerLogic = RD_CycleTrackerLogic or {}
RDCycleTrackerLogic = RD_CycleTrackerLogic -- Alias for backward compatibility
require "RD_cycle_tracker_text"
require "RD_game_api"

function RD_CycleTrackerLogic.LoadPlayerData()
    RD_modData = RD_zapi.getModData()
    RD_modData.ICdata = RD_modData.ICdata or {}
    RD_modData.ICdata.calendar = RD_modData.ICdata.calendar or RD_CycleTrackerText.newCalendar()
    RD_modData.ICdata.calendarMonth = RD_modData.ICdata.calendarMonth or RD_zapi.getGameTime("getMonth") + 1
    RD_modData.ICdata.journalID = RD_modData.ICdata.journalID or RD_CycleTrackerText.generateUID()
end
-- Events.OnGameStart.Add(RD_CycleTrackerLogic.LoadPlayerData)
-- 2026-01-22 Moved to events_intercepts.lua

local function checkIfJournalisBlank(journal)
    -- local allBlank = true
    -- for pageNum = 1, 14 do
    --     local pageData = RD_CycleTrackerLogic.readJournal(journal, pageNum)
    --     if pageData and pageData:match("%S") then -- if any non-whitespace found
    --         allBlank = false
    --         break
    --     end
    -- end
    -- if allBlank then
    --     return journal
    -- end

    -- Just check if page 14 is blank as the user is instructed to blank it if they want to reuse the journal.
    local pageData = RD_CycleTrackerLogic.readJournal(journal, 14)
    if pageData and pageData:match("%S") then
        return false -- ID page not blank
    end
    return journal -- Blank ID page found
end

function RD_CycleTrackerLogic.getJournal(player, idSubstring, returnBlank)
    local function search(container)
        for i = 0, container:getItems():size() - 1 do
            local item = container:getItems():get(i)

            if item:getType() == "Period_Tracker" then
                local pageData = RD_CycleTrackerLogic.readJournal(item, 14)
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

function RD_CycleTrackerLogic.RegisterNewJournal(player, idSubstring)
    print("Registering new journal with ID - " .. tostring(idSubstring))
    journal = RD_CycleTrackerLogic.getJournal(player, idSubstring, true)
    if journal then
        frontCoverData = RD_CycleTrackerText.getFrontPage(player)
        RD_CycleTrackerLogic.writeToJournal(journal, 1, frontCoverData)

        -- Write monthly data for pages 2-13 for each month
        for month = 1, 12 do
            local calendarData = RD_CycleTrackerText.newCalendar()
            local monthText = RD_CycleTrackerText.getCalendarText(calendarData, month)
            RD_CycleTrackerLogic.writeToJournal(journal, month + 1, monthText) -- Pages 2-13 for months
        end

        idPageData = RD_CycleTrackerText.getBackPage(idSubstring)
        RD_CycleTrackerLogic.writeToJournal(journal, 14, idPageData)
        return journal
    end
end

function RD_CycleTrackerLogic.readJournal(journal, pageNum)
    -- There used to be a lot of logic here, but keeping this to keep it consistent.
    return journal:seePage(pageNum)
end

function RD_CycleTrackerLogic.writeToJournal(journal, pageNum, data)
    -- There used to be a lot of logic here, but keeping this to keep it consistent.
    journal:addPage(pageNum, data)
end

local function updateCalendar(calendar, day, value)
    for lineIndex, line in ipairs(calendar) do
        if line.days[day] then
            line.days[day] = value
            RD_modData.ICdata.calendar = calendar
            return true
        end
    end
    return false
end

function RD_CycleTrackerLogic.getDataCodes(cycle)
    stat = RD_CycleManager.getPhaseStatus(cycle) -- returns: phase, time_remaining, percent_complete
    if not stat or not stat.phase then
        return false
    end
    if stat.phase == "redPhase" then
        return RD_CycleTrackerText.redPhaseDataCodes(cycle, stat)

    elseif stat.phase == "follicularPhase" then
        return RD_CycleTrackerText.follicularPhaseDataCodes(cycle, stat)

    elseif stat.phase == "ovulationPhase" then
        return RD_CycleTrackerText.OvulationPhaseDataCodes(cycle, stat)

    elseif stat.phase == "lutealPhase" then
        return RD_CycleTrackerText.lutealPhaseDataCodes(cycle, stat)
    end
    return false
end

function RD_CycleTrackerLogic.cycleTrackerMainLogic(cycle)
    local player = RD_zapi.getPlayer()
    local playerJournalID = RD_modData.ICdata.journalID
    if not playerJournalID then
        print("It appears the player has died and respawned without reloading the game. Generating a new journal ID.")
        RD_modData.ICdata.journalID = RD_CycleTrackerText.generateUID()
        playerJournalID = RD_modData.ICdata.journalID
    end

    local day = RD_zapi.getGameTime("getDayPlusOne")
    local month = RD_zapi.getGameTime("getMonth") + 1
    local year = RD_zapi.getGameTime("getYear")

    if RD_modData.ICdata.calendarMonth ~= month then
        RD_modData.ICdata.calendarMonth = month
        RD_modData.ICdata.calendar = RD_CycleTrackerText.newCalendar() -- Reset calendar for the new month
        print("Cycle Tracker Logic: New month detected, resetting calendar.")
    end

    local journal = RD_CycleTrackerLogic.getJournal(player, playerJournalID, false)
    if not journal then
        journal = RD_CycleTrackerLogic.RegisterNewJournal(player, playerJournalID)
        if not journal then
            print("No valid journal found or registered. Cycle tracking data will not be saved.")
            return
        end
    end

    -- Front cover should exist, but this mainly refreshes the inspirational quotes
    frontCoverData = RD_CycleTrackerText.getFrontPage(player)
    RD_CycleTrackerLogic.writeToJournal(journal, 1, frontCoverData)

    local dataCodes = RD_CycleTrackerLogic.getDataCodes(cycle)
    if dataCodes then
        local dataCodeString = RD_CycleTrackerText.dataCodeFormatter(dataCodes)

        updateCalendar(RD_modData.ICdata.calendar, day, dataCodeString)
        local calendarData = RD_CycleTrackerText.getCalendarText(RD_modData.ICdata.calendar, month)

        local pageMonthNumber = month + 1 -- Adjusted for front cover page
        RD_CycleTrackerLogic.writeToJournal(journal, pageMonthNumber, calendarData)
    end
end

-- Below are intercept functions that are triggered when the player interacts with hygiene items.

-- If player unequips the hygiene item, inspect the item and update the cycle tracker
function RD_CycleTrackerLogic.ISUnequipAction_perform(self)
    if RD_zapi.isItemAtBodyLocation(self.item, "RedDays:HygieneItem") then
        RD_CycleTrackerLogic.cycleTrackerMainLogic(RD_modData.ICdata.currentCycle)
    end
end
-- 2026-01-23 Moved to events_intercepts.lua

-- If the player replaces a hygiene item, inspect the item and update the cycle tracker
function RD_CycleTrackerLogic.ISWearClothing_perform(self)
    if RD_zapi.isItemAtBodyLocation(self.item, "RedDays:HygieneItem") then
        local hygieneItem = RD_HygieneManager.getCurrentlyWornSanitaryItem()
        if hygieneItem then
            RD_CycleTrackerLogic.cycleTrackerMainLogic(RD_modData.ICdata.currentCycle)
        end
    end
end
-- 2026-01-23 Moved to events_intercepts.lua

return RD_CycleTrackerLogic

-- Notes:
-- Add writing tool requirements
-- 	item 1 [Base.Pen;Base.BluePen;Base.GreenPen;Base.RedPen;Base.PenFancy;Base.PenMultiColor;Base.PenSpiffo;Base.Pencil;Base.PencilSpiffo;Base.MarkerBlack;Base.MarkerBlue;Base.MarkerGreen;Base.MarkerRed],
