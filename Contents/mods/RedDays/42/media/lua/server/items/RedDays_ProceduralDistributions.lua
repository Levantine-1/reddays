local spawnRateMultiplier = SandboxVars.RedDays.hygiene_item_spawn_rate_multiplier or 1

-- table.insert(ProceduralDistributions["list"]["BathroomCabinet"].items, "RedDays.PantyLinerBox");
-- table.insert(ProceduralDistributions["list"]["BathroomCabinet"].items, 2 * spawnRateMultiplier);

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
    if not zombie or not zombie:isFemale() then
        return
    end

    local inventory = zombie:getInventory()
    if not inventory then
        return
    end

    local packagedItemChance = ZombRand(100)
    local numberOfItems = ZombRand(1, 3)
    if ZombRand(100) >= 80 then -- 20% chance the poor soul was on their period at time of death.
        if ZombRand(100) > 50 then -- 50% chance to drop either a pad or tampon
            for i = 1, numberOfItems do
                inventory:AddItem("RedDays.Tampon")
            end
            if packagedItemChance > 75 then -- 25% chance to drop a tampon box
                inventory:AddItem("RedDays.TamponBox")
            end
        else
            for i = 1, numberOfItems do
                inventory:AddItem("RedDays.Sanitary_Pad")
            end
            if packagedItemChance > 75 then -- 25% chance to drop a pad box
                inventory:AddItem("RedDays.SanitaryPadBox")
            end
        end
    else -- 80% chance to drop panty liners
        for i = 1, numberOfItems do
            inventory:AddItem("RedDays.Panty_Liner")
        end
        if packagedItemChance > 95 then -- 5% chance to drop a panty liner box
            inventory:AddItem("RedDays.PantyLinerBox")
        end
    end
end
Events.OnZombieDead.Add(OnZombieDead)