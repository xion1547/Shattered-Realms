-- src/gameModes/dungeon/server/services/domain/CombatService/init.luau
--
-- DOMAIN SERVICE. Hit validation, the DamageResolution pipeline, kill
-- detection, loot trigger. Owns the SkillService sub-domain.
-- See Architecture-Reference.md Parts 10 and 11.
--
-- SkillService is a CHILD of this module, not a sibling in domain/. That is
-- structural, not cosmetic: a skill is by definition a combat concept, and
-- combat resolution needs to know what a skill does. Splitting them into
-- independent top-level Services would just recreate a circular dependency
-- between them. Nesting makes the direction obvious at a glance -- Combat
-- calls into Skill, never the reverse -- and it means the PlaceManifest
-- declares one public-facing authority for the whole domain.
--
-- It is also why COMBAT is one eventType covering everything underneath it:
-- a skill activation is COMBAT/SKILL, not its own top-level type.
--
-- The four phases are hard boundaries and the reason this file will not
-- become an 8,000-line god object:
--
--   VALIDATE  here. Legality only. On reject: return, no pipeline, no Fact.
--   RESOLVE   DamageResolution. Pure. Steps mutate a context and nothing else.
--   COMMIT    here. Apply numbers, dispatch content-declared effects.
--   ANNOUNCE  here. Outbound diff, then Facts.
--
-- A new damage modifier is a new STEP file, never a new branch in this
-- service. If you find yourself adding `if` here for a mechanic, it belongs
-- in a phase.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local serverRoot = script.Parent.Parent.Parent
local resolution = serverRoot:WaitForChild("resolution")
local targeting = resolution:WaitForChild("targeting")
local authority = serverRoot:WaitForChild("services"):WaitForChild("authority")

local DamageResolution = require(resolution:WaitForChild("DamageResolution"))
local AttackContext = require(resolution:WaitForChild("AttackContext"))
local EffectHandlers = require(resolution:WaitForChild("EffectHandlers"))

local HitVolume = require(targeting:WaitForChild("HitVolume"))
local TargetQuery = require(targeting:WaitForChild("TargetQuery"))
local TargetResolution = require(targeting:WaitForChild("TargetResolution"))
local EntityService = require(authority:WaitForChild("EntityService"))
local SpatialService = require(authority:WaitForChild("SpatialService"))

-- The verbose per-swing breakdown lived here and is gone: it did its job on
-- 2026-08-15 and the numbers are recorded in Implementation-Status.md.
-- `diagnostics/SwingReport.luau` is still on disk -- require it and call
-- SwingReport.report(player, event, query, hits) to bring it back for an
-- afternoon. A domain service should not carry one permanently.

local eventTypes = game:GetService("ReplicatedStorage"):WaitForChild("eventTape")
    :WaitForChild("event"):WaitForChild("types")
local CombatEvent = require(eventTypes:WaitForChild("CombatEvent"))

-- The sub-domain, required as a child of this module.
local SkillService = require(script:WaitForChild("SkillService"))

-- TEMPORARY. This belongs in the Content Layer next to the skill that owns
-- it -- a volume is data, and the whole point of HitVolume is that a new
-- attack shape is a data edit. It sits here only because nothing declares
-- skills yet, and it is the ONE volume every basic swing uses.
--
-- ARC is the standard melee swing. 120 degrees and 12 studs is wide and
-- generous on purpose: the first thing to prove is that detection fires at
-- all, and a tight volume makes a miss ambiguous between "the math is wrong"
-- and "you were not pointing at it".
local BASIC_SWING = HitVolume.resolve({
    shape = HitVolume.Shape.ARC,
    radius = 12,
    angle = 120,
    maxTargets = 6,
})

local CombatService = {}

CombatService._signals = {}
CombatService.Skills = SkillService

function CombatService:boot()
    -- TODO: declare Combat.OnHit / OnKill / OnParrySuccess once those names
    -- are in this place's vocabulary.

    -- Volumes are validated at boot rather than on first use, so a malformed
    -- one fails at startup instead of the first time a player presses attack.
    -- When volumes move to content this becomes a loop over all of them.
    local ok, reason = HitVolume.validate(BASIC_SWING)
    assert(ok, string.format("[CombatService] BASIC_SWING is malformed: %s", tostring(reason)))

    SkillService:boot()
    DamageResolution.buildPipeline()
end

