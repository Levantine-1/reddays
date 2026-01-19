-- local spawnRateMultiplier = SandboxVars.RedDays.hygiene_item_spawn_rate_multiplier or 1
local spawnRateMultiplier = 1 -- Default multiplier, can't seem to load spawnrate from sandbox vars

local hygieneItemPackages = {
    "RedDays.PantyLinerBox",
    "RedDays.SanitaryPadBox",
    "RedDays.TamponBox"
}

local hygieneItemIndividual = {
    "RedDays.Panty_Liner",
    "RedDays.Sanitary_Pad",
    "RedDays.Tampon"
}

-- List of distributions and their base rates and iterations
local distributions = { -- Format: {distributionName = {baseRate, iterations}}
    BathroomCabinet =       {4, 2},
    BathroomShelf =         {4, 2},
    BedroomDresser =        {2, 1},
    BedroomDresserClassy =  {2, 1},
    BedroomDresserRedneck = {2, 1},
    GigamartCosmetics =     {30, 4},
    HospitalRoomWardrobe =  {20, 4},
    OfficeDeskSecretary =   {2, 4},
    PharmacyCosmetics =     {30, 4},
    StripClubDressers =     {20, 2},
    WaitingRoomDesk =       {2, 2},
    BathroomCounterMotel =  {1, 2},
    GasStoreToiletries =    {30, 4},
    GigamartPaper =         {30, 4},
    GigamartBathing =       {40, 4},
    GigamartToiletries =    {40, 4},
    SafehouseMedical_Late = {20, 4},
    ChangeroomCounters =    {10, 2},
    SafehouseMedical =      {20, 2},
    HospitalRoomShelves =   {20, 3},
}

local function addHygieneItemsToDistribution(distName, baseRate, iterations)
    local items = ProceduralDistributions["list"][distName].items
    for i = 1, iterations do
        for _, item in ipairs(hygieneItemPackages) do
            local spawnRate = baseRate * spawnRateMultiplier
            table.insert(items, item)
            table.insert(items, spawnRate)
        end
    end
end

for distName, values in pairs(distributions) do
    local baseRate, iterations = values[1], values[2]
    addHygieneItemsToDistribution(distName, baseRate, iterations)
end

local function OnZombieDead(zombie)
    local dropPackages = SandboxVars.RedDays.hygiene_item_packages_spawn_on_corpses
    local dropItems = SandboxVars.RedDays.hygiene_items_spawn_on_corpses

    if not dropItems and not dropPackages then
        return
    end

    if not zombie or not zombie:isFemale() then
        return
    end

    local inventory = zombie:getInventory()
    if not inventory then
        return
    end

    local packagedItemChance = ZombRand(100)
    local numberOfItems = ZombRand(1, 3)
    local dropChanceRoll = ZombRand(100)

    if dropChanceRoll >= 90 then -- 10% chance the poor soul was on their period at time of death.
        if ZombRand(100) > 50 and dropItems then -- 50% chance to drop either a pad or tampon
            for i = 1, numberOfItems do
                inventory:AddItem("RedDays.Tampon")
            end
            if packagedItemChance > 95 and dropPackages then -- 5% chance to drop a tampon box
                inventory:AddItem("RedDays.TamponBox")
            end
        elseif dropItems then
            for i = 1, numberOfItems do
                inventory:AddItem("RedDays.Sanitary_Pad")
            end
            if packagedItemChance > 95 and dropPackages then -- 5% chance to drop a pad box
                inventory:AddItem("RedDays.SanitaryPadBox")
            end
        end
    elseif dropChanceRoll >= 50 then -- 50% chance to drop panty liners
        if dropItems then
            for i = 1, numberOfItems do
                inventory:AddItem("RedDays.Panty_Liner")
            end
        end

        if packagedItemChance > 98 and dropPackages then -- 2% chance to drop a panty liner box
            inventory:AddItem("RedDays.PantyLinerBox")
        end
    else
        return -- Drops nothing about 40% of the time
    end
end
-- Events.OnZombieDead.Add(OnZombieDead)

-- NOTE 2025-08-07: For some reason I can't get the sandbox var before the event is added. So the condition is checked after game start and on zombie death
-- if SandboxVars.RedDays.hygiene_items_spawn_on_corpses then
--     Events.OnZombieDead.Add(OnZombieDead)
-- end