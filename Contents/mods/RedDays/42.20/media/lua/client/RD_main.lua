require "RD_game_api"
require "RD_cycle_manager"
require "RD_cycle_irregularity"
require "RD_cycle_tracker_logic"
require "RD_effects_manager"
require "RD_hygiene_manager"
require "RD_effects_pms"
require "RD_hotwater"
require "RD_tss_manager"
require "RD_moodles"
require "RD_debugger"
require "RD_config"
-- In-game SP/MP self-test (rd.mptest.*), off unless RD_Config.selftest (shared/RD_config.lua).
-- Its tracer wraps the vanilla action methods before the intercepts below save them as
-- "original", so it still sees every call. RD_Config can be nil if PZ wasn't fully restarted
-- after RD_config.lua was added (it keeps the file list from launch), so never index it bare.
if RD_Config and RD_Config.selftest then require "RD_selftest" end

-- Gender check
local function isValidGenderCheck()
    if not SandboxVars.RedDays.affectsAllGenders then
        if not RD_zapi.isFemale() then
            return false
        end
    end
    return true
end

-- ================= GLOBAL EVENT HOOKS =================
-- Sync modData to server in multiplayer so it persists across sessions
local function transmitModDataToServer()
    if isClient() then
        local player = getPlayer()
        if player then
            player:transmitModData()
        end
    end
end

local function initializePlayerData()
    RD_CycleManager.LoadPlayerData()
    RD_CycleTrackerLogic.LoadPlayerData()
    RD_EffectsPMS.LoadPlayerData()
    RD_TSSManager.LoadPlayerData()
    RD_HygieneManager.LoadPlayerData()
    RD_HygieneManager.grantStarterHygieneItems()
    RD_moodles.LoadPlayerData()
    transmitModDataToServer() -- Sync initial/generated data to server
end

local function OnGameStart()
    if not isValidGenderCheck() then return end
    initializePlayerData()
end
Events.OnGameStart.Add(OnGameStart)

local function OnCreatePlayer(playerIndex, player) -- When player is created or respawned
    if playerIndex ~= 0 then return end
    if not isValidGenderCheck() then return end
    initializePlayerData()
end
Events.OnCreatePlayer.Add(OnCreatePlayer)

-- ================= TIMED EVENT HOOKS =================
local function EveryHours()
    if not isValidGenderCheck() then return end
    -- Hourly status report in console.txt; the Workshop page's bug-report steps point players at it.
    RD_CycleDebugger.printWrapper()
end
Events.EveryHours.Add(EveryHours)

local function EveryTenMinutes()
    if not isValidGenderCheck() then return end
    RD_CycleIrregularity.checkStressCause(RD_modData.ICdata.currentCycle)
    transmitModDataToServer() -- Periodically sync modData to server for persistence
end
Events.EveryTenMinutes.Add(EveryTenMinutes)

local function EveryOneMinute()
    if not isValidGenderCheck() then return end
    local cycle = RD_CycleManager.tick(1)
    RD_CycleIrregularity.checkTraumaCause(cycle)
    RD_EffectsManager.determineEffects(cycle)
    RD_HotWater.EveryOneMinute()
    RD_EffectsPMS.applyPMSEffectsMain()
    RD_TSSManager.EveryOneMinute(cycle)
    RD_moodles.mainLoop()
end
Events.EveryOneMinute.Add(EveryOneMinute)

local function OnClothingUpdated(player)
    if not isValidGenderCheck() then return end
    RD_moodles.OnClothingUpdated(player)
end
Events.OnClothingUpdated.Add(OnClothingUpdated)

local function EveryDays()
    if not isValidGenderCheck() then return end
    RD_CycleIrregularity.applyDailyWeightCause(RD_modData.ICdata.currentCycle)
end
Events.EveryDays.Add(EveryDays)

local function OnPlayerUpdate(player) -- This is very expensive, make sure everything in here is optimized and only runs when necessary.
    if not isValidGenderCheck() then return end
    RD_TSSManager.ApplyFeverPressure(player)
    if RD_CycleDebugger and RD_CycleDebugger.ApplyDebugStatClamps then
        RD_CycleDebugger.ApplyDebugStatClamps(player)
    end
end
Events.OnPlayerUpdate.Add(OnPlayerUpdate)

