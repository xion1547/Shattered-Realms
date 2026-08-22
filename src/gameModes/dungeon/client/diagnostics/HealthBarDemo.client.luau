-- src/gameModes/dungeon/client/diagnostics/HealthBarDemo.client.luau
--
-- TEMPORARY. Builds the HP bar from the two authored images and drives it off
-- the server's DAMAGED pushes.
--
-- HOW THE TWO IMAGES COMPOSE, since they are not the same thing and it is not
-- obvious from their names:
--
--   PlayerHealthBar     500x500, the WHOLE ornate frame -- carved border,
--                       spikes, gems -- with the red fill already lit inside
--                       it. This is the base and it never changes.
--   PlayerNoHealthBar   356x38, JUST the inner strip, greyed out.
--
-- So the grey is not a second bar, it is a LID. It sits exactly over the red
-- fill and grows in from the RIGHT as HP drops, covering the red rather than
-- shrinking it. At full health it is zero wide and invisible.
--
-- WHY IT CLIPS RATHER THAN SCALES. The obvious version sets the grey image's
-- width to the missing fraction -- and that SQUASHES the texture, so the
-- highlight running down its middle compresses into a blob as you take
-- damage. Instead the grey is held at full size inside a frame that clips, so
-- what changes is how much of it you can see.
--
-- IT LISTENS ON THE REMOTE DIRECTLY rather than going through EventTapeClient,
-- purely so this file can be deleted without touching Main.client.luau.
-- Multiple connections to one RemoteEvent are fine, and a diagnostic that
-- requires editing boot code to remove is a diagnostic nobody removes.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local wire = ReplicatedStorage:WaitForChild("eventTape"):WaitForChild("wire")
local MessageKind = require(wire:WaitForChild("MessageKind"))
local EventType = require(ReplicatedStorage:WaitForChild("eventTape")
    :WaitForChild("event"):WaitForChild("EventType"))
local RemoteEventsEnum = require(ReplicatedStorage:WaitForChild("remoteEvents")
    :WaitForChild("RemoteEventsEnum"))

local ENABLED = true

local FRAME_IMAGE = "rbxassetid://128162112223443"   -- PlayerHealthBar,   500x500
local EMPTY_IMAGE = "rbxassetid://132714067698368"   -- PlayerNoHealthBar, 356x38

-- The frame art is square with a lot of transparent padding, so the whole
-- container is square and the bar is placed inside it by fraction.
local CONTAINER = 460

-- WHERE THE INNER STRIP SITS INSIDE THE 500x500 FRAME. Measured off the art,
-- so these are the numbers to nudge if the grey does not land exactly on the
-- red -- nothing else here is tuning.
--
-- 356/500 = 0.712 wide, and the strip's own aspect (356x38) fixes the height
-- at 0.712 / (356/38) = 0.076. Anything else stretches it.
local BAR_WIDTH_FRACTION = 0.712
local BAR_HEIGHT_FRACTION = 0.076
local BAR_CENTRE_Y_FRACTION = 0.444

local BAR_W = math.round(CONTAINER * BAR_WIDTH_FRACTION)
local BAR_H = math.round(CONTAINER * BAR_HEIGHT_FRACTION)
local BAR_CY = math.round(CONTAINER * BAR_CENTRE_Y_FRACTION)

local DRAIN_TIME = 0.22

local player = Players.LocalPlayer
local state = { hp = 100, maxHp = 100 }
local lid, readout, activeTween

