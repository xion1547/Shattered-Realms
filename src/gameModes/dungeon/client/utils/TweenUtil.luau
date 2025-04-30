-- src/client/utils/TweenUtil.luau

local TweenService = game:GetService("TweenService")

local TweenUtil = {}

function TweenUtil:TweenHealthBar(frame, healthPercent)
	if not frame or not frame:IsA("Frame") then
		warn("[TweenUtil] Invalid frame provided.")
		return
	end

	local slideNoHealthBack = {
		Size = UDim2.new(healthPercent, 0, 1, 0)
	}

	local tweenInfo = TweenInfo.new(
		0.3, -- duration
		Enum.EasingStyle.Quad,
		Enum.EasingDirection.Out
	)

	local tween = TweenService:Create(frame, tweenInfo, slideNoHealthBack)
	tween:Play()
end

return TweenUtil
