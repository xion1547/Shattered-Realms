-- src/gameModes/dungeon/server/diagnostics/HurtboxDebug.luau
--
-- Draws every attached entity's hurtbox as a translucent overlay, so the
-- thing you HIT can be compared against the thing you SEE.
--
-- THIS IS THE INSTRUMENT FOR THE ONE BUG NOBODY CAN SPOT BY PLAYING.
-- HitDetection.md §7.1: the dummies are 4x5x4 bodies wearing a 2.5-radius
-- sphere, which is 5 studs across -- 25% too wide. A player's is worse, ~2.5x
-- too wide against a 2-stud body. Neither is visible in a normal session: a
-- swing that connects a stud early looks exactly like a swing that connected.
-- Turning this on is what makes the gap a thing you can see instead of a
-- number in a document.
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
-- fall behind a body -- it is `anchor.CFrame` plus two numbers, evaluated at
-- the moment a query asks (SpatialComponent:endpoints). There is no stored
-- position to drift. What lagged was the PICTURE.
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

-- Sized from the hurtbox, NOT from the body. Those are the two shapes this
-- tool exists to let you compare, so deriving one from the other would erase
-- the finding.
--
-- IT READS `endpoints` RATHER THAN RECOMPUTING THEM. TargetResolution asks the
-- component the same question with the same method, so the overlay cannot
-- drift from the thing it is drawing -- which is the entire value of a debug
-- overlay and the first thing a hand-rolled copy would lose.
--
-- WHEN HURTBOXES BECOME HITZONE LISTS, THIS FUNCTION IS THE WHOLE CHANGE.
-- Today a body carries ONE capsule, so this builds one set. Under
-- HitDetection.md §7.2 it becomes N capsules, each welded to its own rig part
-- -- so this grows a loop over the hitzone list and `pieces.all` grows with
-- it. Welding rather than teleporting is what makes that version cheap: six
-- capsules per player would otherwise be eighteen CFrame writes per body per
-- redraw, and now it is none.
local function build(entity, spatial, serverView: boolean)
    local pose = spatial:getCFrame()
    if not pose then
        return nil
    end

    local capA, capB = spatial:endpoints(pose)
    local diameter = spatial.radius * 2
    local ball = Vector3.new(diameter, diameter, diameter)
    local anchor = spatial.anchor
    local id = tostring(entity.identity:getId())

    local pieces = {
        -- What this set was built FROM. The loop compares against these to
        -- decide whether the overlay still describes the body, so a respawn,
        -- a resize or a mode flip rebuilds instead of quietly lying.
        anchor = anchor,
        radius = spatial.radius,
        halfHeight = spatial.halfHeight,
        serverView = serverView,
        all = {},
    }

    pieces.capA = spawnPiece(string.format("HB_%s_A", id), Enum.PartType.Ball,
        ball, CFrame.new(capA), serverView, anchor)
    pieces.capB = spawnPiece(string.format("HB_%s_B", id), Enum.PartType.Ball,
        ball, CFrame.new(capB), serverView, anchor)
    table.insert(pieces.all, pieces.capA)
    table.insert(pieces.all, pieces.capB)

    local delta = capB - capA
    local length = delta.Magnitude
    if length > 0 then
        -- A Part's Size.Z runs along its local -Z, which is where lookAt
        -- points -- so a block of this length centred on the midpoint and
        -- looking at capB spans exactly the segment.
        pieces.shaft = spawnPiece(string.format("HB_%s_shaft", id), Enum.PartType.Block,
            Vector3.new(diameter, diameter, length),
            CFrame.lookAt(capA + delta * 0.5, capB), serverView, anchor)
        table.insert(pieces.all, pieces.shaft)
    end

    HurtboxDebug._parts[entity] = pieces
    return pieces
end

-- True when the existing overlay no longer describes the body it was built
-- for. Cheap enough to run per entity per redraw, which is the point: it
-- replaces the CFrame writes rather than adding to them.
local function isStale(pieces, spatial, serverView: boolean): boolean
    return pieces.serverView ~= serverView
        or pieces.anchor ~= spatial.anchor
        or pieces.radius ~= spatial.radius
        or pieces.halfHeight ~= spatial.halfHeight
        -- Destroyed out from under us: a respawn took the character, and with
        -- it the welded pieces parented to its root.
        or pieces.all[1].Parent == nil
end

-- ServerView only. Rewrites the pose from the server's copy of the body, which
-- is the whole point of the mode -- see the header.
local function reposition(pieces, spatial)
    local pose = spatial:getCFrame()
    if not pose then
        return
    end

    local capA, capB = spatial:endpoints(pose)
    pieces.capA.CFrame = CFrame.new(capA)
    pieces.capB.CFrame = CFrame.new(capB)

    if pieces.shaft then
        local delta = capB - capA
        pieces.shaft.CFrame = CFrame.lookAt(capA + delta * 0.5, capB)
    end
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

    local pieces = HurtboxDebug._parts[entity]
    if pieces and isStale(pieces, spatial, serverView) then
        release(entity)
        pieces = nil
    end

    if not pieces then
        pieces = build(entity, spatial, serverView)
    end

    -- Welded pieces need nothing here. That absence is the fix.
    if pieces and serverView then
        reposition(pieces, spatial)
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
        "[HurtboxDebug] armed at %dHz (flag Debug%s) -- the glowing volume is "
            .. "what you actually hit, the model is only what you see",
        REDRAW_HZ, FLAG))
    print(string.format(
        "    welded to the body, so it cannot trail you. Debug%s draws the "
            .. "SERVER's copy instead -- the gap it opens up is the round trip "
            .. "rewind exists to undo.", SERVER_VIEW_FLAG))
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
