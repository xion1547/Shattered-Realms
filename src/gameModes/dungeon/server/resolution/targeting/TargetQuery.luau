-- src/gameModes/dungeon/server/resolution/targeting/TargetQuery.luau
--
-- The declared shape one TargetResolution run is given. See HitDetection.md.
--
-- Mirrors AttackContext in spirit, and the same Part 11.1 rule applies: this
-- is a DECLARED SHAPE, not a scratch bag. A field goes in only when two
-- stages genuinely share it. A query accreting fields because one stage
-- wanted somewhere to put something is how this pattern dies.
--
-- Unlike AttackContext, nothing mutates this. Resolution reads it and
-- returns a list; the query is an input and stays one.

local TargetQuery = {}
TargetQuery.__index = TargetQuery

function TargetQuery.new(config)
    assert(type(config) == "table", "[TargetQuery] a config table is required")
    assert(config.volume, "[TargetQuery] a volume is required")
    assert(type(config.at) == "number", "[TargetQuery] 'at' must be a server timestamp")

    return setmetatable({
        -- Who is swinging. Excluded from its own results, and the source of
        -- the volume's origin unless the volume anchors to a point.
        attacker = config.attacker,

        -- A resolved HitVolume -- defaults filled, already validated.
        volume = config.volume,

        -- THE SERVER TIMESTAMP TARGETS ARE REWOUND TO, and the single
        -- parameter that distinguishes the two directions of combat:
        --
        --   player attacking   at = now - rewindWindow   (they already saw it)
        --   enemy attacking    at = now                  (telegraph is the
        --                                                 compensation)
        --
        -- One engine serves both. Only this number changes.
        at = config.at,

        -- Required when the volume anchors to POINT rather than ATTACKER --
        -- a ground-targeted AoE lands where it was aimed, not where the
        -- caster is standing.
        origin = config.origin,

        -- A unit direction, and ONLY honoured when the volume declares
        -- aimSource = CLIENT_AIM. Never a position, never a distance.
        aim = config.aim,

        -- Who counts as a legal target. A predicate rather than a faction
        -- enum on purpose: whether a pet may hit its owner is a combat rule,
        -- and rules belong to Services (Part 3). This module finds bodies in
        -- a volume and has no opinion about which ones deserve it.
        --
        -- nil means "anything but the attacker".
        filter = config.filter,

        -- The client's targetId, demoted to a HINT. It sorts the result
        -- list; it never adds to it and never bypasses the volume. A
        -- preferredId naming something outside the resolved set is ignored
        -- rather than honoured, which is the whole point of there being one
        -- code path (Part 13).
        preferredId = config.preferredId,
    }, TargetQuery)
end

return TargetQuery
