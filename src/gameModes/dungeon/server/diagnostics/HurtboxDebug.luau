-- src/gameModes/dungeon/server/diagnostics/HurtboxDebug.luau
--
-- Draws every attached entity's hurtbox as a translucent overlay, so the
-- thing you HIT can be compared against the thing you SEE.
--
-- THIS IS THE INSTRUMENT FOR THE ONE BUG NOBODY CAN SPOT BY PLAYING.
-- A swing that connects a stud early looks exactly like a swing that
-- connected, so the gap between a body and its hurtbox is invisible while
-- playing and obvious the moment it is drawn. Turning this on is what makes it
-- a thing you can see instead of a number in a document -- HitDetection 0.5
-- makes that a requirement rather than a nicety.
--
-- A MODULE, NOT A .server SCRIPT, for DummySpawner's reason: Roblox does not
-- order independent Scripts, and anything that touches the world the test
-- suite reads has to run after it, from a place that says so out loud.
-- Main.server.luau owns that ordering.
--
-- THE OVERLAY PARTS CAN NEVER BECOME TARGETS, and that is structural rather
-- than careful: targeting only ever returns entities registered with
-- EntityService and attached to SpatialService (HitDetection.md §4 -- the
-- watch list IS the target list). A loose Part in workspace is invisible to
-- it. The CanQuery/CanTouch/CanCollide flags below are belt-and-braces for
-- raycasts and physics, not for hit detection.
--
-- ---------------------------------------------------------------------------
-- WHY IT USED TO TRAIL YOU, AND WHY IT NO LONGER DOES
-- ---------------------------------------------------------------------------
--
-- The first version created ANCHORED parts in a workspace folder and rewrote
-- their CFrame 20 times a second from `spatial.anchor.CFrame`. On a dummy that
-- looks perfect. On your own character it visibly lagged behind you, and the
-- reason is worth stating because it is the same reason lag compensation
-- exists at all:
--
--   1. YOU own your character's physics (network ownership -- AssetPipeline.md
--      Part 1, concept #3). Your client simulates it and RENDERS IT INSTANTLY.
--   2. Your client tells the server where you went. The server's copy of your
--      HumanoidRootPart is therefore behind your screen by the upstream leg.
--   3. This script read that stale copy and wrote it onto a SERVER-owned part.
--   4. That part's new position then had to replicate back DOWN to you.
--
-- So the overlay was behind your body by a full round trip plus the client's
-- interpolation delay. That is not an approximation of `2L + I` -- it IS
-- `2L + I`, which is exactly the quantity `SpatialService:rewindWindowFor`
-- computes. The overlay was correctly drawing a real thing; it was just not
-- the thing anyone was trying to look at.
--
-- NOTHING WAS EVER WRONG WITH THE HURTBOX. A hurtbox is not an object that can
-- fall behind a body -- it is a limb's pose plus an offset and two numbers,
-- evaluated at the moment a query asks (HurtboxComponent:endpoints). There is
-- no stored position to drift. What lagged was the PICTURE.
--
-- THE FIX IS TO STOP DRAWING AND START ATTACHING. The pieces are now
-- unanchored, parented under the anchor part, and joined to it with a
-- WeldConstraint. A weld makes them part of that body's physics assembly, so
-- they are simulated by whoever owns it -- YOUR client, for your character.
-- They move with you locally, at render rate, with no round trip, because they
-- are no longer being told where to go by anybody.
--
-- It is also strictly cheaper: a weld is a fixed offset the engine maintains,
-- so the loop below stopped writing CFrames and only watches for rebuilds.
--
-- Massless and non-colliding, so joining them to a live character changes
-- nothing about how it moves.
--
-- THE OLD BEHAVIOUR IS STILL AVAILABLE, under `DebugHurtboxServerView`,
-- because it answers a different and genuinely useful question. Two questions,
-- two modes, and conflating them is what produced the confusion:
--
--   Hurtboxes                    "does my hurtbox match my body's SHAPE?"
--     (welded, default)          wants zero lag, so weld it on
--
--   Hurtboxes + ServerView       "how far behind me is the SERVER?"
--     (anchored, teleported)     wants the lag -- the lag IS the reading
--
-- In ServerView the gap you see between your body and the overlay is the
-- distance rewind has to undo. If it looks large, that is what every unrewound
-- hit test would have been wrong by.
--
-- STILL WORTH BUILDING LATER: a THIRD colour drawn at
-- `poseAt(entity, viewTimeFor(player))` -- the rewound pose. Against the other
-- two it shows whether the compensation lands where the client actually saw
-- the body, which is the only way to check the rewind by eye. Needs a second
-- player at real latency to say anything.

