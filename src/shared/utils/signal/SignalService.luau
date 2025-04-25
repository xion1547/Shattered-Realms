-- src/server/shared/utils/signal/SignalService.lua
local SignalService = {}
SignalService.__index = SignalService
local instance

function SignalService.new()
	instance = setmetatable({}, SignalService)
    instance.signals = {}  -- Table to store all signals by their names (signal objects)
	return instance
end

-- Register a signal globally by signal name
function SignalService:registerSignal(signalName, signal)
    if not self.signals[signalName] then
        self.signals[signalName] = signal
    else
        warn(string.format("[SignalService] Signal '%s' is already registered.", signalName))
    end
end

-- Get a signal object by name
function SignalService:getSignal(signalName)
    return self.signals[signalName]
end

-- Fire a signal by its name
function SignalService:fireSignal(signalName, ...)
    -- Use getSignal to safely retrieve the signal by its name
    local signal = self:getSignal(signalName)
    
    if signal then
        -- Fire the signal with provided arguments
        signal:Fire(...)
    else
        -- Warn if the signal does not exist
        warn(string.format("[SignalService] Signal '%s' does not exist!", signalName))
    end
end

-- Singleton instance for SignalService
function SignalService:getInstance()
    if not instance then
        warn("[SignalService] Instance has not been initialized yet. Creating new instance.")
        instance = SignalService.new()
    end
    return instance
end


return SignalService
