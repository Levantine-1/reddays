CycleTracker = {}

local function getPage1()
    local UID = CycleTracker.generateUID()
    local ID_Line = "ID: " .. UID
    local text_body = "Do not modify the ID or journal will stop updating.     Delete all entries to reuse.\
                 *** KEY *** \
H: Heavy        D: Discharge\
M: Medium   DC: Clear/White\
L: Light           DCW: Crmy Wht.\
S: Spotting    DEW: Egg White\
P: BC Pill        <3 :  ;)\
X: No Data\
                  *** PMS ***\
A: Agitated        F: Fatigue\
P: Sadness         T: TenderBrst. \
C: Cramps          Y: Crave Food"
    local text = ID_Line .. "\n" .. text_body
    return text
end

local function pageTemplate()
    local template = [[JULY 1993
1:     {{d1}}             |15:   {{d15}}         |29:   {{d29}} 
2:     {{d2}}             |16:   {{d16}}         |30:   {{d30}} 
3:     {{d3}}             |17:   {{d17}}         |31:   {{d31}} 
4:     {{d4}}             |18:   {{d18}}
5:     {{d5}}             |19:   {{d19}}
6:     {{d6}}             |20:   {{d20}}
7:     {{d7}}             |21:   {{d21}}
8:     {{d8}}             |22:   {{d22}}
9:     {{d9}}             |23:   {{d23}}
10:    {{d10}}            |24:   {{d24}}
11:    {{d11}}            |25:   {{d25}}
12:    {{d12}}            |26:   {{d26}}
13:    {{d13}}            |27:   {{d27}}
14:    {{d14}}            |28:   {{d28}}
]]
    return template
end

function CycleTracker.generateUID()
    local chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'
    local uid = ''
    for i = 1, 12 do
        local rand = ZombRand(#chars) + 1 -- ZombRand is 0-based, Lua strings are 1-based
        uid = uid .. chars:sub(rand, rand)
    end
    return uid
end

function CycleTracker.getJournal(player)
    local inv = player:getInventory()
    for i = 0, inv:getItems():size() - 1 do
        local item = inv:getItems():get(i)
        -- Check if it's a Journal (by type or display name)
        if item:getType() == "Journal" or item:getDisplayName() == "Journal" then
            return item
        end
    end
    return nil
end

function CycleTracker.readJournal(journal)
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

function CycleTracker.writeToJournal(journal, pageNum, text)
    return
end

local function testFunction()
    local player = getPlayer()
    local journal = CycleTracker.getJournal(player)
    -- CycleTracker.readJournal(journal)
    page1 = getPage1()
    if journal then
        print("Adding page 1 to journal.")
        journal:addPage(1, page1)
    end
    local year = getGameTime():getYear()
    local month = getGameTime():getMonth() + 1
    local day = getGameTime():getDay() + 1
    print("DATE: " .. month .. "/" .. day .. "/" .. year)
end
Events.EveryTenMinutes.Add(testFunction)



return CycleTracker