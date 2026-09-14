-- Time-acceleration driver.
--
-- This is the main reason the suite exists: RD_main.lua registers its hooks as
-- file-locals on Events, the fake registry captures them, and this fires THE REAL
-- HANDLERS at the right cadence. Ninety in-game days run in well under a second,
-- so "wait out three cycles" becomes an assertion instead of an evening.

local M = {}

local MINUTES_PER_HOUR = 60
local MINUTES_PER_DAY = 1440

-- Advances the in-game clock by `minutes`, firing hooks on their real cadence.
--
-- opts:
--   framesPerMinute  how many OnPlayerUpdate calls per minute (default 0).
--                    The real engine fires it every frame; it is off by default
--                    because it is expensive and most tests don't need it.
--   onMinute         optional callback(env, minute) run after each minute, for
--                    sampling state across a long run.
function M.advanceMinutes(env, minutes, opts)
    opts = opts or {}
    local events = env.__test.events
    local gameTime = env.__test.gameTime
    local player = env.__test.player
    local framesPerMinute = opts.framesPerMinute or 0

    for minute = 1, minutes do
        gameTime:advanceMinutes(1)
        env.__test.elapsedMinutes = (env.__test.elapsedMinutes or 0) + 1
        local elapsed = env.__test.elapsedMinutes

        events.fire("EveryOneMinute")

        for _ = 1, framesPerMinute do
            events.fire("OnPlayerUpdate", player)
        end

        if elapsed % 10 == 0 then events.fire("EveryTenMinutes") end
        if elapsed % MINUTES_PER_HOUR == 0 then events.fire("EveryHours") end
        if elapsed % MINUTES_PER_DAY == 0 then events.fire("EveryDays") end

        if opts.onMinute then opts.onMinute(env, elapsed) end
    end

    return env
end

function M.advanceHours(env, hours, opts)
    return M.advanceMinutes(env, math.floor(hours * MINUTES_PER_HOUR), opts)
end

function M.advanceDays(env, days, opts)
    return M.advanceMinutes(env, math.floor(days * MINUTES_PER_DAY), opts)
end

-- Runs until `predicate(env)` is true or `limitMinutes` elapses.
-- Returns true plus the minutes taken, or false if the limit was hit.
function M.advanceUntil(env, predicate, limitMinutes, opts)
    limitMinutes = limitMinutes or (90 * MINUTES_PER_DAY)
    for i = 1, limitMinutes do
        M.advanceMinutes(env, 1, opts)
        if predicate(env) then return true, i end
    end
    return false, limitMinutes
end

return M
