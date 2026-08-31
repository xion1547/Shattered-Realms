-- src/serverShared/definitions/skills/Thrust.luau
--
-- TEMPORARY, and the counterpart to Cleave: it exists so a long sweeping
-- CAPSULE has a caller.

return {
    id = "THRUST",
    displayName = "Thrust",

    -- A 20-stud BLADE THAT TRAVELS, not a 140-degree fan that is live all at
    -- once, and the difference is the whole reason `sweep` exists.
    --
    -- A target standing at the far end of the arc has ~0.3s to leave before the
    -- blade arrives -- and if they do, they are genuinely missed rather than
    -- caught by a fan that was never there. That is the dodge behaviour a
    -- static shape cannot express at ANY sample count, because every sample
    -- tests the same fan.
    volume = {
        shape = "CAPSULE",
        length = 20,
        radius = 1.5,
        sweep = 140,
        activeWindow = 0.35,
        maxTargets = 4,
    },
}
