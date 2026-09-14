# RedDays test suite

Runs the mod's real Lua against a fake Project Zomboid, so logic regressions and
client/server protocol drift get caught before the game is ever launched.

Nothing under `Contents/` is modified or required to change for these tests to
run — the actual shipped `.lua` files are loaded unmodified into a sandboxed
environment.

## Setup

```
pip install lupa
```

`lupa` embeds **LuaJIT 2.1**, which is Lua 5.1 — the same dialect PZ's Kahlua2 VM
targets. This matters: under Lua 5.4 `tostring(4.0)` is `"4.0"` where Kahlua and
5.1 both give `"4"`, which would make the journal/day-code text tests lie.

## Running

```
python tests/run.py                 # everything (~11s)
python tests/run.py --lua-only      # behavioural suites only
python tests/run.py --static-only   # static checks only
python tests/run.py -k cycle        # only suites whose filename matches "cycle"
python tests/run.py --version 42.18 # test a different version folder
```

Exit code is non-zero if anything failed, so this is CI-ready as-is.

## What it covers today

**Behavioural suites** (`tests/lua/suites/`) — 84 tests:

| Suite | Covers |
|---|---|
| `smoke_spec.lua` | The harness itself: real modules load, hooks register, worlds are isolated, seeds reproduce |
| `cycle_manager_spec.lua` | `tick()` decrement/transition/overflow, end-of-cycle regeneration, `getPhaseStatus` math, `isCycleValid` field-by-field, `getPMSseverity` curves, `newCycle` sandbox bounds and 10-attempt fallback, first-cycle start delay |
| `cycle_irregularity_spec.lua` | Follicular cap behaviour, per-trait weight delays, severity scaling, trauma threshold and once-per-cycle latch |
| `invariants_spec.lua` | Property tests over many seeds and up to 90 simulated days: no invalid phase, no negative countdown, no stall, cap never exceeded, exact one-minute-per-tick stepping, determinism |
| `mp_sync_spec.lua` | All three client→server commands round-tripped, plus four drift detectors |

**Static checks** (`tests/static/`) — no Lua harness, no game needed:

- `check_syntax.py` — parse-checks every `.lua` in *every* version folder (70 files)
- `check_sandbox_translations.py` — every `SandboxVars.RedDays.X` read exists in
  `sandbox-options.txt`; every option has a name *and* tooltip in `Sandbox.json`;
  every item, recipe, and moodle has its translation entries
- `check_api_contract.py` — every engine call the mod makes is verified to exist
  in `projectzomboid.jar`. Advisory only (constant-pool matching is fuzzy), but a
  clean run means no B42.x API drift

## How the harness works

`tests/lua/harness/` builds a fresh sandboxed global table per test and loads the
real mod files into it with `setfenv`, using a `require` shim that resolves flat
module names against `media/lua/{client,server,shared}` exactly like PZ's loader.

Three pieces do the heavy lifting:

- **`sim.lua` — time acceleration.** `RD_main.lua` registers its hooks as
  file-locals on `Events`; the fake registry captures them, so the simulator
  drives *the real registered handlers* at the right cadence (1/10/60/1440-minute
  buckets). Ninety in-game days run in about a second.
- **`rng.lua` — determinism.** Seeded PRNG replacing `ZombRand`, honouring both
  conventions in the codebase (`ZombRand(n)` → `0..n-1`, `ZombRand(a,b)` →
  `a..b-1`, max-exclusive). `rng.script{...}` feeds an exact roll sequence.
- **`mp.lua` — multiplayer.** A client env and a server env in one process. The
  client's `sendClientCommand` deep-copies the payload (standing in for
  serialisation, so shared-table aliasing shows up) and delivers it to the server
  env's real `OnClientCommand` handlers. The two sides hold *separate* player and
  item doubles that merely share IDs, so a change the server makes does not
  magically appear on the client.

### The MP drift detectors

These target failure modes that are silent in game:

1. **Unread-key detection** — the payload is wrapped in a proxy recording every
   field the handler reads. Anything sent but never read is reported. Client-side
   stat names are string literals passed through a generic `setStat` closure while
   the server reads them via an explicit `if args.X ~= nil` ladder; a mismatch
   currently vanishes without a trace.
2. **Command existence** — every `sendClientCommand(..., 'RedDays', 'x', ...)`
   must have a matching `Commands.x` on the server, and vice versa. Recovered by
   scanning source, because `Commands` is a file-local that cannot be enumerated
   at runtime.
3. **`hpMode` contract** — the set of `hpMode` values the client can emit is
   pinned. The server's final `else` is a deliberate catch-all for the two
   no-antibiotics modes, which may legitimately be lethal; any *new* mode would
   silently inherit that branch and drain an antibiotic-protected player to death
   while ignoring `hpCap`. The test forces that to be a conscious decision.
4. **Container resolution** — `Commands.updateSanitaryItem` scans worn items and
   top-level inventory only, so an item in a backpack is never found and the
   client's change is left unreplicated. Pinned so any change is deliberate.

## Adding a test

```lua
local T = require "runner"
local H = require "harness.init"

T.describe("my feature", function()
    T.it("does the thing", function()
        local w = H.newWorld({
            seed = 1,
            sandbox = { follicular_phase_max_days = 20 },  -- overrides the real defaults
            player  = { traits = { "OBESE" }, health = 80 },
        })
        w.advanceDays(3)
        T.eq(w.cycle().current_phase, "follicularPhase")
    end)
end)
```

Save as `tests/lua/suites/<name>_spec.lua`; it is picked up automatically.

Useful handles: `w.env` (the sandboxed globals, including every `RD_*` module),
`w.icdata()` (`player:getModData().ICdata`), `w.cycle()`, `w.t.player`,
`w.t.rng`, `w.t.mf` (moodle calls), `w.t.log()` (captured `print` output),
`w.t.sentCommands`. Assertions: `eq`, `neq`, `near`, `between`, `truthy`,
`falsy`, `isNil`, `notNil`, `contains`, `fail`.

Sandbox defaults come from the real `media/sandbox-options.txt`, parsed at
startup, so they can never drift from what ships.

## Fidelity notes

The environment deliberately **omits `next`**, because PZ's Kahlua VM does not
provide it (`RD_tss_manager.lua:975` works around exactly that). Using it fails
here instead of crashing a player in game. `io`, `os`, `dofile`, and `loadfile`
are omitted too.

`CharacterStat.TEMPERATURE`'s bounds are modelled as 0..1 with a 0.5 default.
The real values were never confirmed — the mod logs them at runtime for
calibration — so treat temperature-scale assertions as provisional.

## What this cannot catch

The harness models our *understanding* of the engine, not the engine. It will not
catch:

- a wrong assumption baked into both the mock and the mod
- engine behaviour changes between builds (the API contract check only partially
  compensates — it verifies a name still exists, not that it still behaves)
- real network serialisation, packet loss, or server-authority *ordering*
- rendering, model refresh, item script parsing, or world loot distribution
- anything about how the mod feels to play

Manual in-game testing becomes smaller and more targeted. It does not go away.

## Not yet covered (phase 2)

`RD_tss_manager` (stage progression, ABX dosing, complications, fever pressure),
`RD_hygiene_manager` (condition decrement, leak levels, stain tiers),
`RD_moodles` (level thresholds, the `0.42` clear sentinel), `RD_effects_pms`, and
`RD_cycle_tracker_text` (day codes, calendar formatting).

Most of the logic in those files is in file-`local` functions that tests cannot
reach directly. Covering them well needs a single `RD_X.__test = { ... }` export
line at the bottom of each — no logic changes — which is a deliberate decision to
take before touching shipped files.
