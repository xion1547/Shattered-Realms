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

local DefinitionLoader = require(serverRoot:WaitForChild("boot"):WaitForChild("DefinitionLoader"))

-- TEMPORARY, like the print at the end of OnAttack. AttackDebug draws the
-- resolved volume; SwingReport prints the numbers behind it. Two views of the
-- same swing on purpose -- the drawing shows you WHERE, the report shows you
-- WHY, and a disagreement between them is itself a finding.
local diagnostics = serverRoot:WaitForChild("diagnostics")
local AttackDebug = require(diagnostics:WaitForChild("AttackDebug"))
local SwingReport = require(diagnostics:WaitForChild("SwingReport"))
local DebugConfig = require(diagnostics:WaitForChild("DebugConfig"))

-- BOTH ARE WIRED AND BOTH ARE GATED. AttackLog says WHAT an attack caught;
-- SwingReport says WHY -- latency, rewind, what the cull kept, and every
-- surviving candidate with the numbers it was judged on, misses included.
-- "Why did that one miss" is the only question anyone actually asks, and a hit
-- total cannot answer it.
--
-- SwingReport defaults OFF: one block per swing is indispensable for one swing
-- and unreadable for ten.

local eventTypes = game:GetService("ReplicatedStorage"):WaitForChild("eventTape")
    :WaitForChild("event"):WaitForChild("types")
local CombatEvent = require(eventTypes:WaitForChild("CombatEvent"))

-- The sub-domain, required as a child of this module.
local SkillService = require(script:WaitForChild("SkillService"))

-- A comma-separated list of what an attack caught, or "nothing".
local function idsOf(entities): string
    if #entities == 0 then
        return "nothing"
    end
    local names = {}
    for _, entity in ipairs(entities) do
        table.insert(names, tostring(entity.identity:getId()))
    end
    return table.concat(names, ", ")
end

-- WHICH SKILL EACH DEBUG KEYBIND FIRES.
--
-- THIS MAP IS THE LAST REMNANT OF THE OLD SHAPE AND IT IS TEMPORARY. What used
-- to sit here was three HitVolumes typed as locals, keyed by subType -- which
-- meant the volume was chosen by WHICH BUTTON WAS PRESSED and could not vary by
-- who was swinging. A goblin, a giant, a dagger and a greatsword all meleed
-- with the identical 6.5-stud capsule, and there was no path for that to
-- differ. A projectile attack could not exist at all.
--
-- The volumes are now content (`definitions/skills/`). What remains here is a
-- much smaller thing: three debug binds naming three skill ids, so the shapes
-- stay reachable from a keyboard while the real path is built.
--
-- WHAT REPLACES IT: the event names its own skill, and the attacker's own
-- definition says whether they own it. That is one line here plus a real
-- VALIDATE phase -- deliberately not built now, because this restructure is
-- moving configuration out of code and is NOT the skill system. SkillService
-- stays a stub.
local SKILL_BY_SUBTYPE = {
    [CombatEvent.SubType.MELEE] = "BASIC_SWING",
    [CombatEvent.SubType.AOE] = "CLEAVE",
    [CombatEvent.SubType.RANGED] = "THRUST",
}

local CombatService = {}

CombatService._signals = {}
CombatService.Skills = SkillService

-- SWINGS STILL IN FLIGHT. See HitDetection.md §8.2 -- the "stopwatch" half of
-- the two drivers.
--
-- An instantaneous volume resolves inside OnAttack and is gone. A SWEEPING one
-- cannot: its samples are spread across a window that mostly has not happened
-- yet, and there is no history of the future. `poseAt` clamps a future
-- timestamp to its newest entry, so resolving all eight samples up front would
-- return the same instant eight times -- the machinery running and
-- accomplishing nothing.
--
-- So the swing lives here until it finishes, and each sample is evaluated at
-- the moment it actually arrives. THAT IS ALSO WHAT MAKES EVERY SAMPLE
-- REWINDABLE: by the time sample five is due, sample five's moment is in the
-- past, so `viewTimeFor` can reach back to what the attacker saw exactly as it
-- does for an instantaneous swing. The stopwatch does not bypass lag
-- compensation -- it is what allows it across a window.
CombatService._sweeps = {}

-- Monotonic, never reset. Two swings CAN be in flight at once -- two players,
-- or one player and a boss -- and without an id per swing their sample lines
-- interleave in the output with no way to tell which blade is which. Found by
-- reading a log where two `sample 5/8` lines sat next to each other.
CombatService._nextSweepId = 1

