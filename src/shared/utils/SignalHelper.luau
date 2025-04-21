-- src/shared/util/SignalHelper.lua
local SignalHelper = {}

function SignalHelper.ConnectToMethod(signal, object, methodName)
    signal:Connect(function(...)
        object[methodName](object, ...)
    end)
end

return SignalHelper
