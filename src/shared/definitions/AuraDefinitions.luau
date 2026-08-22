-- src/shared/definitions/AuraDefinitions.luau
--
-- AURAS AS CONTENT, not as code. Each entry is a stack of particle layers and
-- an optional light; `client/playback/Aura.luau` is the generic engine that
-- reads one and builds it. Adding an aura is an entry here and nothing else.
--
-- WHY LAYERS. A single emitter always reads as "a Roblox particle effect".
-- What sells an aura is the same trick real VFX artists use: three or four
-- passes at different scales, speeds and lifetimes, so the eye reads a
-- volume instead of a sprite. The canonical stack here is
--
--     column   the body of the aura -- slow, wide, translucent
--     core     a tight white-hot centre -- fast, small, opaque
--     flare    a burst at the feet, thrown outward
--     embers   sparse bright motes that hang and drift
--     accent   whatever makes THIS aura not the others: smoke, frost, arcs
--
-- Remove any one of those and it stops looking like energy.
--
-- TEXTURES ARE ENGINE BUILT-INS (`rbxasset://`), deliberately. They ship with
-- the client, need no upload, and belong to no account -- so nothing here
-- depends on an asset decision that has not been made yet. They are also the
-- first thing to replace when there is real art: swap the string, keep every
-- number.
--
-- THIS IS COSMETIC AND LIVES IN shared/ ON PURPOSE. The client executes it;
-- nothing here is a gameplay number and nothing here is worth hiding. See
-- Architecture-Reference Part 13's three-tree test.

local T = {
    FIRE = "rbxasset://textures/particles/fire_main.dds",
    SMOKE = "rbxasset://textures/particles/smoke_main.dds",
    SPARK = "rbxasset://textures/particles/sparkles_main.dds",
}

-- Shorthands. These read badly inline and the definitions are long enough.
local function seq(...): NumberSequence
    local points = {}
    for _, pair in ipairs({ ... }) do
        table.insert(points, NumberSequenceKeypoint.new(pair[1], pair[2]))
    end
    return NumberSequence.new(points)
end

local function grad(...): ColorSequence
    local points = {}
    for _, pair in ipairs({ ... }) do
        table.insert(points, ColorSequenceKeypoint.new(pair[1], pair[2]))
    end
    return ColorSequence.new(points)
end

local function rgb(r: number, g: number, b: number): Color3
    return Color3.fromRGB(r, g, b)
end

local AuraDefinitions = {}

