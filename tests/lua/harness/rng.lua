-- Deterministic replacement for PZ's ZombRand / ZombRandFloat.
--
-- Two calling conventions are in use across this codebase and both are honoured:
--   ZombRand(n)      -> integer in [0, n-1]
--   ZombRand(a, b)   -> integer in [a, b-1]   (max-exclusive; see RD_cycle_irregularity.lua:52)
--
-- Uses a small xorshift so results are reproducible across platforms and
-- independent of the host's math.random state.

local M = {}

local function newState(seed)
    -- Avoid the all-zero state; any odd constant works as a fallback.
    local s = (seed or 0) % 2147483647
    if s <= 0 then s = s + 2147483646 end
    return s
end

-- Park-Miller minimal standard generator: period 2^31-2, no bit ops needed,
-- so it behaves identically under LuaJIT and plain Lua 5.1.
local function nextInt(self)
    self.state = (self.state * 16807) % 2147483647
    self.calls = self.calls + 1
    return self.state
end

local function nextFloat(self)
    return (nextInt(self) - 1) / 2147483646
end

-- Creates a generator plus the two globals the mod calls.
function M.new(seed)
    local self = { state = newState(seed), calls = 0, scripted = nil, scriptIndex = 0 }

    -- Feed an exact sequence of results for tests that need a specific roll.
    -- Values are returned in order; once exhausted it falls back to the PRNG.
    function self.script(values)
        self.scripted = values
        self.scriptIndex = 0
    end

    function self.reseed(newSeed)
        self.state = newState(newSeed)
        self.calls = 0
        self.scripted = nil
        self.scriptIndex = 0
    end

    local function takeScripted()
        if not self.scripted then return nil end
        self.scriptIndex = self.scriptIndex + 1
        local v = self.scripted[self.scriptIndex]
        if v == nil then self.scripted = nil end
        return v
    end

    function self.ZombRand(a, b)
        local scripted = takeScripted()
        if scripted ~= nil then
            self.calls = self.calls + 1
            return scripted
        end
        local low, high   -- inclusive low, exclusive high
        if b == nil then
            low, high = 0, a
        else
            low, high = a, b
        end
        local span = high - low
        if not span or span <= 0 then return low end
        return low + (nextInt(self) % span)
    end

    function self.ZombRandFloat(a, b)
        local scripted = takeScripted()
        if scripted ~= nil then
            self.calls = self.calls + 1
            return scripted
        end
        if b == nil then a, b = 0, a or 1 end
        return a + nextFloat(self) * (b - a)
    end

    return self
end

return M
