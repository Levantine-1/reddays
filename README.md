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
    - PMS severity varies each cycle and can be reduced by 75% with painkillers.
    - Effects gradually increase during late luteal phase, peak just before menstruation, then quickly subside within 24 hours of bleeding.
    
    PMS Effects:
    - Agitation (A): Uses default unused anger moodle (may conflict with other mods). Doubles stamina/endurance recovery at peak severity. Cancels out Fatigue debuff.
    - Fatigue (F): Halves stamina/endurance recovery and doubles fatigue gain at peak severity. Cancels out Agitation buff.
    - Sadness/Depression (U): Depression level tracks PMS severity. Antidepressants provide relief, but depression naturally subsides as PMS fades.
    - Tender Breasts (T): Causes upper torso muscle strain scaling with severity. Reduced by 50% if Cramps are also active. May interfere with sleep at high severity without painkillers when combined with cramps.
    - Cramps (C): Causes lower torso and groin muscle strain scaling with severity. Stacks with Tender Breasts. May require painkillers for sleep at high severity.
    - Food Cravings (Y): Player always wants to eat.
    
## Planned features

Feminine Hygiene products:
- Craftable re-usable cloth pads
- Menstrual cups

Not wearing hyginene items increases "dirtiness/bloodiness" for certain clothing locations
- Potential for interaction with other mods that have dirt/blood attracts zombies

Traits:
- Hygiene product consumption and stat decrement rates vary by cycle trait:
- Light, Normal, Heavy Cycle Traits
- Right now player starts on red day, but eventually a different start date could be a trait
- Endometriosis by popular request
- PMS symptoms as traits

Health affects menstrual cycle
    - Severe underweight/malnutrition can stop the cycle
    - Severe stress can alter the cycle

Debuffs for insufficient hygienic care:
- TSS or other sickness and debuffs

## Current Known Bugs or Basic ToDos:
- Add more sandbox options:
    - Stat degrade rates
    - painkiller effectiveness

## Fixed Reported Bugs and minor feature change notes:
- Moved change notes to workshop page: https://steamcommunity.com/sharedfiles/filedetails/changelog/3516166810

## FAQ
- Only female characters will experience the menstrual cycle by default, but you can enable for all genders in sandbox options

- This should be safe to add mid save, however feminine hygiene items won't spawn in places you've already looted, but can spawn on corpses.

- The follicular, ovulation and luteal phase doesn't have any other effect besides generating discharge, which is completely a visual thing with no status effects that requires a 1-2 times a day change of panty liners.
