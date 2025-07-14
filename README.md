# Red Days

## Players will now have a menstrual cycle and need to find and stockpile feminine care products

## Current Features
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
    - painkiller effect time
    - Upperbound and Lowerbound durations for cycle phases

- Custom 3D models thanks to sudodski's commit: 6f10ac0bdc8b76750152ad8aa34118ff13c9fa64

## Planned features

Feminine Hygiene products:
- Craftable re-usable cloth pads
- Menstrual cups

Cycle tracking feature:
- Craftable cycle tracker calendar for cycle predictions

Random cycle start dates for new characters
- Currently all characters start the game on red day.

Traits:
- Hygiene product consumption and stat decrement rates vary by cycle trait:
- Light, Normal, Heavy Cycle Traits
- Right now player starts on red day, but eventually a different start date could be a trait
- Endometriosis by popular request

Debuffs for insufficient hygienic care:
- TSS or other sickness and debuffs

## Current Known Bugs or Basic ToDos:
- Add more sandbox options:
    - Stat degrade rates
    - painkiller effectiveness
    - Target discomfort/strain levels

## Fixed Reported Bugs:
- Incompatibility issue - mod conflicts with: 'organizedCategories: Core'
    - Fixed 2025-7-11: User reporting incompatibility issue, however after fixing the avatar in the character info panel
        The mod seems to just rename the category from Feminine Hygiene -> Clothing - Protective. Which I assume is correct behavior.

- Equipping a sanitary item causes the character avatar to fail to render in the character info menu.
    - Fixed 2025-7-11: Updated clothingItems xml files to render an invisible model to address some warnings and null exceptions

## FAQ
- Groin bleeding doesn't decrement HP and will not kill you
- Only female characters will experience the menstrual cycle by default, but you can enable for all genders in sandbox options
- This should be safe to add mid save, however feminine hygiene items won't spawn in places you've already looted and they don't spawn on zombies at this time.
- The follicular, ovulation and luteal phase doesn't have any other effect besides generating discharge, which is completely a visual thing with no status effects that requires a 1-2 times a day change of panty liner.
