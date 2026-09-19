# RedDays — Claude reference

Project Zomboid mod adding a menstrual cycle mechanic. This file exists so a fresh session doesn't have to re-derive architecture, wiring order, and hard-won PZ engine gotchas from scratch. Verified against the actual repo state on 2026-09-08 — if something here looks stale, trust the live files over this doc and fix the doc.

## Repo layout

```
Contents/mods/RedDays/{42, 42.13, 42.17, 42.18, 42.20}/   one full copy per supported PZ build
notes/apiDocumentation/                                    vanilla PZ API references (see below)
notes/42_13_MigrationGuide/                                prior build-migration notes + registries testmod example
README.md                                                  user-facing feature list, changelog, FAQ
workshop.txt                                                Steam Workshop description
```

**Version-folder convention**: new features land ONLY in the newest folder (`42.20` currently — check `mod.info`'s `pzversion` in each folder if unsure which is newest). Confirmed repo convention: e.g. TSS only ever existed in `42.18`+, never backported. Bugfixes sometimes get backported to older folders; features don't. Each folder is a full standalone copy — there's no shared/symlinked code between them.

The bare `42` folder is a legacy/stale snapshot with different (non-`RD_`-prefixed) file names (`main.lua` not `RD_main.lua`, etc.) and a smaller feature set — don't assume parity with the others, and don't assume a fix made in `42.20` applies there.

`notes/apiDocumentation/` currently holds: `Class_BodyDamage.txt`, `Class_BodyLocationGroup.txt`, `Class_BodyPart`, `Class_CharacterSmartTexture.txt`, `Class_InventoryItem.txt`, `Class_isoGameCharacter.txt`, `Class_stats.txt`, `Class_Literature`, `Lua_EventHooks`, `ModDoc_MoodleFrameWork.txt`, `RedDays_Debug_API_42_18.txt`, `ZombieDocs`. Check here before web-searching for vanilla API behavior.

## Architecture (as of 42.20)

All client Lua lives in `media/lua/client/`, one `RD_*.lua` file per concern:

| File | Responsibility |
|---|---|
| `RD_main.lua` | Wiring hub — all `require`s, all `Events.*` registration, all vanilla-method intercepts. Read this first in any new session. |
| `RD_game_api.lua` | `RD_zapi` — thin wrapper layer over vanilla PZ API calls (`getPlayer`, `getModData`, `getBodyPart`, worn-item lookups, etc.). Other files should go through this rather than calling vanilla API directly, for consistency. |
| `RD_cycle_manager.lua` | Core phase/duration engine — rolls cycle length and phase durations from sandbox bounds, `tick()` advances `phase_minutes_remaining` and transitions phases. |
| `RD_cycle_irregularity.lua` | Health-driven phase delays layered on top of the cycle manager's random roll: weight traits and a trauma/low-HP delay extend the **follicular** phase; chronic stress (sampled every ten minutes into `ICdata.chronicStressScore`) extends the **luteal** phase. Each phase has its own capped `add*Minutes` helper. |
| `RD_hygiene_manager.lua` | Hygiene item saturation — plain integer `condition` (10→1), decremented on a timer during the red phase; also owns blood/dirt stain spreading on body + clothing. |
| `RD_effects_manager.lua` | Registers/unregisters the red-phase consumption tick and the non-red-phase discharge tick based on current cycle phase. |
| `RD_effects_pms.lua` | PMS symptom effects (agitation/cramps/fatigue/tender breasts/food cravings/sadness), painkiller suppression, and `FOOD_PMS_REDUCTIONS` (the comfort-food list — milk/yoghurt/cheese/oatmeal/peanut-butter/banana plus a chocolate-dessert tier and a lower other-sweets tier; check the table itself for the current item list rather than trusting a stale copy here). |
| `RD_hotwater.lua` | Hot water bottle heat model — the engine heats any FluidContainer item but cools it far too fast, so this tracks heat on a half-life curve in the item's own modData, adopts the engine's value while something is actively heating it, and writes the result back with `setItemHeat`. Feeds a third PMS reduction source. |
| `RD_tss_manager.lua` | Toxic Shock Syndrome — stage 0-4 progression, antibiotic treatment, fever/HP effects. Largest, most stateful subsystem. |
| `RD_moodles.lua` | Drives the 8 MoodleFramework moodles (`Dirty*`/`Bloody*` per item type, `Leak`, `TSSInfection`) from item condition / `LeakLevel` / TSS stage. |
| `RD_cycle_tracker_logic.lua` / `RD_cycle_tracker_text.lua` | The in-game "Period Tracker" book — logs a day-code (H/M/L/S flow intensity + PMS letter codes) into an in-item calendar on unequip/wear. |
| `RD_debugger.lua` | The `rd.*` console debug API + `RD_CycleDebugger.printWrapper()`, the full-state dump fired once per in-game hour. |
| `RD_selftest.lua` | In-game SP/MP self-test, `rd.mptest.run()` / `rd.mptest.actions()`. Loaded only when `RD_Config.selftest` is true; its server half (`rdTestProbe`, `rdTestGiveItems`, a `complete()` tracer) sits in `RD_server_commands.lua` behind the same flag. |

Shared:
- `media/lua/shared/RD_config.lua` — `RD_Config.selftest` build switch, read by client and server. **Set it to `false` before a Workshop upload.**
- `RD_Config.verboseLog` (same file, default `false`) gates every non-debugger diagnostic print (load banners, cycle/TSS/PMS state chatter, in-fiction TSS `notifyPlayer` messages) through `RD_zapi.log(msg)` (client, `RD_game_api.lua`) or a matching local `rdLog(msg)` (server, `RD_server_commands.lua` — server never loads client Lua). `RD_debugger.lua`'s `rd.*` console commands and genuine error/warning prints (`RD_main.lua`'s pcall failure, `BodyLocations.lua`'s nil warning, the self-test's own `[RD-TEST]` lines) are never gated by it — flip it on only when chasing a bug that needs more than `rd.*` shows.
- `media/lua/shared/RD_stains.lua` — `RD_Stains.apply`, the groin → thighs → shins → feet stain spread. The client hygiene code and the server's `applyStains` both call it, so they stain identically.