local RunService = game:GetService("RunService")

local authority = script.Parent.Parent:WaitForChild("services"):WaitForChild("authority")
local SpatialService = require(authority:WaitForChild("SpatialService"))
local DebugConfig = require(script.Parent:WaitForChild("DebugConfig"))

local FLAG = "Hurtboxes"
local SERVER_VIEW_FLAG = "HurtboxServerView"

-- Bright, and unlike anything else in the world. A hurtbox that blends into
-- the body it wraps defeats the point.
local COLOR = Color3.fromRGB(0, 255, 200)

-- A second colour for ServerView, because the two modes show different things
-- and a reading you can misidentify is worse than no reading. Amber says "this
-- one is deliberately behind you."
local SERVER_VIEW_COLOR = Color3.fromRGB(255, 170, 0)

local TRANSPARENCY = 0.7

-- 20Hz, not 60. In ServerView this is a redraw rate, and it is drawing on top
-- of a 30Hz sampler -- a frame-perfect overlay would be showing precision the
-- underlying data does not have. In the welded default it is only the rate at
-- which rebuilds are NOTICED, and nothing is written at all.
local REDRAW_HZ = 20

local HurtboxDebug = {}

HurtboxDebug._folder = nil          -- ServerView only; welded pieces live on the body
HurtboxDebug._parts = {}            -- entity -> pieces
HurtboxDebug._connection = nil
HurtboxDebug._accumulator = 0

local function ensureFolder()
    local folder = HurtboxDebug._folder
    if folder and folder.Parent then
        return folder
    end

    folder = Instance.new("Folder")
    folder.Name = "HurtboxDebug"
    folder.Parent = workspace
    HurtboxDebug._folder = folder
    return folder
end

-- THREE PARTS PER HURTBOX, because Roblox has no capsule primitive: a ball at
-- each end of the segment, and a block spanning between them. That is exactly
-- what a capsule IS -- a segment thickened by a radius -- so the drawing and
-- the maths describe the same object rather than approximating each other.
--
-- A sphere hurtbox has both endpoints at the same place, so the two balls
-- coincide and there is no shaft to build. It falls out of the arithmetic the
-- same way `Overlap` handles a zero-length segment with no special case.
--
-- `cf` is set BEFORE parenting, so a welded piece never appears at the origin
-- for a frame on its way to the body.
local function spawnPiece(name: string, shape: Enum.PartType, size: Vector3, cf: CFrame,
    serverView: boolean, anchor: BasePart): Part

    local part = Instance.new("Part")
    part.Name = name
    part.Shape = shape
    part.Size = size
    part.CFrame = cf
    part.CanCollide = false
    part.CanQuery = false     -- keeps it out of raycasts, incl. future line-of-sight
    part.CanTouch = false
    part.Massless = true      -- welded to a live body; must not change how it moves
    part.CastShadow = false
    part.Color = serverView and SERVER_VIEW_COLOR or COLOR
    part.Material = Enum.Material.Neon
    part.Transparency = TRANSPARENCY

    if serverView then
        -- Free-standing and teleported. Anchored so physics never touches it
        -- between writes.
        part.Anchored = true
        part.Parent = ensureFolder()
    else
        -- Parented under the ANCHOR PART rather than under the character Model,
        -- deliberately: plenty of Roblox machinery iterates a character's direct
        -- children looking for limbs, accessories and tools, and three glowing
        -- decoys in that list is the kind of thing that breaks something
        -- unrelated six weeks from now. Nothing walks the children of a part.
        --
        -- It also gets the lifetime for free -- the character is destroyed on
        -- respawn and takes these with it.
        part.Anchored = false
        part.Parent = anchor

        local weld = Instance.new("WeldConstraint")
        weld.Part0 = anchor
        weld.Part1 = part
        weld.Parent = part
    end

    return part
end

local function release(entity)
    local pieces = HurtboxDebug._parts[entity]
    if not pieces then
        return
    end
    for _, part in ipairs(pieces.all) do
        part:Destroy()
    end
    HurtboxDebug._parts[entity] = nil
end

