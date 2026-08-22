-- src/gameModes/dungeon/client/diagnostics/AuraDemo.client.luau
--
-- TEMPORARY. Cycles the aura definitions on your own character so they can be
-- looked at instead of imagined.
--
--     E          next aura
--     Q          previous aura
--     R          off
--
-- A .client SCRIPT rather than a module, and safely so: this only OBSERVES and
-- renders locally. It mutates nothing the test suite reads and nothing the
-- server can see, which is the same reason PingProbe is allowed to be a Script
-- while DummySpawner is not.
--
-- WHEN AURAS BECOME REAL, none of this survives -- a buff applies an aura,
-- a Presenter reads the fact and calls `Aura.play`, and nobody presses E. The
-- module it drives is the part that stays.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local AuraDefinitions = require(
    ReplicatedStorage:WaitForChild("definitions"):WaitForChild("AuraDefinitions"))

local playback = script.Parent.Parent:WaitForChild("playback")
local Aura = require(playback:WaitForChild("Aura"))

local ENABLED = true

local player = Players.LocalPlayer
local index = 0            -- 0 means "none"
local current = nil

local function rootOf(): BasePart?
    local character = player.Character
    return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function clear(immediate: boolean?)
    if current then
        current:stop(immediate)
        current = nil
    end
end

local function apply()
    clear()

    if index == 0 then
        print("[AuraDemo] off")
        return
    end

    local root = rootOf()
    if not root then
        warn("[AuraDemo] no HumanoidRootPart yet -- respawn and try again")
        return
    end

    local id = AuraDefinitions.ORDER[index]
    local definition = AuraDefinitions[id]

    current = Aura.play(root, id)
    print(string.format("[AuraDemo] %d/%d  %s  (%d layers%s)",
        index, #AuraDefinitions.ORDER,
        definition.displayName,
        #definition.layers,
        definition.light and " + light" or ""))
end

local function step(delta: number)
    local count = #AuraDefinitions.ORDER
    -- Wraps through 0, so cycling forward always passes back through "off" --
    -- comparing an aura against no aura is most of what looking at them is
    -- for, and having to reach for a third key to do it is friction.
    index = (index + delta) % (count + 1)
    apply()
end

if ENABLED then
    UserInputService.InputBegan:Connect(function(input, processedByUI)
        if processedByUI then
            return
        end

        if input.KeyCode == Enum.KeyCode.E then
            step(1)
        elseif input.KeyCode == Enum.KeyCode.Q then
            step(-1)
        elseif input.KeyCode == Enum.KeyCode.R then
            index = 0
            apply()
        end
    end)

    -- Death destroys the character, and with it the host parts and the
    -- attachment the light hung on. Re-applying on respawn is what keeps the
    -- aura from silently disappearing the first time you fall off the map.
    player.CharacterAdded:Connect(function()
        if index ~= 0 then
            task.wait(0.4)      -- let the rig finish assembling
            apply()
        end
    end)

    print(string.format(
        "[AuraDemo] %d auras loaded -- E next, Q previous, R off",
        #AuraDefinitions.ORDER))
end
