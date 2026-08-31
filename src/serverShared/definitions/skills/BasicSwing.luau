-- src/serverShared/definitions/skills/BasicSwing.luau
--
-- ONE FILE, ONE SKILL. See `DefinitionLoader` for why skills are flat and
-- ungrouped, and why `volume` is a plain table rather than a resolved one.

return {
    id = "BASIC_SWING",
    displayName = "Swing",

    -- A SWORD IS A CAPSULE THE SIZE OF A SWORD. This was an ARC -- a 12-stud,
    -- 120-degree cone -- until 2026-08-16, and that was wrong in a way worth
    -- keeping rather than quietly deleting.
    --
    -- An ARC measures the full THREE-DIMENSIONAL angle to a target, so a
    -- 120-degree arc opens 60 degrees in every direction, up and down included.
    -- Jump clean over an enemy and you hit them anyway. Nothing about that
    -- resembles a sword. It survived only because it was the first shape
    -- written, back when the question was "does detection fire at all".
    --
    --   length 6.5   arm plus blade, pivoting at the body
    --   radius 0.5   a blade is THIN -- the number a cone has no equivalent of
    --   sweep  160   a horizontal slash, shoulder to shoulder
    --   window 0.4   fast, but slow enough to step out of
    --
    -- Those give 8 wedges automatically: 160/20 and 0.40/0.05 both land on 8.
    volume = {
        shape = "CAPSULE",
        length = 6.5,
        radius = 0.5,
        sweep = 160,
        activeWindow = 0.4,

        -- Hand height rather than through the middle of the chest. A guess
        -- standing in for a real grip point: when a rigged weapon arrives this
        -- stops being typed and gets read from the hand attachment the blade
        -- is welded to.
        offset = CFrame.new(0, -0.5, 0),

        maxTargets = 5,
    },
}
