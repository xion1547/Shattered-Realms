-- src/gameModes/dungeon/server/tests/SpatialTests.luau
--
-- The Spatial component and SpatialService. See HitDetection.md.
--
-- The ring buffer is the part worth testing hardest, and specifically its
-- WRAP. A buffer that is correct for the first N samples and subtly wrong
-- afterwards is the worst possible bug here: it would work perfectly in
-- every short test, then start returning positions from the wrong moment
-- once a server had been up for half a second. Several cases below
-- deliberately write past the end and read across the seam.
--
-- What is NOT tested here, because it needs a live client: the actual
-- latency figure. PingProbe covers that.

local ServerStorage = game:GetService("ServerStorage")
local components = ServerStorage:WaitForChild("Shared"):WaitForChild("components")

local Spatial = require(components:WaitForChild("Spatial"))

local serverRoot = game.ServerScriptService:WaitForChild("Server")
local SpatialService = require(serverRoot:WaitForChild("services"):WaitForChild("authority")
    :WaitForChild("SpatialService"))

local TestRunner = require(script.Parent:WaitForChild("TestRunner"))

-- A body in the world. Parented to workspace because isAnchored() asks
-- IsDescendantOf(workspace) -- an unparented part is deliberately not
-- "in the world" as far as this layer is concerned.
local function makeAnchor(position)
    local part = Instance.new("Part")
    part.Anchored = true
    part.CanCollide = false
    part.CanQuery = false
    part.Transparency = 1
    part.Size = Vector3.one
    part.CFrame = CFrame.new(position or Vector3.zero)
    part.Parent = workspace
    return part
end

local function entityWith(historyLength)
    return { spatial = Spatial.new(historyLength) }
end

