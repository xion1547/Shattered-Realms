-- src/replicatedStorage/remoteEvents/RemoteEventsEnum.lua
local RemoteEventsEnum = {
	Player = {
		HealthUpdate = "Player_HealthUpdate",
		HealthUpdateRequest = "Player_HealthUpdateRequest",
		GoldUpdate = "Player_GoldUpdate",
		Joined = "Player_Joined",
		LevelUp = "Player_LevelUp",
        Inventory = {
            ItemAdded = "Inventory_ItemAdded",
            ItemRemoved = "Inventory_ItemRemoved",
        },
	},
	World = {
		ZoneEntered = "World_ZoneEntered",
		TimeOfDayChanged = "World_TimeOfDayChanged",
	},

	-- Add more categories as needed
}

return table.freeze(RemoteEventsEnum)
