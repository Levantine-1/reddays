CycleTracker = {}


local function getInspirationalQuote()
    local quotes = {
        -- Quotes from International Women's Day 2024
        '"There is no limit to what we, as women, can accomplish." - Michelle Obama',
        '"A girl should be two things: Who and what she wants." - Coco Chanel',
        '"As long as you live, there`s something new every day." - Dolly Parton',
        '"Always be a first-rate version of yourself instead of a second-rate version of somebody else." - Judy Garland',
        '"Do not live someone else`s life and someone else`s idea of what womanhood is. Womanhood is you." - Viola Davis',
        '"Life is tough, my darling, but so are you." - Stephanie Bennett-Henry',
        '"Do not ever sell yourself short." - Jameela Jamil',
        '"I am grateful to be a woman. I must have done something great in another life." - Maya Angelou',
        '"I`ve never been interested in being invisible and erased." - Laverne Cox',
        '"I`d rather regret the things I`ve done than regret the things I haven`t done." - Lucille Ball',
        '"I am a woman and I get to define what that means." - Swati Sharma',
        '"Girls should never be afraid to be smart." - Emma Watson',
        '"You may be disappointed if you fail, but you are doomed if you don`t try." - Beverly Sills',
        '"If you don`t see a clear path for what you want, sometimes you have to make it yourself." - Mindy Kaling',
        '"The only one who can tell you `you can`t win` is you, and you don`t have to listen" - Dame Jessica Ennis-Hill',
        '"The most beautiful thing a woman can wear is confidence." - Blake Lively',
        '"I don`t get my inspiration from books or a painting. I get it from the women I meet." - Carolina Herrera',
        '"Alone we can do so little; together we can do so much." - Helen Keller',
        -- Quotes from UCSF Health - Inspire: Women to Women 2020
        '"A strong woman stands up for herself. A stronger woman stands up for others." - Unknown UCSF 2020',
        '"No one can make you feel inferior without your consent." - Eleanor Roosevelt',
        '"You`ve always had the power, my dear, you just had to learn it for yourself." - Glinda the Good Witch',
        '"A strong woman looks a challenge in the eye and gives it a wink" - Gina Carey',
        '"The more you love your decisions, the less you need others to love them." - Lisa Messenger',
        '"A queen is not afraid to fail. Failure is another stepping stone to greatness." - Oprah Winfrey',
        '"I figure if a girl wants to be a legend, she should go ahead and be one." - Calamity Jane',
        -- Quotes I thought were also good
        '"Life isn`t fair, but your reaction to injustice is what defines the content of your character" - Unknown',
        '"More good women have been lost to marriage than to war, famine, disease, and disaster. You have talent, darling. Don`t squander it." - Cruela De Vil' -- I thought this quote was so good it was worth breaking the character limit.
    }
    return quotes[ZombRand(#quotes) + 1]
end


local function getFrontPage(player)
    local playerName = player:getDescriptor():getForename() .. " " .. player:getDescriptor():getSurname()
    local nameLine = "Name: " .. playerName
    local inspirationalQuote = getInspirationalQuote()
    local text_body = "                 *** KEY *** \
H: Heavy        D: Discharge\
M: Medium   Dc: Clear/White\
L: Light           Dcw: Crmy Wht.\
S: Spotting    Dew: Egg White\
A: Agitated    F: Fatigue\
U: Sadness     Tb: TenderBrst.\
C: Cramps      Y: Crave Food\
X: No Data     Bc: BC Pill  Taken"
    local text = nameLine .. "\n" .. inspirationalQuote .. "\n" .. text_body
    return text
end

local function getBackPage()
    local UID = CycleTracker.generateUID()
    local ID_Line = "ID: " .. UID
    local text_body = "Do not modify the ID or journal will stop updating.     Delete all entries to reuse."
    local text = text_body
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
        if string.find(item:getDisplayName(), "Period Tracker") then -- Match substring because the appended year may vary
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
    frontPage = getFrontPage(player)
    if journal then
        print("Adding frontPage to journal.")
        journal:addPage(1, frontPage)
    end
    local year = getGameTime():getYear()
    local month = getGameTime():getMonth() + 1
    local day = getGameTime():getDay() + 1
    print("DATE: " .. month .. "/" .. day .. "/" .. year)
end
Events.EveryTenMinutes.Add(testFunction)



return CycleTracker