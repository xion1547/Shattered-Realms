-- src/gameModes/dungeon/server/resolution/targeting/TargetResolution.luau
--
-- The generic engine of hit detection. See HitDetection.md.
--
-- WHY targeting/ IS ITS OWN DIRECTORY, beside resolution/ rather than inside
-- it loose: resolution/ answers "how much damage" and targeting/ answers
-- "to whom". They run in different phases, at different cardinalities -- one
-- DETECT per activation, one RESOLVE per target -- and share no state. Four
-- files sitting loose next to DamageResolution read as one system; they are
-- two, and the directory is what says so at a glance.
--
-- Named after what it RESOLVES, not what triggers it -- the same rule that
-- made DamageResolution not AttackPipeline. It resolves a volume into a set
-- of entities. A player swing, a boss slam, a DoT aura tick and a future
-- zone hazard all need the identical stages; HitboxSystem would imply
-- attacks own it and make the first hazard feel like a hack.
--
-- IT IS NOT A PIPELINE, AND THAT IS DELIBERATE. DamageResolution earns its
-- phases-and-registration machinery because Part 11.1 counts twelve-plus
-- modifier types that will genuinely accumulate. This has five stages and
-- will still have five in a year -- they do not accumulate, they are not
-- independently authored, and nobody will ever register a sixth from a
-- content file. Part 2 has a section on not applying that pattern where it
-- does not fit, and this is what it describes.
--
-- THIS MODULE FINDS BODIES. IT NEVER DECIDES WHETHER A HIT LANDS. Parry,
-- block, dodge and invulnerability all stay in the INTERCEPT phase of
-- DamageResolution. A dodging player is returned by this module; INTERCEPT
-- is what decides they dodged. Skipping them here would put mitigation in
-- two places and silently stop INTERCEPT's steps from ever running -- the
-- first symptom being a parry that awards no stagger because the parrier
-- was never a target at all.

-- script -> targeting -> resolution -> server root
local serverRoot = script.Parent.Parent.Parent

local HitVolume = require(script.Parent:WaitForChild("HitVolume"))
local Overlap = require(script.Parent:WaitForChild("Overlap"))
local SpatialService = require(serverRoot:WaitForChild("services"):WaitForChild("authority")
    :WaitForChild("SpatialService"))

local TargetResolution = {}

-- Used only to widen the broadphase cull. Deliberately generous: this is a
-- bound on how far anything could have travelled during the rewind window,
-- and being wrong high costs a few extra exact tests, while being wrong low
-- silently discards real hits before they are ever measured.
local MAX_ENTITY_SPEED = 120

-- STAGE 1 — ORIGIN -----------------------------------------------------
--
-- THE ATTACKER IS NOT REWOUND. ONLY THE TARGETS ARE.
--
-- Walk the timeline. The client is at P when it presses attack. Its position
-- update and its attack command travel to the server together and arrive
-- together -- so at the moment the server processes the swing, its NEWEST
-- record of the attacker already IS P. Rewinding the attacker on top of that
-- double-counts the latency and drags the swing backwards through space,
-- which shows up as attacks landing behind a moving player.
--
-- The target is the opposite case: the client saw it where the server said
-- it was a full round trip plus interpolation ago, which is exactly what
-- gets rewound in stage 3.
function TargetResolution._origin(query): CFrame?
    local volume = query.volume

    if volume.anchor == HitVolume.Anchor.POINT then
        local origin = query.origin
        if not origin then
            return nil
        end
        return volume.offset and (origin * volume.offset) or origin
    end

    local attacker = query.attacker
    local spatial = attacker and attacker.spatial
    local pose = spatial and spatial:getCFrame()
    if not pose then
        return nil
    end

    local direction
    if volume.aimSource == HitVolume.AimSource.CLIENT_AIM and query.aim then
        local aim = query.aim
        -- A zero or near-zero vector has no direction to speak of; fall back
        -- rather than producing a NaN CFrame that would silently match
        -- nothing for the rest of the swing.
        direction = aim.Magnitude > 1e-4 and aim.Unit or pose.LookVector
    else
        direction = pose.LookVector
    end

    local origin = CFrame.lookAt(pose.Position, pose.Position + direction)

    -- THE SWING, APPLIED BEFORE THE OFFSET. Rotating the facing first means an
    -- offset volume travels on an ARC around the attacker rather than sliding
    -- sideways in front of them -- which is the difference between a sword
    -- swing and a shove.
    --
    -- About the attacker's own up axis, not the world's, so a swing on a slope
    -- stays in the plane the attacker is standing in.
    if query.sweepAngle and query.sweepAngle ~= 0 then
        origin = origin * CFrame.Angles(0, query.sweepAngle, 0)
    end

    return volume.offset and (origin * volume.offset) or origin
end

-- STAGE 2 — BROAD ------------------------------------------------------
--
-- A squared-distance cull over attached entities, widened by how far
-- anything could have moved during the rewind window. Without that margin
-- this discards an entity that has since run out of range but WAS inside the
-- volume at the moment being resolved -- a miss caused by culling, which
-- looks identical to a miss caused by bad detection and is much harder to
-- find.
function TargetResolution._candidates(query, origin: CFrame)
    local now = workspace:GetServerTimeNow()
    local rewound = math.max(0, now - query.at)
    local window = rewound + (query.volume.activeWindow or 0)

    return SpatialService:candidatesNear(
        origin.Position,
        HitVolume.reach(query.volume),
        MAX_ENTITY_SPEED * window)
end

