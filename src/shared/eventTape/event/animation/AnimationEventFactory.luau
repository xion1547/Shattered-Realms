local EventType = require(script.Parent.Parent:WaitForChild("EventType"))
local EventFactory = require(script.Parent.Parent:WaitForChild("EventFactory"))
local AnimationRegistry = require(script.Parent:WaitForChild("AnimationRegistry"))
local AnimationEvent = require(script.Parent:WaitForChild("AnimationEvent"))
local AnimationEventType = require(script.Parent.AnimationEventType)

local AnimationEventFactory = {}

-- Static method to create a new AnimationEventFactory instance
function AnimationEventFactory.builder()
    local builder = EventFactory.createBuilder()
        
        builder._subType = nil
        builder._id = nil
        builder._params = {}
    
        function builder:withSubType(subType)
            assert(EventType.ANIMATION.subType[subType], "Invalid subType for AnimationEvent")
            self._subType = subType
            return self
        end

        function builder:withRange(range)
            assert(type(range) == "number", "Range must be a number")
            self._params.range = range
            return self
        end
    
        function builder:build()
            assert(self._subType, "SubType must be set before building AnimationEvent")
            assert(self._id, "ID must be set before building AnimationEvent")
            assert(AnimationRegistry.validateAnimation(self._id), "Invalid animation ID")
    
            -- Validate params against AnimationEventType
            local processedParams = {}
            for field, config in pairs(AnimationEventType.params) do
                if self._params[field] ~= nil then
                    assert(type(self._params[field]) == config.type, 
                        string.format("%s must be %s", field, config.type))
                    processedParams[field] = self._params[field]
                elseif not config.optional then
                    processedParams[field] = config.default
                end
            end
    
            return AnimationEvent.new(self._subType, self._id, processedParams)
        end
    
        return builder
    end

return AnimationEventFactory