-- ============================================================ SUPER SAIYAN
--
-- The reference implementation, and the one every other entry is a variation
-- on. Gold, violently upward, white-hot at the centre.
--
-- The two details that make it read as Super Saiyan rather than as fire:
--
--   SQUASH. Particles are stretched along their direction of travel, hard, and
--   MORE as they age. That vertical smear is the difference between a flame
--   and a column of energy -- fire billows outward, this is drawn upward.
--
--   DRAG PLUS ACCELERATION. Particles are thrown up fast and then slowed, so
--   they bunch and flicker near the top of the column instead of streaming off
--   forever. That bunching is what makes the aura look like it has a ceiling.
AuraDefinitions.SUPER_SAIYAN = {
    displayName = "Super Saiyan",

    light = {
        color = rgb(255, 210, 90),
        brightness = 3.5,
        range = 26,
        flicker = 0.18,     -- how much the brightness wobbles, 0 for steady
        flickerHz = 14,
    },

    layers = {
        {
            name = "column",
            texture = T.FIRE,
            attachTo = "ROOT",
            offset = Vector3.new(0, -2.4, 0),

            shape = "Cylinder",
            shapeStyle = "Volume",
            shapeInOut = "Outward",
            emissionDirection = "Top",
            shapeSize = Vector3.new(2.6, 0.6, 2.6),

            rate = 95,
            lifetime = NumberRange.new(0.55, 0.95),
            speed = NumberRange.new(13, 21),
            spreadAngle = Vector2.new(9, 9),
            acceleration = Vector3.new(0, 26, 0),
            drag = 3.4,

            size = seq({ 0, 0.6 }, { 0.18, 3.9 }, { 0.7, 3.1 }, { 1, 0.9 }),
            squash = seq({ 0, 1.6 }, { 1, 4.2 }),
            transparency = seq({ 0, 1 }, { 0.12, 0.32 }, { 0.62, 0.5 }, { 1, 1 }),
            color = grad(
                { 0, rgb(255, 255, 236) },
                { 0.22, rgb(255, 232, 128) },
                { 0.6, rgb(255, 190, 40) },
                { 1, rgb(226, 140, 20) }
            ),

            lightEmission = 1,
            lightInfluence = 0,
            brightness = 2.2,
            orientation = "VelocityParallel",
            rotSpeed = NumberRange.new(-25, 25),
            zOffset = -0.4,
        },

        {
            name = "core",
            texture = T.FIRE,
            attachTo = "ROOT",
            offset = Vector3.new(0, -2.2, 0),

            shape = "Cylinder",
            shapeStyle = "Volume",
            shapeInOut = "Outward",
            emissionDirection = "Top",
            shapeSize = Vector3.new(1.15, 0.4, 1.15),

            rate = 65,
            lifetime = NumberRange.new(0.34, 0.55),
            speed = NumberRange.new(20, 30),
            spreadAngle = Vector2.new(4, 4),
            acceleration = Vector3.new(0, 34, 0),
            drag = 2.2,

            size = seq({ 0, 0.4 }, { 0.2, 2.2 }, { 1, 0.5 }),
            squash = seq({ 0, 2.2 }, { 1, 5.5 }),
            transparency = seq({ 0, 1 }, { 0.1, 0.05 }, { 0.7, 0.3 }, { 1, 1 }),
            color = grad(
                { 0, rgb(255, 255, 255) },
                { 0.5, rgb(255, 250, 205) },
                { 1, rgb(255, 214, 96) }
            ),

            lightEmission = 1,
            lightInfluence = 0,
            brightness = 3.4,
            orientation = "VelocityParallel",
            zOffset = 0.3,
        },

        {
            name = "flare",
            texture = T.FIRE,
            attachTo = "ROOT",
            offset = Vector3.new(0, -2.9, 0),

            shape = "Sphere",
            shapeStyle = "Surface",
            shapeInOut = "Outward",
            emissionDirection = "Top",
            shapeSize = Vector3.new(1.6, 0.3, 1.6),

            rate = 46,
            lifetime = NumberRange.new(0.28, 0.5),
            speed = NumberRange.new(11, 17),
            spreadAngle = Vector2.new(62, 62),
            acceleration = Vector3.new(0, 14, 0),
            drag = 6,

            size = seq({ 0, 1.4 }, { 0.4, 3.2 }, { 1, 0.2 }),
            squash = seq({ 0, 0.8 }, { 1, 2.2 }),
            transparency = seq({ 0, 0.5 }, { 0.5, 0.62 }, { 1, 1 }),
            color = grad(
                { 0, rgb(255, 246, 190) },
                { 1, rgb(240, 160, 30) }
            ),

            lightEmission = 1,
            lightInfluence = 0,
            brightness = 1.6,
            orientation = "VelocityParallel",
        },

        {
            name = "embers",
            texture = T.SPARK,
            attachTo = "ROOT",
            offset = Vector3.new(0, -2.2, 0),

            shape = "Cylinder",
            shapeStyle = "Volume",
            shapeInOut = "Outward",
            emissionDirection = "Top",
            shapeSize = Vector3.new(3.4, 1.4, 3.4),

            -- SPARSE AND LONG-LIVED, which is the opposite of every other
            -- layer. Embers are the only thing on screen the eye can actually
            -- track, and tracking one is what makes the whole column feel like
            -- it is moving rather than shimmering.
            rate = 26,
            lifetime = NumberRange.new(1.1, 2.0),
            speed = NumberRange.new(9, 17),
            spreadAngle = Vector2.new(26, 26),
            acceleration = Vector3.new(0, 9, 0),
            drag = 1.5,

            size = seq({ 0, 0.42 }, { 0.3, 0.3 }, { 1, 0 }),
            transparency = seq({ 0, 0.1 }, { 0.75, 0.2 }, { 1, 1 }),
            color = grad(
                { 0, rgb(255, 255, 232) },
                { 0.5, rgb(255, 226, 120) },
                { 1, rgb(255, 168, 40) }
            ),

            lightEmission = 1,
            lightInfluence = 0,
            brightness = 4,
            orientation = "FacingCameraWorldUp",
            rotSpeed = NumberRange.new(-180, 180),
        },

        {
            name = "crackle",
            texture = T.SPARK,
            attachTo = "ROOT",
            offset = Vector3.new(0, -0.5, 0),

            shape = "Sphere",
            shapeStyle = "Surface",
            shapeInOut = "Outward",
            emissionDirection = "Top",
            shapeSize = Vector3.new(3.2, 4.6, 3.2),

            -- VERY SHORT LIFETIME, VERY HIGH SPEED, HEAVY SQUASH. A particle
            -- that exists for 80ms and is stretched six times its width reads
            -- as an arc rather than a dot -- which is how you get lightning
            -- out of a particle system that has no line primitive.
            rate = 14,
            lifetime = NumberRange.new(0.06, 0.13),
            speed = NumberRange.new(26, 46),
            spreadAngle = Vector2.new(180, 180),
            drag = 0,

            size = seq({ 0, 0.85 }, { 1, 0.25 }),
            squash = seq({ 0, 5 }, { 1, 8 }),
            transparency = seq({ 0, 0.15 }, { 0.6, 0.35 }, { 1, 1 }),
            color = grad(
                { 0, rgb(255, 255, 255) },
                { 1, rgb(255, 236, 150) }
            ),

            lightEmission = 1,
            lightInfluence = 0,
            brightness = 5,
            orientation = "VelocityParallel",
        },
    },
}