-- Draws ONE capsule: a ball at each end of the segment and a block spanning
-- between them, which is exactly what a capsule is.
--
-- Returns the three parts so the caller can record them; a zero-length segment
-- (a sphere zone, like a head) produces two coincident balls and no shaft, the
-- same way `Overlap` handles it with no special case.
local function drawCapsule(idPrefix: string, capA: Vector3, capB: Vector3, radius: number,
    serverView: boolean, anchor: BasePart)

    local diameter = radius * 2
    local ball = Vector3.new(diameter, diameter, diameter)

    local a = spawnPiece(idPrefix .. "_A", Enum.PartType.Ball,
        ball, CFrame.new(capA), serverView, anchor)
    local b = spawnPiece(idPrefix .. "_B", Enum.PartType.Ball,
        ball, CFrame.new(capB), serverView, anchor)

    local shaft = nil
    local delta = capB - capA
    local length = delta.Magnitude
    if length > 0 then
        -- A Part's Size.Z runs along its local -Z, which is where lookAt
        -- points -- so a block of this length centred on the midpoint and
        -- looking at capB spans exactly the segment.
        shaft = spawnPiece(idPrefix .. "_shaft", Enum.PartType.Block,
            Vector3.new(diameter, diameter, length),
            CFrame.lookAt(capA + delta * 0.5, capB), serverView, anchor)
    end

    return a, b, shaft
end

-- Sized from the hurtbox, NOT from the body. Those are the two shapes this
-- tool exists to let you compare, so deriving one from the other would erase
-- the finding.
--
-- IT READS `endpoints` RATHER THAN RECOMPUTING THEM. Resolution asks the same
-- component the same question with the same method, so the overlay cannot
-- drift from the thing it is drawing -- the entire value of a debug overlay and
-- the first thing a hand-rolled copy would lose.
--
-- ============================================================================
-- THIS NOW DRAWS THE ZONE LIST, and an earlier revision of this comment
-- predicted it would be the whole change. It was.
-- ============================================================================
--
-- `entity.hurtbox` is a HurtboxComponent holding N capsules; each zone's
-- endpoints are computed against the body's ROOT pose. Welding rather than
-- teleporting is what makes N affordable -- six capsules per player would
-- otherwise be eighteen CFrame writes per body per redraw, and welded it is
-- none.
--
-- FALLS BACK TO THE SPATIAL COMPONENT'S SINGLE CAPSULE when no hurtbox is
-- attached, so anything not yet wired still draws something rather than
-- silently vanishing from the overlay. A body that disappears from a debug
-- view reads as "not attached", which would be a lie.
local function build(entity, spatial, serverView: boolean)
    local pose = spatial:getCFrame()
    if not pose then
        return nil
    end

    local anchor = spatial.anchor
    local id = tostring(entity.identity:getId())
    local hurtbox = entity.hurtbox

    local pieces = {
        -- What this set was built FROM. The loop compares against these to
        -- decide whether the overlay still describes the body, so a respawn,
        -- a resize or a mode flip rebuilds instead of quietly lying.
        anchor = anchor,
        hurtbox = hurtbox,
        zoneCount = hurtbox:zoneCount(),
        serverView = serverView,
        zones = {},
        all = {},
    }

    local count = pieces.zoneCount
    for index = 1, count do
        local capA, capB, radius

        -- EACH ZONE IS WELDED TO ITS OWN LIMB, not all of them to the root,
        -- and that is the whole difference between an overlay that follows the
        -- pose and a mannequin riding the body. An arm capsule welded to
        -- `LeftUpperArm` goes up when the arm goes up, for free, with nothing
        -- writing a CFrame -- the same weld trick that stopped the overlay
        -- trailing the player in the first place, applied per zone.
        local zoneAnchor = anchor

        local bound = hurtbox and hurtbox:anchorFor(index)
        if bound and bound.Parent then
            zoneAnchor = bound
        end

        -- Endpoints come from the LIMB's pose, so the drawing matches where
        -- the zone actually is rather than where the root is.
        capA, capB, radius = hurtbox:endpoints(index, zoneAnchor.CFrame)

        -- The zone's NAME goes in the part name, not just its index. When a
        -- capsule is in the wrong place, "ArmLowerL is too long" is a sentence
        -- you can act on; "zone 4" means opening a file to find out which one
        -- that is.
        local label = hurtbox:zoneName(index)
        local a, b, shaft = drawCapsule(
            string.format("HB_%s_%s", id, label), capA, capB, radius, serverView, zoneAnchor)

        pieces.zones[index] = { capA = a, capB = b, shaft = shaft, anchor = zoneAnchor }
        table.insert(pieces.all, a)
        table.insert(pieces.all, b)
        if shaft then
            table.insert(pieces.all, shaft)
        end
    end

    HurtboxDebug._parts[entity] = pieces
    return pieces
end

