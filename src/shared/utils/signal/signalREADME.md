# 📣 Signal System Documentation

This Signal System provides a highly structured, modular, and scalable event-handling architecture for your Roblox project.  
It is built with multiple layers of abstraction, designed to keep your **Signal**, **Registry**, **Manager**, and **Service** code cleanly separated.

---

## ✨ Overview

| Component         | Purpose |
|-------------------|---------|
| `Signal`          | Core class for connecting and firing individual signals. |
| `GlobalRegistry`  | Houses **all** signals organized by system path. |
| `SignalHelper`    | Automatically wires signals to the correct Manager methods based on directory structure. |
| `SignalEnum`      | Auto-generates an enum structure to reference signals by path safely. |
| `SignalService`   | Central service for firing, getting, and managing signals globally. |

---

## 🏗️ Project Structure

Signals must live inside the `src/signals/GlobalRegistry.lua` and correspond to the correct **Manager** in the `src/system/` directory.

Example:

```
src/
 ├── system/
 │    └── player/
 │         ├── subSystem/
 │         │     └── EXP/
 │         │         └── EXPManager.luau
 │         └── PlayerManager.luau
 └── signals/
      └── GlobalRegistry.lua
```

---

## ⚡ Signal (Base Class)

**Path:** `src/shared/utils/signal/Signal.lua`

The lowest level event system.  
It provides:

- `Connect(listenerFunction)`
- `Fire(listenerFunction?, ...)`
- `Disconnect(listenerFunction)`
- `DisconnectAll()`
- `Destroy()`

Example usage:

```lua
local mySignal = Signal.new()

local function onFired(arg)
    print("Signal fired with:", arg)
end

mySignal:Connect(onFired)
mySignal:Fire(nil, "Hello World!")
```

---

## 📚 GlobalRegistry

**Path:** `src/signals/GlobalRegistry.lua`

A tree structure that organizes all signals by system.  
Example registry:

```lua
local GlobalRegistry = {
    Player = {
        EXP = {
            OnLevelUp = Signal.new(),
            OnEXPChanged = Signal.new(),
        },
        Inventory = {
            OnItemAdded = Signal.new(),
        },
    },
}
```

> All signals must be created in the correct structure here for automatic wiring to work.

---

## 🔌 SignalHelper

**Path:** `src/shared/utils/signal/SignalHelper.lua`

Responsible for **auto-connecting** signals to manager methods!

- **`SignalHelper.AutoConnectAll(GlobalRegistry)`**  
  Traverses the registry, finds the correct Manager module based on the system folder structure, and connects each signal to the corresponding method.

Example flow:

```lua
SignalHelper.AutoConnectAll(GlobalRegistry)
```

When it finds `Player.EXP.OnLevelUp`, it automatically searches for:

> `system/player/subSystem/EXP/EXPManager.luau` ➔ method `OnLevelUp`

---

## 🗺️ SignalEnum

**Path:** `src/shared/utils/signal/SignalEnum.lua`

Generates a **typed enum tree** for safe reference to your signals by path.

Example usage:

```lua
local SignalEnum = require(PATH_TO_SignalEnum)
local enums = SignalEnum.getInstance():getEnums()

local mySignalEnum = enums.Player.EXP.OnLevelUp
```

No more typos like `"Player.EXP.OnLevelUp"` — you get real auto-completion and strict references!

---

## 🛰️ SignalService

**Path:** `src/shared/utils/signal/SignalService.lua`

Top-layer abstraction for interacting with signals globally.

Use this to **fire** and **get** signals anywhere.

```lua
local SignalService = require(PATH_TO_SignalService):getInstance()

-- Fire a signal
SignalService:fireSignal("Player.EXP.OnLevelUp", player, newLevel)

-- Get a signal manually
local signal = SignalService:getSignal("Player.Inventory.OnItemAdded")
if signal then
    signal:Connect(function(item)
        print("Item added to inventory:", item)
    end)
end
```

✅ Centralized  
✅ Consistent  
✅ Safe

---

## 🛠️ Full Usage Example

```lua
-- Startup: Auto-connect all signals
local GlobalRegistry = require(PATH_TO_GlobalRegistry)
local SignalHelper = require(PATH_TO_SignalHelper)
local SignalEnum = require(PATH_TO_SignalEnum)
local SignalService = require(PATH_TO_SignalService)

-- Initialize Enum System
SignalEnum.new(GlobalRegistry)

-- Auto-connect all signals to the managers
SignalHelper.AutoConnectAll(GlobalRegistry)

-- Example: Fire a level-up signal when a player levels up
SignalService:getInstance():fireSignal(
    SignalEnum.getInstance():getEnums().Player.EXP.OnLevelUp,
    player,
    newLevel
)
```

---

## ⚙️ Key Rules

- **All signals must exist in `GlobalRegistry`.**
- **Your `system/` folder structure must match the registry tree.**
- **Manager module names must follow the convention:**  
  `{FolderName}Manager.luau`
- **All handler methods must match the signal name exactly** (case-sensitive).
- **Call `SignalEnum.new(GlobalRegistry)` at startup.**
- **Call `SignalHelper.AutoConnectAll(GlobalRegistry)` after that.**

---

## 🧹 Best Practices

- Keep systems modular by separating into subSystems if needed (`player/subSystem/EXP/`).
- Only call `SignalService:fireSignal()` from your gameplay scripts — avoid directly firing `Signal` objects manually.
- Use `SignalEnum` enums to reference signals safely and consistently across the project.
- Never manually `Connect()` to raw signals unless absolutely necessary; prefer automatic SignalHelper wiring.

---

# 🚀 Ready to use.

This system gives you:

✅ **Centralized signal management**  
✅ **Auto-wiring of signals**  
✅ **Safe enums for event references**  
✅ **Global access and firing**  
✅ **Flexible directory structure**

---