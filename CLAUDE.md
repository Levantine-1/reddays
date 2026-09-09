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
| `RD_cycle_irregularity.lua` | Follicular-phase-only health-driven delays (weight-trait status via `CharacterTrait.*`, and a trauma/low-HP delay), layered additively on top of the cycle manager's normal random roll. |
| `RD_hygiene_manager.lua` | Hygiene item saturation — plain integer `condition` (10→1), decremented on a timer during the red phase; also owns blood/dirt stain spreading on body + clothing. |
| `RD_effects_manager.lua` | Registers/unregisters the red-phase consumption tick and the non-red-phase discharge tick based on current cycle phase. |
| `RD_effects_pms.lua` | PMS symptom effects (agitation/cramps/fatigue/tender breasts/food cravings/sadness), painkiller suppression. |
| `RD_tss_manager.lua` | Toxic Shock Syndrome — stage 0-4 progression, antibiotic treatment, fever/HP effects. Largest, most stateful subsystem. |
| `RD_moodles.lua` | Drives the 8 MoodleFramework moodles (`Dirty*`/`Bloody*` per item type, `Leak`, `TSSInfection`) from item condition / `LeakLevel` / TSS stage. |
| `RD_cycle_tracker_logic.lua` / `RD_cycle_tracker_text.lua` | The in-game "Period Tracker" book — logs a day-code (H/M/L/S flow intensity + PMS letter codes) into an in-item calendar on unequip/wear. |
| `RD_debugger.lua` | The `rd.*` console debug API + `RD_CycleDebugger.printWrapper()`, the full-state dump fired on `EveryHours`/`EveryTenMinutes`. |

Server-side: `media/lua/server/RD_server_commands.lua` (MP item-condition sync via `sendClientCommand`), `media/lua/server/items/RedDays_ProceduralDistributions.lua` (corpse loot spawning).

Item/model scripts: `media/scripts/clothing/item{Tampon,SanitaryPad,PantyLiner,CycleJournal}.txt` + matching `model*.txt` files. Recipes in `media/scripts/RedDays_recipes.txt`.

## Event wiring (from `RD_main.lua`)

`require` order matters (dependency order between managers) — currently: `RD_game_api` → `RD_cycle_manager` → `RD_cycle_irregularity` → `RD_cycle_tracker_logic` → `RD_effects_manager` → `RD_hygiene_manager` → `RD_effects_pms` → `RD_tss_manager` → `RD_moodles` → `RD_debugger`.

A local `isValidGenderCheck()` (female, or `SandboxVars.RedDays.affectsAllGenders`) gates almost every hook below — reuse this pattern for any new hook rather than duplicating the check.