Server-side: `media/lua/server/RD_server_commands.lua` (the MP sync commands clients send: `updateSanitaryItem`, `applyBodyStiffness`, `applyPMSStats`, `applyStains`, `applyTSSStats`), `media/lua/server/items/RedDays_ProceduralDistributions.lua` (corpse loot spawning).

Item/model scripts: `media/scripts/clothing/item{Tampon,SanitaryPad,PantyLiner,CycleJournal}.txt` + matching `model*.txt` files. Recipes in `media/scripts/RedDays_recipes.txt`.

## Event wiring (from `RD_main.lua`)

`require` order matters (dependency order between managers) — currently: `RD_game_api` → `RD_cycle_manager` → `RD_cycle_irregularity` → `RD_cycle_tracker_logic` → `RD_effects_manager` → `RD_hygiene_manager` → `RD_effects_pms` → `RD_tss_manager` → `RD_moodles` → `RD_debugger` → `RD_config` (→ `RD_selftest` when the flag is on, before the intercepts, so its tracer is what they save as "original").

A local `isValidGenderCheck()` (female, or `SandboxVars.RedDays.affectsAllGenders`) gates almost every hook below — reuse this pattern for any new hook rather than duplicating the check.

Registered events: `OnGameStart` / `OnCreatePlayer` → `initializePlayerData()` (loads every manager's per-player data, grants starter hygiene items if enabled); `EveryHours` → the status report (`printWrapper`); `EveryTenMinutes` → `RD_CycleIrregularity.checkStressCause` + periodic modData sync to server; `EveryOneMinute` → the main tick chain (`RD_CycleManager.tick(1)` → `RD_CycleIrregularity.checkTraumaCause` → `RD_EffectsManager.determineEffects` → `RD_HotWater.EveryOneMinute` → `RD_EffectsPMS.applyPMSEffectsMain` → `RD_TSSManager.EveryOneMinute` → `RD_moodles.mainLoop`); `EveryDays` → `RD_CycleIrregularity.applyDailyWeightCause`; `OnPlayerUpdate` → TSS fever pressure (runs every frame — keep this cheap).

Six vanilla methods are intercepted (original saved, called after the mod's hook), all on `perform()`: `ISUnequipAction`, `ISWearClothing`, `ISWashYourself`, `ISTakePillAction`, `ISEatFoodAction` (TSS antibiotic dose + food PMS), `ISDrinkFluidAction` (milk PMS). `ISDrinkFluidAction:stop()` is also hooked, for a drink that empties its container (see the gotcha below). Never hook `complete()` from client code.

## Data model (`RD_modData.ICdata`, i.e. `player:getModData().ICdata`)

- `currentCycle` — the active cycle table: `current_phase`, `phase_minutes_remaining`, one `<phase>Phase_duration_mins` per phase, `cycle_duration_mins`, health/PMS-effect targets, `pms_*` symptom flags, `traumaDelayAppliedThisCycle`. Built by `RD_CycleManager.newCycle()`; see that function (or `CYCLE_DEFAULTS` in `RD_debugger.lua`) for the exact current field list rather than trusting a stale copy here.
- `tss` — TSS state (stage, exposure/severity minutes, wear_minutes, source_active/type/item_id, recovery + antibiotic-bank fields). Full field list: `TSS_DEFAULTS` in `RD_debugger.lua`.
- `cSIHDC_counter` — hygiene item condition-decrement accumulator.
- `LeakLevel` / `LeakSwitchState` — leak moodle/stain state.
- `chronicStressScore` — 0-100 chronic stress accumulator, deliberately outside `currentCycle` so it survives the end-of-cycle regeneration.
- `pmsSymptoms`, `cycleDelayed`, `calendar` / `calendarMonth` / `journalID` (tracker book), `pill_recently_taken` / `pill_effect_active` / `pill_effect_counter` (painkiller), `food_pms_*` (food relief), `hygieneStarterItemsGranted`.

**Save-compatibility rules** (enforced by `tests/lua/suites/save_compat_spec.lua`, which loads the real ICdata shapes from the legacy `42` build through 42.20 in SP and as an MP client):
- Every key the code reads must get a default on load (`x = x or default` in a `LoadPlayerData`). A missing key is the normal case for an older save.
- Only add a field to `RD_CycleManager.isCycleValid`'s required list when regenerating everyone's cycle is intended. That list is what turns an outdated cycle (e.g. the legacy day-based one) into a fresh one.
- Renamed fields need a migration in `LoadPlayerData`, like TSS `untreated_minutes` → `severity`.

## Sandbox options

`media/sandbox-options.txt` (48 options currently, all under `page = RedDays`) + matching `Sandbox_RedDays_<name>` / `Sandbox_RedDays_<name>_tooltip` entries in `media/lua/shared/Translate/EN/Sandbox.json`. **PZ sandbox options don't support floats** — if you need fractional precision, encode as an integer at 10x/100x scale and divide in Lua (a `_x10`-suffixed option existed for this during the fluid-container experiment; pattern is gone from the current file but is the right move if it comes up again). Note `menstrual_cycle_duration_lowerBound`'s `min = -100` is a pre-existing oddity (a negative duration bound makes no real sense) — don't "fix" it without being asked, it may be intentional or just untouched cruft.

## Translation files

`media/lua/shared/Translate/EN/{Sandbox,Moodles,ItemName,RecipeName,IG_UI}.json`. `RecipeName.json` didn't exist until recently (all 7 of this mod's recipes were silently untranslated, showing raw script names in-game) — if a future version-folder copy is missing it again, that's the same latent bug recurring, not a new one.

## PZ engine gotchas confirmed via direct research (expensive to relearn — read before re-investigating)

- **Item script `Tags`**: always lowercase, always `base:`-prefixed (`Tags = base:isfirefuel;base:omitemptyfromname`), confirmed against dozens of vanilla examples in `media/scripts/generated/`.
- **`FluidContainer` item component is a confirmed dead end** for tracking hygiene-item saturation — fully investigated and reverted; see README.md's "Investigated and abandoned: real fluid containers for hygiene items" section for the three specific blocking reasons (50mL capacity floor via `PZMath.max(f, 0.05f)`, `canAddFluid()`/`addFluid()` silently no-op'ing whenever the player-facing lock flags are set — the exact flags needed to keep players out also blocked the mod's own writes, and an unconditional `getName()` override with no way to suppress it). Read that section in full before ever reconsidering this approach — do not re-attempt it starting from a blank slate.
- **MoodleFramework default value→level thresholds**: `setThresholds(0.1,0.2,0.3,0.4, 0.6,0.7,0.8,0.9)`, confirmed against the installed mod's own `MF_ISMoodle.lua`. This mod's `0.42` "clear" sentinel is this mod's own convention, not a framework constant.
- **`syncItemFields(player, item)` is a real two-argument global** (`LuaManager$GlobalObject.syncItemFields(IsoPlayer, InventoryItem)`, confirmed via bytecode). `RD_server_commands.lua` calls it correctly — don't "fix" it into an instance method.
- **`hasTag` only accepts an `ItemTag` object**, never a string: `InventoryItem`/`Food` expose only `hasTag(ItemTag)` and `hasTag(ItemTag[])`. `item:hasTag("fishmeat")` throws "No implementation found for function" for any item; use `item:hasTag(ItemTag.FISH_MEAT)`. `check_api_contract.py` hard-fails on a string literal here.
- **`getExtraItems()` / `getSpices()` return full-type strings** (`ArrayList<String>`), not items — calling a method on an element throws "Object tried to call nil". Use the string-taking globals vanilla uses on them: `hasItemTag(String, ItemTag)`, `getItemFoodType(String)`, `isItemFood(String)`. Serving a pot into bowls copies these lists (`InheritFood` → `Food.copyExtraItems`).
- **A timed action's `complete()` runs only on the server in B42 MP; client code must hook `perform()`.** The server never loads `client/` Lua (a hosted game's `coop-console.txt` shows only `RD_server_commands.lua` loading), so a client `complete()` hook works in SP and silently never fires in MP. This is why antibiotic doses never registered and TSS was force-disabled in MP until 2026-09. In SP the engine runs both locally (the in-game trace shows `perform()` entered first), so hook only one. `mp_sync_spec.lua` fails on any client `IS*:complete` override.
- **In MP, a drink that empties its container ends with `stop()` on the client, not `perform()`.**
  - The server drinks the fluid during the action, slightly ahead of the client.
  - Once the container is empty, `ISDrinkFluidAction:isValid()` (`fluidContainer:isEmpty()`) fails on the client before the action finishes.
  - Seen in a hosted game (2026-09-17): a whole milk carton never registered, a partial one did.
  - `RD_main.lua` also credits the drink on `stop()` when the container is empty, at most once per action.
  - Eating doesn't have this problem: `ISEatFoodAction:isValid()` calls `forceComplete()` when the item is gone.
