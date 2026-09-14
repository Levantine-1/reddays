# Red Days

## Players will now have a menstrual cycle and need to find and stockpile feminine care products

## Current Major Features
- The basic menstrual cycle including the following phases:
    - Menstural
    - Follicular
    - Ovulation
    - Luteal
    - Character generates discharge outside of the menstrual cycle.

- Debuff effects during the Menstrual Phase
    - Reduced Endurance
    - Increased Fatigue
    - Groin bleeding and muscle strain (to simulate cramps)
    - Lower torso muscle strain (to simulate cramps and increase pain level so the moodle shows up)
    - Increased discomfort levels

- Painkillers negates debuffs (6 ingame hours default)

- Feminine Hygiene products:
    - Boxes of Sanitary Pads
    - Boxes of Tampons
    - Boxes of Panty Liners
    - Bandages will work as a quick stop gap if regular feminine hygiene products are not available.

- Add sandbox options for customization
    - Hygiene product spawn rates
    - Option to enable MS for male characters (For FTM roleplay)
    - painkiller effect time and effectiveness
    - PMS-easing food effect duration and total reduction cap
    - Upperbound and Lowerbound durations for cycle phases

- Custom 3D models thanks to Sudodski

- Craftable cycle tracker calendar:
    - If tracker book is in equipped bag or inventory and page 14 ID matches character ID
        - Everytime player unequips or replaces a sanitary item, it as assumed the player 
            inspected the item and results are automatically logged in the book.
    - If data isn't being written, delete all contents on page 14 or craft a new book.
    - IDK how to make a custom UI and I have 0 artistic talent so a text based calendar is the best I've got.
    - The inspirational quote changes everytime you unequip/replace a sanitary pad item.
        Let me know if there are any you'd like to add. Just make sure the quote and the author credit would fit in the character limits. Refer to existing quotes as a guideline.
    - Writing tools aren't needed for now, but will be made necessary later.
    - If you are on a new character and delayed phase is enabled, no data will be recorded until your first period occurs. After that however, everything should work normally.

- Moodles
    - Moodles reminding players to change out products

- Pre-Menstrual Symptoms (PMS)
    - Characters spawn with 3 randomly selected PMS symptoms that remain consistent throughout their life. Enable random symptoms per cycle in sandbox options if you prefer variety.
    - PMS severity can be reduced by painkillers (50% by default, sandbox-configurable) and by eating certain foods (see below). Both sources stack independently, so eating well on top of painkillers gives a bit of extra relief.
    - Effects gradually increase during late luteal phase, peak just before menstruation, then quickly subside within 24 hours of bleeding.

    Food-based PMS relief:
    - Eating or drinking certain foods temporarily reduces PMS severity, decaying over 6 in-game hours by default (same duration knob style as painkillers) unless you eat another qualifying food, which tops up the reduction and restarts the timer.
    - The total reduction from food stacks across different foods eaten in that window, capped at 20% by default (sandbox-configurable).
    - Milk (Carton, Bottle, or Personal-sized) / Yogurt / Milk Chocolate Bar: -10%
    - Cheese (regular or Processed Cheese): -8%
    - Bowl of Oatmeal: -6%
    - Peanuts / Peanut Butter / Banana / Fish (any raw species, or Fish Fillet): -4%
        - Only raw fish counts, not an already-cooked fish item eaten on its own (Fried Fish, Fish Fingers, Sushi). Cooking a stew or other dish you added raw fish to is fine -- the dish still gets credit for what went in.
    - Home-cooked meals count too: a stew, soup, or other cooked dish gets credit for whichever of the above ingredients were mixed in, on top of the meal's own type if it matches. Works if food is divided into bowls.

    PMS Effects:
    - Agitation (A): Uses default unused anger moodle (may conflict with other mods). Doubles stamina/endurance recovery at peak severity. Cancels out Fatigue debuff.
    - Fatigue (F): Halves stamina/endurance recovery and doubles fatigue gain at peak severity. Cancels out Agitation buff.
    - Sadness/Depression (U): Depression level tracks PMS severity. Antidepressants provide relief, but depression naturally subsides as PMS fades.
    - Tender Breasts (T): Causes upper torso muscle strain scaling with severity. Reduced by 50% if Cramps are also active. May interfere with sleep at high severity without painkillers when combined with cramps.
    - Cramps (C): Causes lower torso and groin muscle strain scaling with severity. Stacks with Tender Breasts. May require painkillers for sleep at high severity.
    - Food Cravings (Y): Player always wants to eat.

- Not wearing hyginene items increases "dirtiness/bloodiness" for certain clothing locations
    - Potential for interaction with other mods that have dirt/blood attracts zombies