-- ======================================================= SUPER SAIYAN BLUE
--
-- The same skeleton, retuned into something calmer and colder. Worth reading
-- as a diff against the gold: the shape numbers barely move, and the whole
-- change in character comes from SLOWER SPEED, LONGER LIFETIME and MORE DRAG.
-- Restraint reads as control, and control reads as a higher power level.
AuraDefinitions.SUPER_SAIYAN_BLUE = {
    displayName = "Super Saiyan Blue",

    light = { color = rgb(90, 200, 255), brightness = 3.2, range = 28, flicker = 0.08, flickerHz = 6 },

    layers = {
        {
            name = "column",
            texture = T.FIRE,
            attachTo = "ROOT", offset = Vector3.new(0, -2.4, 0),
            shape = "Cylinder", shapeStyle = "Volume", shapeInOut = "Outward",
            emissionDirection = "Top", shapeSize = Vector3.new(2.4, 0.6, 2.4),

            rate = 80,
            lifetime = NumberRange.new(0.8, 1.4),
            speed = NumberRange.new(9, 14),
            spreadAngle = Vector2.new(7, 7),
            acceleration = Vector3.new(0, 16, 0),
            drag = 4.5,

            size = seq({ 0, 0.5 }, { 0.22, 3.6 }, { 0.72, 3.0 }, { 1, 0.7 }),
            squash = seq({ 0, 1.8 }, { 1, 5 }),
            transparency = seq({ 0, 1 }, { 0.14, 0.38 }, { 0.65, 0.55 }, { 1, 1 }),
            color = grad(
                { 0, rgb(240, 253, 255) },
                { 0.28, rgb(150, 230, 255) },
                { 0.68, rgb(60, 165, 255) },
                { 1, rgb(30, 100, 230) }
            ),
            lightEmission = 1, lightInfluence = 0, brightness = 2.4,
            orientation = "VelocityParallel", zOffset = -0.4,
        },
        {
            name = "core",
            texture = T.FIRE,
            attachTo = "ROOT", offset = Vector3.new(0, -2.2, 0),
            shape = "Cylinder", shapeStyle = "Volume", shapeInOut = "Outward",
            emissionDirection = "Top", shapeSize = Vector3.new(1, 0.4, 1),

            rate = 55,
            lifetime = NumberRange.new(0.45, 0.7),
            speed = NumberRange.new(15, 23),
            spreadAngle = Vector2.new(3, 3),
            acceleration = Vector3.new(0, 22, 0),
            drag = 3,

            size = seq({ 0, 0.35 }, { 0.2, 2 }, { 1, 0.4 }),
            squash = seq({ 0, 2.4 }, { 1, 6 }),
            transparency = seq({ 0, 1 }, { 0.1, 0.06 }, { 0.7, 0.3 }, { 1, 1 }),
            color = grad({ 0, rgb(255, 255, 255) }, { 1, rgb(160, 235, 255) }),
            lightEmission = 1, lightInfluence = 0, brightness = 3.6,
            orientation = "VelocityParallel", zOffset = 0.3,
        },
        {
            name = "embers",
            texture = T.SPARK,
            attachTo = "ROOT", offset = Vector3.new(0, -2, 0),
            shape = "Cylinder", shapeStyle = "Volume", shapeInOut = "Outward",
            emissionDirection = "Top", shapeSize = Vector3.new(3.6, 2, 3.6),

            rate = 22,
            lifetime = NumberRange.new(1.6, 2.8),
            speed = NumberRange.new(5, 11),
            spreadAngle = Vector2.new(20, 20),
            acceleration = Vector3.new(0, 5, 0),
            drag = 1.1,

            size = seq({ 0, 0.36 }, { 0.35, 0.26 }, { 1, 0 }),
            transparency = seq({ 0, 0.12 }, { 0.8, 0.24 }, { 1, 1 }),
            color = grad({ 0, rgb(255, 255, 255) }, { 1, rgb(120, 210, 255) }),
            lightEmission = 1, lightInfluence = 0, brightness = 4.5,
            orientation = "FacingCameraWorldUp",
            rotSpeed = NumberRange.new(-120, 120),
        },
        {
            name = "ripple",
            texture = T.SMOKE,
            attachTo = "ROOT", offset = Vector3.new(0, -2.9, 0),
            shape = "Sphere", shapeStyle = "Surface", shapeInOut = "Outward",
            emissionDirection = "Top", shapeSize = Vector3.new(2, 0.2, 2),

            -- A slow pale disc pushed outward along the ground. Reads as
            -- displaced air rather than as fire, which is the whole point of
            -- the blue: it does not burn, it pressurises.
            rate = 9,
            lifetime = NumberRange.new(0.9, 1.3),
            speed = NumberRange.new(6, 9),
            spreadAngle = Vector2.new(88, 88),
            acceleration = Vector3.new(0, 2, 0),
            drag = 5,

            size = seq({ 0, 1 }, { 0.5, 5.5 }, { 1, 7.5 }),
            transparency = seq({ 0, 0.82 }, { 0.4, 0.88 }, { 1, 1 }),
            color = grad({ 0, rgb(210, 245, 255) }, { 1, rgb(90, 180, 255) }),
            lightEmission = 0.85, lightInfluence = 0, brightness = 1,
            orientation = "FacingCameraWorldUp",
            rotSpeed = NumberRange.new(-14, 14),
        },
    },
}