Registered events: `OnGameStart` / `OnCreatePlayer` → `initializePlayerData()` (loads every manager's per-player data, grants starter hygiene items if enabled); `EveryHours` and `EveryTenMinutes` → debug dump + periodic modData sync to server; `EveryOneMinute` → the main tick chain (`RD_CycleManager.tick(1)` → `RD_CycleIrregularity.checkTraumaCause` → `RD_EffectsManager.determineEffects` → `RD_EffectsPMS.applyPMSEffectsMain` → `RD_TSSManager.EveryOneMinute` → `RD_moodles.mainLoop`); `EveryDays` → `RD_CycleIrregularity.applyDailyWeightCause`; `OnPlayerUpdate` → TSS fever pressure (runs every frame — keep this cheap).

Five vanilla methods are intercepted (original saved, called after the mod's hook): `ISUnequipAction:perform`, `ISWearClothing:perform`, `ISWashYourself:perform`, `ISTakePillAction:perform`, `ISEatFoodAction:complete`.

## Data model (`RD_modData.ICdata`, i.e. `player:getModData().ICdata`)

- `currentCycle` — the active cycle table: `current_phase`, `phase_minutes_remaining`, one `<phase>Phase_duration_mins` per phase, `cycle_duration_mins`, health/PMS-effect targets, `pms_*` symptom flags, `traumaDelayAppliedThisCycle`. Built by `RD_CycleManager.newCycle()`; see that function (or `CYCLE_DEFAULTS` in `RD_debugger.lua`) for the exact current field list rather than trusting a stale copy here.
- `tss` — TSS state (stage, exposure/severity minutes, wear_minutes, source_active/type/item_id, recovery + antibiotic-bank fields). Full field list: `TSS_DEFAULTS` in `RD_debugger.lua`.
- `cSIHDC_counter` — hygiene item condition-decrement accumulator.
- `LeakLevel` / `LeakSwitchState` — leak moodle/stain state.
- `pmsSymptoms`, `cycleDelayed`, `calendar` / `calendarMonth` / `journalID` (tracker book), `pill_recently_taken` / `pill_effect_active` / `pill_effect_counter` (painkiller), `hygieneStarterItemsGranted`.

## Sandbox options

`media/sandbox-options.txt` (48 options currently, all under `page = RedDays`) + matching `Sandbox_RedDays_<name>` / `Sandbox_RedDays_<name>_tooltip` entries in `media/lua/shared/Translate/EN/Sandbox.json`. **PZ sandbox options don't support floats** — if you need fractional precision, encode as an integer at 10x/100x scale and divide in Lua (a `_x10`-suffixed option existed for this during the fluid-container experiment; pattern is gone from the current file but is the right move if it comes up again). Note `menstrual_cycle_duration_lowerBound`'s `min = -100` is a pre-existing oddity (a negative duration bound makes no real sense) — don't "fix" it without being asked, it may be intentional or just untouched cruft.

## Translation files

`media/lua/shared/Translate/EN/{Sandbox,Moodles,ItemName,RecipeName,IG_UI}.json`. `RecipeName.json` didn't exist until recently (all 7 of this mod's recipes were silently untranslated, showing raw script names in-game) — if a future version-folder copy is missing it again, that's the same latent bug recurring, not a new one.

## PZ engine gotchas confirmed via direct research (expensive to relearn — read before re-investigating)

- **Item script `Tags`**: always lowercase, always `base:`-prefixed (`Tags = base:isfirefuel;base:omitemptyfromname`), confirmed against dozens of vanilla examples in `media/scripts/generated/`.
- **`FluidContainer` item component is a confirmed dead end** for tracking hygiene-item saturation — fully investigated and reverted; see README.md's "Investigated and abandoned: real fluid containers for hygiene items" section for the three specific blocking reasons (50mL capacity floor via `PZMath.max(f, 0.05f)`, `canAddFluid()`/`addFluid()` silently no-op'ing whenever the player-facing lock flags are set — the exact flags needed to keep players out also blocked the mod's own writes, and an unconditional `getName()` override with no way to suppress it). Read that section in full before ever reconsidering this approach — do not re-attempt it starting from a blank slate.
- **MoodleFramework default value→level thresholds**: `setThresholds(0.1,0.2,0.3,0.4, 0.6,0.7,0.8,0.9)`, confirmed against the installed mod's own `MF_ISMoodle.lua`. This mod's `0.42` "clear" sentinel is this mod's own convention, not a framework constant.
- **`item:syncItemFields()` is an instance method**, not a two-argument global function — a real bug (called as `syncItemFields(player, item)`) was found and fixed once already in `RD_server_commands.lua`. If MP item sync throws, check this first.
- **`ZombRand` conventions are mixed in this codebase** — some call sites use `ZombRand(min, max)` (max-exclusive, two-arg), some use `ZombRand(n)` (0-based, need `+1` for Lua's 1-based indexing/ranges), one uses `ZombRand(range + 1)` to make an inclusive roll. Check what a specific call site is actually doing rather than assuming a single global convention.
- **A Java-bound "static class" Lua object (e.g. `Fluid`, `FluidType`) calling a nonexistent/mis-signatured method is not reliably caught by `pcall`** in this build's Kahlua VM — confirmed via a real in-game crash where a `pcall`-wrapped call still crashed the whole event dispatch uncaught. Guard with `type(obj[method]) == "function"` before calling, rather than trusting `pcall` alone, when the method's existence/signature isn't independently verified.

## Bytecode research technique (reusable — PZ is installed locally)

`D:\SteamLibrary\steamapps\common\ProjectZomboid\projectzomboid.jar` contains all compiled Java classes. No `javap`/JDK is available in the bundled `jre64`, so: `unzip -o -j projectzomboid.jar "zombie/path/to/Class.class" -d <scratchdir>`, then either `grep -a -o "[A-Za-z_][A-Za-z0-9_]\{3,40\}"` on the raw class file for constant-pool strings (method/field names — fast, good for "does this method exist"), or write a small class-file/bytecode parser when the question is about control flow (e.g. "which script key backs this runtime field") — this has been done ad hoc in scratchpad scripts each time rather than kept as a reusable tool; re-write it if needed rather than searching for a prior copy.

`media/scripts/generated/` (vanilla item/fluid/trait script dumps) and `media/lua/` (vanilla Lua source, all of it present and readable) are both directly available in the install and have repeatedly been more reliable than web sources — `pzwiki.net` blocked several fetch attempts.

## Debug workflow

`notes/apiDocumentation/RedDays_Debug_API_42_18.txt` documents the `rd.*` in-game console API (`rd.cycle.*`, `rd.tss.*`, `rd.debug.*`, `rd.goToPhase(...)`, `rd.goToTSSStage(...)`, `rd.status.print()`). `RD_CycleDebugger.printWrapper()` (`RD_debugger.lua`) fires on `EveryHours`/`EveryTenMinutes` and dumps a full state block (cycle, TSS, hygiene, PMS) to the log — useful for diagnosing without needing a repro script.

Player-facing log: `C:\Users\<user>\Zomboid\console.txt` — this is where in-game Lua errors and the debug dumps above end up; the user has been pasting sections of this file directly when reporting bugs.

**Script (`.txt`) changes require a full game restart to take effect for newly-spawned items.** An item already spawned/equipped before a script edit keeps whatever component config it was created under — reloading Lua or continuing the same session is not enough, and an old item can look like the fix didn't work when it's actually just stale data. Hit this for real during the fluid-container investigation.

## What NOT to assume

- The fluid-container migration (custom `RD_fluid_api.lua`, `FluidContainer` components on hygiene items) does **not** exist in the current codebase — it was fully implemented, tested, and then reverted after the blocking issues above were found. If you see any reference to it in old conversation history, it's describing dead code that no longer exists on disk.
- In-flight task status, current open items, and what's mid-progress are tracked in the auto-memory system (`project_reddays_open_items.md` and friends), not here — this file is a stable architecture reference and won't be updated every session, so don't expect it to reflect "what's being worked on right now."