local function build()
    local gui = Instance.new("ScreenGui")
    gui.Name = "HealthBarDemo"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    gui.Parent = player:WaitForChild("PlayerGui")

    local container = Instance.new("Frame")
    container.Name = "Bar"
    container.Size = UDim2.fromOffset(CONTAINER, CONTAINER)
    container.Position = UDim2.new(0, 24, 1, -24)
    container.AnchorPoint = Vector2.new(0, 1)
    container.BackgroundTransparency = 1
    container.Parent = gui

    local frame = Instance.new("ImageLabel")
    frame.Name = "Frame"
    frame.Size = UDim2.fromScale(1, 1)
    frame.BackgroundTransparency = 1
    frame.Image = FRAME_IMAGE
    frame.ZIndex = 1
    frame.Parent = container

    -- ANCHORED TO THE RIGHT EDGE OF THE BAR. Growing leftward from a fixed
    -- right edge is what makes the drain read as the bar emptying rather than
    -- as a grey box sliding in.
    local clipper = Instance.new("Frame")
    clipper.Name = "Lid"
    clipper.AnchorPoint = Vector2.new(1, 0.5)
    clipper.Position = UDim2.fromOffset(
        math.round(CONTAINER / 2 + BAR_W / 2), BAR_CY)
    clipper.Size = UDim2.fromOffset(0, BAR_H)
    clipper.BackgroundTransparency = 1
    clipper.ClipsDescendants = true
    clipper.ZIndex = 2
    clipper.Parent = container

    -- FULL SIZE INSIDE THE CLIPPER, pinned to its right edge, so the texture
    -- never distorts however narrow the clipper gets.
    local empty = Instance.new("ImageLabel")
    empty.Name = "Empty"
    empty.AnchorPoint = Vector2.new(1, 0.5)
    empty.Position = UDim2.new(1, 0, 0.5, 0)
    empty.Size = UDim2.fromOffset(BAR_W, BAR_H)
    empty.BackgroundTransparency = 1
    empty.Image = EMPTY_IMAGE
    empty.ZIndex = 2
    empty.Parent = clipper

    local label = Instance.new("TextLabel")
    label.Name = "Readout"
    label.AnchorPoint = Vector2.new(0.5, 0.5)
    label.Position = UDim2.fromOffset(math.round(CONTAINER / 2), BAR_CY)
    label.Size = UDim2.fromOffset(BAR_W, BAR_H)
    label.BackgroundTransparency = 1
    label.Font = Enum.Font.GothamBold
    label.TextSize = 18
    label.TextColor3 = Color3.fromRGB(255, 235, 235)
    label.TextStrokeTransparency = 0.4
    label.Text = "100 / 100"
    label.ZIndex = 3
    label.Parent = container

    return clipper, label
end

local function render(animate: boolean)
    local missing = 1 - math.clamp(state.hp / state.maxHp, 0, 1)
    local goal = UDim2.fromOffset(math.round(BAR_W * missing), BAR_H)

    readout.Text = string.format("%d / %d", state.hp, state.maxHp)

    if activeTween then
        activeTween:Cancel()
        activeTween = nil
    end

    if not animate then
        lid.Size = goal
        return
    end

    -- A short tween rather than a snap. The bar's job here is to make a
    -- 20-point hit legible, and an instant jump is easy to miss entirely --
    -- the movement is what draws the eye, not the final width.
    activeTween = TweenService:Create(
        lid,
        TweenInfo.new(DRAIN_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        { Size = goal })
    activeTween:Play()
end

if ENABLED then
    lid, readout = build()
    render(false)

    local remote = ReplicatedStorage:WaitForChild(RemoteEventsEnum.EventTapeRemote)

    remote.OnClientEvent:Connect(function(message)
        if type(message) ~= "table" then
            return
        end
        if message.kind ~= MessageKind.PUSH or message.eventType ~= EventType.COMBAT then
            return
        end

        local payload = message.payload
        if type(payload) ~= "table" or payload.hp == nil then
            return
        end

        state.hp = payload.hp
        state.maxHp = payload.maxHp or state.maxHp

        if payload.kind == "DAMAGED" then
            print(string.format(
                "[HealthBarDemo] hit by %s (%s) for %d -- HP %d/%d",
                tostring(payload.source), tostring(payload.attack),
                payload.amount or 0, state.hp, state.maxHp))
        elseif payload.kind == "HEALED" then
            print(string.format("[HealthBarDemo] reset to %d/%d", state.hp, state.maxHp))
        end

        render(true)
    end)

    print("[HealthBarDemo] listening for COMBAT pushes on the EventTape remote")
end
