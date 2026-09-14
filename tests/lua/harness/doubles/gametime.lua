-- GameTime double.
--
-- RD_zapi.getGameTime(name) indexes this dynamically -- gameTime[name](gameTime)
-- -- so every accessor must exist as a named field, not just on a metatable.

local M = {}

function M.new(opts)
    opts = opts or {}
    local gt = {
        __gameTime = true,
        day = opts.day or 0,             -- 0-based, as the engine reports it
        month = opts.month or 6,         -- 0-based
        year = opts.year or 1993,
        worldAgeHours = opts.worldAgeHours or 0,
        secondsSinceLastUpdate = opts.secondsSinceLastUpdate or 3.0,
    }

    function gt:getDay() return self.day end
    function gt:getDayPlusOne() return self.day + 1 end
    function gt:getMonth() return self.month end
    function gt:getYear() return self.year end
    function gt:getWorldAgeHours() return self.worldAgeHours end
    function gt:getGameWorldSecondsSinceLastUpdate() return self.secondsSinceLastUpdate end

    -- Advances the clock the way sim.lua's minute loop expects.
    function gt:advanceMinutes(mins)
        self.worldAgeHours = self.worldAgeHours + (mins / 60)
        local totalDays = math.floor(self.worldAgeHours / 24)
        self.day = totalDays % 30
        self.month = math.floor(totalDays / 30) % 12
    end

    return gt
end

return M