-- True when the existing overlay no longer describes the body it was built
-- for. Cheap enough to run per entity per redraw, which is the point: it
-- replaces the CFrame writes rather than adding to them.
--
-- `hurtbox` is compared by IDENTITY, not by contents. attach rebuilds the
-- component on every respawn, so a new component object means a body that may
-- be a different shape -- and comparing contents would be both slower and
-- wrong the moment two bodies share a definition table.
local function isStale(pieces, spatial, serverView: boolean, hurtbox): boolean
    return pieces.serverView ~= serverView
        or pieces.anchor ~= spatial.anchor
        or pieces.hurtbox ~= hurtbox
        -- Destroyed out from under us: a respawn took the character, and with
        -- it the welded pieces parented to its root.
        or pieces.all[1].Parent == nil
end

-- ServerView only. Rewrites the pose from the server's copy of the body, which
-- is the whole point of the mode -- see the header.
local function reposition(pieces, spatial, hurtbox)
    local pose = spatial:getCFrame()
    if not pose then
        return
    end

    for index, zone in ipairs(pieces.zones) do
        -- The limb's live pose, matching what build() drew from. Reading the
        -- root here instead would make ServerView disagree with the welded
        -- mode about where a zone is, which would look like a latency finding
        -- and be a bug in this file.
        local zonePose = (zone.anchor and zone.anchor.Parent and zone.anchor.CFrame) or pose
        local capA, capB = hurtbox:endpoints(index, zonePose)

        zone.capA.CFrame = CFrame.new(capA)
        zone.capB.CFrame = CFrame.new(capB)

        if zone.shaft then
            local delta = capB - capA
            zone.shaft.CFrame = CFrame.lookAt(capA + delta * 0.5, capB)
        end
    end
end

-- LOGGING ---------------------------------------------------------------
--
-- Exists to separate two complaints that look identical on screen and have
-- completely different causes:
--
--   "the hurtbox does not move"        -> is WORLD position changing as the
--                                         body walks? If not, the weld or the
--                                         attach is broken. Real bug.
--   "the hurtbox does not bend"        -> is REL ROOT changing as limbs
--                                         animate? It is not supposed to.
--                                         Zones hang off the ROOT for a
--                                         client-owned rig, so a swinging arm
--                                         moves the arm and not its zone.
--                                         Working as designed -- HitDetection
--                                         7.2a -- and the fix is a different
--                                         piece of work, not a repair.
--
-- Printing both columns is what makes the distinction visible instead of
-- arguable.

local LOG_FLAG = "HurtboxLog"
local LOG_SECONDS = 2.0

HurtboxDebug._logAccumulator = 0
HurtboxDebug._lastSeen = {}     -- entity -> { root = Vector3, rel = { Vector3 } }

local function logEntity(entity, spatial, hurtbox)
    local pose = spatial:getCFrame()
    if not pose then
        return
    end

    local id = tostring(entity.identity:getId())
    local last = HurtboxDebug._lastSeen[entity]
    local rootMoved = last and (pose.Position - last.root).Magnitude or 0

    local humanoidState = "?"
    local model = spatial.anchor and spatial.anchor.Parent
    local humanoid = model and model:FindFirstChildOfClass("Humanoid")
    if humanoid then
        humanoidState = humanoid:GetState().Name
    end

    print(string.format(
        "[HurtboxLog] %s  hurtbox=%s  state=%s",
        id,
        string.format("%d zones", hurtbox:zoneCount()),
        humanoidState))
    print(string.format(
        "    root world (%.1f, %.1f, %.1f)   moved %.2f studs since last block",
        pose.Position.X, pose.Position.Y, pose.Position.Z, rootMoved))

    local count = hurtbox:zoneCount()
    local rel = {}

    for index = 1, count do
        local capA, capB, radius
        local label, ridden
            -- READ FROM THE LIMB, not the root. Reading the root here would
            -- report zero rel-root drift on every zone forever, which is
            -- exactly the symptom this log exists to distinguish -- the
            -- instrument would be manufacturing the finding.
            local bound = hurtbox:anchorFor(index)
            local zonePose = (bound and bound.Parent and bound.CFrame) or pose
            capA, capB, radius = hurtbox:endpoints(index, zonePose)
            label = hurtbox:zoneName(index)
            ridden = (bound and bound.Parent) and bound.Name or "ROOT (unbound)"


        -- The capsule's centre is the honest single number for "where is this
        -- zone" -- an endpoint moves when the zone merely rotates.
        local centre = (capA + capB) * 0.5
        local relative = pose:Inverse() * centre
        rel[index] = relative

        local drift = 0
        if last and last.rel[index] then
            drift = (relative - last.rel[index]).Magnitude
        end

        print(string.format(
            "    %-10s on %-14s rel root (%5.2f,%5.2f,%5.2f)   r=%.2f   "
                .. "rel drift %.3f",
            label, ridden,
            relative.X, relative.Y, relative.Z,
            radius, drift))
    end

    HurtboxDebug._lastSeen[entity] = { root = pose.Position, rel = rel }
