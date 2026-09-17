-- RedDays in-game self-test: rd.mptest.run() and rd.mptest.actions().
--
-- Loaded by RD_main.lua only when RD_Config.selftest is true (shared/RD_config.lua). The same
-- entry points work in singleplayer AND multiplayer; every check judges its result against the
-- current mode. One grep-able line per result:
--   [RD-TEST] PASS|FAIL|INFO|SKIP <id> <label> ---- <detail>
-- Colons are stripped from output: the in-game console truncates a line at the first colon.
--
-- Server-side values come from the rdTestProbe command (RD_server_commands.lua). In SP the
-- engine loops client commands back locally (SinglePlayerClient -> SinglePlayerServer), so the
-- same probe works there too -- it just reads the same player object.

require "RD_game_api"
require "RD_debugger"

RD_SelfTest = RD_SelfTest or {}
local ST = RD_SelfTest
RD_DebugAPI.mptest = ST

local HYGIENE_LOCATION = "RedDays:HygieneItem"
local PROBE_TIMEOUT_MS = 5000
local ACTION_TIMEOUT_MS = 120000
local TRACED_ACTIONS = {
    "ISEatFoodAction", "ISDrinkFluidAction", "ISTakePillAction", "ISUnequipAction", "ISWearClothing",
}

-- ================= OUTPUT =================

local counts = { PASS = 0, FAIL = 0, INFO = 0, SKIP = 0 }

local function noColons(s)
    return (string.gsub(tostring(s), ":", " "))
end

local function fmt(v)
    if type(v) == "number" then return string.format("%.3f", v) end
    return tostring(v)
end

local function note(msg)
    print("[RD-TEST] " .. noColons(msg))
end

local function report(kind, id, label, detail)
    if counts[kind] then counts[kind] = counts[kind] + 1 end
    local line = kind .. " " .. id .. " " .. label
    if detail ~= nil and detail ~= "" then line = line .. " ---- " .. detail end
    note(line)
end

local function isMP() return isClient() end
local function modeName() return isMP() and "mp" or "sp" end

-- ================= STATE HELPERS =================

local function player() return RD_zapi.getPlayer() end

local function icdata()
    local md = RD_zapi.getModData()
    return md and md.ICdata
end

local function transmit()
    if isClient() then
        local p = player()
        if p then p:transmitModData() end
    end
end

-- The same server command the TSS tick uses; the mod itself only sends it in MP.
local function sendStats(args)
    if isClient() then
        sendClientCommand(player(), 'RedDays', 'applyTSSStats', args)
    end
end

local function near(a, b, tolerance)
    return type(a) == "number" and type(b) == "number" and math.abs(a - b) <= tolerance
end