-- ==================================================================== ROSE
--
-- Magenta, and deliberately UGLIER than the other two -- ragged edges, higher
-- spread, faster flicker. A villain's aura should look unstable.
AuraDefinitions.SUPER_SAIYAN_ROSE = {
    displayName = "Rosé",

    light = { color = rgb(255, 110, 190), brightness = 3.2, range = 24, flicker = 0.3, flickerHz = 22 },

    layers = {
        {
            name = "column",
            texture = T.FIRE,
            attachTo = "ROOT", offset = Vector3.new(0, -2.4, 0),
            shape = "Cylinder", shapeStyle = "Volume", shapeInOut = "Outward",
            emissionDirection = "Top", shapeSize = Vector3.new(2.5, 0.6, 2.5),

            rate = 100,
            lifetime = NumberRange.new(0.45, 0.9),
            speed = NumberRange.new(15, 26),
            spreadAngle = Vector2.new(17, 17),      -- ragged, not clean
            acceleration = Vector3.new(0, 28, 0),
            drag = 3,

            size = seq({ 0, 0.5 }, { 0.16, 4.2 }, { 0.7, 3 }, { 1, 0.8 }),
            squash = seq({ 0, 1.4 }, { 1, 4.6 }),
            transparency = seq({ 0, 1 }, { 0.12, 0.3 }, { 0.6, 0.5 }, { 1, 1 }),
            color = grad(
                { 0, rgb(255, 245, 250) },
                { 0.25, rgb(255, 170, 215) },
                { 0.65, rgb(240, 70, 150) },
                { 1, rgb(150, 20, 90) }
            ),
            lightEmission = 1, lightInfluence = 0, brightness = 2.2,
            orientation = "VelocityParallel", zOffset = -0.4,
            rotSpeed = NumberRange.new(-60, 60),
        },
        {
            name = "core",
            texture = T.FIRE,
            attachTo = "ROOT", offset = Vector3.new(0, -2.2, 0),
            shape = "Cylinder", shapeStyle = "Volume", shapeInOut = "Outward",
            emissionDirection = "Top", shapeSize = Vector3.new(1.1, 0.4, 1.1),

            rate = 60,
            lifetime = NumberRange.new(0.3, 0.5),
            speed = NumberRange.new(22, 34),
            spreadAngle = Vector2.new(6, 6),
            acceleration = Vector3.new(0, 36, 0),
            drag = 2,

            size = seq({ 0, 0.4 }, { 0.2, 2.1 }, { 1, 0.4 }),
            squash = seq({ 0, 2.6 }, { 1, 6 }),
            transparency = seq({ 0, 1 }, { 0.1, 0.08 }, { 0.7, 0.32 }, { 1, 1 }),
            color = grad({ 0, rgb(255, 255, 255) }, { 1, rgb(255, 150, 205) }),
            lightEmission = 1, lightInfluence = 0, brightness = 3.6,
            orientation = "VelocityParallel", zOffset = 0.3,
        },
        {
            name = "shards",
            texture = T.SPARK,
            attachTo = "ROOT", offset = Vector3.new(0, -1.4, 0),
            shape = "Sphere", shapeStyle = "Volume", shapeInOut = "Outward",
            emissionDirection = "Top", shapeSize = Vector3.new(3.4, 4, 3.4),

            rate = 30,
            lifetime = NumberRange.new(0.35, 0.7),
            speed = NumberRange.new(16, 30),
            spreadAngle = Vector2.new(180, 180),
            drag = 3,

            size = seq({ 0, 0.7 }, { 1, 0.1 }),
            squash = seq({ 0, 3.5 }, { 1, 6 }),
            transparency = seq({ 0, 0.2 }, { 0.7, 0.4 }, { 1, 1 }),
            color = grad({ 0, rgb(255, 255, 255) }, { 1, rgb(255, 90, 170) }),
            lightEmission = 1, lightInfluence = 0, brightness = 5,
            orientation = "VelocityParallel",
        },
    },
}

