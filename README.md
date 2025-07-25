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
    - painkiller effect time
    - Upperbound and Lowerbound durations for cycle phases

- Custom 3D models thanks to sudodski's commit: 6f10ac0bdc8b76750152ad8aa34118ff13c9fa64

## Planned features

Feminine Hygiene products:
- Craftable re-usable cloth pads
- Menstrual cups

Cycle tracking feature:
- Craftable cycle tracker calendar for cycle predictions

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

## Fixed Reported Bugs and minor feature change notes:
- Incompatibility issue - mod conflicts with: 'organizedCategories: Core'
    - Fixed 2025-7-11: User reporting incompatibility issue
        The mod seems to just rename the category from Feminine Hygiene -> Clothing - Protective. Which I assume is correct behavior.
    - Fixed 2025-7-26: While the above is correct behavior for the organizer mod, by changing the category, red days no longer reconizes a feminine hygiene items because it relies on searching equipped items by category. I've updated the way this is handled so this shouldn't affect category organiziers in the future.

- Equipping a sanitary item causes the character avatar to fail to render in the character info menu.
    - Fixed 2025-7-11: Updated clothingItems xml files to render an invisible model to address some warnings and null exceptions

- Random cycle start dates for new characters
    - 2025-26-07 Added feature to start on random dates and added respective sandbox options

- 2025-26-07 Items will now spawn on zombies

## FAQ
- Groin bleeding time is set to 0 and should not kill you. However upon some testing, if bleeding and if you speed up time, it might decrement some HP so be careful if low HP.

- Only female characters will experience the menstrual cycle by default, but you can enable for all genders in sandbox options

- This should be safe to add mid save, however feminine hygiene items won't spawn in places you've already looted, but can spawn on corpses.

- The follicular, ovulation and luteal phase doesn't have any other effect besides generating discharge, which is completely a visual thing with no status effects that requires a 1-2 times a day change of panty liners.