-- ================= INTERCEPT FUNCTIONS =================
local o_ISUnequipAction_perform = ISUnequipAction.perform
function ISUnequipAction:perform()
    if isValidGenderCheck() then
        RD_moodles.ISUnequipAction_perform(self)
        RD_CycleTrackerLogic.ISUnequipAction_perform(self)
    end
    o_ISUnequipAction_perform(self)
end

local o_ISWearClothing_perform = ISWearClothing.perform
function ISWearClothing:perform()
    if isValidGenderCheck() then
        RD_moodles.ISWearClothing_perform(self)
        RD_CycleTrackerLogic.ISWearClothing_perform(self)
    end
    o_ISWearClothing_perform(self)
end

local o_ISWashYourself_perform = ISWashYourself.perform
function ISWashYourself:perform()
    if isValidGenderCheck() then
        RD_moodles.ISWashYourself_perform()
    end
    o_ISWashYourself_perform(self)
end

local o_ISTakePillAction_perform = ISTakePillAction.perform
function ISTakePillAction:perform()
    if isValidGenderCheck() then
        RD_EffectsPMS.ISTakePillAction_perform(self)
    end
    o_ISTakePillAction_perform(self)
end

-- Eat/drink hooks go on perform(), NEVER complete(). In B42 a timed action's complete() (the
-- half that applies the effect) runs only on the server in MP, and the server never loads
-- client/ Lua -- coop-console.txt shows only RD_server_commands.lua loading. A complete() hook
-- works in SP and silently never fires in MP: that is why antibiotic doses never registered and
-- TSS had to be disabled in multiplayer. perform() runs client-side in both SP and MP, and once
-- per finished action, so SP doesn't double-count. mp_sync_spec.lua fails on a complete() hook.
--
-- Antibiotics are Type=Food, consumed via ISEatFoodAction like any other food item.
local o_ISEatFoodAction_perform = ISEatFoodAction.perform
function ISEatFoodAction:perform()
    if isValidGenderCheck() then
        RD_TSSManager.registerTreatmentFromItem(self.item, "ISEatFoodAction")
        -- pcall-wrapped so an exception in our own food-PMS logic (a mistagged item, an
        -- unanticipated composite meal shape, anything) can NEVER skip the vanilla action
        -- below -- confirmed the hard way once already (see RD_effects_pms.lua).
        local ok, err = pcall(RD_EffectsPMS.ISEatFoodAction_perform, self)
        if not ok then
            print("[RedDays] food-PMS effect skipped for this item (see error): " .. tostring(err))
        end
    end
    return o_ISEatFoodAction_perform(self)
end

-- Milk (Base.Milk/MilkBottle/Milk_Personalsized) is a FluidContainer item, drunk via
-- ISDrinkFluidAction rather than eaten via ISEatFoodAction -- confirmed via vanilla source
-- (media/lua/shared/TimedActions/ISDrinkFluidAction.lua). This is its only consumption path.
--
-- In MP the server drinks the fluid during the action, a little ahead of the client. When it
-- drains the container, the client's isValid() (fluidContainer:isEmpty()) fails before the action
-- finishes, so the client gets stop() instead of perform() -- seen in a hosted game: a whole carton
-- never registered, a partial one did. So a drink also counts on stop(), but only once the
-- container really is empty (a cancelled drink leaves fluid behind), and at most once per action.
local function creditDrink(action)
    if action.rdDrinkCredited then return end
    action.rdDrinkCredited = true
    local ok, err = pcall(RD_EffectsPMS.ISDrinkFluidAction_perform, action)
    if not ok then
        print("[RedDays] food-PMS effect skipped for this item (see error): " .. tostring(err))
    end
end

local function drankContainerDry(action)
    local container = action.fluidContainer
    if not container then return false end
    local ok, empty = pcall(function() return container:isEmpty() end)
    return ok and empty == true
end

local o_ISDrinkFluidAction_perform = ISDrinkFluidAction.perform
function ISDrinkFluidAction:perform()
    if isValidGenderCheck() then
        creditDrink(self)
    end
    return o_ISDrinkFluidAction_perform(self)
end

local o_ISDrinkFluidAction_stop = ISDrinkFluidAction.stop
function ISDrinkFluidAction:stop()
    if isValidGenderCheck() and drankContainerDry(self) then
        creditDrink(self)
    end
    return o_ISDrinkFluidAction_stop(self)
end
