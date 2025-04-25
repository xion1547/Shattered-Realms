-- src/server/shared/utils/signal/SignalEnum.lua
local SignalEnum = {}
SignalEnum.__index = SignalEnum

-- Static variable to hold the instance
local instance

-- Singleton pattern for SignalEnum
function SignalEnum.getInstance(registry)
    if not instance then
        instance = SignalEnum.new(registry)
        instance:initialize()  -- Ensure the enum is populated
    end
    return instance
end

-- Constructor to create a new SignalEnum object
function SignalEnum.new(registry)
    local self = setmetatable({}, SignalEnum)
    self.registry = registry
    self.enums = {}
    return self
end

-- Recursive function to generate enums based on the registry
function SignalEnum:generateEnums(registry, enumsTable)
    for category, signals in pairs(registry) do
        if type(signals) == "table" then
            enumsTable[category] = {}
            self:generateEnums(signals, enumsTable[category])
        end
    end
end

-- Populate the enum names
function SignalEnum:populateEnumNames()
    local function recursePopulate(registry, enumsTable)
        for category, signals in pairs(registry) do
            -- Ensure the category is a table
            if type(signals) == "table" then
                enumsTable[category] = enumsTable[category] or {}

                for signalName, signal in pairs(signals) do
                    -- Check if the value is a valid Signal object
                    if type(signal) == "table" and signal._isSignal then
                        -- Add the signal to the enumsTable
                        enumsTable[category][signalName] = signalName
                    elseif type(signal) == "table" then
                        -- If it's a nested table (but not a signal), recurse into it
                        recursePopulate(signal, enumsTable[category])
                    else
                        -- If it's not a signal or a table, log it
                        warn(string.format("[SignalEnum] Skipping invalid entry for '%s' in '%s' category: %s", signalName, category, tostring(signal)))
                    end
                end
            end
        end
    end
    recursePopulate(self.registry, self.enums)
end

-- Method to initialize and populate the enums
function SignalEnum:initialize()
    self:populateEnumNames()
end

-- Method to get the enums
function SignalEnum:getEnums()
    return self.enums
end

return SignalEnum
