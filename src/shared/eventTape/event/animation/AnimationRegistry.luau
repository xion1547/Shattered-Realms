local AnimationRegistry = {
    _animations = {
        animation1 = "rbxassetid://1234567890", -- Example animation asset ID
        animation2 = "rbxassetid://0987654321", -- Another example animation asset ID

        animation3 = workspace.Animations.Animation3, -- Example animation asset from workspace
    }
}

function AnimationRegistry.getAnimation(animationName)
    local animation = AnimationRegistry._animations[animationName]
    assert(animation, "Animation not found: " .. tostring(animationName))
    return animation
end

function AnimationRegistry.validateAnimation(animationName)
    local animation = AnimationRegistry._animations[animationName]
    if not animation then
        print("Animation not found: " .. tostring(animationName))
        return false
    end
    return true
end

return AnimationRegistry