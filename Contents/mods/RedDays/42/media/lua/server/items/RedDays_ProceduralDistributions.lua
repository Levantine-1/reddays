local spawnRateMultiplier = SandboxVars.RedDays.hygiene_item_spawn_rate_multiplier or 1

-- table.insert(ProceduralDistributions["list"]["BathroomCabinet"].items, "RedDays.PantyLinerBox");
-- table.insert(ProceduralDistributions["list"]["BathroomCabinet"].items, 2 * spawnRateMultiplier);

local hygieneItems = {
    "RedDays.PantyLinerBox",
    "RedDays.SanitaryPadBox",
    "RedDays.TamponBox"
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
        for _, item in ipairs(hygieneItems) do
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