end

local function refresh(entity, serverView: boolean)
    local spatial = entity.spatial
    if not spatial or not spatial:isAnchored() then
        -- The body left the world: a respawn, a despawn, a disconnect.
        -- Self-healing for the same reason SpatialService:tick is -- without
        -- it, every departure leaves a glowing shape where a corpse used to be.
        release(entity)
        return
    end

    local hurtbox = entity.hurtbox

    local pieces = HurtboxDebug._parts[entity]
    if pieces and isStale(pieces, spatial, serverView, hurtbox) then
        release(entity)
        pieces = nil
    end

    if not pieces then
        pieces = build(entity, spatial, serverView)
    end

    -- Welded pieces need nothing here. That absence is the fix.
    if pieces and serverView then
        reposition(pieces, spatial, hurtbox)
    end
end

function HurtboxDebug.start()
    if HurtboxDebug._connection then
        return
    end

    -- Torn down rather than paused when the flag goes off, or the last frame
    -- of overlays would hang in the air forever -- a frozen hurtbox on a body
    -- that has since walked away is worse than none at all.
    DebugConfig.onChanged(FLAG, function(enabled)
        if not enabled then
            for entity in pairs(HurtboxDebug._parts) do
                release(entity)
            end
        end
    end)

    -- The mode flip needs no handler: `isStale` sees `serverView` disagree on
    -- the next tick and rebuilds. One rule deciding when an overlay is wrong,
    -- rather than one rule plus a handler that has to remember to agree.

    local interval = 1 / REDRAW_HZ

    HurtboxDebug._connection = RunService.Heartbeat:Connect(function(deltaTime)
        -- The LOG runs off its own accumulator and its own flag, deliberately
        -- ahead of the drawing gate. It has to be readable with the overlay
        -- turned OFF -- "nothing is drawn" and "nothing is attached" look
        -- identical in the viewport, and the log is what tells them apart.
        if DebugConfig.get(LOG_FLAG) then
            HurtboxDebug._logAccumulator += deltaTime
            if HurtboxDebug._logAccumulator >= LOG_SECONDS then
                HurtboxDebug._logAccumulator = 0
                print("")
                SpatialService:forEachAttached(function(entity)
                    local spatial = entity.spatial
                    if spatial and spatial:isAnchored() then
                        logEntity(entity, spatial, entity.hurtbox)
                    end
                end)
            end
        end

        if not DebugConfig.get(FLAG) then
            return
        end

        HurtboxDebug._accumulator += deltaTime
        if HurtboxDebug._accumulator < interval then
            return
        end
        HurtboxDebug._accumulator = 0

        local serverView = DebugConfig.get(SERVER_VIEW_FLAG)

        local seen = {}
        SpatialService:forEachAttached(function(entity)
            seen[entity] = true
            refresh(entity, serverView)
        end)

        -- Anything that detached between frames. refresh() catches bodies that
        -- left the world, but not an entity that was cleanly detached while
        -- its part still exists -- EntityService:deleteEntity does exactly
        -- that, detaching before destroying (Architecture Part 7).
        for entity in pairs(HurtboxDebug._parts) do
            if not seen[entity] then
                release(entity)
            end
        end
    end)

    print(string.format(
        "[HurtboxDebug] armed at %dHz (flag Debug%s) -- drawing the ZONE LIST, "
            .. "welded, so it cannot trail you", REDRAW_HZ, FLAG))

    print(string.format(
        "    Debug%s draws the SERVER's copy instead -- the gap it opens up is "
            .. "the round trip rewind exists to undo.", SERVER_VIEW_FLAG))
end

function HurtboxDebug.stop()
    if HurtboxDebug._connection then
        HurtboxDebug._connection:Disconnect()
        HurtboxDebug._connection = nil
    end
    for entity in pairs(HurtboxDebug._parts) do
        release(entity)
    end
    if HurtboxDebug._folder then
        HurtboxDebug._folder:Destroy()
        HurtboxDebug._folder = nil
    end
end

return HurtboxDebug