-- ================================================================= INFERNO
--
-- Actual fire, and the point of including it is the contrast: fire BILLOWS.
-- Low squash, wide spread, heavy drag, and a smoke layer that outlives the
-- flame -- everything the Saiyan auras deliberately are not.
AuraDefinitions.INFERNO = {
    displayName = "Inferno",

    light = { color = rgb(255, 130, 40), brightness = 3, range = 22, flicker = 0.35, flickerHz = 9 },

    layers = {
        {
            name = "smoke",
            texture = T.SMOKE,
            attachTo = "ROOT", offset = Vector3.new(0, -1.2, 0),
            shape = "Cylinder", shapeStyle = "Volume", shapeInOut = "Outward",
            emissionDirection = "Top", shapeSize = Vector3.new(2.4, 1, 2.4),

            -- FIRST IN THE LIST AND FURTHEST BACK. Smoke has to sit behind the
            -- flame or the whole thing turns grey.
            rate = 22,
            lifetime = NumberRange.new(1.4, 2.4),
            speed = NumberRange.new(6, 11),
            spreadAngle = Vector2.new(24, 24),
            acceleration = Vector3.new(0, 7, 0),
            drag = 1.6,

            size = seq({ 0, 1.5 }, { 0.5, 5 }, { 1, 8 }),
            transparency = seq({ 0, 1 }, { 0.2, 0.62 }, { 0.7, 0.78 }, { 1, 1 }),
            color = grad({ 0, rgb(70, 50, 45) }, { 1, rgb(24, 20, 20) }),
            lightEmission = 0, lightInfluence = 0.4, brightness = 0,
            orientation = "FacingCameraWorldUp",
            rotSpeed = NumberRange.new(-30, 30),
            zOffset = -2,
        },
        {
            name = "flame",
            texture = T.FIRE,
            attachTo = "ROOT", offset = Vector3.new(0, -2.6, 0),
            shape = "Cylinder", shapeStyle = "Volume", shapeInOut = "Outward",
            emissionDirection = "Top", shapeSize = Vector3.new(2.2, 0.5, 2.2),

            rate = 110,
            lifetime = NumberRange.new(0.5, 0.9),
            speed = NumberRange.new(8, 15),
            spreadAngle = Vector2.new(22, 22),
            acceleration = Vector3.new(0, 15, 0),
            drag = 4.2,

            size = seq({ 0, 0.8 }, { 0.25, 3.4 }, { 0.7, 2.6 }, { 1, 0.6 }),
            squash = seq({ 0, 1 }, { 1, 2 }),          -- billows, not smears
            transparency = seq({ 0, 1 }, { 0.12, 0.25 }, { 0.6, 0.5 }, { 1, 1 }),
            color = grad(
                { 0, rgb(255, 244, 200) },
                { 0.2, rgb(255, 190, 60) },
                { 0.6, rgb(240, 90, 20) },
                { 1, rgb(120, 22, 10) }
            ),
            lightEmission = 1, lightInfluence = 0, brightness = 2.4,
            orientation = "VelocityParallel",
            rotSpeed = NumberRange.new(-45, 45),
        },
        {
            name = "embers",
            texture = T.SPARK,
            attachTo = "ROOT", offset = Vector3.new(0, -2.2, 0),
            shape = "Cylinder", shapeStyle = "Volume", shapeInOut = "Outward",
            emissionDirection = "Top", shapeSize = Vector3.new(3, 1.2, 3),

            rate = 34,
            lifetime = NumberRange.new(1.4, 2.6),
            speed = NumberRange.new(7, 16),
            spreadAngle = Vector2.new(34, 34),
            acceleration = Vector3.new(0, 6, 0),
            drag = 1.2,

            size = seq({ 0, 0.34 }, { 0.4, 0.22 }, { 1, 0 }),
            transparency = seq({ 0, 0.1 }, { 0.7, 0.3 }, { 1, 1 }),
            color = grad({ 0, rgb(255, 236, 170) }, { 0.6, rgb(255, 140, 40) }, { 1, rgb(180, 40, 10) }),
            lightEmission = 1, lightInfluence = 0, brightness = 4,
            orientation = "FacingCameraWorldUp",
            rotSpeed = NumberRange.new(-200, 200),
        },
    },
}

