-- src/serverShared/definitions/skills/Fissure.luau
--
-- PLANNED. NOT BUILT. Deliberately has no volume.
--
-- The first real player attack, and the target the animation work is aimed at.
-- This file exists so the name is settled and greppable -- `planned = true`
-- keeps it out of every lookup, and the loader skips validating a volume it
-- knows is absent.
--
-- ============================================================================
-- IT CANNOT BE WRITTEN YET, AND THAT IS THE POINT
-- ============================================================================
--
-- A skill's numbers are the OUTPUT of a workflow nobody has run:
--
--   1. author the animation
--   2. build the hitbox against it
--   3. run it once
--   4. read the diagnostics
--   5. capture the path and the timings
--   6. THEN write this row
--
-- Typing a volume here now would be guessing at step 6 before steps 1-5, which
-- is exactly what the capture workflow exists to stop. The numbers come from
-- watching the thing run, not from deciding in advance what they ought to be.
--
-- WHAT THIS ROW WILL EVENTUALLY HOLD, and where each field comes from:
--
--   volume    captured  -- shape, and a PATH recorded off the authored swing
--   clip      authored  -- a manifest key, once the animation is uploaded
--   score     authored  -- "FISSURE". The Score already exists
--   cooldown  designed  -- the one field that is a pure balance decision
--
-- ============================================================================
-- THE PAIRING THIS NAME ALREADY HAS
-- ============================================================================
--
--   skills/Fissure.luau    serverShared/  ->  ServerStorage    what it HITS
--   scores/Fissure.luau    shared/        ->  ReplicatedStorage  what it LOOKS like
--
-- SAME NAME, TWO TREES, AND THAT IS THE DESIGN. The skill is server-only so its
-- reach and arc are never published to a client. The Score is in
-- ReplicatedStorage so every client can play it from a name and a timestamp
-- instead of the server streaming ~120 property values per player.
--
-- `score = "FISSURE"` is the only thing that will ever connect them, and it
-- crosses as a NAME. Neither file imports the other.

return {
    id = "FISSURE",
    displayName = "Fissure",
    planned = true,
}
