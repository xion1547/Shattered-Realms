-- src/shared/eventTape/event/animation/AnimationRegistry.luau
--
-- Declared animation ids -> asset. Content Layer data (Part 6): read at
-- runtime, never written to.
--
-- This module previously read `workspace.Animations.Animation3` at the top
-- level, which ran on require. It threw whenever that instance was absent --
-- and because this file lives in shared/, it took the client down with it.
-- A definitions table must never touch the DataModel at load time.

local AnimationRegistry = {}

local ANIMATIONS = {
    animation1 = "rbxassetid://1234567890",
    animation2 = "rbxassetid://0987654321",
}

-- `isKnown` USED TO LIVE HERE and was wired into AnimationEvent's schema as a
-- constraint. It is gone: that made EventTape ask the Content Layer whether an
-- animation exists, which is a dependency the transport layer should not have
-- and a check it could not act on -- see the boundary note in Validators.luau.
--
-- Nothing needs a separate existence test today. `get` already fails loudly on
-- an unknown id, which is the one place a miss actually matters. Add one back
-- only when a caller genuinely needs to ask without throwing.
function AnimationRegistry.get(animationId)
    local asset = ANIMATIONS[animationId]
    assert(asset, string.format(
        "[AnimationRegistry] unknown animation id: %s", tostring(animationId)))
    return asset
end

function AnimationRegistry.all()
    return table.clone(ANIMATIONS)
end

return AnimationRegistry