-- Routed from EventTape: eventType COMBAT resolves here, by ordinary
-- function call. The event arrives already deserialized into a typed Event
-- and already validated for SHAPE -- what remains is validating LEGALITY.
-- `_receivedAt` is accepted and DELIBERATELY UNUSED. EventRouter forwards it
-- and its comment there offers it as the anchor for the latency rewind -- but
-- it is stamped with os.clock(), and every timestamp in the spatial ring
-- buffer comes from workspace:GetServerTimeNow(). Those are two clocks with
-- unrelated origins. Subtracting a rewind window from one and looking the
-- result up in the other lands far outside the buffer, poseAt clamps to its
-- oldest sample, and every hit silently resolves against a position from
-- seconds ago. HitDetection.md's clock-source rule exists for exactly this.
--
-- The cost of using this frame's time instead is under-compensating by the
-- gap between arrival and drain -- at most one frame, against a 100ms
-- interpolation constant. Inside the noise, and correct rather than wrong.
function CombatService:OnAttack(player, event, _receivedAt)
    -- The Roblox Player becomes an entity here, at the boundary where it
    -- entered the system. EntityService has no forPlayer on purpose -- a
    -- registry that can tell a player from a boss leaks that distinction to
    -- every caller. player.UserId IS the id, because PlayerEntity builds its
    -- identity from it.
    local attacker = EntityService:get(player.UserId)
    if not attacker then
        return false, "NO_ENTITY"
    end

    -- Sub-domain dispatch is Combat's own business from here on, never
    -- EventTape's -- which is why SKILL is a COMBAT subType rather than its
    -- own top-level eventType.
    if CombatEvent.isSkillActivation(event) then
        -- TODO: SkillService:activate(attacker, event:get("skillId"), event:get("targetId"))
    end

    -- VALIDATE ------------------------------------------------------------
    -- TODO: does this player own the skill, is it off cooldown, is it in
    -- latency-tolerant range, does StateService allow the attacker to act. On
    -- reject, return and let the router's explicit reject reach the client
    -- (Part 15). Legality only -- whether anything is standing there is the
    -- next phase's question, not this one's.

    -- DETECT --------------------------------------------------------------
    --
    -- The entire lag compensation of this game is one argument: `at`. It is
    -- the server timestamp of what this player's screen was showing when they
    -- clicked, so every candidate is rewound to that moment before being
    -- tested. The attacker is NOT rewound -- their position and their command
    -- travelled the same direction on the same connection and arrived
    -- together (HitDetection.md).
    -- Held in a local rather than inlined, so the diagnostic below reports on
    -- the SAME query that produced the result. Rebuilding it would describe a
    -- different swing by a frame.
    local query = TargetQuery.new({
        attacker = attacker,
        volume = BASIC_SWING,
        at = SpatialService:viewTimeFor(player),

        -- What the client clicked on, demoted to a HINT. It sorts the result
        -- list so a capped skill hits what the player was pointing at; it can
        -- never add a target the volume did not already contain, and a junk
        -- value simply matches nothing.
        preferredId = CombatEvent.getTargetId(event),
    })

    local hits = TargetResolution.resolve(query)

    -- TEMPORARY. resolveAttack is deliberately NOT called yet:
    -- DamageResolution's steps are still TODOs, and a half-run pipeline is a
    -- worse signal than no pipeline. When RESOLVE lands, a loop over `hits`
    -- replaces this line.
    print(string.format("[CombatService] %s swung -- %d hit(s)", player.Name, #hits))

    return true
end

-- The one entry point every source of damage uses: a basic swing, a skill, a
-- parry counter, a DoT tick, a future zone hazard. Naming it after what it
-- RESOLVES rather than what triggers it is what keeps it reusable.
function CombatService:resolveAttack(attacker, target, activation)
    -- VALIDATE
    -- TODO: StateService gate on the target.

    -- RESOLVE
    local ctx = AttackContext.new(attacker, target, activation)
    DamageResolution.run(ctx)

    -- COMMIT
    -- TODO: drain ShieldHits or HP with ctx.final, collect the REAL applied
    -- amounts into a diff, apply ctx.lifesteal, then dispatch any
    -- content-declared effects. Must not yield: that is what makes the whole
    -- commit atomic for free.
    self:_dispatchEffects(ctx)

    -- ANNOUNCE
    -- TODO: push the outbound diff built from what the commits RETURNED,
    -- never from what the pipeline computed. Then fire the Facts.

    return ctx
end

-- Consequences the Content Layer declared, dispatched by label. Numbers the
-- pipeline computed are applied directly above; only these go through the
-- table, because only these arrived as data.
function CombatService:_dispatchEffects(ctx)
    for _, effect in ipairs(ctx.pendingEffects) do
        local handler = EffectHandlers[effect.type]
        if handler then
            handler.apply(ctx.target, effect, ctx.attacker)
        end
    end
end

return CombatService