- **In singleplayer only client→server commands loop back.** `sendClientCommand` → `SinglePlayerClient` → `OnClientCommand` works, and `server/` Lua loads in SP. But **the `sendServerCommand` global is a no-op in SP**: both overloads return unless `GameServer.serverZ` (confirmed via bytecode), so a server reply is silently lost. Deliver SP replies another way: client and server share one Lua state in SP, so the self-test's server handler calls the client reply handler (`RD_SelfTest.onServerCommand`) directly. Found the hard way: the self-test probe was answered but never received in SP. For server-side admin checks, use vanilla's `player:getRole():hasCapability(Capability.AddItem)`.
- **Character stats and body damage are server-authoritative in MP** (in-game proof, 2026-09-15: a client's direct `stats:set()` was reverted within seconds, while a sync command reached the server). Any client-side stat/HP/stiffness change must also go to the server.
  - The pattern (`applyTSSStats`, `applyPMSStats`): apply locally for instant feedback, collect a `pending` table, flush one command per minute.
  - Send **steps and targets, not final values**, so the server applies them to its own live value.
  - In game this applied once, not twice (client rise = server rise).
  - **Body and clothing stains:** the hosted self-test showed client-only stains never reaching the server. `applyStains` fixes it: the server re-runs `RD_Stains.apply`, then syncs the way vanilla washing does:
    - `syncItemFields(player, item)` for each stained garment
    - `syncVisuals(player)`
    - `sendHumanVisual(player)`
- **TSS warnings are console-only.** `RD_tss_manager.lua`'s `notifyPlayer` prints (now behind `verboseLog`); the character never says them. The only in-game TSS signal is the `TSSInfection` moodle. The one `Say()` in the mod is in the self-test.
- **`InventoryItem.itemHeat` is a base-class field, and the engine only ticks it for items carrying a `FluidContainer` component** (`InventoryItem.update`, confirmed via bytecode) — item type is irrelevant, so a non-food item heats fine. Heating also needs `base:cookable`, or `base:cookablemicrowave` while the container's type is `microwave`. Temperature comes from `ItemContainer.getTemprature()`, which covers stoves, ovens, BBQs and campfires.
  - `getItemHeat()` / `setItemHeat()` on any item; `getHeat()` is the `Food`/`DrainableComboItem` accessor. 1.0 is ambient, vanilla treats ~1.6 as cooked.
  - Vanilla cools far too fast for a hot water bottle, so `RD_hotwater.lua` keeps its own value. Because `setItemHeat` writes into the same field the engine reads, the module compares against **what it last wrote** (`rdHeatWritten`) to tell "an oven is heating this" from "that's my own number coming back".
- **The mod never injures the player.** Periods show through moodles and stains: nothing touches the groin's bleeding state, and bandages are not a pad substitute (removed 2026-09; folding a bandage into a pad is a possible future feature). TSS still reads a *real* groin wound when deciding if a pad or liner is an infection source.
- **The game fades the sleeping-tablet effect (TSS blur) by itself every frame and clears it during sleep** (`IsoGameCharacter.updateInternal`, confirmed via bytecode). TSS only has to stop pushing it up. Note: the user reports the TSS blur has never actually been visible in game (open todo in README), so don't advertise it or assume the effect renders. The harness has no such fade, so tests that care apply one.
- **`Events.X.Add` never deduplicates** (plain `ArrayList.add`), and **`Events.X.Remove` strips only the first match**. Re-adding the same handler makes it fire twice per event and leaves an orphan after one `Remove`. Guard registration with a state flag, as `RD_effects_pms.lua`'s countdowns do.
  - **Dispatch (`Event.trigger`) walks the live list by index** and advances only if the handler it just ran is still registered (confirmed via bytecode).
  - So a handler added during dispatch runs in that same dispatch. That's why `RD_effects_manager`'s set-the-flag-when-it-runs registration is safe.
  - A self-removing orphan duplicate survives one extra dispatch.
  - `tests/lua/harness/events.lua` mirrors this. An earlier snapshot-based harness reported a double registration that can't happen in game.
- **`ZombRand` conventions are mixed in this codebase** — some call sites use `ZombRand(min, max)` (max-exclusive, two-arg), some use `ZombRand(n)` (0-based, need `+1` for Lua's 1-based indexing/ranges), one uses `ZombRand(range + 1)` to make an inclusive roll. Check what a specific call site is actually doing rather than assuming a single global convention.
- **A Java-bound "static class" Lua object (e.g. `Fluid`, `FluidType`) calling a nonexistent/mis-signatured method is not reliably caught by `pcall`** in this build's Kahlua VM — confirmed via a real in-game crash where a `pcall`-wrapped call still crashed the whole event dispatch uncaught. Guard with `type(obj[method]) == "function"` before calling, rather than trusting `pcall` alone, when the method's existence/signature isn't independently verified.

## Bytecode research technique (reusable — PZ is installed locally)

`D:\SteamLibrary\steamapps\common\ProjectZomboid\projectzomboid.jar` contains all compiled Java classes. No `javap`/JDK is available in the bundled `jre64`. **Use `tools/pz_bytecode.py`** (reads the jar directly; set `PZ_JAR` to override the path):

```
python tools/pz_bytecode.py methods  zombie/characters/BodyDamage/BodyPart        # names + overload signatures
python tools/pz_bytecode.py disasm   zombie/Lua/Event trigger                     # calls/fields/branches in one method
python tools/pz_bytecode.py refs     zombie/characters/IsoGameCharacter leepingTablet   # which methods touch X
python tools/pz_bytecode.py strings  'zombie/Lua/LuaManager$GlobalObject' sendServer    # does a Lua global exist
```

Lua globals live in `zombie/Lua/LuaManager$GlobalObject`. Useful classes found so far:
- **Timed actions:** `zombie/characters/CharacterTimedActions/LuaTimedActionNew`, `zombie/core/NetTimedAction`
- **Singleplayer networking:** `zombie/spnetwork/SinglePlayerClient` / `SinglePlayerServer`
- **Events:** `zombie/Lua/Event`
- **Character and body:** `zombie/characters/IsoGameCharacter`, `.../BodyDamage/BodyPart`, `.../BodyDamage/BodyDamage`
- **Roles:** `zombie/characters/Role`, `zombie/characters/Capability`

`unzip -l projectzomboid.jar | grep <Name>` finds a class's path.

`media/scripts/generated/` (vanilla item/fluid/trait script dumps) and `media/lua/` (vanilla Lua source, all of it present and readable) are both directly available in the install and have repeatedly been more reliable than web sources — `pzwiki.net` blocked several fetch attempts.

## Engine API cheat sheet (all confirmed in vanilla Lua or bytecode, 2026-09)

**Server-side sync after changing a player or item** (copy vanilla's pattern for the same kind of change):

| Change | Sync call(s) | Vanilla example |
|---|---|---|
| item fields (condition, name, blood, dirt, wetness) | `syncItemFields(player, item)` | `ISWashClothing:complete` |
| worn clothing visuals | `syncVisuals(player)` | `ISWashClothing:complete` |
| body blood/dirt | `sendHumanVisual(player)` (+ `syncVisuals`) | `ISWashYourself:complete`, `server/ClientCommands.lua` health cheat |
| a body part (bleeding, bandage, stiffness…) | `syncBodyPart(bodyPart, 0xFFFFFFFFFFF)` | `server/ClientCommands.lua` `onHealthCheatCurrentPlayer` |
| character stats | `syncPlayerStats(player, flagBits)` / `sendPlayerStatsChange` | `ISApplyBandage:complete` (panic) |
| pill effects | `sendPlayerEffects(player)` | `ISTakePillAction:complete` |
| inventory add/remove | `sendAddItemToContainer(inv, item)` / `sendRemoveItemFromContainer(inv, item)` | `server/ClientCommands.lua` |

This mod uses its own commands with local apply + server replay (`applyTSSStats`, `applyPMSStats`, `applyStains`, `applyBodyStiffness`, `updateSanitaryItem`). All are proven in a hosted game.

**Other confirmed calls:**
- **Server → client:** `sendServerCommand(player, module, command, args)`. The client handler is `Events.OnServerCommand(module, command, args)`. It's a no-op in SP (see gotchas).
- **Admin check (server):** `player:getRole():hasCapability(Capability.AddItem)`, as in `server/ClientCommands.lua`.
- **Session state:** `isClient()`, `isServer()`, `isCoopHost()`, `isDebugEnabled()`. A hosted game is `isClient()=true` on the host's client, with a separate server process.
- **Files** in `Zomboid/Lua/`:
  - write: `getFileWriter(name, createIfNull, append)` → `:write(s)`, `:close()`
  - read: `getFileReader(name, createIfNull)` → `:readLine()` (nil at EOF), `:close()`
- **Clock:** `getTimestampMs()` is the real-time clock, fine for OnTick-based waits.
- **Bandages:** `bodyDamage:SetBandaged(partIndex, on, life, alcoholic, typeString)` (`ISApplyBandage:complete`); `BodyPart.setBandaged(boolean, float[, boolean, String])` also exists. The vanilla UI won't bandage an unhurt part.
- **Blood/dirt:**
  - clothing: `Clothing:getBlood(BloodBodyPartType)` / `setBlood(part, value)`, and the same for dirt
  - covered parts: `BloodClothingType.getCoveredParts(item:getBloodClothingType())`
  - body: `player:getHumanVisual():getBlood(part)` / `setBlood(part, value)`
- **Timed actions (vanilla source: `media/lua/shared/TimedActions/`):**
  - SP runs `perform()` and `complete()` locally; MP splits them (see gotchas).
  - `stop()` is what a client gets when `isValid()` fails mid-action.
- **Items:** `ISDrinkFluidAction` keeps `self.fluidContainer` (`isEmpty()`, `getFilledRatio()`); drinkable milk is a FluidContainer item.

**Harmless known log noise:** `Translator.reportMissingArgumentsFromPastAbuse ... UnknownFormatConversionException ... Sandbox_RedDays_*Pct`. Sandbox translation strings containing `(%)` are read as format specifiers. It hasn't been fixed yet; the likely fix is `%%` or rewording.

## Tests (`python tests/run.py`, ~280 tests + static checks)

**Layout:**
- LuaJIT harness under `tests/lua/harness/`: `env.lua` (sandboxed globals), `doubles/` (fake engine objects), `mp.lua` (a client env and server env joined by a bus), `sim.lua` (fires the real registered event handlers)
- suites: `tests/lua/suites/*_spec.lua`
- static checks: `tests/static/`, including a jar lookup of every engine call name

**Fidelity rules learned the hard way.** The doubles must behave like the engine, or tests pass while the game breaks:
- `events.lua` walks the live handler list like `Event.trigger`.
- `sendServerCommand` does not loop back in SP.
- Timed-action doubles have `perform`, `complete` **and** `stop`.
- Clothing blood/dirt is per body part.
- `setBleeding` sets a flag.
- Extra-item lists hold strings.
- `hasTag` rejects strings.
- `RD_Config` is pre-seeded, so tests never depend on the shipped flag value.
- Things the harness can't model (engine visual/stat sync, the sleeping-tablet fade) get an in-game self-test check instead.

**Workflow:**
- Every bug fix gets a test shown failing on the old code first.
- New checks get a quick mutation run: break the fix, confirm the test fails, restore.
- **Key suites:**
  - `save_compat_spec`: real historical save shapes
  - `tss_core_spec`: the TSS state machine
  - `hygiene_spec`
  - `pms_effects_spec` and `pms_mp_spec`
  - `mp_sync_spec`: the wire contract; every client command needs a server handler, and no client `complete()` hooks
  - `selftest_spec`: runs the real in-game self-test end to end in simulated SP and MP

## Debug workflow

`notes/apiDocumentation/RedDays_Debug_API_42_18.txt` documents the `rd.*` in-game console API (`rd.cycle.*`, `rd.tss.*`, `rd.debug.*`, `rd.goToPhase(...)`, `rd.goToTSSStage(...)`, `rd.status.print()`). `RD_CycleDebugger.printWrapper()` (`RD_debugger.lua`) fires once per in-game hour and dumps a full state block (cycle, TSS, hygiene, PMS) to the log, ungated by `verboseLog`. The Workshop page's bug-report steps tell players to copy this block ("Generated menstrual cycle details"), so keep it on in release builds.

**In-game self-test** (`RD_Config.selftest = true`, launch with `-debug`). The console commands are the same in SP and MP:

- `rd.mptest.run()` is automated. Wear a hygiene item and pants first so `item`, `wear` and clothing `stains` are covered. It checks:
  - `moddata`: the modData transmit
  - `stat`: which side owns a stat
  - `hp`: HP double drain
  - `stiff` / `item`: stiffness and item sync
  - `wear`: red-phase wear-down sync
  - `tss`: a live TSS tick
  - `pms`: PMS stat sync
  - `stains`: body and clothing stain sync (clothing only when pants are worn)
- `rd.mptest.actions()` gives test items (pills, two antibiotics, cheese, milk, tampon) and walks through:
  - taking a pill, eating an antibiotic, eating cheese, drinking milk
  - re-wearing the tampon
  - `abx4`: a toxic-shock antibiotic course
- `rd.mptest.persistSave()`, then save, quit to menu and reload, then `rd.mptest.persistCheck()`. The snapshot lives in `Zomboid/Lua/RD_selftest_persist.txt`, never in the save.

**Verified in game on 2026-09-17** (42.20; SP and a solo hosted MP game): every `run()`, `actions()` and `persist` check passed in both modes.

Reading results: `grep -a "RD-TEST" console.txt` for the client, and `coop-console.txt` for the hosted server. The server lines show which `complete()` ran there.

Every result is a `[RD-TEST] PASS|FAIL|INFO|SKIP <id> ...` line, ending in `[RD-TEST] DONE`. In a hosted MP game, the server's half (`[RD-TEST][server]` lines, `complete()` traces) is in `coop-console.txt`. Checks that change state restore it afterwards, but quitting mid-run can leave test state in a save, so this flag must be off for release.

Player-facing log: `C:\Users\<user>\Zomboid\console.txt` — this is where in-game Lua errors and the debug dumps above end up; the user has been pasting sections of this file directly when reporting bugs.

**Script (`.txt`) changes require a full game restart to take effect for newly-spawned items.** An item already spawned/equipped before a script edit keeps whatever component config it was created under — reloading Lua or continuing the same session is not enough, and an old item can look like the fix didn't work when it's actually just stale data. Hit this for real during the fluid-container investigation.

**A newly added Lua file also needs a full game restart** (quit to desktop, not back to the main menu). PZ keeps the mod file list it scanned at launch: edits to existing files reload, but a new file isn't loaded by the directory pass, and a server-side `require` of it fails. Hit this with `shared/RD_config.lua` (2026-09-15), where `RD_Config` was nil on the server. Tell: `console.txt` still starts with the previous session's lines, because a fresh launch overwrites it. Code reading a value from another file should tolerate its absence (`RD_Config and RD_Config.selftest`).

## What NOT to assume

- The fluid-container migration (custom `RD_fluid_api.lua`, `FluidContainer` components on hygiene items) does **not** exist in the current codebase — it was fully implemented, tested, and then reverted after the blocking issues above were found. If you see any reference to it in old conversation history, it's describing dead code that no longer exists on disk.
- In-flight task status, current open items, and what's mid-progress are tracked in the auto-memory system (`project_reddays_open_items.md` and friends), not here — this file is a stable architecture reference and won't be updated every session, so don't expect it to reflect "what's being worked on right now."
