local EventFactory = {}

-- Abstract method to validate the subType, must be implemented by subclasses
function EventFactory:validateSubType(subType)
    error("validateSubType must be implemented by subclasses")
end

-- Static method to create a new EventFactory instance
function EventFactory.createBuilder()
    return {
        _subType = nil,
        _id = nil,
        _params = {},

        withSubType = function(self, subType)
            error("validateSubType must be implemented by subclasses")
        end,

        withId = function(self, id)
            assert((type(id) == "string") or type(id) == "number"  , "ID must be string or number")
            self._id = id
            return self
        end,
    }
end 

return EventFactory