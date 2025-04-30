-- ReplicatedStorage/Modules/AnimationLibrary.lua

local AnimationLibrary = {}

AnimationLibrary.Animations = {
    {
        Name = "Idle",
        AnimationId = "rbxassetid://180426354"  -- Correct default Idle animation
    },
    {
        Name = "Walk",
        AnimationId = "rbxassetid://656121766"  -- Correct default Walk animation
    },
    {
        Name = "Run",
        AnimationId = "rbxassetid://656118852"  -- Correct default Run animation
    },
    {
        Name = "Jump",
        AnimationId = "rbxassetid://656117878"  -- Correct default Jump animation
    },
    {
        Name = "Swim",
        AnimationId = "rbxassetid://656119721"  -- Correct wave animation for testing
    },
    {
        Name = "NinjaFall",  -- Custom name for the animation
        AnimationId = "rbxassetid://656117878",  -- Roblox's default walk animation (works for both R6 and R15)
    },
    
}

function AnimationLibrary:GetOwnedAnimations()
    -- Replace this with actual filtering if needed
    return self.Animations
end

return AnimationLibrary
