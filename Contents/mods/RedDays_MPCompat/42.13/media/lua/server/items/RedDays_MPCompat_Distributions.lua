-- Red Days MP Compatibility Add-on
-- This add-on spawns individual hygiene items in packs of 12 instead of boxes,
-- and adds period trackers to journal spawn locations.
-- This is a workaround for multiplayer issues with unpacking and crafting.

local spawnRateMultiplier = 1

-- Individual items - boxes contain 12 items each (panty liners have 24)
local hygieneItems = {
    {item = "RedDays.Panty_Liner", count = 24},
    {item = "RedDays.Sanitary_Pad", count = 12},
    {item = "RedDays.Tampon", count = 12},
}

-- Map of room types to container types that should spawn hygiene items
-- Format: roomType = { containerType = {baseChance, iterations}, ... }
local roomContainerMap = {
    bathroom = {
        medicine = {4, 2},      -- BathroomCabinet equivalent
        shelves = {4, 2},       -- BathroomShelf equivalent
        counter = {4, 2},
    },
    bedroom = {
        dresser = {2, 1},       -- BedroomDresser equivalent
        sidetable = {2, 1},     -- BedroomSideTable equivalent
    },
    motel = {
        counter = {1, 2},       -- BathroomCounterMotel equivalent
        medicine = {1, 2},
    },
    gigamart = {
        shelves = {30, 4},      -- GigamartCosmetics, GigamartToiletries
        counter = {30, 4},
        displaycase = {30, 4},
    },
    grocery = {
        shelves = {30, 4},
        grocerstand = {30, 4},
        counter = {20, 3},
    },
    pharmacy = {
        shelves = {30, 4},      -- PharmacyCosmetics
        counter = {30, 4},
        displaycase = {30, 4},
    },
    medical = {
        shelves = {20, 4},      -- HospitalRoomShelves, SafehouseMedical
        counter = {20, 3},
        medicine = {20, 3},
    },
    hospital = {
        wardrobe = {20, 4},     -- HospitalRoomWardrobe
        shelves = {20, 3},      -- HospitalRoomShelves
        medicine = {20, 3},
    },
    office = {
        desk = {2, 4},          -- OfficeDeskSecretary
    },
    stripclub = {
        dresser = {20, 2},      -- StripClubDressers
    },
    waitingroom = {
        desk = {2, 2},          -- WaitingRoomDesk
    },
    gasstore = {
        shelves = {30, 4},      -- GasStoreToiletries
        counter = {30, 4},
    },
    conveniencestore = {
        shelves = {30, 4},
        counter = {20, 3},
    },
    cornerstore = {
        shelves = {30, 4},
        counter = {20, 3},
        overhead = {20, 2},
    },
    changeroom = {
        counter = {10, 2},      -- ChangeroomCounters
    },
    clothesstore = {
        counter = {10, 2},
    },
}

-- Distributions where journals/notebooks spawn - we'll add period trackers here
local journalDistributions = {
    BookstoreMisc =         {8, 2},
    CratePaper =            {6, 1},
    LibraryDesk =           {8, 2},
    LivingRoomShelf =       {6, 1},
    LivingRoomShelfClassy = {6, 1},
    LivingRoomShelfRedneck ={6, 1},
    MagazineRackMixed =     {6, 1},
    OfficeDesk =            {6, 1},
    OfficeDeskHome =        {6, 1},
    SchoolLockers =         {6, 1},
    StoreShelfMechanics =   {4, 1},
    WardrobeChild =         {6, 1},
    ClassroomDesk =         {6, 1},
    ClassroomMisc =         {6, 1},
    ClassroomShelves =      {8, 2},
    CrateOfficeSupplies =   {6, 1},
    BedroomDresser =        {4, 1},
    BedroomSideTable =      {4, 1},
}

-- Add period trackers to procedural distributions (single items, no stacking needed)
local function addPeriodTrackersToDistribution(distName, baseRate, iterations)
    local dist = ProceduralDistributions["list"][distName]
    if not dist or not dist.items then 
        return 
    end
    local items = dist.items
    
    for i = 1, iterations do
        local spawnRate = baseRate * spawnRateMultiplier
        table.insert(items, "RedDays.Period_Tracker")
        table.insert(items, spawnRate)
    end
end

-- Add period trackers to journal spawn locations
for distName, values in pairs(journalDistributions) do
    local baseRate, iterations = values[1], values[2]
    addPeriodTrackersToDistribution(distName, baseRate, iterations)
end
print("[RedDays MP Compat] Period trackers added to journal spawn locations")

-- Use OnFillContainer to add hygiene items in proper quantities (12/24 per "box equivalent")
local function onFillContainer(roomName, containerType, container)
    if not container then
        return
    end
    -- Normalize room name to lowercase for matching
    local roomLower = string.lower(roomName or "")
    local containerLower = string.lower(containerType or "")
    
    -- Find matching room in our map
    local roomData = nil
    for roomKey, containers in pairs(roomContainerMap) do
        if string.find(roomLower, roomKey) then
            roomData = containers
            break
        end
    end
    
    if not roomData then return end
    
    -- Find matching container in that room
    local distData = nil
    for containerKey, data in pairs(roomData) do
        if string.find(containerLower, containerKey) then
            distData = data
            break
        end
    end
    
    if not distData then return end
    
    local baseChance = distData[1]
    local iterations = distData[2]
    
    -- Roll for each iteration and each item type
    for i = 1, iterations do
        for _, itemData in ipairs(hygieneItems) do
            -- Roll against the base chance (same as packages would have)
            local roll = ZombRand(100)
            if roll < baseChance then
                -- Add items in quantity (12 for pads/tampons, 24 for panty liners)
                for j = 1, itemData.count do
                    container:AddItem(itemData.item)
                end
            end
        end
    end
end

Events.OnFillContainer.Add(onFillContainer)
print("[RedDays MP Compat] Initialized - individual hygiene items (12/24-packs) will spawn in containers")