- Toxic Shock Syndrome (WARNING: TSS IS LETHAL BY DEFAULT! Can be disabled entirely or made non-lethal in sandbox options.)
    - Neglecting your hygiene items for too long can develop into a progressive infection, starting with mild warning symptoms and, if ignored long enough, escalating all the way to full Toxic Shock.
    - Early on it's just stamina/fatigue penalties and a nagging feeling something's off. Left unchecked, it can spiral into a dangerous late stage where your health itself starts draining -- made worse by stress, exhaustion, thirst, body temperature, and hunger.
    - Changing your hygiene items regularly keeps it from ever starting. Once infected, removing the source lets your body recover on its own over time -- no medication strictly required, just patience.
    - Antibiotics (a regular food item) speed up recovery and are your best safety net if things get bad.
    - Known limitation: TSS is currently disabled automatically when playing on a true multiplayer/dedicated server, due to an unresolved sync bug -- it works as described above in singleplayer. Will be revisited in a future update. I've tested SP to work fine, but for both MP and SP, if you encounter something that doesn't seem right.                                                   
        - RESET TSS:
            - You can reset TSS by launching the game in debug mode, and running this command: rd.goToTSSStage(0)
        - COLLECT REPORT:
            - Go to your zomboid user data files, usually here: C:\Users\<your username>\Zomboid\console.txt
            - Find a block of lines that look like : f:5891> =========================== Generated menstrual cycle details ==============================
            - Submit the bug report, what you did leading up to the bug, what you expected, what you got and then the error.

- Health affects menstrual cycle
    - Severe underweight/malnutrition can stop the cycle
    - Severe stress can alter the cycle
    
## Planned features

Feminine Hygiene products:
- Craftable re-usable cloth pads
- Menstrual cups


Integrate with other lifestyle mods for features like bathing to remove leak moodles.

Traits:
- Hygiene product consumption and stat decrement rates vary by cycle trait:
- Light, Normal, Heavy Cycle Traits
- Right now player starts on red day, but eventually a different start date could be a trait
- Endometriosis by popular request
- PMS symptoms as traits



## Investigated and abandoned: real fluid containers for hygiene items

Tampons/pads/liners currently track saturation as a simple integer `condition`
(10→1) that decrements on a timer. It would be more realistic to track real
fluid volume (mL of blood vs. discharge) using Project Zomboid's native
`FluidContainer` item component instead of a plain counter, and it was tried.
It's being shelved: the engine fights this use case hard enough that every
fix required another workaround, and the payoff (more realistic numbers
under the hood) is invisible to players either way. Documenting the findings
here so nobody re-discovers them the hard way:

- **50 mL hard floor.** `FluidContainer.setCapacity()` is
  `this.capacity = PZMath.max(f, 0.05f)` (confirmed by disassembling
  `projectzomboid.jar`) — any script `Capacity` below 0.05 L is silently
  clamped up to it. A real tampon/pad/liner (3-12 mL) can't be expressed as a
  capacity at all; the smallest capacity used anywhere in vanilla is 0.1 L
  (100 mL), so nothing this small had ever been exercised before. Workable
  around by giving every item the same 0.1 L container and treating it as an
  abstract 0-100 percentage gauge, with the real mL numbers kept in Lua.
- **The player-facing locks also lock out the mod's own code.**
  `Opened = false` and `InputLocked = true` are needed to stop players from
  pouring, filling, transferring, or drinking from these items — but
  `FluidContainer.canAddFluid()` returns `false` whenever either flag is
  set, and `addFluid()` silently no-ops when `canAddFluid()` is false (no
  error, no return value). That means the exact flags needed to lock the
  player out also silently blocked every fluid addition the mod itself tried
  to make. Workable around by having the mod unlock the container, write,
  and immediately relock it, all inside one synchronous call.
- **The item renames itself and nothing can stop it.** Once a
  `FluidContainer` holds any fluid, `InventoryItem.getName()` unconditionally
  returns `FluidContainer.getUiName()` — confirmed as the very first branch
  of that method, with no script field, tag, or `HiddenAmount` setting able
  to suppress it. A worn tampon would start display as "Menstrual Blood
  (Tampon)" everywhere: inventory, tooltip, hotbar, world-floor label. This
  one had no clean workaround — patching every Lua UI surface that calls
  `item:getName()` would still miss native-only surfaces like the
  floor-drop label, so the item would show inconsistent names depending on
  where you looked at it.

None of these are bugs in this mod's own code — all three were confirmed at
the engine bytecode level. The first two have workarounds; the third
doesn't, short of abandoning the display name entirely (which defeats the
point of a game that's supposed to read clearly at a glance). Combined with
the growing pile of workarounds needed just to get partway there, it wasn't
worth it for a change players would never actually see the internals of.

If this gets revisited: track saturation as a plain number pair in the
item's own `modData` (blood mL, discharge mL) instead of a real
`FluidContainer`. That sidesteps all three problems outright — no engine
capacity, no engine locks to fight, and the item's name stays under the
mod's own control — at the cost of not being backed by the engine's native
fluid API (which wasn't buying anything user-visible anyway, since the
numbers were being hidden from players either way).

## Current Known Bugs or Basic ToDos:
- Add more sandbox options:
    - Stat degrade rates
- Fix bug related to randomized starts
- Player spawns with a few sanitary items

## Fixed Reported Bugs and minor feature change notes:
- Moved change notes to workshop page: https://steamcommunity.com/sharedfiles/filedetails/changelog/3516166810

## FAQ
- Only female characters will experience the menstrual cycle by default, but you can enable for all genders in sandbox options

- This should be safe to add mid save, however feminine hygiene items won't spawn in places you've already looted, but can spawn on corpses.

- The follicular, ovulation and luteal phase doesn't have any other effect besides generating discharge, which is completely a visual thing with no status effects that requires a 1-2 times a day change of panty liners.
