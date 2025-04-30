local AnimationLibrary = require(game:WaitForChild("ReplicatedStorage"):WaitForChild("modules"):WaitForChild("AnimationLibrary"))

local PlayerAnimationController = {}
PlayerAnimationController.__index = PlayerAnimationController

function PlayerAnimationController.new(humanoid)
    local self = setmetatable({}, PlayerAnimationController)
    self.Humanoid = humanoid
    self.AnimationTracks = {}
    return self
end

function PlayerAnimationController:LoadOwnedAnimations()
    local animations = AnimationLibrary:GetOwnedAnimations()

    for _, animData in ipairs(animations) do
        local animation = Instance.new("Animation")
        animation.Name = animData.Name
        animation.AnimationId = animData.AnimationId

        local track = self.Humanoid:LoadAnimation(animation)
        self.AnimationTracks[animData.Name] = track
    end
end

-- Stop all currently playing animations
function PlayerAnimationController:StopAllAnimations()
    for _, track in pairs(self.AnimationTracks) do
        if track.IsPlaying then
            track:Stop()
        end
    end
end

function PlayerAnimationController:PlayAnimation(name)
    local track = self.AnimationTracks[name]
    if track then
        -- Stop all animations before playing the new one
        self:StopAllAnimations()
        
        -- Play the new animation
        print("Playing animation: " .. name)
        track:Play()
    else
        warn("Animation not loaded: " .. name)
    end
end


return PlayerAnimationController