-- STAGE 3 + 4 — NARROW and FILTER --------------------------------------
--
-- Filtering runs BEFORE the overlap test rather than after it, which is a
-- deliberate departure from the order the design document lists. The stages
-- are conceptually the same; running the cheap rejection first just avoids
-- paying for an exact test on an entity that was never eligible.
--
-- SAMPLING ACROSS THE ACTIVE WINDOW is why one instantaneous query is not
-- enough. A wide swing live for 120ms while a mob runs through it returns
-- nothing if sampled once at the wrong instant. Results are unioned and
-- deduplicated by entity, so something caught by all three samples of one
-- swing is still ONE target and takes ONE damage roll -- Part 8's rule,
-- enforced here rather than trusted to the caller.
-- Was any part of this body inside the volume at moment `at`?
--
-- ONE ZONE IS ENOUGH, so this returns on the first hit rather than testing the
-- rest. Dedup would discard the others anyway -- an activation applies to an
-- entity at most once however many moments or zones caught it -- so continuing
-- is pure wasted arithmetic on the exact test, which is the expensive one.
--
-- EACH ZONE REWINDS THROUGH ITS OWN LIMB'S HISTORY. `poseAt(at, part)` reads
-- the buffer for that specific part, which is why per-part tracking had to
-- exist before this could. Passing the ROOT pose instead would put every zone
-- back in the rest arrangement and quietly undo the whole hitzone list.
--
-- ENDPOINTS COME FROM THE REWOUND POSE, never the live one. A capsule leans
-- with the thing it rides, so a target that has rotated since the attacker saw
-- it has to be reconstructed at the orientation they saw -- which is exactly
-- why the ring buffer stores CFrames rather than positions.
--
-- NO HURTBOX MEANS NOT HITTABLE, and that is deliberate rather than defensive.
-- The attached set IS the target set, and a body registers by declaring a shape
-- -- so a hurtbox-less entity in that set is a wiring bug, and returning false
-- surfaces it as "nothing is hittable" rather than hiding it behind an old
-- single-capsule guess that no longer exists.
function TargetResolution._hits(entity, spatial, origin: CFrame, volume, at: number): boolean
    local hurtbox = entity.hurtbox

    if not hurtbox then
        return false
    end

    for zone = 1, hurtbox:zoneCount() do
        local pose = spatial:poseAt(at, hurtbox:anchorFor(zone))
        if pose then
            local capA, capB, radius = hurtbox:endpoints(zone, pose)
            if Overlap.test(origin, volume, capA, capB, radius) then
                return true
            end
        end
    end

    return false
end

function TargetResolution._sweep(query, origin: CFrame, candidates)
    local volume = query.volume
    local attacker = query.attacker
    local filter = query.filter

    local samples = volume.samples or 1
    local window = volume.activeWindow or 0
    local step = samples > 1 and (window / (samples - 1)) or 0

    local seen = {}
    local found = {}

    for index = 1, samples do
        local at = query.at + step * (index - 1)

        for _, entity in ipairs(candidates) do
            if not seen[entity] and entity ~= attacker then
                local eligible = (filter == nil) or filter(entity)
                if eligible then
                    local spatial = entity.spatial
                    if spatial and TargetResolution._hits(entity, spatial, origin, volume, at) then
                        seen[entity] = true
                        table.insert(found, entity)
                    end
                end
            end
        end
    end

    return found
end

-- STAGE 5 — LIMIT ------------------------------------------------------
--
-- maxTargets makes a skill single-target by data rather than by code. The
-- client's preferredId sorts first when present, so a capped skill hits what
-- the player was pointing at rather than whichever body the iteration order
-- happened to reach -- without the id ever adding a target the volume did
-- not already contain.
function TargetResolution._limit(query, found)
    local preferredId = query.preferredId
    if preferredId ~= nil and #found > 1 then
        for index, entity in ipairs(found) do
            local identity = entity.identity
            if identity and identity:getId() == preferredId then
                if index ~= 1 then
                    table.remove(found, index)
                    table.insert(found, 1, entity)
                end
                break
            end
        end
    end

    local max = query.volume.maxTargets
    if max and #found > max then
        for index = #found, max + 1, -1 do
            found[index] = nil
        end
    end

    return found
end

-- The whole engine. Returns a list of entities, possibly empty. Never nil.
function TargetResolution.resolve(query)
    local origin = TargetResolution._origin(query)
    if not origin then
        -- No body and no anchor point: the attacker is not in the world.
        -- Empty rather than an error -- an entity dying mid-swing is
        -- ordinary, not exceptional.
        return {}
    end

    local candidates = TargetResolution._candidates(query, origin)
    if #candidates == 0 then
        return {}
    end

    return TargetResolution._limit(query, TargetResolution._sweep(query, origin, candidates))
end

-- Diagnostics. Returns the resolved origin without running the sweep, so a
-- debug visualiser can draw exactly the volume that was tested rather than
-- an approximation of it -- when detection is wrong, seeing WHERE it looked
-- is most of the answer.
function TargetResolution.originOf(query): CFrame?
    return TargetResolution._origin(query)
end

-- Exposed for diagnostics, which need the broadphase margin to report what
-- the cull actually did. An accessor rather than letting a second file write
-- `120` next to a comment saying "same as TargetResolution" -- that is the
-- duplicated-constant failure this codebase keeps closing, and a diagnostic
-- that drifts from the thing it measures is worse than no diagnostic.
function TargetResolution.constants()
    return {
        maxEntitySpeed = MAX_ENTITY_SPEED,
    }
end

return TargetResolution