-- =============================================================== FROSTBITE
--
-- The one that inverts the whole model: gravity is NEGATIVE-ish, mist falls
-- and pools rather than rising, and the motes drift down. An aura does not
-- have to go up -- most of them do only because fire does.
AuraDefinitions.FROSTBITE = {
    displayName = "Frostbite",

    light = { color = rgb(160, 225, 255), brightness = 2.2, range = 20, flicker = 0.05, flickerHz = 3 },

    layers = {
        {
            name = "mist",
            texture = T.SMOKE,
            attachTo = "ROOT", offset = Vector3.new(0, 1.2, 0),
            shape = "Cylinder", shapeStyle = "Volume", shapeInOut = "Outward",
            emissionDirection = "Bottom",
            shapeSize = Vector3.new(3, 2.4, 3),

            rate = 30,
            lifetime = NumberRange.new(1.6, 2.6),
            speed = NumberRange.new(2, 5),
            spreadAngle = Vector2.new(30, 30),
            acceleration = Vector3.new(0, -6, 0),    -- FALLS
            drag = 2.4,

            size = seq({ 0, 1.2 }, { 0.5, 4.4 }, { 1, 6 }),
            transparency = seq({ 0, 1 }, { 0.25, 0.72 }, { 0.75, 0.8 }, { 1, 1 }),
            color = grad({ 0, rgb(235, 250, 255) }, { 1, rgb(150, 205, 240) }),
            lightEmission = 0.6, lightInfluence = 0, brightness = 0.8,
            orientation = "FacingCameraWorldUp",
            rotSpeed = NumberRange.new(-10, 10),
            zOffset = -1,
        },
        {
            name = "crystals",
            texture = T.SPARK,
            attachTo = "ROOT", offset = Vector3.new(0, 0.4, 0),
            shape = "Sphere", shapeStyle = "Volume", shapeInOut = "Outward",
            emissionDirection = "Top", shapeSize = Vector3.new(3.8, 5, 3.8),

            -- Slow, sparse, hard-edged and nearly still. Frost is the absence
            -- of motion, so the trick is a lifetime long enough that a mote
            -- barely appears to move at all.
            rate = 20,
            lifetime = NumberRange.new(2.4, 4),
            speed = NumberRange.new(0.4, 1.6),
            spreadAngle = Vector2.new(180, 180),
            acceleration = Vector3.new(0, -1.2, 0),
            drag = 0.6,

            size = seq({ 0, 0 }, { 0.2, 0.42 }, { 0.8, 0.34 }, { 1, 0 }),
            transparency = seq({ 0, 1 }, { 0.2, 0.06 }, { 0.8, 0.2 }, { 1, 1 }),
            color = grad({ 0, rgb(255, 255, 255) }, { 1, rgb(175, 230, 255) }),
            lightEmission = 1, lightInfluence = 0, brightness = 3.5,
            orientation = "FacingCameraWorldUp",
            rotSpeed = NumberRange.new(-40, 40),
        },
        {
            name = "chill",
            texture = T.FIRE,
            attachTo = "ROOT", offset = Vector3.new(0, -2.6, 0),
            shape = "Cylinder", shapeStyle = "Volume", shapeInOut = "Outward",
            emissionDirection = "Top", shapeSize = Vector3.new(1.8, 0.4, 1.8),

            rate = 32,
            lifetime = NumberRange.new(0.8, 1.4),
            speed = NumberRange.new(3, 6),
            spreadAngle = Vector2.new(12, 12),
            acceleration = Vector3.new(0, 4, 0),
            drag = 3,

            size = seq({ 0, 0.5 }, { 0.3, 2.4 }, { 1, 0.6 }),
            squash = seq({ 0, 2 }, { 1, 4 }),
            transparency = seq({ 0, 1 }, { 0.2, 0.6 }, { 0.7, 0.72 }, { 1, 1 }),
            color = grad({ 0, rgb(255, 255, 255) }, { 1, rgb(120, 195, 255) }),
            lightEmission = 1, lightInfluence = 0, brightness = 1.6,
            orientation = "VelocityParallel",
        },
    },
}

