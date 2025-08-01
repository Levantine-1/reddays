CycleTrackerText = {}

function CycleTrackerText.getInspirationalQuote()
    local quotes = {
        -- Quotes from International Women's Day 2024
        '"There is no limit to what we, as women, can accomplish." - Michelle Obama',
        '"A girl should be two things: Who and what she wants." - Coco Chanel',
        '"As long as you live, there\'s something new every day." - Dolly Parton',
        '"Always be a first-rate version of yourself instead of a second-rate version of somebody else." - Judy Garland',
        '"Do not live someone else\'s life and someone else\'s idea of what womanhood is. Womanhood is you." - Viola Davis',
        '"Life is tough, my darling, but so are you." - Stephanie Bennett-Henry',
        '"Do not ever sell yourself short." - Jameela Jamil',
        '"I am grateful to be a woman. I must have done something great in another life." - Maya Angelou',
        '"I\'ve never been interested in being invisible and erased." - Laverne Cox',
        '"I\'d rather regret the things I\'ve done than regret the things I haven\'t done." - Lucille Ball',
        '"I am a woman and I get to define what that means." - Swati Sharma',
        '"Girls should never be afraid to be smart." - Emma Watson',
        '"You may be disappointed if you fail, but you are doomed if you don\'t try." - Beverly Sills',
        '"If you don\'t see a clear path for what you want, sometimes you have to make it yourself." - Mindy Kaling',
        '"The only one who can tell you \"you can\'t win\" is you, and you don\'t have to listen" - Dame Jessica Ennis-Hill',
        '"The most beautiful thing a woman can wear is confidence." - Blake Lively',
        '"I don\'t get my inspiration from books or a painting. I get it from the women I meet." - Carolina Herrera',
        '"Alone we can do so little; together we can do so much." - Helen Keller',
        -- Quotes from UCSF Health - Inspire: Women to Women 2020
        '"A strong woman stands up for herself. A stronger woman stands up for others." - Unknown UCSF 2020',
        '"No one can make you feel inferior without your consent." - Eleanor Roosevelt',
        '"You\'ve always had the power, my dear, you just had to learn it for yourself." - Glinda the Good Witch',
        '"A strong woman looks a challenge in the eye and gives it a wink" - Gina Carey',
        '"The more you love your decisions, the less you need others to love them." - Lisa Messenger',
        '"A queen is not afraid to fail. Failure is another stepping stone to greatness." - Oprah Winfrey',
        '"I figure if a girl wants to be a legend, she should go ahead and be one." - Calamity Jane',
        -- Quotes from Rebel Girls Blog
        '"You are more powerful than you know; you are beautiful just as you are." - Melissa Etheridge',
        '"It\'s tougher to be vulnerable than to be tough." - Rihanna',
        '"You can never leave footprints that last if you are always walking on tiptoe." - Leymah Gbowee',
        '"The art of life is not controlling what happens to us, but using what happens to us." - Gloria Steinem',
        '"Your story is what you have, what you will always have. It is something to own." - Michelle Obama',
        -- Random Quotes I thought were also good
        '"Life isn\'t fair, but your reaction to injustice is what defines the content of your character" - Unknown',
        '"All adventures, especially into new territory, are scary." - Sally Ride',
        '"More good women have been lost to marriage than to war, famine, disease, and disaster. You have talent, darling. Don\'t squander it." - Cruela De Vil' -- I thought this quote was so good it was worth breaking the character limit.
    }
    return quotes[ZombRand(#quotes) + 1]
end

function CycleTrackerText.getFrontPage(player)
    local playerName = player:getDescriptor():getForename() .. " " .. player:getDescriptor():getSurname()
    local nameLine = "Name: " .. playerName
    local inspirationalQuote = CycleTrackerText.getInspirationalQuote()
    local text_body = "                 *** KEY *** \
H: Heavy        D: Discharge\
M: Medium   Dc: Clear/White\
L: Light           Dcw: Crmy Wht.\
S: Spotting    Dew: Egg White\
A: Agitated    F: Fatigue\
U: Sadness     T: TenderBrst.\
C: Cramps      Y: Crave Food\
X: No Data     B: BC Pill Taken"
    local text = nameLine .. "\n" .. inspirationalQuote .. "\n"  .. text_body
    return text
end

function CycleTrackerText.generateUID()
    local chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'
    local uid = ''
    for i = 1, 12 do
        local rand = ZombRand(#chars) + 1 -- ZombRand is 0-based, Lua strings are 1-based
        uid = uid .. chars:sub(rand, rand)
    end
    return uid
end

function CycleTrackerText.getBackPage(UID)
    local ID_Line = "ID: " .. UID
    local text_body = "Do not modify the ID or this tracker will stop updating.\
   \
 If you want to overwrite  or reuse this journal, delete all contents on this page.\
\
This tracker is automatically updated when the you unequip or replace a feminine hygiene item.\
If changed multiple times, only last data for the day is saved."
    local text = ID_Line .. "\n" .. text_body
    return text
end

local function getMonthName(index)
    local monthNames = {
        "January", "February", "March", "April", "May", "June",
        "July", "August", "September", "October", "November", "December"
    }
    return monthNames[index] or "Unknown"
end

function CycleTrackerText.newCalendar()
    local lines = {
        [1] = { days = { [1] = "______", [15] = "______", [29] = "______" } },
        [2] = { days = { [2] = "______", [16] = "______", [30] = "______" } },
        [3] = { days = { [3] = "______", [17] = "______", [31] = "______" } },
        [4] = { days = { [4] = "______", [18] = "______" } },
        [5] = { days = { [5] = "______", [19] = "______" } },
        [6] = { days = { [6] = "______", [20] = "______" } },
        [7] = { days = { [7] = "______", [21] = "______" } },
        [8] = { days = { [8] = "______", [22] = "______" } },
        [9] = { days = { [9] = "______", [23] = "______" } },
        [10] = { days = { [10] = "______", [24] = "______" } },
        [11] = { days = { [11] = "______", [25] = "______" } },
        [12] = { days = { [12] = "______", [26] = "______" } },
        [13] = { days = { [13] = "______", [27] = "______" } },
        [14] = { days = { [14] = "______", [28] = "______" } },
    }
    return lines
end

function CycleTrackerText.getCalendarText(calendar, month)
    local year = getGameTime():getYear()
    local monthName = getMonthName(month)

    local text = monthName .. " " .. year .. "\n"
    for i = 1, #calendar do
        local month = calendar[i]
        if month then
            local line = ""
            for day, value in pairs(month.days) do
                if day < 10 then
                    day = "0" .. day -- Pad single-digit days with a leading zero
                end
                line = line .. day .. ": " .. value .. "  "
            end
            text = text .. line:sub(1, -2) .. "\n"
        end
    end
    return text
end

local function symptomShuffle(possibleValues, valuesToReturnLowerBound, valuesToReturnUpperBound)
    -- Pick a random number in the range [lowerBound, upperBound]
    local count = ZombRand(valuesToReturnUpperBound - valuesToReturnLowerBound + 1) + valuesToReturnLowerBound

    -- Make a shallow copy to avoid modifying the original table
    local shuffled = {}
    for i, v in ipairs(possibleValues) do shuffled[i] = v end

    -- Fisher-Yates shuffle
    for i = #shuffled, 2, -1 do
        local j = ZombRand(i) + 1
        shuffled[i], shuffled[j] = shuffled[j], shuffled[i]
    end

    -- Return the first 'count' elements
    local result = {}
    for i = 1, math.min(count, #shuffled) do
        table.insert(result, shuffled[i])
    end
    return result
end

function CycleTrackerText.redPhaseDataCodes(cycle, stat)
    local datacodes = {}
    local statusMap = {
                        {threshold = 15, code = "S"},
                        {threshold = 25, code = "L"},
                        {threshold = 35, code = "M"},
                        {threshold = 50, code = "H"},
                        {threshold = 70, code = "M"},
                        {threshold = 85, code = "L"},
                        {threshold = 100, code = "S"},
                    }
    for _, entry in ipairs(statusMap) do
        if stat.percent_complete < entry.threshold then
            table.insert(datacodes, entry.code)
            break
        end
    end

    local extraSymptomCodes = {"A", "C", "F"} -- Agitated, Cramps, Fatigue
    local randomSymptoms = symptomShuffle(extraSymptomCodes, 1, 3) -- returns 1 to 3 random symptoms
    for _, code in ipairs(randomSymptoms) do
        table.insert(datacodes, code)
    end

    return datacodes
end

function CycleTrackerText.follicularPhaseDataCodes(cycle, stat)
    -- quotes[ZombRand(#quotes) + 1]
    local datacodes = {}
    local validDischargeCodes = {"Dc", "Dcw", "D"}
    local randomDischargeCode = validDischargeCodes[ZombRand(#validDischargeCodes) + 1]
    local statusMap = {
                        {threshold = 90, code = randomDischargeCode},
                        {threshold = 100, code = "Dew"}, -- Starting to ovulate
                    }
    for _, entry in ipairs(statusMap) do
        if stat.percent_complete < entry.threshold then
            table.insert(datacodes, entry.code)
            break
        end
    end
    -- No random symptoms in follicular phase
    return datacodes
end

function CycleTrackerText.OvulationPhaseDataCodes(cycle, stat)
    local datacodes = {"Dew"} -- Egg White Discharge

    local extraSymptomCodes = {"A"} -- Agitated (I guess it can mean different things...)
    local randomSymptoms = symptomShuffle(extraSymptomCodes, 0, 1) -- returns 0 to 1 random symptoms
    for _, code in ipairs(randomSymptoms) do
        table.insert(datacodes, code)
    end

    return datacodes
end

function CycleTrackerText.lutealPhaseDataCodes(cycle, stat)
    local datacodes = {}
    local validDischargeCodes = {"Dc", "Dcw"}
    local randomDischargeCode = validDischargeCodes[ZombRand(#validDischargeCodes) + 1]
    local statusMap = {
                        {threshold = 75, code = randomDischargeCode},
                        {threshold = 100, code = "D"}, -- Starting to menstruate
                    }
    for _, entry in ipairs(statusMap) do
        if stat.percent_complete < entry.threshold then
            table.insert(datacodes, entry.code)
            break
        end
    end

    if stat.percent_complete >= 75 then
        local extraSymptomCodes = {"A", "C", "F", "T", "Y", "U"} -- Agitated, Cramps, Fatigue, Tender Breasts, Crave Food, Sadness
        local randomSymptoms = symptomShuffle(extraSymptomCodes, 1, 3) -- returns 1 to 3 random symptoms
        for _, code in ipairs(randomSymptoms) do
            table.insert(datacodes, code)
        end
    end
    return datacodes
end

local function tableToString(tbl) -- Converts a table to a string
    local result = ""
    for _, v in ipairs(tbl) do
        result = result .. tostring(v)
    end
    return result
end

function CycleTrackerText.dataCodeFormatter(dataCodes)
    local datacodeString = tableToString(dataCodes)

    -- Limit to 4 characters, and pad if not all characters are used
    if #datacodeString > 4 then
        datacodeString = datacodeString:sub(1, 4)
    end

    local missing = 4 - #datacodeString
    if missing == 1 then
        datacodeString = datacodeString .. string.rep(" ", 2)
    elseif missing > 1 then
        local totalSpaces = math.ceil(missing * 2.5)
        datacodeString = datacodeString .. string.rep(" ", totalSpaces)
    end
    return datacodeString
end

return CycleTrackerText
