-- src/server/shared/utils/signal/SignalHelper.lua
-- SignalHelper.lua
local SignalService = require(game:GetService("ReplicatedStorage").utils.signal.SignalService)
local signalServiceInstance = SignalService.getInstance()
local SignalHelper = {}


-- Safe Connect for signals
function SignalHelper.SafeConnect(signal, callback)
    if typeof(callback) ~= "function" then
        warn("[SignalHelper] Tried to connect a non-function callback.")
        return
    end

    local success, err = pcall(function()
        signal:Connect(callback)
    end)

    if not success then
        warn("[SignalHelper] Failed to connect callback:", err)
    end
end

-- 🌟 AutoConnect signals from registry to methods on the handler module
function SignalHelper.AutoConnect(registry, handlerModule)
    -- Traverse registry and bind signals to methods
    for key, value in pairs(registry) do
        if typeof(value) == "table" then
            -- If this value is a table and has signals, recurse into it
            if value._isSignal then
                -- Directly handle signals
                SignalHelper.AutoConnectSignal(key, value, handlerModule)
            elseif typeof(value) == "table" then
                -- Recurse into nested registries (signals could be deep inside nested tables)
                SignalHelper.AutoConnect(value, handlerModule)
            else
                -- Log if it's not a valid signal object
                warn(string.format("[SignalHelper] Unexpected structure for '%s'. Expected signal or registry.", key))
            end
        end
    end
end

-- Helper function to connect a signal to the handler
function SignalHelper.AutoConnectSignal(signalName, signal, handlerModule)
    local handler = handlerModule[signalName]  -- Get method (e.g., PlayerManager:OnLevelUp)

    if type(handler) == "function" then
        -- Bind the signal to the handler method
        SignalHelper.SafeConnect(signal, function(...)
            handler(handlerModule, ...)  -- Call the handler with the player manager object
        end)

        -- Register the signal in SignalService
        signalServiceInstance:registerSignal(signalName, signal)  -- Use key (e.g., "OnLevelUp") directly as the name
    else
        warn(string.format("[SignalHelper] No handler found for signal '%s'", signalName))
    end
end

return SignalHelper