-- ==================================================================== VOID
--
-- Particles are emitted at the SURFACE of a large sphere and travel INWARD.
-- Nothing else in this file does that, and it is unreasonably effective --
-- energy being pulled into a body reads as menace in a way that energy
-- leaving one never does.
AuraDefinitions.VOID = {
    displayName = "Void",

    light = { color = rgb(150, 60, 255), brightness = 2, range = 18, flicker = 0.22, flickerHz = 5 },

    layers = {
        {
            name = "collapse",
            texture = T.FIRE,
            attachTo = "ROOT", offset = Vector3.new(0, 0, 0),
            shape = "Sphere", shapeStyle = "Surface",
            shapeInOut = "Inward",                       -- THE WHOLE TRICK
            emissionDirection = "Top",
            shapeSize = Vector3.new(7, 8, 7),

            rate = 70,
            lifetime = NumberRange.new(0.5, 0.9),
            speed = NumberRange.new(9, 15),
            spreadAngle = Vector2.new(6, 6),
            drag = -1.2,                                 -- ACCELERATES inward
            acceleration = Vector3.new(0, 0, 0),

            size = seq({ 0, 2.4 }, { 0.7, 1 }, { 1, 0 }),
            squash = seq({ 0, 2.5 }, { 1, 5 }),
            transparency = seq({ 0, 1 }, { 0.2, 0.35 }, { 0.8, 0.4 }, { 1, 1 }),
            color = grad(
                { 0, rgb(190, 130, 255) },
                { 0.5, rgb(110, 40, 220) },
                { 1, rgb(20, 0, 40) }
            ),
            lightEmission = 0.9, lightInfluence = 0, brightness = 2,
            orientation = "VelocityParallel",
        },
        {
            name = "shroud",
            texture = T.SMOKE,
            attachTo = "ROOT", offset = Vector3.new(0, -1.6, 0),
            shape = "Cylinder", shapeStyle = "Volume", shapeInOut = "Outward",
            emissionDirection = "Top", shapeSize = Vector3.new(2.6, 1, 2.6),

            rate = 26,
            lifetime = NumberRange.new(1.2, 2),
            speed = NumberRange.new(2, 5),
            spreadAngle = Vector2.new(18, 18),
            acceleration = Vector3.new(0, 5, 0),
            drag = 2.5,

            size = seq({ 0, 1.6 }, { 0.5, 4.6 }, { 1, 5.5 }),
            transparency = seq({ 0, 1 }, { 0.2, 0.55 }, { 0.75, 0.7 }, { 1, 1 }),
            color = grad({ 0, rgb(60, 20, 100) }, { 1, rgb(8, 0, 16) }),
            lightEmission = 0.25, lightInfluence = 0, brightness = 0,
            orientation = "FacingCameraWorldUp",
            rotSpeed = NumberRange.new(-24, 24),
            zOffset = -2,
        },
        {
            name = "motes",
            texture = T.SPARK,
            attachTo = "ROOT", offset = Vector3.new(0, 0, 0),
            shape = "Sphere", shapeStyle = "Surface", shapeInOut = "Inward",
            emissionDirection = "Top", shapeSize = Vector3.new(9, 9, 9),

            rate = 18,
            lifetime = NumberRange.new(0.9, 1.5),
            speed = NumberRange.new(6, 10),
            spreadAngle = Vector2.new(0, 0),
            drag = -0.8,

            size = seq({ 0, 0.5 }, { 1, 0 }),
            transparency = seq({ 0, 0.15 }, { 0.8, 0.3 }, { 1, 1 }),
            color = grad({ 0, rgb(220, 180, 255) }, { 1, rgb(120, 50, 230) }),
            lightEmission = 1, lightInfluence = 0, brightness = 4,
            orientation = "VelocityParallel",
        },
    },
}

-- ================================================================= TEMPEST
--
-- Almost no body, almost all crackle. Proof that an aura can be built out of
-- one idea if the idea is strong enough -- here, particles that live for a
-- twelfth of a second and are stretched eight times their width.
AuraDefinitions.TEMPEST = {
    displayName = "Tempest",

    light = { color = rgb(140, 200, 255), brightness = 4, range = 24, flicker = 0.55, flickerHz = 30 },

    layers = {
        {
            name = "arcs",
            texture = T.SPARK,
            attachTo = "ROOT", offset = Vector3.new(0, -0.4, 0),
            shape = "Sphere", shapeStyle = "Volume", shapeInOut = "Outward",
            emissionDirection = "Top", shapeSize = Vector3.new(3.4, 5.4, 3.4),

            rate = 55,
            lifetime = NumberRange.new(0.05, 0.12),
            speed = NumberRange.new(30, 60),
            spreadAngle = Vector2.new(180, 180),
            drag = 0,

            size = seq({ 0, 1 }, { 1, 0.3 }),
            squash = seq({ 0, 6 }, { 1, 9 }),
            transparency = seq({ 0, 0.1 }, { 0.7, 0.3 }, { 1, 1 }),
            color = grad({ 0, rgb(255, 255, 255) }, { 1, rgb(130, 195, 255) }),
            lightEmission = 1, lightInfluence = 0, brightness = 6,
            orientation = "VelocityParallel",
        },
        {
            name = "charge",
            texture = T.FIRE,
            attachTo = "ROOT", offset = Vector3.new(0, -2.4, 0),
            shape = "Cylinder", shapeStyle = "Volume", shapeInOut = "Outward",
            emissionDirection = "Top", shapeSize = Vector3.new(2, 0.5, 2),

            rate = 42,
            lifetime = NumberRange.new(0.3, 0.6),
            speed = NumberRange.new(16, 26),
            spreadAngle = Vector2.new(10, 10),
            acceleration = Vector3.new(0, 24, 0),
            drag = 3.5,

            size = seq({ 0, 0.4 }, { 0.25, 2.6 }, { 1, 0.4 }),
            squash = seq({ 0, 3 }, { 1, 6 }),
            transparency = seq({ 0, 1 }, { 0.15, 0.5 }, { 0.7, 0.62 }, { 1, 1 }),
            color = grad({ 0, rgb(240, 250, 255) }, { 1, rgb(70, 150, 255) }),
            lightEmission = 1, lightInfluence = 0, brightness = 2.5,
            orientation = "VelocityParallel",
        },
        {
            name = "ground",
            texture = T.SPARK,
            attachTo = "ROOT", offset = Vector3.new(0, -3, 0),
            shape = "Sphere", shapeStyle = "Surface", shapeInOut = "Outward",
            emissionDirection = "Top", shapeSize = Vector3.new(4.5, 0.2, 4.5),

            rate = 26,
            lifetime = NumberRange.new(0.12, 0.28),
            speed = NumberRange.new(14, 26),
            spreadAngle = Vector2.new(80, 80),
            drag = 2,

            size = seq({ 0, 0.8 }, { 1, 0.15 }),
            squash = seq({ 0, 4 }, { 1, 7 }),
            transparency = seq({ 0, 0.12 }, { 1, 1 }),
            color = grad({ 0, rgb(255, 255, 255) }, { 1, rgb(110, 180, 255) }),
            lightEmission = 1, lightInfluence = 0, brightness = 5,
            orientation = "VelocityParallel",
        },
    },
}