return function()
    local t = TestRunner.new("Spatial")

    -- Component: anchoring ------------------------------------------------

    t:case("a new Spatial is unanchored and answers nothing", function(a)
        local spatial = Spatial.new()
        a.isFalse(spatial:isAnchored())
        a.isNil(spatial:getCFrame(), "an unanchored component has no position")
        a.isNil(spatial:poseAt(0), "an unanchored component has no history")
        a.equal(spatial:sampleCount(), 0)
    end)

    t:case("an anchor removed from the world reads as unanchored", function(a)
        -- This is what a respawn and a disconnect both look like from here,
        -- and it is what SpatialService's self-healing detach keys off.
        local part = makeAnchor()
        local spatial = Spatial.new()
        spatial:setAnchor(part, 2)
        a.isTrue(spatial:isAnchored())

        part.Parent = nil
        a.isFalse(spatial:isAnchored(), "an anchor outside workspace is not in the world")
        a.isNil(spatial:getCFrame())
        part:Destroy()
    end)

    t:case("setAnchor rejects a non-part and a non-positive radius", function(a)
        local spatial = Spatial.new()
        a.throws(function() spatial:setAnchor(nil, 2) end, "must be a BasePart")
        a.throws(function() spatial:setAnchor(Instance.new("Folder"), 2) end, "must be a BasePart")

        local part = makeAnchor()
        a.throws(function() spatial:setAnchor(part, 0) end, "must be positive")
        a.throws(function() spatial:setAnchor(part, -1) end, "must be positive")
        part:Destroy()
    end)

    t:case("re-anchoring clears the previous body's history", function(a)
        -- History from a previous body is not history for this one. A
        -- respawned character that inherited the old buffer would be
        -- rewindable to a position it never occupied.
        local first, second = makeAnchor(), makeAnchor()
        local spatial = Spatial.new()

        spatial:setAnchor(first, 2)
        spatial:record(1, CFrame.new(50, 0, 0))
        a.equal(spatial:sampleCount(), 1)

        spatial:setAnchor(second, 2)
        a.equal(spatial:sampleCount(), 0, "the new body starts with no past")
        a.isNil(spatial:poseAt(1))

        first:Destroy()
        second:Destroy()
    end)

    -- Component: the ring buffer ------------------------------------------

    t:case("poseAt returns an exact sample at its exact timestamp", function(a)
        local spatial = Spatial.new(4)
        spatial:record(10, CFrame.new(0, 0, 0))
        spatial:record(11, CFrame.new(10, 0, 0))

        a.near(spatial:poseAt(10).Position.X, 0)
        a.near(spatial:poseAt(11).Position.X, 10)
    end)

    t:case("poseAt interpolates between the bracketing samples", function(a)
        local spatial = Spatial.new(4)
        spatial:record(10, CFrame.new(0, 0, 0))
        spatial:record(11, CFrame.new(10, 0, 0))

        a.near(spatial:poseAt(10.5).Position.X, 5, 0.001, "halfway between two samples")
        a.near(spatial:poseAt(10.25).Position.X, 2.5)
        a.near(spatial:poseAt(10.9).Position.X, 9)
    end)

    t:case("poseAt clamps at both ends rather than returning nil", function(a)
        local spatial = Spatial.new(4)
        spatial:record(10, CFrame.new(0, 0, 0))
        spatial:record(11, CFrame.new(10, 0, 0))

        a.near(spatial:poseAt(99).Position.X, 10, 0.001, "past the newest, the newest is the best answer")
        a.near(spatial:poseAt(0).Position.X, 0, 0.001, "past the oldest, clamp rather than guess")
    end)

    t:case("a single sample answers every query", function(a)
        local spatial = Spatial.new(4)
        spatial:record(10, CFrame.new(7, 0, 0))
        a.near(spatial:poseAt(0).Position.X, 7)
        a.near(spatial:poseAt(10).Position.X, 7)
        a.near(spatial:poseAt(99).Position.X, 7)
    end)

    t:case("the buffer wraps and evicts oldest first", function(a)
        local spatial = Spatial.new(3)
        for i = 1, 4 do
            spatial:record(i, CFrame.new(i, 0, 0))
        end

        a.equal(spatial:sampleCount(), 3, "capacity is a hard ceiling")
        a.near(spatial:poseAt(0).Position.X, 2, 0.001,
            "sample 1 was evicted, so the oldest available is 2")
        a.near(spatial:poseAt(4).Position.X, 4, 0.001, "the newest survives the wrap")
    end)

    t:case("interpolation is correct ACROSS the physical wrap seam", function(a)
        -- The case a naive implementation gets wrong. With capacity 3 and
        -- four samples written, logical samples 2,3,4 sit at physical slots
        -- 2,3,1 -- so interpolating between logical 3 and 4 reads across the
        -- end of the array and back to the front.
        local spatial = Spatial.new(3)
        for i = 1, 4 do
            spatial:record(i, CFrame.new(i * 10, 0, 0))
        end

        a.near(spatial:poseAt(3.5).Position.X, 35, 0.001, "between logical 3 and 4, across the seam")
        a.near(spatial:poseAt(2.5).Position.X, 25, 0.001, "between logical 2 and 3, no seam crossed")
    end)

    t:case("the binary search finds the right bracket deep in a full buffer", function(a)
        -- Many samples, many wraps, and a query near the middle. A search
        -- that was off by one physical slot would still return a plausible
        -- position, which is why the expected value here is exact.
        local spatial = Spatial.new(17)
        for i = 1, 100 do
            spatial:record(i * 0.1, CFrame.new(i, 0, 0))
        end

        a.equal(spatial:sampleCount(), 17)
        -- Samples 84..100 survive, at times 8.4 .. 10.0
        a.near(spatial:poseAt(9.0).Position.X, 90, 0.001)
        a.near(spatial:poseAt(9.05).Position.X, 90.5, 0.01)
        a.near(spatial:poseAt(8.4).Position.X, 84, 0.001, "the oldest surviving sample")
        a.near(spatial:poseAt(10.0).Position.X, 100, 0.001, "the newest")
    end)

    t:case("non-advancing timestamps are ignored, not recorded", function(a)
        -- The binary search depends on ordering. This is a guard rather
        -- than an assert because it runs inside a pcall'd Scheduler tick,
        -- where an assert would warn once per frame forever.
        local spatial = Spatial.new(4)
        spatial:record(10, CFrame.new(0, 0, 0))
        spatial:record(10, CFrame.new(99, 0, 0))
        spatial:record(9, CFrame.new(99, 0, 0))

        a.equal(spatial:sampleCount(), 1, "duplicate and backwards samples are dropped")
        a.near(spatial:poseAt(10).Position.X, 0, 0.001, "the original sample is untouched")
    end)

    t:case("span reports how far back the buffer actually reaches", function(a)
        local spatial = Spatial.new(4)
        spatial:record(100, CFrame.new())
        spatial:record(101, CFrame.new())

        local oldest, newest = spatial:span(102)
        a.near(oldest, 2, 0.001)
        a.near(newest, 1, 0.001)
    end)

    -- Service: registration -----------------------------------------------

    t:case("attach and detach maintain the attached count", function(a)
        local before = SpatialService:attachedCount()
        local entity = entityWith()
        local part = makeAnchor()

        SpatialService:attach(entity, part, 2.5)
        a.isTrue(SpatialService:isAttached(entity))
        a.equal(SpatialService:attachedCount(), before + 1)

        SpatialService:attach(entity, part, 2.5)
        a.equal(SpatialService:attachedCount(), before + 1, "attaching twice is not two entities")

        SpatialService:detach(entity)
        a.isFalse(SpatialService:isAttached(entity))
        a.equal(SpatialService:attachedCount(), before, "the count returns to where it started")

        SpatialService:detach(entity)
        a.equal(SpatialService:attachedCount(), before, "detaching twice does not go negative")

        part:Destroy()
    end)

    t:case("attach refuses an entity with no Spatial component", function(a)
        local part = makeAnchor()
        a.throws(function() SpatialService:attach({}, part, 2) end, "no Spatial component")
        part:Destroy()
    end)

    t:case("attach refuses a buffer too short to span the rewind ceiling", function(a)
        -- The buffer length is chosen in the component and the rewind
        -- ceiling in the service. A mismatch is silent -- poseAt would clamp
        -- to its oldest sample and return a real position from the wrong
        -- moment -- so it is checked rather than trusted.
        local part = makeAnchor()
        a.throws(function() SpatialService:attach(entityWith(4), part, 2) end, "samples")
        part:Destroy()
    end)

    t:case("detach clears the anchor as well as the registration", function(a)
        local entity = entityWith()
        local part = makeAnchor()

        SpatialService:attach(entity, part, 2)
        SpatialService:detach(entity)

        a.isFalse(entity.spatial:isAnchored(), "a detached entity is not still holding a body")
        part:Destroy()
    end)

    -- Service: sampling ---------------------------------------------------

    t:case("tick records a sample for every attached entity", function(a)
        local entity = entityWith()
        local part = makeAnchor(Vector3.new(5, 0, 0))
        SpatialService:attach(entity, part, 2)

        a.equal(entity.spatial:sampleCount(), 0, "attach does not sample")

        SpatialService:tick(1 / 30)
        a.equal(entity.spatial:sampleCount(), 1)

        local pose = entity.spatial:poseAt(workspace:GetServerTimeNow())
        a.notNil(pose)
        a.near(pose.Position.X, 5, 0.001, "it recorded where the anchor actually is")

        SpatialService:detach(entity)
        part:Destroy()
    end)

    t:case("tick auto-detaches an entity whose body left the world", function(a)
        -- Self-healing on purpose: without it, every departure that forgot
        -- to call detach would leak an entry and a long-running server
        -- would iterate a growing list of corpses every tick.
        local entity = entityWith()
        local part = makeAnchor()
        SpatialService:attach(entity, part, 2)

        local before = SpatialService:attachedCount()
        part.Parent = nil
        SpatialService:tick(1 / 30)

        a.isFalse(SpatialService:isAttached(entity), "a body outside workspace is detached")
        a.equal(SpatialService:attachedCount(), before - 1)
        part:Destroy()
    end)

    -- Service: broadphase and rewind --------------------------------------

    t:case("candidatesNear culls by distance and respects the margin", function(a)
        local near, far = entityWith(), entityWith()
        local nearPart = makeAnchor(Vector3.new(0, 0, 0))
        local farPart = makeAnchor(Vector3.new(100, 0, 0))

        SpatialService:attach(near, nearPart, 2)
        SpatialService:attach(far, farPart, 2)

        local function contains(list, entity)
            for _, found in ipairs(list) do
                if found == entity then
                    return true
                end
            end
            return false
        end

        local hits = SpatialService:candidatesNear(Vector3.zero, 10)
        a.isTrue(contains(hits, near), "the close one is a candidate")
        a.isFalse(contains(hits, far), "the distant one is culled")

        -- The margin is what stops a cull from discarding something that has
        -- since run out of range but WAS inside the volume when it mattered.
        local widened = SpatialService:candidatesNear(Vector3.zero, 10, 200)
        a.isTrue(contains(widened, far), "the margin widens the cull")

        SpatialService:detach(near)
        SpatialService:detach(far)
        nearPart:Destroy()
        farPart:Destroy()
    end)

    t:case("the hurtbox radius counts toward the cull", function(a)
        -- An entity whose centre is outside the reach but whose body
        -- overlaps it must survive the broadphase, or narrow phase never
        -- gets the chance to find the hit.
        local entity = entityWith()
        local part = makeAnchor(Vector3.new(12, 0, 0))
        SpatialService:attach(entity, part, 5)

        local hits = SpatialService:candidatesNear(Vector3.zero, 8)
        a.isTrue(#hits >= 1, "centre at 12, reach 8, radius 5 -- overlapping")

        SpatialService:detach(entity)
        part:Destroy()
    end)

    t:case("the rewind window is clamped and never errors on a non-player", function(a)
        local constants = SpatialService:constants()

        -- roundTripOf pcalls GetNetworkPing, so anything that is not a
        -- Player contributes zero rather than throwing. What remains is the
        -- interpolation constant, which is not latency-dependent.
        local window = SpatialService:rewindWindowFor({})
        a.near(window, constants.interpolationConstant, 0.0001,
            "with no measurable latency, only the interpolation constant applies")

        a.isTrue(window <= constants.maxRewind, "the window can never exceed the ceiling")
        a.isTrue(window >= 0, "the window is never negative")
    end)

    t:case("viewTimeFor is in the past by exactly the rewind window", function(a)
        local now = workspace:GetServerTimeNow()
        local viewTime = SpatialService:viewTimeFor({})
        local window = SpatialService:rewindWindowFor({})

        a.isTrue(viewTime < now, "a player's view of the world is always behind the server's")
        a.near(now - viewTime, window, 0.05, "the gap is the rewind window")
    end)

    t:case("the buffer is long enough to span the rewind ceiling", function(a)
        -- The arithmetic tying SAMPLE_HZ, MAX_REWIND and the default
        -- component buffer together. If someone retunes one of the three,
        -- this is what says so.
        local constants = SpatialService:constants()
        local needed = constants.maxRewind * constants.sampleHz

        a.isTrue(constants.historyLength > needed, string.format(
            "history of %d must exceed %.1f samples", constants.historyLength, needed))
        a.isTrue(Spatial.new():historyLength() >= constants.historyLength,
            "the component's default buffer must satisfy the service's ceiling")
    end)

    return t:run()
end
