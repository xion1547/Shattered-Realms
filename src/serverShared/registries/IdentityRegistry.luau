local IdentityRegistry = {
    PLAYER = "PLAYER",
    ENEMY = "ENEMY",
    BOSS = "BOSS",
    PET = "PET",
    FRIENDLY = "FRIENDLY",
    ITEM = "ITEM"
}

local identityNames = table.clone(IdentityRegistry)

function IdentityRegistry.isValidIdentity(identity: string): boolean
    return identityNames[identity] ~= nil
end

return table.freeze(IdentityRegistry)