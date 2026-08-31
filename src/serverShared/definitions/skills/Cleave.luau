-- src/serverShared/definitions/skills/Cleave.luau
--
-- TEMPORARY, and here to be LOOKED AT rather than shipped.
--
-- It exists so BOX has a caller. BOX and CAPSULE were once stubbed out of
-- Overlap on the reasoning that nothing declared them -- true, and still the
-- wrong call: both will carry most of this game's attacks, and "no caller yet"
-- is a thing a keybind fixes in a minute.
--
-- THIS IS THE VOLUME THAT PROVES `offset` WORKS AT ALL. The field was declared,
-- validated and reach-accounted from the day HitVolume was written, and
-- silently ignored by Overlap until 2026-08-16 -- so a cleave declared four
-- studs forward resolved centred on the attacker, and every part of the system
-- except the one that decides hits agreed it should not have.

return {
    id = "CLEAVE",
    displayName = "Cleave",

    -- A wide flat box pushed four studs forward, so it reads as a horizontal
    -- bar swept left to right rather than as a fan.
    volume = {
        shape = "BOX",
        size = Vector3.new(18, 4, 5),
        offset = CFrame.new(0, 0, -4),
        maxTargets = 8,
    },
}