function CombatService:boot()
    -- TODO: declare Combat.OnHit / OnKill / OnParrySuccess once those names
    -- are in this place's vocabulary.

    -- CONTENT LOADS AND VALIDATES HERE, before anything can ask for a skill.
    -- `DefinitionLoader.load` resolves every volume through HitVolume and
    -- collects every problem into one boot failure naming the file -- so a
    -- malformed volume stops the server rather than surfacing the first time
    -- somebody presses attack.
    --
    -- This used to be a loop over three locals declared in this file. That it
    -- is now a loop over content is the entire point of the restructure.
    local content = DefinitionLoader.load()

    -- TEMPORARY, and paired with SwingReport: the STARTING VALUES, printed
    -- once, so a swing's numbers can be read against what was declared rather
    -- than against memory. Half of "why did that miss" is answered by the
    -- volume being a different size than anyone thought.
    local skillIds = {}
    for id in pairs(content.skills) do
        table.insert(skillIds, id)
    end
    table.sort(skillIds)

    print(string.format("[CombatService] %d skill(s) loaded:", #skillIds))
    for _, id in ipairs(skillIds) do
        local skill = content.skills[id]

        if skill.planned then
            -- Printed rather than skipped. A reserved name that never appears
            -- reads as a name nobody chose, and the point of declaring one
            -- early is that it is visible.
            print(string.format("    %-14s PLANNED -- no volume yet", id))
            continue
        end

        local volume = skill.volume

        local sweepNote = ""
        if (volume.sweep or 0) > 0 then
            local wedges = HitVolume.wedgeCount(volume)
            local limits = HitVolume.wedgeLimits()
            sweepNote = string.format(
                "  sweep=%g deg over %.2fs -> %d wedges of %.1f deg / %.0fms "
                    .. "(caps %g deg, %.0fms)",
                volume.sweep, volume.activeWindow, wedges,
                volume.sweep / wedges, volume.activeWindow / wedges * 1000,
                limits.maxDegrees, limits.maxSeconds * 1000)
        end

        print(string.format("    %-14s %-8s reach=%.1f  maxTargets=%s  offset=%s%s",
            id,
            volume.shape,
            HitVolume.reach(volume),
            tostring(volume.maxTargets),
            volume.offset and tostring(volume.offset.Position) or "none",
            sweepNote))
    end

    local enemyIds = {}
    for id in pairs(content.enemies) do
        table.insert(enemyIds, id)
    end
    table.sort(enemyIds)
    print(string.format("[CombatService] %d enem(y/ies) loaded: %s",
        #enemyIds, #enemyIds > 0 and table.concat(enemyIds, ", ") or "none"))

    local spatial = SpatialService:constants()
    print(string.format(
        "[CombatService] rewind config: sample %dHz, history %.2fs (%d slots), "
            .. "maxRewind %.2fs, interp %.2fs, ping x%d",
        spatial.sampleHz, spatial.historySeconds, spatial.historyLength,
        spatial.maxRewind, spatial.interpolationConstant, spatial.pingToRoundTrip))

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
    -- THE VOLUME IS THE SKILL'S, and the skill is content.
    --
    -- The subType still picks WHICH skill, which is the temporary half -- three
    -- debug binds. What is no longer temporary is where the geometry comes
    -- from: `skill.volume`, resolved and frozen at boot from a definitions
    -- file, rather than a local typed in this service.
    --
    -- That is what makes a per-attacker volume expressible at all. Whether a
    -- goblin's swing differs from a giant's is now a content question with a
    -- content answer, instead of being structurally impossible.
    local skillId = SKILL_BY_SUBTYPE[event:getSubType()]
    if not skillId then
        return false, "NO_SKILL_FOR_SUBTYPE"
    end

    local skill = DefinitionLoader.skill(skillId)
    local volume = skill.volume

    -- A SWEEPING VOLUME TAKES THE OTHER PATH. It cannot resolve here: most of
    -- its window has not happened, and there is no history of the future
    -- (§8.2). It goes on the in-flight list and is stepped by tick.
    if volume.sweep > 0 then
        -- ONE BLADE PER ATTACKER AT A TIME. Without this, holding the key
        -- stacks overlapping swings that each resolve independently -- and
        -- since dedup is per swing, the same body takes a hit from every one
        -- of them. That is a damage multiplier for pressing a button faster,
        -- which is the shape of a real exploit rather than a debug annoyance.
        --
        -- THIS IS A PLACEHOLDER FOR A COOLDOWN, not a substitute for one.
        -- SkillService:isReady already exists and nothing calls it; when
        -- VALIDATE is written this check belongs there, expressed as the
        -- skill's own recovery time rather than as "is the animation still
        -- playing". Combo chaining, if it ever exists, is a cooldown that
        -- ends before the swing does -- which this cannot express.
        if self:_hasSweepInFlight(attacker) then
            return false, "SWING_IN_PROGRESS"
        end

        -- ============================================================
        -- THE WEDGE, and this is what closes the tunneling gap.
        -- ============================================================
        --
        -- The obvious way to resolve a sweep is to test the blade AT each
        -- sample angle. That leaves the space BETWEEN angles untested -- with
        -- 140 degrees over 8 samples the blade jumps 20 degrees per step, and
        -- anything narrow enough to sit in that gap is passed straight
        -- through. The industry name for it is tunneling and every discretely
        -- sampled system has it.
        --
        -- The fix falls out of the geometry: a blade that PIVOTS AT ITS OWN
        -- ORIGIN and rotates from one angle to the next sweeps out a pie
        -- slice. Radius is the blade's length; width is the step.
        --
        -- A pie slice is an ARC. So instead of 8 thin blade tests with gaps
        -- between them, this resolves 7 wedges that TILE the whole sweep with
        -- nothing left out -- using overlap maths that already exists and is
        -- already tested.
        --
        -- It is also cheaper: 7 tests instead of 8.
        -- DERIVED FROM THE SWEEP ITSELF, not authored. Bigger arcs and faster
        -- swings get more wedges automatically; a slow wide boss sweep and a
        -- fast narrow flick both land at a resolution that fits them, and
        -- nobody has to pick a number per attack. HitVolume.wedgeCount carries
        -- the reasoning.
        local wedgeCount = HitVolume.wedgeCount(volume)
        local stepDegrees = volume.sweep / wedgeCount

        -- The blade's reach, and how wide the blade itself is in DEGREES.
        -- The two shapes name these differently, which is the only reason
        -- this needs a branch.
        local reach, bladeDegrees
        if volume.shape == HitVolume.Shape.CAPSULE then
            reach = volume.length
            -- A blade of thickness `radius` looks wider the closer you stand
            -- to the pivot, so there is no single correct number. Measured at
            -- half the blade's length: representative, and it errs generous,
            -- which is the right direction for an attacker's own swing.
            bladeDegrees = 2 * math.deg(
                math.asin(math.clamp(volume.radius / (reach * 0.5), -1, 1)))
        else
            reach = volume.radius
            bladeDegrees = volume.angle    -- an ARC already states its width
        end

        local instant = table.clone(volume)
        instant.sweep = 0
        instant.activeWindow = 0
        instant.samples = 1
        instant.shape = HitVolume.Shape.ARC
        instant.radius = reach
        instant.angle = math.min(360, stepDegrees + bladeDegrees)
        instant.length = nil     -- meaningless now that this is an ARC

        local sweep = {
            id = self._nextSweepId,
            player = player,
            attacker = attacker,
            volume = volume,
            instant = table.freeze(instant),

            -- N sample angles make N-1 gaps between them, and it is the GAPS
            -- that get resolved. Stored rather than recomputed so the tick
            -- loop and the trace cannot disagree about how many there are.
            wedges = wedgeCount,
            subType = event:getSubType(),
            preferredId = CombatEvent.getTargetId(event),
            startedAt = workspace:GetServerTimeNow(),
            nextSample = 1,
            seen = {},
            order = {},
        }
        self._nextSweepId += 1
        table.insert(self._sweeps, sweep)

        -- Nothing is due yet -- the first wedge fires half a step in, at the
        -- middle of the span it covers. Called anyway so that a degenerate
        -- volume (a zero-length window, say) finishes and cleans up here
        -- rather than living on the list until the next tick.
        if self:_advanceSweep(sweep, sweep.startedAt) then
            table.remove(self._sweeps, #self._sweeps)
            self:_finishSweep(sweep)
        end

        return true
    end

    local query = TargetQuery.new({
        attacker = attacker,
        volume = volume,
        at = SpatialService:viewTimeFor(player),

        -- What the client clicked on, demoted to a HINT. It sorts the result
        -- list so a capped skill hits what the player was pointing at; it can
        -- never add a target the volume did not already contain, and a junk
        -- value simply matches nothing.
        preferredId = CombatEvent.getTargetId(event),
    })

    local hits = TargetResolution.resolve(query)

    -- TEMPORARY, and paired with HurtboxDebug: draws the fan the server
    -- actually resolved, plus a red ball on everything it caught. Delete both
    -- together once hit detection stops being the thing under construction.
    AttackDebug.show(query, hits)

    -- The SAME query object that produced `hits`, never a rebuilt one -- a
    -- second TargetQuery would describe a different swing by a frame and the
    -- report would quietly stop matching the result it claims to explain.
    if DebugConfig.get("SwingReport") then
        SwingReport.report(player, event, query, hits)
    end

    -- TEMPORARY. resolveAttack is deliberately NOT called yet:
    -- DamageResolution's steps are still TODOs, and a half-run pipeline is a
    -- worse signal than no pipeline. When RESOLVE lands, a loop over `hits`
    -- replaces this print.
    if DebugConfig.get("AttackLog") then
        print(string.format("[CombatService] %s %s (%s) -- %d hit(s): %s",
            player.Name, event:getSubType(), volume.shape, #hits, idsOf(hits)))
    end

    -- TRUE IS AN ANSWER TO THE CLIENT, not just a status code. EventRouter
    -- turns it into a CONFIRM addressed to this event's id, which is what
    -- resolves the client's pending action and lets it stop holding
    -- optimistic state. Returning nothing leaves the client waiting until its
    -- sweep times out -- which is exactly what it did until 2026-08-16.
    return true
end


-- SWEEPS -----------------------------------------------------------------

-- One evaluation of a sweeping volume, at the blade's position for `index`.
--
-- Resolves an INSTANT: `sweep.instant` is the same volume with its window and
-- sample count stripped, so TargetResolution's own multi-sample loop does not
-- run a second stepping on top of this one. Two loops stepping the same window
-- would each be right and the pair would be wrong.
function CombatService:_evaluateSweepSample(sweep, index: number)
    local volume = sweep.volume
    local wedges = sweep.wedges

    -- WEDGE `index` COVERS THE SPAN, so it is aimed at the MIDDLE of that
    -- span rather than at either edge. Wedge 1 of 7 across 140 degrees spans
    -- -70 to -50 and points at -60; the volume's own width covers the rest.
    --
    -- Aiming at an edge instead would leave half of each wedge hanging
    -- outside the swing at one end and overlapping nothing at the other --
    -- correct total coverage, shifted 10 degrees off where the blade is.
    local half = math.rad(volume.sweep) * 0.5
    local step = (half * 2) / wedges
    local angle = -half + (index - 0.5) * step

    -- How far through the swing this wedge is, 0 to 1. Used only to tint the
    -- debug overlay from cold to hot.
    local fraction = wedges > 1 and ((index - 1) / (wedges - 1)) or 0.5

    local query = TargetQuery.new({
        attacker = sweep.attacker,
        volume = sweep.instant,
        at = SpatialService:viewTimeFor(sweep.player),
        sweepAngle = angle,
        preferredId = sweep.preferredId,
    })

    -- The moment this wedge resolved against, kept on the sweep so a
    -- diagnostic can rewind targets to the SAME instant rather than reading
    -- `now` again and describing a different one by a frame.
    sweep.lastAt = query.at

    local hits = TargetResolution.resolve(query)

    -- SHORT LIFETIME SO THE BLADE ANIMATES. Samples are ~50ms apart; at the
    -- default 0.35s every one of them is on screen at once for most of the
    -- swing, which is geometrically correct and looks completely static.
    -- Roughly two alive at a time reads as a moving blade.
    --
    -- Cold at the start of the arc, hot at the end, so the direction of travel
    -- is readable from a still frame.
    AttackDebug.show(query, hits, nil, {
        lifetime = 0.10,
        color = AttackDebug.SWEEP_START_COLOR:Lerp(AttackDebug.SWEEP_END_COLOR, fraction),
    })

    -- DEDUPLICATED ACROSS THE WHOLE SWING, not per sample. A body the blade
    -- passes through for three consecutive samples is one target taking one
    -- damage roll -- Part 8's rule, and the reason `seen` lives on the sweep
    -- rather than on the query.
    --
    -- `newlyCounted` is what the trace needs to tell "in the volume again"
    -- apart from "counted" -- the two are indistinguishable from a hit total,
    -- and the difference IS the once-per-attack rule.
    local newlyCounted = {}
    local firstTouch = 0
    for _, entity in ipairs(hits) do
        if not sweep.seen[entity] then
            sweep.seen[entity] = true
            table.insert(sweep.order, entity)
            newlyCounted[entity] = true
            firstTouch += 1
        end
    end

    if DebugConfig.get("SweepWedges") then
        print(string.format(
            "    [sweep #%d] wedge %d/%d  centred %+.1f deg (%.1f wide)  %d in volume, %d new",
            sweep.id, index, wedges, math.deg(angle), sweep.instant.angle,
            #hits, firstTouch))
    end
end

-- Whether this attacker already has a blade in the air.
--
-- A linear scan, and correct to keep as one: the list holds swings in flight,
-- which is a handful at most even in a busy fight. A map keyed by attacker
-- would be faster and would have to be kept in step with the list on every
-- add and remove -- two representations of the same fact, which is the bug
-- this codebase keeps choosing to avoid.
function CombatService:_hasSweepInFlight(attacker): boolean
    for _, sweep in ipairs(self._sweeps) do
        if sweep.attacker == attacker then
            return true
        end
    end
    return false
end

-- Fires every sample whose moment has arrived. A loop rather than an `if`
-- because a frame drop can leave two or three due at once, and skipping them
-- would put a hole in the blade's path -- the one failure a swept volume
-- exists to avoid.
function CombatService:_advanceSweep(sweep, now: number): boolean
    local volume = sweep.volume
    local wedges = sweep.wedges
    local step = volume.activeWindow / wedges

    while sweep.nextSample <= wedges do
        -- Due at the MIDDLE of the span this wedge covers, matching the angle
        -- it is aimed at. The wedge is a shape and covers its whole span
        -- regardless of when it is evaluated -- what the timing decides is
        -- where the TARGETS are, and the middle of the span is the least
        -- wrong single moment to ask about.
        local due = sweep.startedAt + (sweep.nextSample - 0.5) * step
        if now < due then
            break
        end

        -- ADVANCED BEFORE THE EVALUATION, NOT AFTER, and that ordering is the
        -- fix for a real failure: an error inside the evaluation used to leave
        -- `nextSample` unchanged, so the tick retried the same wedge every
        -- frame forever. The swing never finished, the attacker never cleared
        -- `_hasSweepInFlight`, and every further attack was refused with
        -- SWING_IN_PROGRESS -- from one nil argument.
        --
        -- Incrementing first guarantees forward progress no matter what the
        -- evaluation does. A wedge that fails is a wedge that is skipped,
        -- which is a bad swing; a wedge that fails forever is a dead player.
        local wedge = sweep.nextSample
        sweep.nextSample += 1
        self:_evaluateSweepSample(sweep, wedge)
    end

    return sweep.nextSample > wedges
end

-- Scheduled. See the CombatService row in Scheduler.luau.
function CombatService:tick(_dt: number)
    if #self._sweeps == 0 then
        return
    end

    local now = workspace:GetServerTimeNow()

    -- Backwards, so removing an entry cannot shift one this loop has not
    -- visited yet.
    for index = #self._sweeps, 1, -1 do
        local sweep = self._sweeps[index]
        if self:_advanceSweep(sweep, now) then
            table.remove(self._sweeps, index)
            self:_finishSweep(sweep)
        end
    end
end

function CombatService:_finishSweep(sweep)
    -- ONCE PER SWING, not once per wedge. Eight blocks for one attack would
    -- bury the finding in its own output; the last wedge's query is the one
    -- that resolved most recently and is representative of the geometry.
    --
    -- Rebuilt rather than stored: the query object is per-wedge and short
    -- lived, and keeping one alive on the sweep just to print it later would
    -- be state held for a diagnostic.
    if DebugConfig.get("SwingReport") and sweep.lastAt then
        SwingReport.report(sweep.player, {
            getEventId = function() return "sweep#" .. sweep.id end,
            getSubType = function() return sweep.subType end,
        }, TargetQuery.new({
            attacker = sweep.attacker,
            volume = sweep.instant,
            at = sweep.lastAt,
            preferredId = sweep.preferredId,
            sweepSpan = sweep.volume.sweep,
        }), sweep.order)
    end


    -- TEMPORARY, and where the loop over `sweep.order` into resolveAttack goes
    -- when RESOLVE lands. Announced at the END of the swing rather than per
    -- wedge, because one swing is one attack no matter how many moments it
    -- was tested at -- and because a body caught on wedge 2 and again on
    -- wedge 6 must produce exactly one damage roll.
    --
    -- ON `AttackLog`, NOT `SweepWedges`. This is one line describing one
    -- attack, the same as an instantaneous swing produces; the per-wedge
    -- chatter is a separate, louder thing. Tying them together is what made a
    -- sweeping attack print nothing at all while a click printed nothing
    -- either -- symmetric, and useless.
    if DebugConfig.get("AttackLog") then
        print(string.format(
            "[CombatService] %s %s (%s, sweep #%d, %g deg over %.2fs) -- %d hit(s): %s",
            sweep.player.Name, sweep.subType, sweep.volume.shape, sweep.id,
            sweep.volume.sweep, sweep.volume.activeWindow,
            #sweep.order, idsOf(sweep.order)))
    end
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
