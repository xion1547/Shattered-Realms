-- src/replicatedStorage/remoteEvents/RemoteEventsEnum.lua
local RemoteEventsEnum = {
	Server = {
		Player = {
			PlayerUpdate = "Player_PlayerUpdate",
			HealthUpdate = "Player_HealthUpdate",
			GoldUpdate = "Player_GoldUpdate",
			Joined = "Player_Joined",
			LevelUp = "Player_LevelUp",
			Inventory = {
				ItemAdded = "Inventory_ItemAdded",
				ItemRemoved = "Inventory_ItemRemoved",
			},
		},
	},
	Client = {
		Player = {
			PlayerRequestUpdate = "Player_PlayerRequestUpdate",
			HealthRequestUpdate = "Player_HealthRequestUpdate",
			GoldRequestUpdate = "Player_GoldRequestUpdate",
			Joined = "Player_Joined",
			LevelUp = "Player_LevelUp",
			Inventory = {
				ItemAdded = "Inventory_ItemRequestAdd",
				ItemRemoved = "Inventory_ItemRequestRemoved",
			},
		},
	}
	-- Add more categories as needed
}

return table.freeze(RemoteEventsEnum)