local function deepCopy(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, val in pairs(v) do out[k] = deepCopy(val) end
    return out
end

-- The first worn garment (not the hygiene item) whose blood coverage includes the groin.
local function findGroinGarment()
    local wornItems = RD_zapi.getWornItems()
    if not wornItems then return nil end
    for i = 0, wornItems:size() - 1 do
        local entry = wornItems:get(i)
        local item = entry and entry:getItem()
        if item and RD_zapi.isClothingItem(item) and not RD_zapi.isItemAtBodyLocation(item, HYGIENE_LOCATION) then
            local parts = RD_zapi.getClothingCoveredParts(item)
            if parts then
                for j = 0, parts:size() - 1 do
                    if parts:get(j) == BloodBodyPartType.Groin then return item end
                end
            end
        end
    end
    return nil
end

local PMS_SYMPTOM_KEYS = {
    "pms_agitation", "pms_cramps", "pms_fatigue", "pms_tenderBreasts", "pms_craveFood", "pms_Sadness",
}

-- ================= HOOK TRACER =================
-- Counts every perform() and complete() of the consumption/clothing actions, per item type.
-- In MP a client only ever sees perform(); the server log shows complete() (see
-- RD_server_commands.lua). This file only observes complete() -- it never applies an effect
-- there, which is why mp_sync_spec.lua exempts it from the "no complete() hooks" guard.

ST.hookCounts = ST.hookCounts or {}

local function hookKey(className, method, fullType)
    return className .. "|" .. method .. "|" .. (fullType or "*")
end

function ST.hookCount(className, method, fullType)
    return ST.hookCounts[hookKey(className, method, fullType)] or 0
end

-- Order of hook calls, for checks where the sequence matters ("take off, THEN wear again").
ST.hookSeq = ST.hookSeq or {}
ST.hookSeqCounter = ST.hookSeqCounter or 0

local function bumpHook(className, method, fullType)
    for _, key in ipairs({ hookKey(className, method, nil), hookKey(className, method, fullType) }) do
        ST.hookCounts[key] = (ST.hookCounts[key] or 0) + 1
    end
    ST.hookSeqCounter = ST.hookSeqCounter + 1
    ST.hookSeq[className .. "|" .. method] = ST.hookSeqCounter
end

-- Sequence number of the most recent call, or 0 if it never ran.
local function lastHookSeq(className, method)
    return ST.hookSeq[className .. "|" .. method] or 0
end

local function actionItemType(action)
    local item = action and action.item
    if not item then return "none" end
    local ok, fullType = pcall(function() return item:getFullType() end)
    if ok and fullType then return fullType end
    return "unknown"
end

local function installTracer()
    if ST._tracerInstalled then return end
    ST._tracerInstalled = true
    for _, className in ipairs(TRACED_ACTIONS) do
        local class = _G[className]
        if class then
            for _, method in ipairs({ "perform", "complete", "stop" }) do
                local original = class[method]
                if type(original) == "function" then
                    class[method] = function(self)
                        local fullType = actionItemType(self)
                        bumpHook(className, method, fullType)
                        note("HOOK " .. className .. " " .. method .. " fired "
                            .. (isMP() and "client-side" or "locally") .. " ---- " .. fullType)
                        return original(self)
                    end
                end
            end
        end
    end
end

-- ================= SYNC TRAFFIC COUNTER =================
-- Counts the mod's own RedDays commands (not rdTest*), installed only while a run is active.
-- sendClientCommand has a 3-argument form (module, command, args) as well as the 4-argument
-- one, and vanilla calls both, so the wrapper forwards exactly the arguments it was given.

ST.syncSends = ST.syncSends or {}
local underlyingSend = nil

local function countingSend(a, b, c, d)
    local module, command
    if type(a) == "string" then module, command = a, b else module, command = b, c end
    if module == "RedDays" and string.sub(tostring(command), 1, 6) ~= "rdTest" then
        ST.syncSends[command] = (ST.syncSends[command] or 0) + 1
    end
    if type(a) == "string" then return underlyingSend(a, b, c) end
    return underlyingSend(a, b, c, d)
end

local function installTrafficCounter()
    if sendClientCommand == countingSend then return end
    underlyingSend = sendClientCommand
    sendClientCommand = countingSend
end

local function uninstallTrafficCounter()
    if sendClientCommand == countingSend then
        sendClientCommand = underlyingSend
    end
end

local function sends(command) return ST.syncSends[command] or 0 end

-- ================= SCHEDULER =================
-- OnTick-driven waiters with real-time deadlines. OnTick is registered once and never
-- removed: removing a handler from inside that same event's dispatch is not worth the risk.

local waiters = {}
local running = nil
local advanceCurrentStep = nil  -- the running step's nextStep, to recover from a thrown callback

local function now() return getTimestampMs() end

local function waitUntil(predicate, timeoutMs, callback)
    waiters[#waiters + 1] = { predicate = predicate, deadline = now() + timeoutMs, callback = callback }
end

local function after(ms, callback)
    local at = now() + ms
    waitUntil(function() return now() >= at end, ms + 1000, function() callback() end)
end

local function runCallback(callback, arg)
    local ok, err = pcall(callback, arg)
    if not ok then
        report("FAIL", "internal", "callback threw", tostring(err))
        if advanceCurrentStep then advanceCurrentStep() end
    end
end

local function onTick()
    if #waiters == 0 then return end
    local snapshot = waiters
    waiters = {}
    local t = now()
    for _, waiter in ipairs(snapshot) do
        local okPredicate, done = pcall(waiter.predicate)
        if okPredicate and done then
            runCallback(waiter.callback, true)
        elseif t >= waiter.deadline then
            runCallback(waiter.callback, false)
        else
            waiters[#waiters + 1] = waiter
        end
    end
end

ST.minuteTicks = ST.minuteTicks or 0
local function onMinute() ST.minuteTicks = ST.minuteTicks + 1 end

local function startRun(name)
    if running then
        note("BUSY ---- " .. running .. " is still running, wait for its DONE line")
        return false
    end
    running = name
    counts.PASS, counts.FAIL, counts.INFO, counts.SKIP = 0, 0, 0, 0
    installTrafficCounter()
    note("BEGIN " .. name .. " mode=" .. modeName())
    return true
end

local function finishRun()
    note("DONE " .. tostring(running) .. " mode=" .. modeName()
        .. " pass=" .. counts.PASS .. " fail=" .. counts.FAIL
        .. " skip=" .. counts.SKIP .. " info=" .. counts.INFO)
    running = nil
    advanceCurrentStep = nil
    uninstallTrafficCounter()
end

local function runSteps(steps, index)
    index = index or 1
    local step = steps[index]
    if not step then
        finishRun()
        return
    end
    local advanced = false
    local function nextStep()
        if advanced then return end
        advanced = true
        runSteps(steps, index + 1)
    end
    advanceCurrentStep = nextStep
    local ok, err = pcall(step, nextStep)
    if not ok then
        report("FAIL", "internal", "step " .. index .. " threw", tostring(err))
        nextStep()
    end
end

-- ================= PROBE =================

local probeReplies = {}
local nonceSeq = 0

local function onServerCommand(module, command, args)
    if module ~= "RedDays" or command ~= "rdTestProbeReply" or type(args) ~= "table" then return end
    if args.nonce then probeReplies[args.nonce] = args end
end

-- Calls back with the server's view of this player, or nil after PROBE_TIMEOUT_MS.
local function probe(callback)
    nonceSeq = nonceSeq + 1
    local nonce = "n" .. nonceSeq .. "t" .. string.format("%.0f", now())
    local worn = RD_zapi.getWornItemAtLocation(HYGIENE_LOCATION)
    local garment = findGroinGarment()
    local args = {
        nonce = nonce,
        itemId = worn and worn:getID() or -1,
        clothingId = garment and garment:getID() or -1,
    }
    sendClientCommand(player(), 'RedDays', 'rdTestProbe', args)
    waitUntil(function() return probeReplies[nonce] ~= nil end, PROBE_TIMEOUT_MS, function()
        local reply = probeReplies[nonce]
        probeReplies[nonce] = nil
        callback(reply)
    end)
end

local function needsProbe(id, step)
    return function(nextStep)
        if not ST._probeOK then
            report("SKIP", id, "needs a working probe", "see the probe line above")
            return nextStep()
        end
        return step(nextStep)
    end
end

-- ================= AUTOMATED CHECKS =================

local function stepEnv(nextStep)
    local sb = SandboxVars.RedDays or {}
    local coopHost = type(isCoopHost) == "function" and isCoopHost() or false
    local debugOn = type(isDebugEnabled) == "function" and isDebugEnabled() or false
    report("INFO", "env", "session", "isClient=" .. tostring(isClient()) .. " isServer=" .. tostring(isServer())
        .. " coopHost=" .. tostring(coopHost) .. " debug=" .. tostring(debugOn))

    local genderOK = RD_zapi.isFemale() == true or sb.affectsAllGenders == true
    local tssOn = RD_TSSManager.isEnabled and RD_TSSManager.isEnabled() or false
    local detail = "genderGate=" .. tostring(genderOK) .. " tss_enabled=" .. tostring(tssOn)
    if genderOK and tssOn then
        report("PASS", "env", "RedDays active and TSS enabled", detail)
    else
        report("FAIL", "env", "RedDays or TSS inactive on this character", detail)
    end
    nextStep()
end

local function stepProbe(nextStep)
    probe(function(reply)
        ST._probeOK = reply ~= nil
        if reply then
            report("PASS", "probe", "server replied", "side=" .. tostring(reply.side))
        else
            report("FAIL", "probe", "no reply in 5s",
                "check RD_Config.selftest is true and you are admin or running -debug")
        end
        nextStep()
    end)
end

local function stepModData(nextStep)
    local ic = icdata()
    if not ic then
        report("FAIL", "moddata", "no ICdata on this player")
        return nextStep()
    end
    local nonce = "md" .. string.format("%.0f", now())
    ic._selftest_nonce = nonce
    transmit()
    after(2000, function()
        probe(function(reply)
            ic._selftest_nonce = nil
            transmit()
            if not reply then
                report("FAIL", "moddata", "probe timed out")
            elseif reply.icNonce == nonce then
                report("PASS", "moddata", isMP() and "server sees transmitted modData" or "modData visible", "nonce matched")
            else
                report("FAIL", "moddata", "server copy of modData is stale",
                    "expected " .. nonce .. " got " .. tostring(reply.icNonce))
            end
            nextStep()
        end)
    end)
end

local function stepStat(nextStep)
    local stats = player():getStats()
    local original = stats:get(CharacterStat.FATIGUE)
    local target = original < 0.5 and original + 0.1 or original - 0.1
    stats:set(CharacterStat.FATIGUE, target)

    after(3000, function()
        local localNow = stats:get(CharacterStat.FATIGUE)
        local kept = near(localNow, target, 0.02)
        probe(function(reply)
            local function restore()
                stats:set(CharacterStat.FATIGUE, original)
                sendStats({ fatigue = original })
            end
            if not reply then
                report("FAIL", "stat", "probe timed out")
                restore()
                return nextStep()
            end
            if not isMP() then
                if kept then
                    report("PASS", "stat", "local stat set sticks", "set=" .. fmt(target) .. " now=" .. fmt(localNow))
                else
                    report("FAIL", "stat", "local stat set was reverted", "set=" .. fmt(target) .. " now=" .. fmt(localNow))
                end
                restore()
                return nextStep()
            end

            report("INFO", "stat", "direct client set without a command",
                "client kept=" .. tostring(kept) .. " client=" .. fmt(localNow)
                .. " server=" .. fmt(reply.fatigue) .. " server saw it=" .. tostring(near(reply.fatigue, target, 0.02)))
            -- Commands are processed in send order, so a probe sent right after sees the result.
            sendStats({ fatigue = target })
            probe(function(reply2)
                if reply2 and near(reply2.fatigue, target, 0.02) then
                    report("PASS", "stat", "applyTSSStats changes the server copy", "server=" .. fmt(reply2.fatigue))
                else
                    report("FAIL", "stat", "applyTSSStats did not reach the server",
                        "expected " .. fmt(target) .. " server=" .. fmt(reply2 and reply2.fatigue))
                end
                restore()
                nextStep()
            end)
        end)
    end)
end

local function stepHP(nextStep)
    local bd = player():getBodyDamage()
    local before = bd:getHealth()
    if before < 50 then
        report("SKIP", "hp", "health below 50", "heal up and rerun, this check spends 1 HP")
        return nextStep()
    end
    probe(function(reply0)
        -- Exactly what a Stage 4 TSS tick does: drain locally, and in MP also send the drain.
        bd:ReduceGeneralHealth(1)
        sendStats({ hpMode = "abx_flat_drain", hpDrain = 1, hpCap = math.max(0, before - 20) })

        after(3000, function()
            local clientDrop = before - bd:getHealth()
            probe(function(reply1)
                if not isMP() then
                    if clientDrop >= 0.5 and clientDrop < 1.5 then
                        report("PASS", "hp", "drained exactly once", "drop=" .. fmt(clientDrop) .. " (1 HP spent, regenerates)")
                    else
                        report("FAIL", "hp", "unexpected local drain", "drop=" .. fmt(clientDrop))
                    end
                    return nextStep()
                end
                if not (reply0 and reply1) then
                    report("FAIL", "hp", "probe timed out")
                    return nextStep()
                end
                local serverDrop = reply0.health - reply1.health
                local detail = "client drop=" .. fmt(clientDrop) .. " server drop=" .. fmt(serverDrop)
                if clientDrop >= 1.5 or serverDrop >= 1.5 then
                    report("FAIL", "hp", "double HP drain", detail)
                elseif clientDrop >= 0.5 and serverDrop >= 0.5 then
                    report("PASS", "hp", "drained once on both sides", detail .. " (1 HP spent, regenerates)")
                else
                    report("FAIL", "hp", "drain did not land on both sides", detail)
                end
                nextStep()
            end)
        end)
    end)
end

local function stepStiffness(nextStep)
    -- Torso_Upper: the red-phase cramps effect writes Groin and Torso_Lower every minute,
    -- which would overwrite the value under test. Only PMS tender breasts touches this part.
    local part = player():getBodyDamage():getBodyPart(BodyPartType.Torso_Upper)
    local original = part:getStiffness()
    local target = original <= 90 and original + 10 or original - 10
    local baseSends = sends("applyBodyStiffness")
    part:setStiffness(target)
    if isMP() then
        sendClientCommand(player(), 'RedDays', 'applyBodyStiffness', { Torso_Upper = target })
    end
    probe(function(reply)
        if isMP() then
            if reply and near(reply.upperTorsoStiffness, target, 1) then
                report("PASS", "stiff", "stiffness reached the server", "server=" .. fmt(reply.upperTorsoStiffness))
            else
                report("FAIL", "stiff", "server stiffness differs",
                    "expected " .. fmt(target) .. " server=" .. fmt(reply and reply.upperTorsoStiffness))
            end
        else
            local localNow = part:getStiffness()
            if near(localNow, target, 1) and sends("applyBodyStiffness") == baseSends then
                report("PASS", "stiff", "stiffness applied locally with no network traffic", "now=" .. fmt(localNow))
            else
                report("FAIL", "stiff", "local stiffness wrong or a command was sent",
                    "now=" .. fmt(localNow) .. " sends=" .. (sends("applyBodyStiffness") - baseSends))
            end
        end
        part:setStiffness(original)
        if isMP() then
            sendClientCommand(player(), 'RedDays', 'applyBodyStiffness', { Torso_Upper = original })
        end
        nextStep()
    end)
end

local function stepItem(nextStep)
    local item = RD_zapi.getWornItemAtLocation(HYGIENE_LOCATION)
    if not item then
        report("SKIP", "item", "no hygiene item worn", "wear a tampon pad or liner and rerun to cover item sync")
        return nextStep()
    end
    local original = item:getCondition()
    local target = original > 1 and original - 1 or original + 1
    local baseSends = sends("updateSanitaryItem")
    RD_HygieneManager.debugSetCondition(target)
    probe(function(reply)
        if isMP() then
            if reply and reply.itemCondition == target then
                report("PASS", "item", "item condition reached the server", "server=" .. tostring(reply.itemCondition))
            else
                report("FAIL", "item", "server item condition differs",
                    "expected " .. target .. " server=" .. tostring(reply and reply.itemCondition))
            end
        else
            if item:getCondition() == target and sends("updateSanitaryItem") == baseSends then
                report("PASS", "item", "condition changed locally with no network traffic")
            else
                report("FAIL", "item", "local condition wrong or a command was sent",
                    "now=" .. tostring(item:getCondition()))
            end
        end
        RD_HygieneManager.debugSetCondition(original)
        nextStep()
    end)
end

local TSS_RESTORED_STATS = {
    { key = "sickness", stat = "SICKNESS" },
    { key = "unhappiness", stat = "UNHAPPINESS" },
    { key = "thirst", stat = "THIRST" },
    { key = "fatigue", stat = "FATIGUE" },
    { key = "endurance", stat = "ENDURANCE" },
}

local function stepTSS(nextStep)
    local ic = icdata()
    if not (ic and ic.tss) then
        report("FAIL", "tss", "no TSS data on this player")
        return nextStep()
    end
    if not RD_TSSManager.isEnabled() then
        report("SKIP", "tss", "TSS disabled in sandbox")
        return nextStep()
    end

    local p = player()
    local stats = p:getStats()
    local snapshot = deepCopy(ic.tss)
    local saved = { blur = p:getSleepingTabletEffect() }
    for _, entry in ipairs(TSS_RESTORED_STATS) do
        saved[entry.key] = stats:get(CharacterStat[entry.stat])
    end

    probe(function(reply0)
        local baseSends = sends("applyTSSStats")
        local baseMinutes = ST.minuteTicks
        local unhappyBefore = stats:get(CharacterStat.UNHAPPINESS)
        RD_DebugAPI.tss.preset.apply("stage2_progressing")
        -- Only the TSS tick advances this, so it proves the tick ran. Unhappiness can't: PMS
        -- sadness and the game's own mood changes move it too, in either direction.
        local symptomMinutesBefore = ic.tss.first_symptom_minutes or 0

        waitUntil(function() return ST.minuteTicks - baseMinutes >= 3 end, 60000, function(ticked)
            after(1500, function()
                probe(function(reply1)
                    local tssTicks = (ic.tss.first_symptom_minutes or 0) - symptomMinutesBefore
                    local clientChange = stats:get(CharacterStat.UNHAPPINESS) - unhappyBefore
                    local sent = sends("applyTSSStats") - baseSends
                    local detail = "tss ticks=" .. tssTicks .. " sends=" .. sent
                        .. " client unhappiness change=" .. fmt(clientChange)

                    if not ticked then
                        report("FAIL", "tss", "fewer than 3 game minutes passed in 60s", detail)
                    elseif tssTicks < 1 then
                        report("FAIL", "tss", "the TSS tick did not run", detail)
                    elseif isMP() then
                        local serverChange = (reply0 and reply1) and (reply1.unhappiness - reply0.unhappiness) or nil
                        detail = detail .. " server change=" .. fmt(serverChange)
                        -- Synced means the server moved exactly as the client did, whichever way.
                        if sent >= 1 and serverChange and math.abs(serverChange - clientChange) <= 0.05 then
                            report("PASS", "tss", "TSS tick runs and syncs to the server", detail)
                        else
                            report("FAIL", "tss", "TSS tick did not reach the server", detail)
                        end
                    elseif sent == 0 then
                        report("PASS", "tss", "TSS ticks locally with no network traffic", detail)
                    else
                        report("FAIL", "tss", "TSS sent network traffic in SP", detail)
                    end

                    ic.tss = snapshot
                    for _, entry in ipairs(TSS_RESTORED_STATS) do
                        stats:set(CharacterStat[entry.stat], saved[entry.key])
                    end
                    p:setSleepingTabletEffect(saved.blur)
                    sendStats(saved)
                    transmit()
                    nextStep()
                end)
            end)
        end)
    end)
end

local function stepWear(nextStep)
    local item = RD_zapi.getWornItemAtLocation(HYGIENE_LOCATION)
    local ic = icdata()
    local cycle = ic and ic.currentCycle
    if not item then
        report("SKIP", "wear", "no hygiene item worn", "wear a tampon pad or liner and rerun to cover wear-down sync")
        return nextStep()
    end
    if not cycle then
        report("FAIL", "wear", "no cycle data on this player")
        return nextStep()
    end

    local savedPhase, savedRemaining = cycle.current_phase, cycle.phase_minutes_remaining
    local savedCondition, savedName = item:getCondition(), item:getName()
    local function restore()
        cycle.current_phase = savedPhase
        cycle.phase_minutes_remaining = savedRemaining
        item:setCondition(savedCondition)
        item:setName(savedName)
        if isMP() then
            sendClientCommand(player(), 'RedDays', 'updateSanitaryItem',
                { itemId = item:getID(), newCondition = savedCondition, newName = savedName })
        end
        transmit()
    end

    -- A fresh item wears down on the very first red-phase tick.
    RD_HygieneManager.debugSetCondition(10)
    cycle.current_phase = "redPhase"
    cycle.phase_minutes_remaining = math.max(60, cycle.redPhase_duration_mins or 1440)

    waitUntil(function() return item:getCondition() < 10 end, 60000, function(ok)
        after(1500, function()
            probe(function(reply)
                local condition, name = item:getCondition(), item:getName()
                local detail = "client " .. tostring(condition) .. " " .. tostring(name)
                if not ok then
                    report("FAIL", "wear", "the item did not wear down within 60s", detail)
                elseif not isMP() then
                    report("PASS", "wear", "red-phase wear-down works", detail)
                elseif reply and reply.itemCondition == condition and reply.itemName == name then
                    report("PASS", "wear", "wear-down reached the server", detail)
                else
                    report("FAIL", "wear", "the server's item differs", detail .. " server "
                        .. tostring(reply and reply.itemCondition) .. " " .. tostring(reply and reply.itemName))
                end
                restore()
                nextStep()
            end)
        end)
    end)
end

local PMS_STAT_SYMPTOMS = { pms_agitation = true, pms_fatigue = true, pms_craveFood = true, pms_Sadness = true }

local function stepPMS(nextStep)
    local ic = icdata()
    local cycle = ic and ic.currentCycle
    if not cycle then
        report("FAIL", "pms", "no cycle data on this player")
        return nextStep()
    end
    local p = player()
    local stats = p:getStats()
    local savedCycle = deepCopy(cycle)
    local saved = {
        anger = stats:get(CharacterStat.ANGER),
        unhappiness = stats:get(CharacterStat.UNHAPPINESS),
        fatigue = stats:get(CharacterStat.FATIGUE),
        endurance = stats:get(CharacterStat.ENDURANCE),
    }

    probe(function(reply0)
        local baseSends = sends("applyPMSStats")
        local baseMinutes = ST.minuteTicks
        local angerBefore = stats:get(CharacterStat.ANGER)
        -- Late luteal: PMS near full strength, with only the four stat-based symptoms on.
        cycle.current_phase = "lutealPhase"
        cycle.phase_minutes_remaining = 30
        cycle.healthEffectSeverity = 100
        for _, key in ipairs(PMS_SYMPTOM_KEYS) do cycle[key] = PMS_STAT_SYMPTOMS[key] == true end

        waitUntil(function() return ST.minuteTicks - baseMinutes >= 3 end, 60000, function(ticked)
            after(1500, function()
                probe(function(reply1)
                    local sent = sends("applyPMSStats") - baseSends
                    local angerRise = stats:get(CharacterStat.ANGER) - angerBefore
                    local detail = "sends=" .. sent .. " client anger rise=" .. fmt(angerRise)

                    if not ticked then
                        report("FAIL", "pms", "fewer than 3 game minutes passed in 60s", detail)
                    elseif isMP() then
                        local serverRise = (reply0 and reply1) and (reply1.anger - reply0.anger) or nil
                        detail = detail .. " server anger rise=" .. fmt(serverRise)
                        if sent >= 1 and serverRise and serverRise > 0 then
                            report("PASS", "pms", "PMS stat effects reach the server", detail)
                        else
                            report("FAIL", "pms", "PMS stat effects did not reach the server", detail)
                        end
                    elseif angerRise > 0 and sent == 0 then
                        report("PASS", "pms", "PMS stat effects apply locally with no network traffic", detail)
                    else
                        report("FAIL", "pms", "PMS stat effects missing or sent network traffic in SP", detail)
                    end

                    -- Restore. The cycle loses the few minutes the check took.
                    ic.currentCycle = savedCycle
                    stats:set(CharacterStat.ANGER, saved.anger)
                    stats:set(CharacterStat.UNHAPPINESS, saved.unhappiness)
                    stats:set(CharacterStat.FATIGUE, saved.fatigue)
                    stats:set(CharacterStat.ENDURANCE, saved.endurance)
                    if isMP() then
                        -- A huge step with the old value as the target sets anger to exactly that value.
                        sendClientCommand(p, 'RedDays', 'applyPMSStats', { angerTarget = saved.anger, angerStep = 1000 })
                        sendStats({ unhappiness = saved.unhappiness, fatigue = saved.fatigue, endurance = saved.endurance })
                    end
                    transmit()
                    nextStep()
                end)
            end)
        end)
    end)
end

-- Body and clothing stains must reach the server. The first hosted run reported both LOST, which
-- led to Commands.applyStains; this now checks that fix.
local function stepStains(nextStep)
    local ic = icdata()
    local visual = RD_zapi.getHumanVisual()
    if not (ic and visual) then
        report("FAIL", "stains", "no player data or body visual")
        return nextStep()
    end
    local garment = findGroinGarment()
    local groin = BloodBodyPartType.Groin
    local function readStains()
        return {
            blood = visual:getBlood(groin), dirt = visual:getDirt(groin),
            garmentBlood = garment and garment:getBlood(groin) or 0,
            garmentDirt = garment and garment:getDirt(groin) or 0,
        }
    end

    probe(function(reply0)
        local before = readStains()
        local savedLeak = ic.LeakLevel
        ic.LeakLevel = 0.35  -- the lightest tier: groin only, no dripping
        RD_HygieneManager.addBloodStains()
        RD_HygieneManager.addDirtStains()
        ic.LeakLevel = savedLeak
        local stained = readStains()
        local bodyChanged = stained.blood > before.blood or stained.dirt > before.dirt
        local garmentChanged = stained.garmentBlood > before.garmentBlood or stained.garmentDirt > before.garmentDirt

        after(3000, function()
            probe(function(reply1)
                local detail = "client body blood " .. fmt(before.blood) .. " to " .. fmt(stained.blood)
                    .. " dirt " .. fmt(before.dirt) .. " to " .. fmt(stained.dirt)
                if not bodyChanged then
                    report("SKIP", "stains", "the groin is already fully stained", "wash and rerun")
                    return nextStep()
                end
                if not isMP() then
                    report("PASS", "stains", "stains applied locally", detail)
                    return nextStep()
                end
                if not (reply0 and reply1) then
                    report("FAIL", "stains", "probe timed out")
                    return nextStep()
                end

                local bodyReached = (reply1.groinBlood or 0) > (reply0.groinBlood or 0)
                    or (reply1.groinDirt or 0) > (reply0.groinDirt or 0)
                report(bodyReached and "PASS" or "FAIL", "stains",
                    "body stains " .. (bodyReached and "reached" or "did not reach") .. " the server",
                    detail .. " server blood " .. fmt(reply0.groinBlood) .. " to " .. fmt(reply1.groinBlood)
                    .. " dirt " .. fmt(reply0.groinDirt) .. " to " .. fmt(reply1.groinDirt))

                if garment and garmentChanged then
                    local garmentReached = (reply1.garmentBlood or 0) > (reply0.garmentBlood or 0)
                        or (reply1.garmentDirt or 0) > (reply0.garmentDirt or 0)
                    report(garmentReached and "PASS" or "FAIL", "stains",
                        "clothing stains " .. (garmentReached and "reached" or "did not reach") .. " the server",
                        "client blood " .. fmt(before.garmentBlood) .. " to " .. fmt(stained.garmentBlood)
                        .. " server " .. fmt(reply0.garmentBlood) .. " to " .. fmt(reply1.garmentBlood))
                else
                    report("INFO", "stains", "no garment over the groin",
                        "wear pants to also cover clothing stains")
                end
                nextStep()
            end)
        end)
    end)
end

-- ================= GUIDED CHECKS =================

local function instruct(msg)
    note("ACTION NEEDED ---- " .. msg)
    local p = player()
    if p and p.Say then p:Say(msg) end
end

-- Waits for the player to finish an action, then reports which methods ran on this side.
-- `finishedBy` lists the methods that end the wait (default perform). A drink that empties its
-- container ends through stop() on an MP client, so the milk step also accepts stop.
local function waitForAction(className, fullType, callback, finishedBy)
    finishedBy = finishedBy or { "perform" }
    local base = {}
    for _, method in ipairs({ "perform", "complete", "stop" }) do
        base[method] = ST.hookCount(className, method, fullType)
    end
    local function delta(method) return ST.hookCount(className, method, fullType) - base[method] end
    waitUntil(function()
        for _, method in ipairs(finishedBy) do
            if delta(method) > 0 then return true end
        end
        return false
    end, ACTION_TIMEOUT_MS, function(ok)
        after(1000, function()
            callback(ok, (isMP() and "client" or "local") .. " perform x" .. delta("perform")
                .. " complete x" .. delta("complete") .. " stop x" .. delta("stop"), delta)
        end)
    end)
end

local function stepGiveItems(nextStep)
    sendClientCommand(player(), 'RedDays', 'rdTestGiveItems', {})
    after(1500, function()
        report("INFO", "give", "requested test items", "Pills 2 Antibiotics Cheese Milk Tampon")
        nextStep()
    end)
end

local function stepPill(nextStep)
    instruct("Take one Painkillers now")
    waitForAction("ISTakePillAction", "Base.Pills", function(ok, hooks)
        local ic = icdata()
        if not ok then
            report("FAIL", "pill", "no painkiller taken within 120s", hooks)
        elseif ic.pill_effect_active and (ic.pill_effect_counter or 0) <= 1 then
            report("PASS", "pill", "painkiller effect registered", hooks)
        else
            report("FAIL", "pill", "painkiller effect not registered",
                "active=" .. tostring(ic.pill_effect_active) .. " " .. hooks)
        end
        nextStep()
    end)
end

local function stepAntibiotics(nextStep)
    local ic = icdata()
    if not (ic and ic.tss) then
        report("FAIL", "abx", "no TSS data on this player")
        return nextStep()
    end
    if not RD_TSSManager.isEnabled() then
        report("SKIP", "abx", "TSS disabled in sandbox")
        return nextStep()
    end
    local snapshot = deepCopy(ic.tss)
    if (ic.tss.stage or 0) < 1 then
        ic.tss.stage = 1
        transmit()
    end
    local baseDoses = ic.tss.abx_dose_count or 0
    instruct("Eat one Antibiotics now. TSS is at stage 1 for this check and gets restored after")

    waitForAction("ISEatFoodAction", "Base.Antibiotics", function(ok, hooks)
        local live = icdata().tss
        local delta = (live.abx_dose_count or 0) - baseDoses
        local function finish()
            icdata().tss = snapshot
            transmit()
            nextStep()
        end
        if not ok then
            report("FAIL", "abx", "no antibiotics eaten within 120s", hooks)
            return finish()
        end
        if delta ~= 1 then
            report("FAIL", "abx", delta == 0 and "dose did not register" or ("dose counted " .. delta .. " times"), hooks)
            return finish()
        end
        if not isMP() then
            report("PASS", "abx", "dose registered exactly once", hooks)
            return finish()
        end
        transmit()
        after(2000, function()
            probe(function(reply)
                if reply and reply.abxDoses == live.abx_dose_count then
                    report("PASS", "abx", "dose registered once and the server modData sees it", hooks)
                else
                    report("FAIL", "abx", "dose registered but the server modData is stale",
                        "client=" .. tostring(live.abx_dose_count) .. " server=" .. tostring(reply and reply.abxDoses)
                        .. " " .. hooks)
                end
                finish()
            end)
        end)
    end)
end

local function stepCheese(nextStep)
    local ic = icdata()
    ic.food_pms_reduction_pct = 0
    report("INFO", "cheese", "food PMS reduction reset to 0 for a clean reading")
    instruct("Eat some Cheese now")
    waitForAction("ISEatFoodAction", "Base.Cheese", function(ok, hooks)
        local pct = icdata().food_pms_reduction_pct or 0
        if not ok then
            report("FAIL", "cheese", "no cheese eaten within 120s", hooks)
        elseif pct == 8 then
            report("PASS", "cheese", "food PMS credit registered once", "pct=" .. pct .. " " .. hooks)
        else
            report("FAIL", "cheese", pct == 16 and "credit counted twice" or "unexpected credit",
                "pct=" .. pct .. " " .. hooks)
        end
        nextStep()
    end)
end

local function stepMilk(nextStep)
    local base = icdata().food_pms_reduction_pct or 0
    local cap = (SandboxVars.RedDays or {}).foodPMSReductionCapPct or 20
    local expected = math.min(cap, base + 10)
    -- The whole carton on purpose: in MP that ends the client's action through stop(), the path
    -- that used to lose the credit.
    instruct("Drink the whole Milk carton now")
    waitForAction("ISDrinkFluidAction", nil, function(ok, hooks, delta)
        local pct = icdata().food_pms_reduction_pct or 0
        if not ok then
            report("FAIL", "milk", "nothing drunk within 120s", hooks)
        elseif pct == expected then
            report("PASS", "milk", "drink credit registered once", "pct=" .. pct .. " " .. hooks)
        elseif pct == base and delta("perform") == 0 then
            report("FAIL", "milk", "the drink stopped before the carton was empty, so it did not count",
                "pct=" .. pct .. " " .. hooks)
        else
            report("FAIL", "milk", "unexpected drink credit",
                "expected " .. expected .. " pct=" .. pct .. " " .. hooks)
        end
        nextStep()
    end, { "perform", "stop" })
end

local function stepHygiene(nextStep)
    local startSeq = ST.hookSeqCounter
    instruct("Wear the Tampon or your pad or liner if not already, take it off, then wear it again")
    -- Order matters: finish only once a wear happens AFTER a take-off. Waiting on "both have
    -- happened" ended the check during the pause between taking it off and putting it back on.
    waitUntil(function()
        local unequipped = lastHookSeq("ISUnequipAction", "perform")
        return unequipped > startSeq and lastHookSeq("ISWearClothing", "perform") > unequipped
    end, ACTION_TIMEOUT_MS * 2, function(ok)
        after(1000, function()
            local worn = RD_zapi.getWornItemAtLocation(HYGIENE_LOCATION)
            if not ok then
                report("FAIL", "hygiene", "take off then wear again not done within 240s")
            elseif worn then
                report("PASS", "hygiene", "unequip and wear hooks fired", "worn=" .. tostring(worn:getFullType()))
            else
                report("FAIL", "hygiene", "hooks fired but no hygiene item is worn now")
            end
            nextStep()
        end)
    end)
end

local function stepToxicShockCourse(nextStep)
    local ic = icdata()
    if not (ic and ic.tss) then
        report("FAIL", "abx4", "no TSS data on this player")
        return nextStep()
    end
    if not RD_TSSManager.isEnabled() then
        report("SKIP", "abx4", "TSS disabled in sandbox")
        return nextStep()
    end
    local p = player()
    local bd = p:getBodyDamage()
    if bd:getHealth() < 80 then
        report("SKIP", "abx4", "health below 80", "heal up and rerun, this check spends a few HP")
        return nextStep()
    end

    local stats = p:getStats()
    local snapshot = deepCopy(ic.tss)
    local savedSickness = stats:get(CharacterStat.SICKNESS)
    local savedBlur = p:getSleepingTabletEffect()
    local function finish()
        icdata().tss = snapshot
        stats:set(CharacterStat.SICKNESS, savedSickness)
        p:setSleepingTabletEffect(savedBlur)
        sendStats({ sickness = savedSickness, blur = savedBlur })
        transmit()
        nextStep()
    end

    RD_DebugAPI.tss.preset.apply("stage4_critical")
    instruct("Eat one more Antibiotics now. TSS is at toxic shock for this check and gets restored after")

    waitForAction("ISEatFoodAction", "Base.Antibiotics", function(ok, hooks)
        local live = icdata().tss
        if not ok then
            report("FAIL", "abx4", "no antibiotics eaten within 120s", hooks)
            return finish()
        end
        if (live.abx_suppress_mins or 0) <= 0 or (live.abx_dose_count or 0) ~= 1 then
            report("FAIL", "abx4", "the dose did not start the suppression window",
                "doses=" .. tostring(live.abx_dose_count) .. " suppress=" .. tostring(live.abx_suppress_mins) .. " " .. hooks)
            return finish()
        end

        local cap = (SandboxVars.RedDays or {}).tss_abx_sleep_health_cap_pct or 50
        local lowest = bd:getHealth()
        local baseMinutes = ST.minuteTicks
        waitUntil(function()
            local h = bd:getHealth()
            if h < lowest then lowest = h end
            return ST.minuteTicks - baseMinutes >= 2
        end, 60000, function(ticked)
            after(1500, function()
                probe(function(reply)
                    local mode = tostring(live._lastHPDrainMode)
                    local detail = "mode=" .. mode .. " lowest hp=" .. fmt(lowest) .. " cap=" .. fmt(cap) .. " " .. hooks
                    local protected = mode == "abx_cap_sickness_drain" or mode == "abx_flat_drain"
                        or mode == "abx_sleep_regen"
                    if not ticked then
                        report("FAIL", "abx4", "fewer than 2 game minutes passed in 60s", detail)
                    elseif not protected then
                        report("FAIL", "abx4", "health drain is not in an antibiotic mode", detail)
                    elseif lowest < cap then
                        report("FAIL", "abx4", "health fell below the antibiotic cap", detail)
                    elseif isMP() and not (reply and reply.abxDoses == live.abx_dose_count
                            and (reply.health or 0) >= cap) then
                        report("FAIL", "abx4", "the server disagrees", detail .. " server doses="
                            .. tostring(reply and reply.abxDoses) .. " hp=" .. fmt(reply and reply.health))
                    else
                        report("PASS", "abx4", "antibiotics protect health during toxic shock", detail)
                    end
                    finish()
                end)
            end)
        end)
    end)
end

-- ================= SAVE / RELOAD =================
-- The snapshot goes to a file in the Zomboid/Lua folder, not into the save, so nothing
-- test-related is ever stored on the character.

local PERSIST_FILE = "RD_selftest_persist.txt"
local PERSIST_KEYS = {
    "phase", "remaining", "worldMinutes", "tssStage", "abxDoses", "foodPct", "journalID",
    "pms_agitation", "pms_cramps", "pms_fatigue", "pms_tenderBreasts", "pms_craveFood", "pms_Sadness",
}

local function persistSnapshot()
    local ic = icdata() or {}
    local cycle = ic.currentCycle or {}
    local tss = ic.tss or {}
    local snap = {
        phase = cycle.current_phase,
        remaining = cycle.phase_minutes_remaining,
        worldMinutes = math.floor((RD_zapi.getGameTime("getWorldAgeHours") or 0) * 60 + 0.5),
        tssStage = tss.stage,
        abxDoses = tss.abx_dose_count,
        foodPct = ic.food_pms_reduction_pct,
        journalID = ic.journalID,
    }
    for _, key in ipairs(PMS_SYMPTOM_KEYS) do snap[key] = cycle[key] end
    return snap
end

local function readPersistFile()
    local reader = getFileReader(PERSIST_FILE, false)
    if not reader then return nil end
    local saved, any = {}, false
    local line = reader:readLine()
    while line do
        local key, value = string.match(line, "^([%w_]+)=([^\r]*)")
        if key then
            saved[key] = value
            any = true
        end
        line = reader:readLine()
    end
    reader:close()
    if not any then return nil end
    return saved
end

local function clearPersistFile()
    local writer = getFileWriter(PERSIST_FILE, true, false)
    if writer then writer:close() end
end

function ST.persistSave()
    local snap = persistSnapshot()
    local writer = getFileWriter(PERSIST_FILE, true, false)
    if not writer then
        note("FAIL persist could not write the snapshot file")
        return
    end
    for _, key in ipairs(PERSIST_KEYS) do
        writer:write(key .. "=" .. tostring(snap[key]) .. "\n")
    end
    writer:close()
    note("INFO persist snapshot saved ---- save the game, quit to the main menu, load it again, "
        .. "then run rd.mptest.persistCheck()")
end

local function stepPersistCompare(nextStep)
    local saved = readPersistFile()
    if not saved then
        report("FAIL", "persist", "no snapshot found", "run rd.mptest.persistSave() before saving and reloading")
        return nextStep()
    end
    local live = persistSnapshot()
    local elapsed = live.worldMinutes - (tonumber(saved.worldMinutes) or 0)
    report("INFO", "persist", "snapshot loaded", "in-game minutes since the snapshot " .. tostring(elapsed)
        .. " food pct " .. tostring(saved.foodPct) .. " now " .. tostring(live.foodPct))

    local function same(key, label)
        if tostring(live[key]) == saved[key] then
            report("PASS", "persist", label .. " survived the reload", tostring(live[key]))
        else
            report("FAIL", "persist", label .. " changed across the reload",
                "saved " .. tostring(saved[key]) .. " now " .. tostring(live[key]))
        end
    end
    same("journalID", "journal ID")
    same("tssStage", "TSS stage")
    same("abxDoses", "antibiotic dose count")

    local symptomsSame = true
    for _, key in ipairs(PMS_SYMPTOM_KEYS) do
        if tostring(live[key]) ~= saved[key] then symptomsSame = false end
    end
    if symptomsSame then
        report("PASS", "persist", "PMS symptom flags survived the reload")
    else
        report("FAIL", "persist", "PMS symptom flags changed across the reload")
    end

    -- The cycle keeps running, so allow for the in-game minutes between snapshot and check.
    if live.phase == saved.phase then
        local drift = (tonumber(saved.remaining) or 0) - (live.remaining or 0) - elapsed
        local detail = "saved " .. tostring(saved.remaining) .. " now " .. tostring(live.remaining)
            .. " elapsed " .. tostring(elapsed)
        if math.abs(drift) <= 30 then
            report("PASS", "persist", "cycle countdown survived the reload", detail)
        else
            report("FAIL", "persist", "cycle countdown jumped across the reload", detail)
        end
    else
        report("INFO", "persist", "the cycle moved to a new phase since the snapshot",
            "saved " .. tostring(saved.phase) .. " now " .. tostring(live.phase))
    end
    nextStep()
end

local function stepPersistServer(nextStep)
    if not isMP() then return nextStep() end
    probe(function(reply)
        local live = persistSnapshot()
        if reply and reply.tssStage == live.tssStage and reply.abxDoses == live.abxDoses
                and reply.journalID == live.journalID then
            report("PASS", "persist", "the server's copy matches after the reload")
        else
            report("FAIL", "persist", "the server's copy differs after the reload",
                "server stage " .. tostring(reply and reply.tssStage) .. " doses " .. tostring(reply and reply.abxDoses)
                .. " journal " .. tostring(reply and reply.journalID))
        end
        nextStep()
    end)
end

-- ================= ENTRY POINTS =================

function ST.run()
    if not startRun("run") then return end
    runSteps({
        stepEnv,
        stepProbe,
        needsProbe("moddata", stepModData),
        needsProbe("stat", stepStat),
        needsProbe("hp", stepHP),
        needsProbe("stiff", stepStiffness),
        needsProbe("item", stepItem),
        needsProbe("wear", stepWear),
        needsProbe("tss", stepTSS),
        needsProbe("pms", stepPMS),
        needsProbe("stains", stepStains),
    })
end

function ST.actions()
    if not startRun("actions") then return end
    ST._probeOK = true
    runSteps({
        stepGiveItems,
        stepPill,
        stepAntibiotics,
        stepCheese,
        stepMilk,
        stepHygiene,
        stepToxicShockCourse,
    })
end

function ST.persistCheck()
    if not startRun("persist") then return end
    ST._probeOK = true
    runSteps({
        stepPersistCompare,
        stepPersistServer,
        function(nextStep)
            clearPersistFile()
            nextStep()
        end,
    })
end

function ST.help()
    note("rd.mptest.run() runs the automated checks, about a minute. Wear a hygiene item and pants first")
    note("rd.mptest.actions() gives test items and walks you through eating drinking and dressing")
    note("rd.mptest.persistSave() then save, quit to menu, reload, and rd.mptest.persistCheck()")
    note("each run ends with a DONE line. Logs go to console.txt, and coop-console.txt for the MP server")
end

installTracer()
Events.OnTick.Add(onTick)
Events.EveryOneMinute.Add(onMinute)
Events.OnServerCommand.Add(onServerCommand)
-- In SP the sendServerCommand global is a no-op, so RD_server_commands.lua calls this directly.
ST.onServerCommand = onServerCommand
note("self-test loaded ---- type rd.mptest.help() for usage")
