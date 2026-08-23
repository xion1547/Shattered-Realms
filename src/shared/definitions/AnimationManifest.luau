-- src/shared/definitions/AnimationManifest.luau
--
-- NAME YOU CHOSE -> ID ROBLOX CHOSE. That is the entire job. See Animation.md.
--
-- Adding an animation is one row here and nothing else (Animation.md Part 14).
-- No code edit, no engine change, no networking. The generic engine that reads
-- this is `client/playback/Rig.luau`.
--
-- ============================================================================
-- WHY THIS IS IN src/shared/ WHEN ALMOST NOTHING ELSE IS
-- ============================================================================
--
-- ReplicatedStorage is a BROADCAST, not a shared folder -- every client gets
-- everything in it and can read it whether or not any LocalScript requires it
-- (AssetPipeline Part 3). So living here is a deliberate disclosure and needs
-- a reason.
--
-- The reason: the client is the peer that plays a player's own animations
-- (Animation.md Part 3), so it genuinely executes this. That is the three-tree
-- test and this passes it.
--
-- AND THE DISCLOSURE COSTS NOTHING. An asset id is readable off any
-- character's Animator by anyone who cares to look. There is nothing here a
-- client could not already obtain, which makes this one of the few additions
-- to ReplicatedStorage that is genuinely free.
--
-- ============================================================================
-- WHAT MUST NEVER BE ADDED TO THIS TABLE
-- ============================================================================
--
-- `activeWindow`. Damage. Range. Cooldown. `sweep`. ANY number the server
-- resolves an attack with.
--
-- This is not tidiness, and the reasoning is worth keeping because the mistake
-- looks like a fix (Animation.md Part 9.5). The tempting framing is "hit timing
-- is mirrored between client and server, so put it somewhere both can see."
-- There is no client copy today. Putting one here would:
--
--   1. broadcast every hitbox timing in the game to every client, and
--   2. CREATE the second copy whose drift it claims to prevent.
--
-- The framing error manufactures the bug. Gameplay numbers live on the skill
-- definition, server-side, read only by TargetResolution.
--
-- The real axis is code <-> art: one number in the repo, one asset in the
-- cloud, and no automatic relationship between them. This table is the art
-- side and holds nothing else.

local AnimationManifest = {}

-- A row that has not been uploaded yet. Spelled as a constant rather than an
-- empty string so the intent is unmistakable at a glance and greppable in one
-- search -- and so `validate` can tell "nobody has uploaded this yet" apart
-- from "an id is here and it is wrong", which are completely different
-- problems with completely different fixes.
AnimationManifest.NOT_UPLOADED = "NOT_UPLOADED"

-- ============================================================================
-- THE ROWS
-- ============================================================================
--
-- KEY NAMING mirrors the Roblox asset name minus its `SR_` prefix
-- (Animation.md Part 4.1), so one grep finds the manifest row, the skill
-- definition that names it, and the upload itself:
--
--     SR_WARRIOR_SWING_1   ->   WARRIOR_SWING_1
--
-- The asset name is not load-bearing -- the id is -- but it is the only thing
-- visible in a list of two hundred uploads, which is the whole reason a
-- convention exists at all.
local ROWS = {
    WARRIOR_SWING_1 = {
        -- FILL THIS IN after uploading. Everything else is ready for it.
        assetId = AnimationManifest.NOT_UPLOADED,

        -- SET THIS AT AUTHOR TIME TOO, in Studio's editor. The value here is a
        -- backstop, not the source of truth.
        --
        -- A swing authored at `Core` is silently overpowered by the default
        -- walk cycle and simply does not appear to play. That looks EXACTLY
        -- like a failed asset load, it is the standard first-day bug, and no
        -- error is raised for either. `Action` outranks `Movement`, which is
        -- also what lets an upper-body swing play over a walk cycle without
        -- this system doing anything (HitDetection 9.4.3).
        priority = Enum.AnimationPriority.Action,

        -- Blend in and out. Short, because an attack should feel immediate --
        -- a long fade on a swing reads as input lag rather than as smoothness.
        fadeTime = 0.1,

        -- WHICH LOADOUTS BUILD A TRACK FOR THIS.
        --
        -- Listing every animation in the game here costs nothing -- it is a
        -- table of strings. The real cost is `Animator:LoadAnimation`, which
        -- builds an AnimationTrack per animation per rig and holds it in
        -- memory. So the manifest is exhaustive and the TRACKS are scoped.
        -- Animation.md Part 5.3.
        loadFor = { "WARRIOR" },
    },
}