-- ================================================================= VERDANT
--
-- The quiet one. Slow, sparse, mostly transparent, and it uses NEGATIVE drag
-- nowhere and heavy drag everywhere -- motes that rise and then simply hang.
-- Included because a healing effect that screams is a healing effect nobody
-- can stand next to.
AuraDefinitions.VERDANT = {
    displayName = "Verdant",

    light = { color = rgb(140, 255, 160), brightness = 1.6, range = 18, flicker = 0.06, flickerHz = 2 },

    layers = {
        {
            name = "motes",
            texture = T.SPARK,
            attachTo = "ROOT", offset = Vector3.new(0, -2, 0),
            shape = "Cylinder", shapeStyle = "Volume", shapeInOut = "Outward",
            emissionDirection = "Top", shapeSize = Vector3.new(3.2, 1, 3.2),

            rate = 24,
            lifetime = NumberRange.new(2.2, 3.6),
            speed = NumberRange.new(3, 7),
            spreadAngle = Vector2.new(22, 22),
            acceleration = Vector3.new(0, 2.4, 0),
            drag = 2.2,

            size = seq({ 0, 0 }, { 0.15, 0.4 }, { 0.8, 0.3 }, { 1, 0 }),
            transparency = seq({ 0, 1 }, { 0.15, 0.12 }, { 0.85, 0.28 }, { 1, 1 }),
            color = grad({ 0, rgb(240, 255, 225) }, { 0.5, rgb(150, 255, 150) }, { 1, rgb(60, 190, 90) }),
            lightEmission = 1, lightInfluence = 0, brightness = 3,
            orientation = "FacingCameraWorldUp",
            rotSpeed = NumberRange.new(-60, 60),
        },
        {
            name = "bloom",
            texture = T.FIRE,
            attachTo = "ROOT", offset = Vector3.new(0, -2.7, 0),
            shape = "Cylinder", shapeStyle = "Volume", shapeInOut = "Outward",
            emissionDirection = "Top", shapeSize = Vector3.new(1.8, 0.4, 1.8),

            rate = 26,
            lifetime = NumberRange.new(1, 1.6),
            speed = NumberRange.new(3, 6),
            spreadAngle = Vector2.new(14, 14),
            acceleration = Vector3.new(0, 5, 0),
            drag = 4,

            size = seq({ 0, 0.5 }, { 0.35, 2.6 }, { 1, 0.5 }),
            squash = seq({ 0, 1.6 }, { 1, 3.4 }),
            transparency = seq({ 0, 1 }, { 0.2, 0.68 }, { 0.75, 0.78 }, { 1, 1 }),
            color = grad({ 0, rgb(235, 255, 225) }, { 1, rgb(90, 220, 120) }),
            lightEmission = 1, lightInfluence = 0, brightness = 1.4,
            orientation = "VelocityParallel",
        },
    },
}

-- The order the demo cycles through. Kept explicit rather than iterating the
-- table, because `pairs` order is arbitrary and "press the key twice, get the
-- same aura" is a bad first impression of a system that works.
AuraDefinitions.ORDER = {
    "SUPER_SAIYAN",
    "SUPER_SAIYAN_BLUE",
    "SUPER_SAIYAN_ROSE",
    "INFERNO",
    "FROSTBITE",
    "VOID",
    "TEMPEST",
    "VERDANT",
}

return AuraDefinitions
