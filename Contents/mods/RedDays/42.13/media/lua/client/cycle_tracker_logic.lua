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
    -- local allBlank = true
    -- for pageNum = 1, 14 do
    --     local pageData = CycleTrackerLogic.readJournal(journal, pageNum)
    --     if pageData and pageData:match("%S") then -- if any non-whitespace found
    --         allBlank = false
    --         break
    --     end
    -- end
    -- if allBlank then
    --     return journal
    -- end

    -- Just check if page 14 is blank as the user is instructed to blank it if they want to reuse the journal.
    local pageData = CycleTrackerLogic.readJournal(journal, 14)
    if pageData and pageData:match("%S") then
        return false -- ID page not blank
    end
    return journal -- Blank ID page found
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
    print("Registering new journal with ID - " .. tostring(idSubstring))
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

        idPageData = CycleTrackerText.getBackPage(idSubstring)
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

function CycleTrackerLogic.getDataCodes(cycle)
    stat = CycleManager.getPhaseStatus(cycle) -- returns: phase, time_remaining, percent_complete
    if not stat or not stat.phase then
        return false
    end
    if stat.phase == "redPhase" then
        return CycleTrackerText.redPhaseDataCodes(cycle, stat)

    elseif stat.phase == "follicularPhase" then
        return CycleTrackerText.follicularPhaseDataCodes(cycle, stat)

    elseif stat.phase == "ovulationPhase" then
        return CycleTrackerText.OvulationPhaseDataCodes(cycle, stat)

    elseif stat.phase == "lutealPhase" then
        return CycleTrackerText.lutealPhaseDataCodes(cycle, stat)
    end
    return false
end

function CycleTrackerLogic.cycleTrackerMainLogic(cycle)
    local player = getPlayer()
    local playerJournalID = modData.ICdata.journalID
    if not playerJournalID then
        print("It appears the player has died and respawned without reloading the game. Generating a new journal ID.")
        modData.ICdata.journalID = CycleTrackerText.generateUID()
        playerJournalID = modData.ICdata.journalID
    end

    local day = getGameTime():getDayPlusOne()
    local month = getGameTime():getMonth() + 1
    local year = getGameTime():getYear()

    if modData.ICdata.calendarMonth ~= month then
        modData.ICdata.calendarMonth = month
        modData.ICdata.calendar = CycleTrackerText.newCalendar() -- Reset calendar for the new month
        print("Cycle Tracker Logic: New month detected, resetting calendar.")
    end

    local journal = CycleTrackerLogic.getJournal(player, playerJournalID, false)
    if not journal then
        journal = CycleTrackerLogic.RegisterNewJournal(player, playerJournalID)
        if not journal then
            print("No valid journal found or registered. Cycle tracking data will not be saved.")
            return
        end
    end

    -- Front cover should exist, but this mainly refreshes the inspirational quotes
    frontCoverData = CycleTrackerText.getFrontPage(player)
    CycleTrackerLogic.writeToJournal(journal, 1, frontCoverData)

    local dataCodes = CycleTrackerLogic.getDataCodes(cycle)
    if dataCodes then
        local dataCodeString = CycleTrackerText.dataCodeFormatter(dataCodes)

        updateCalendar(modData.ICdata.calendar, day, dataCodeString)
        local calendarData = CycleTrackerText.getCalendarText(modData.ICdata.calendar, month)

        local pageMonthNumber = month + 1 -- Adjusted for front cover page
        CycleTrackerLogic.writeToJournal(journal, pageMonthNumber, calendarData)
    end
end

-- Below are intercept functions that are triggered when the player interacts with hygiene items.

--If player unequips the hygiene item, inspect the item and update the cycle tracker
local o_ISUnequipAction_perform = ISUnequipAction.perform
function ISUnequipAction:perform()
    local hygieneLocation = ItemBodyLocation.get(ResourceLocation.of("RedDays:HygieneItem"))
    if hygieneLocation and self.item:isBodyLocation(hygieneLocation) then
        CycleTrackerLogic.cycleTrackerMainLogic(modData.ICdata.currentCycle)
    end
    o_ISUnequipAction_perform(self)
end

-- If the player replaces a hygiene item, inspect the item and update the cycle tracker
local o_ISWearClothing_perform = ISWearClothing.perform
function ISWearClothing:perform()
    local hygieneLocation = ItemBodyLocation.get(ResourceLocation.of("RedDays:HygieneItem"))
    if hygieneLocation and self.item:isBodyLocation(hygieneLocation) then
        local hygieneItem = HygieneManager.getCurrentlyWornSanitaryItem()
        if hygieneItem then
            CycleTrackerLogic.cycleTrackerMainLogic(modData.ICdata.currentCycle)
        end
    end
    o_ISWearClothing_perform(self)
end

return CycleTrackerLogic

-- Notes:
-- Add writing tool requirements
-- 	item 1 [Base.Pen;Base.BluePen;Base.GreenPen;Base.RedPen;Base.PenFancy;Base.PenMultiColor;Base.PenSpiffo;Base.Pencil;Base.PencilSpiffo;Base.MarkerBlack;Base.MarkerBlue;Base.MarkerGreen;Base.MarkerRed],