-- ============================================================================
-- READING
-- ============================================================================

-- Fails loudly on an unknown key rather than returning nil.
--
-- A nil row travels: it becomes a nil assetId, becomes an Animation instance
-- pointing at nothing, becomes a track that never plays, and surfaces as "my
-- swing does not animate" three layers from the typo that caused it.
function AnimationManifest.get(name: string)
    local row = ROWS[name]
    assert(row, string.format(
        "[AnimationManifest] unknown animation '%s' -- add a row or fix the "
            .. "spelling", tostring(name)))
    return row
end

function AnimationManifest.has(name: string): boolean
    return ROWS[name] ~= nil
end

-- Every row whose `loadFor` includes this loadout, as name -> row.
--
-- A row with no `loadFor` at all belongs to EVERY loadout. That default is
-- deliberate: the failure mode of forgetting the field is then "this loads for
-- everyone", which costs a little memory, rather than "this silently loads for
-- nobody", which costs an animation that never plays and gives no clue why.
-- Wrong-generous over wrong-silent, the same asymmetry as the broadphase
-- margin.
function AnimationManifest.forLoadout(loadout: string)
    local matched = {}

    for name, row in pairs(ROWS) do
        if row.loadFor == nil then
            matched[name] = row
        else
            for _, entry in ipairs(row.loadFor) do
                if entry == loadout then
                    matched[name] = row
                    break
                end
            end
        end
    end

    return matched
end

function AnimationManifest.all()
    return table.clone(ROWS)
end

-- ============================================================================
-- VALIDATION
-- ============================================================================
--
-- Shape only. Whether an id actually RESOLVES is a different question, answered
-- by `AnimationTrack.Length > 0` once a track is built (Animation.md Part 7.4),
-- because that is the only symptom the asset-ownership trap produces.
--
-- RETURNS A LIST OF PROBLEMS RATHER THAN THROWING ON THE FIRST. Boot validation
-- exists so a developer sees everything wrong in one pass instead of fixing one
-- typo, restarting, and finding the next -- the same aggregate-and-fail-once
-- discipline as SignalService.validate and the place manifest check.
function AnimationManifest.validate(): (boolean, { string })
    local problems = {}

    for name, row in pairs(ROWS) do
        if type(row) ~= "table" then
            table.insert(problems, string.format("'%s' is not a table", name))
            continue
        end

        if type(row.assetId) ~= "string" or row.assetId == "" then
            table.insert(problems, string.format(
                "'%s': assetId must be a non-empty string", name))
        elseif row.assetId ~= AnimationManifest.NOT_UPLOADED
            and not string.match(row.assetId, "^rbxassetid://%d+$")
        then
            -- A BARE NUMBER IS THE COMMON MISTAKE and it fails in a confusing
            -- place: `Animation.AnimationId` accepts the string happily and the
            -- track just never loads, so the symptom is again "nothing plays".
            table.insert(problems, string.format(
                "'%s': assetId must look like 'rbxassetid://123456789' "
                    .. "(got '%s') -- a bare number is accepted by the engine "
                    .. "and then silently never loads", name, row.assetId))
        end

        if row.priority ~= nil
            and typeof(row.priority) ~= "EnumItem"
        then
            table.insert(problems, string.format(
                "'%s': priority must be an Enum.AnimationPriority", name))
        end

        if row.fadeTime ~= nil
            and (type(row.fadeTime) ~= "number" or row.fadeTime < 0)
        then
            table.insert(problems, string.format(
                "'%s': fadeTime must be zero or positive", name))
        end

        if row.loadFor ~= nil and type(row.loadFor) ~= "table" then
            table.insert(problems, string.format(
                "'%s': loadFor must be a table of loadout names", name))
        end
    end

    return #problems == 0, problems
end

-- Names still waiting on an upload. Separate from `validate` on purpose: this
-- is a normal state during development, not a fault, and conflating the two
-- would either make the game refuse to boot until every animation exists or
-- bury a real error among expected ones.
function AnimationManifest.pending(): { string }
    local waiting = {}

    for name, row in pairs(ROWS) do
        if type(row) == "table" and row.assetId == AnimationManifest.NOT_UPLOADED then
            table.insert(waiting, name)
        end
    end

    table.sort(waiting)
    return waiting
end

return AnimationManifest
