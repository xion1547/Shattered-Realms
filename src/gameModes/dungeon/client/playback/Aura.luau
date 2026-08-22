-- src/gameModes/dungeon/client/playback/Aura.luau
--
-- The generic engine for AuraDefinitions. Reads a definition, builds the
-- emitters, returns a handle that tears them down.
--
-- CLIENT-SIDE, and that is not an accident of where the file sits. An aura is
-- pure PLAYBACK (Client-Architecture): it damages nothing, blocks nothing, and
-- is not a fact anyone needs to agree on. Building it on the server would
-- replicate dozens of instances per player to describe something every client
-- can construct for itself from a string.
--
-- ADDING AN AURA NEVER TOUCHES THIS FILE. That is Architecture-Reference Part
-- 2's test, and it is why the definitions are tables of numbers rather than a
-- function per effect. A new aura is content; a new KIND of aura -- one
-- needing a property nothing else uses -- is the only thing that brings
-- anyone back here.
--
-- ============================================================================
-- THE ONE PIECE OF ROBLOX TRIVIA THIS FILE EXISTS TO ABSORB
-- ============================================================================
--
-- A ParticleEmitter's emission SHAPE is sized by the BasePart it is parented
-- to. Parented to an Attachment it emits from a POINT, and the docs are
-- explicit that Sphere and Cylinder "will not display correctly" that way.
--
-- That failure is silent. The emitter still runs, particles still fly, and the
-- column just quietly becomes a fountain from a single spot -- which looks
-- like a badly tuned effect rather than a structural mistake, so it would
-- never have been found by staring at the numbers.
--
-- So every layer gets an invisible host Part sized to its `shapeSize`, welded
-- to the root. That is the entire reason this module is more than twenty
-- lines, and it is worth the instances: it is what makes `shapeSize` mean
-- anything at all.

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AuraDefinitions = require(
    ReplicatedStorage:WaitForChild("definitions"):WaitForChild("AuraDefinitions"))

local Aura = {}
Aura.__index = Aura

-- Properties copied straight across when present. LISTED RATHER THAN LOOPED,
-- so a typo in a definition fails loudly below instead of being ignored -- a
-- misspelled `lifetim` that silently does nothing is the worst kind of content
-- bug, because the effect still plays and merely looks wrong.
local DIRECT = {
    rate = "Rate",
    lifetime = "Lifetime",
    speed = "Speed",
    spreadAngle = "SpreadAngle",
    acceleration = "Acceleration",
    drag = "Drag",
    size = "Size",
    squash = "Squash",
    transparency = "Transparency",
    color = "Color",
    lightEmission = "LightEmission",
    lightInfluence = "LightInfluence",
    brightness = "Brightness",
    rotation = "Rotation",
    rotSpeed = "RotSpeed",
    zOffset = "ZOffset",
    texture = "Texture",
    shapePartial = "ShapePartial",
    velocityInheritance = "VelocityInheritance",
    timeScale = "TimeScale",
    windAffectsDrag = "WindAffectsDrag",
}

-- Enum-valued properties, written as plain strings in the definitions.
-- Content should never have to spell `Enum.ParticleEmitterShape.Cylinder` --
-- that is an implementation detail leaking into a data table.
local ENUMS = {
    shape = { property = "Shape", enum = Enum.ParticleEmitterShape },
    shapeStyle = { property = "ShapeStyle", enum = Enum.ParticleEmitterShapeStyle },
    shapeInOut = { property = "ShapeInOut", enum = Enum.ParticleEmitterShapeInOut },
    emissionDirection = { property = "EmissionDirection", enum = Enum.NormalId },
    orientation = { property = "Orientation", enum = Enum.ParticleOrientation },
}

-- Consumed by this module rather than set on the emitter.
local STRUCTURAL = {
    name = true,
    attachTo = true,
    offset = true,
    shapeSize = true,
}

local DEFAULT_SHAPE_SIZE = Vector3.new(0.2, 0.2, 0.2)

-- An invisible, massless, weightless part that exists only to give the
-- emitter a volume to emit from and a body to follow.
local function buildHost(root: BasePart, layer, container: Instance): BasePart
    local host = Instance.new("Part")
    host.Name = string.format("AuraHost_%s", tostring(layer.name))
    host.Size = layer.shapeSize or DEFAULT_SHAPE_SIZE
    host.CFrame = root.CFrame * CFrame.new(layer.offset or Vector3.zero)

    host.Transparency = 1
    host.CanCollide = false
    host.CanQuery = false
    host.CanTouch = false
    host.Massless = true
    host.CastShadow = false
    host.Locked = true
    host.Parent = container

    -- WeldConstraint rather than setting CFrame every frame: the physics
    -- solver already moves welded parts with their anchor, and doing it in Lua
    -- would add a Heartbeat connection per layer for a job the engine does for
    -- free. Massless keeps it from affecting how the character moves.
    local weld = Instance.new("WeldConstraint")
    weld.Part0 = root
    weld.Part1 = host
    weld.Parent = host

    return host
