local TweenService = game:GetService("TweenService")

local TweenUtil = {}

function TweenUtil.tweenObject(object, targetProps, tweenInfo)
	local info = tweenInfo or TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local tween = TweenService:Create(object, info, targetProps)
	tween:Play()
	return tween
end

function TweenUtil.fadeOut(frame, duration)
	return TweenUtil.tweenObject(frame, { Transparency = 1 }, TweenInfo.new(duration or 0.5))
end

function TweenUtil.pulseScale(object, scale)
	return TweenUtil.tweenObject(object, {
		Size = UDim2.fromScale(scale, scale)
	}, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out))
end

return TweenUtil
