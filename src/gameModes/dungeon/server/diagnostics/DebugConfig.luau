-- src/gameModes/dungeon/server/diagnostics/DebugConfig.luau
--
-- ONE SWITCHBOARD FOR EVERY DIAGNOSTIC. Replaces the `local ENABLED = true`
-- that had accumulated in six separate files.
--
-- WHY THIS EXISTS. Per-file flags fail in a specific way: turning things off
-- means editing six files, so nobody does, so the output stays loud, so the
-- output stops being read. A flag you have to hunt for is a flag that stays
-- wherever it was last left.
--
-- BACKED BY WORKSPACE ATTRIBUTES, which is the part worth knowing:
--
--     workspace:SetAttribute("DebugHurtboxes", false)
--
-- typed into Studio's command bar -- or edited in the Properties panel with
-- the game RUNNING -- takes effect immediately. No restart, no rebuild, no
-- recompile. That is what makes this a debug MODE rather than a constant.
--
-- The defaults below are what you get when no attribute is set, so a fresh
-- session starts sensible and a session you have been poking at stays poked.
--
-- THE SPLIT THAT MATTERS: visuals default ON, logs default OFF. A coloured
-- volume you can see costs a glance; a line printed eight times per swing
-- costs the whole output window. They are not the same kind of thing and
-- should not share a switch.

local DebugConfig = {}

local PREFIX = "Debug"

-- name -> default. Each becomes a Workspace attribute `Debug<Name>`.
local FLAGS = {
    -- ---- VISUAL: coloured parts in the world -------------------------------
    -- Every attached body's hurtbox, drawn live and following it.
    Hurtboxes = true,

    -- The attack volume the server actually resolved, drawn for a third of a
    -- second, plus a marker on everything it caught.
    Hitboxes = true,

    -- A sweeping blade's whole arc, left standing for a few seconds after the
    -- swing. Off by default: useful for one swing, unreadable for ten.
    SweepPath = false,

    -- RETIRED 2026-08-21, with the files they switched (`_toDelete/`):
    --   SweepTrace     per-wedge table. Went with the SWEEP default
    --   LimbProbe      answered its question; finding is in HitDetection 9.6
    --   EnemyAttacks   the whole enemy attack path, until PATH hitboxes exist
    --
    -- Listed rather than silently dropped because a flag that vanishes leaves
    -- `workspace:SetAttribute("DebugSweepTrace", true)` sitting in someone's
    -- command-bar history doing nothing, with no clue why.

    -- Draws hurtboxes from the SERVER'S copy of each body instead of welding
    -- them to it. On your own character the difference is the whole round trip
    -- made visible -- the overlay trails you by however far behind the server
    -- is. That is a real measurement and a terrible way to check shape, which
    -- is why it is a separate switch and why it is off.
    -- See HurtboxDebug's header.
    HurtboxServerView = false,

    -- ---- LOGGING: text ----------------------------------------------------
    -- Per-swing breakdown: latency, rewind, broadphase, and every candidate
    -- with the numbers it was judged on.
    SwingReport = false,

    -- Per-zone positions, printed periodically, in BOTH world space and
    -- relative to the body's root.
    --
    -- The two columns answer two different questions and the difference is
    -- the whole reason both are printed:
    --
    --   WORLD changes as you walk        -> the overlay is attached and riding
    --                                       the body. If it does NOT change,
    --                                       the weld is broken.
    --   REL ROOT stays fixed             -> zones are anchored to the root,
    --                                       which is the current design for
    --                                       client-owned rigs (HitDetection
    --                                       7.2a). Limbs animating do not move
    --                                       them, and that is not a bug.
    HurtboxLog = false,


    -- One line per wedge as it fires. The noisy one.
    SweepWedges = false,

    -- ONE line per attack YOU make, with what it caught. The counterpart to
    -- DamageLog, which covers attacks made at you -- and on by default for the
    -- same reason: without it you can see every hit you take and none you
    -- land, which reads as the swing being broken.
    AttackLog = true,


    -- HP changes as they happen. Cheap and low-volume; the one log that
    -- earns being on by default.
    DamageLog = true,
}

local function attributeName(flag: string): string
    return PREFIX .. flag
end

-- Reads the live attribute, falling back to the default. Deliberately NOT
-- cached: the whole point is that flipping the attribute mid-session works,
-- and an attribute read is a hash lookup.
function DebugConfig.get(flag: string): boolean
    local default = FLAGS[flag]
    assert(default ~= nil, string.format(
        "[DebugConfig] unknown flag '%s' -- add it to FLAGS or fix the spelling",
        tostring(flag)))

    local value = workspace:GetAttribute(attributeName(flag))
    if type(value) ~= "boolean" then
        return default
    end
    return value
end

function DebugConfig.set(flag: string, value: boolean)
    assert(FLAGS[flag] ~= nil, string.format(
        "[DebugConfig] unknown flag '%s'", tostring(flag)))
    workspace:SetAttribute(attributeName(flag), value == true)
end

-- Fires when a flag changes, so a module holding instances (HurtboxDebug's
-- overlay parts) can tear them down rather than freezing them mid-air.
function DebugConfig.onChanged(flag: string, handler: (boolean) -> ())
    assert(FLAGS[flag] ~= nil, string.format(
        "[DebugConfig] unknown flag '%s'", tostring(flag)))

    return workspace:GetAttributeChangedSignal(attributeName(flag)):Connect(function()
        handler(DebugConfig.get(flag))
    end)
end

-- Writes every default onto Workspace at boot so the flags are VISIBLE in the
-- Properties panel. Without this they exist only in this file, and a toggle
-- nobody can find is a toggle nobody uses.
function DebugConfig.publish()
    for flag, default in pairs(FLAGS) do
        if workspace:GetAttribute(attributeName(flag)) == nil then
            workspace:SetAttribute(attributeName(flag), default)
        end
    end

    local on, off = {}, {}
    for flag in pairs(FLAGS) do
        table.insert(DebugConfig.get(flag) and on or off, flag)
    end
    table.sort(on)
    table.sort(off)

    print(string.format(
        "[DebugConfig] on: %s | off: %s",
        #on > 0 and table.concat(on, ", ") or "nothing",
        #off > 0 and table.concat(off, ", ") or "nothing"))
    print("    toggle live: select Workspace, edit the Debug* attributes -- "
        .. "or workspace:SetAttribute(\"DebugSwingReport\", true) in the command bar")
end

return DebugConfig
