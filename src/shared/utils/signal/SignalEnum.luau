-- src/shared/utils/signal/SignalEnum.lua
local SignalEnum = {}
SignalEnum.__index = SignalEnum

-- Static variable to hold the instance
local instance

-- Simplified signal detection without noisy warnings
local function isSignal(obj)
    return type(obj) == "table" and obj._isSignal == true
end

-- Strict singleton pattern (must be initialized first)
function SignalEnum.getInstance()
    if not instance then
        warn("[SignalEnum] FATAL: getInstance() called before initialization. Call SignalEnum.new() first.")
        error("SignalEnum not initialized", 2)
    end
    return instance
end

-- Constructor with validation
function SignalEnum.new(registry)
    if instance then
        warn("[SignalEnum] WARNING: new() called when instance already exists. Overwriting previous instance.")
    end
    
    if type(registry) ~= "table" then
        error("[SignalEnum] CRITICAL: registry must be a table", 2)
    end
    
    instance = setmetatable({}, SignalEnum)
    instance.registry = registry
    instance.enums = {}
    instance:initialize()
    return instance
end

-- Robust path builder with error checking
local function buildEnumPath(registry, pathParts, currentIndex, enumTable)
    if currentIndex > #pathParts then
        warn(string.format("[SignalEnum] Path index overflow at: %s", table.concat(pathParts, ".")))
        return
    end
    
    local currentPart = pathParts[currentIndex]
    if type(currentPart) ~= "string" then
        warn(string.format("[SignalEnum] Invalid path part (%s) at position %d in path: %s", 
            tostring(currentPart), currentIndex, table.concat(pathParts, ".")))
        return
    end
    
    -- Initialize path segment if not exists
    if enumTable[currentPart] == nil then
        enumTable[currentPart] = {}
    elseif type(enumTable[currentPart]) ~= "table" then
        warn(string.format("[SignalEnum] Path conflict at %s: expected table, got %s", 
            table.concat(pathParts, ".", 1, currentIndex), type(enumTable[currentPart])))
        return
    end
    
    if currentIndex == #pathParts then
        -- Final segment - store the string value
        enumTable[currentPart] = currentPart
    else
        if registry[currentPart] == nil then
            warn(string.format("[SignalEnum] Missing registry path: %s", 
                table.concat(pathParts, ".", 1, currentIndex)))
        elseif type(registry[currentPart]) ~= "table" then
            warn(string.format("[SignalEnum] Expected table at %s, got %s", 
                table.concat(pathParts, ".", 1, currentIndex), type(registry[currentPart])))
        else
            -- Recurse with next index
            buildEnumPath(
                registry[currentPart],
                pathParts,
                currentIndex + 1,
                enumTable[currentPart]
            )
        end
    end
end

-- Safe enum population with validation
function SignalEnum:populateEnumNames()
    local function recurseRegistry(registry, currentPath, enumTable)
        if type(registry) ~= "table" then
            warn(string.format("[SignalEnum] Invalid registry node at %s: expected table, got %s",
                #currentPath > 0 and table.concat(currentPath, ".") or "root",
                type(registry)))
            return
        end
        
        for key, value in pairs(registry) do
            -- Skip non-string keys
            if type(key) ~= "string" then
                warn(string.format("[SignalEnum] Non-string key detected at %s: %s",
                    #currentPath > 0 and table.concat(currentPath, ".") or "root",
                    tostring(key)))
                -- Skip to next iteration (replaces goto continue)
            else
                -- Track path depth
                table.insert(currentPath, key)
                
                if isSignal(value) then
                    buildEnumPath(self.registry, currentPath, 1, enumTable)
                elseif type(value) == "table" then
                    recurseRegistry(value, currentPath, enumTable)
                else
                    warn(string.format("[SignalEnum] Invalid registry value at %s: expected Signal or table, got %s",
                        table.concat(currentPath, "."),
                        type(value)))
                end
                
                -- Backtrack path
                table.remove(currentPath)
            end
        end
    end
    
    -- Reset and rebuild enums
    self.enums = {}
    recurseRegistry(self.registry, {}, self.enums)
end

-- Initialize with validation
function SignalEnum:initialize()
    if type(self.registry) ~= "table" then
        error("[SignalEnum] CRITICAL: Cannot initialize with invalid registry", 2)
    end
    self:populateEnumNames()
end

-- Safe enum access
function SignalEnum:getEnums()
    if not (self == instance) then
        warn("[SignalEnum] WARNING: getEnums() should be called on singleton instance")
    end
    return self.enums
end

return SignalEnum