end

local function buildEmitter(layer, host: BasePart): ParticleEmitter
    local emitter = Instance.new("ParticleEmitter")

    for key, value in pairs(layer) do
        if DIRECT[key] then
            emitter[DIRECT[key]] = value
        elseif ENUMS[key] then
            local spec = ENUMS[key]
            local item = spec.enum[value]
            assert(item, string.format(
                "[Aura] layer '%s': '%s' is not a valid %s",
                tostring(layer.name), tostring(value), spec.property))
            emitter[spec.property] = item
        elseif not STRUCTURAL[key] then
            error(string.format(
                "[Aura] layer '%s' declares unknown field '%s' -- check the "
                    .. "spelling, or add it to DIRECT/ENUMS if it is real",
                tostring(layer.name), tostring(key)), 0)
        end
    end

    emitter.Name = layer.name or "layer"
    emitter.Parent = host
    return emitter
end

-- `root` is whatever the aura hangs off -- a HumanoidRootPart, a boss's torso,
-- an anchored part for a stationary effect. Anything with a CFrame works.
function Aura.play(root: BasePart, auraId: string)
    local definition = AuraDefinitions[auraId]
    assert(definition, string.format("[Aura] unknown aura: %s", tostring(auraId)))
    assert(typeof(root) == "Instance" and root:IsA("BasePart"),
        "[Aura] needs a BasePart to hang off")

    -- One container per aura, so teardown is a single Destroy and a half-torn
    -- aura is not a state this module can be left in.
    local container = Instance.new("Folder")
    container.Name = string.format("Aura_%s", auraId)
    container.Parent = root.Parent or workspace

    local self = setmetatable({
        _root = root,
        _id = auraId,
        _container = container,
        _emitters = {},
        _light = nil,
        _lightConnection = nil,
    }, Aura)

    for _, layer in ipairs(definition.layers) do
        local host = buildHost(root, layer, container)
        table.insert(self._emitters, buildEmitter(layer, host))
    end

    if definition.light then
        local spec = definition.light
        local light = Instance.new("PointLight")
        light.Color = spec.color
        light.Brightness = spec.brightness
        light.Range = spec.range
        light.Shadows = false
        light.Parent = root
        self._light = light

        -- FLICKER IS WHAT SELLS THE LIGHT. A steady PointLight reads as a lamp
        -- someone left on; the same light wobbling a few percent at 14Hz reads
        -- as combustion.
        --
        -- Two sines at unrelated frequencies rather than one, because a single
        -- sine has an obvious period the eye finds within a couple of seconds.
        -- Not random, either -- random flicker reads as a fault, periodic
        -- flicker reads as a process.
        if (spec.flicker or 0) > 0 then
            local base = spec.brightness
            local amount = spec.flicker
            local hz = spec.flickerHz or 10
            local elapsed = 0

            self._lightConnection = RunService.Heartbeat:Connect(function(dt)
                elapsed += dt
                local wobble =
                    math.sin(elapsed * hz) * 0.6
                    + math.sin(elapsed * hz * 0.37) * 0.4
                light.Brightness = base * (1 + wobble * amount)
            end)
        end
    end

    return self
end

-- Stops emitting but lets particles already in the air finish their lifetime,
-- then tears down. An aura that vanishes mid-particle looks like a bug even
-- when the shutdown was deliberate.
function Aura:stop(immediate: boolean?)
    if self._lightConnection then
        self._lightConnection:Disconnect()
        self._lightConnection = nil
    end

    local longest = 0
    for _, emitter in ipairs(self._emitters) do
        emitter.Enabled = false
        longest = math.max(longest, emitter.Lifetime.Max)
    end

    local function destroy()
        if self._light then
            self._light:Destroy()
            self._light = nil
        end
        if self._container then
            self._container:Destroy()
            self._container = nil
        end
        table.clear(self._emitters)
    end

    if immediate or longest <= 0 then
        destroy()
        return
    end

    -- The light fades WITH the particles rather than cutting out, which is the
    -- difference between "the aura ended" and "the aura was deleted".
    if self._light then
        local light = self._light
        local from = light.Brightness
        local started = os.clock()
        local fade
        fade = RunService.Heartbeat:Connect(function()
            local t = (os.clock() - started) / longest
            if t >= 1 or not light.Parent then
                fade:Disconnect()
                return
            end
            light.Brightness = from * (1 - t)
        end)
    end

    task.delay(longest, destroy)
end

function Aura:isPlaying(): boolean
    return #self._emitters > 0
end

return Aura
