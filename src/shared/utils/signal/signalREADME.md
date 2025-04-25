# Signal System Documentation

This documentation describes how to use the signal system implemented in this project. The system is made up of the following key components:

- **SignalService**: A singleton service to manage and fire signals.
- **SignalEnum**: An automatically-generated list of signal names for easy, centralized reference.
- **PlayerRegistry**: A registry that groups signals related to different aspects of the player (e.g., health, inventory, gold).
- **SignalHelper**: A helper that automatically connects signals to the corresponding handler methods.

## Components Overview

### SignalService
**SignalService** is a singleton class that manages signals across the application. It stores signals, allows registering new signals, and facilitates firing them by name. This ensures proper signal management and enables dynamic addition and usage of signals.

#### Usage

1. **Initialize the SignalService:**
   The SignalService is a singleton. Access it using `SignalService.getInstance()`. Only one instance should exist across the entire project.

    ```lua
    local SignalService = require(game:GetService("ReplicatedStorage").utils.signal.SignalService)
    local signalServiceInstance = SignalService.getInstance()
    ```

2. **Register Signals:**
   Register a signal by name in the SignalService. You can register any signal (e.g., `Signal.new()`), although this is typically handled automatically by `SignalHelper:AutoConnect`.

    ```lua
    local signal = Signal.new()
    signalServiceInstance:registerSignal("OnDamageTaken", signal)
    ```

3. **Fire Signals:**
   To trigger a signal, use `fireSignal`, passing in the registered signal name.

    ```lua
    signalServiceInstance:fireSignal(SignalEnum:getEnums().Healthbar.OnDamageTaken, 10) -- Firing with 10 damage
    ```

4. **Access a Signal:**
   Directly access a signal by name using `getSignal`. However, you should probably be using the SignalEnum to be doing this.

    ```lua
    local signal = signalServiceInstance:getSignal("OnDamageTaken")
    ```

---

### SignalEnum
**SignalEnum** is an automatically-generated enumeration of all available signals in the project. It pulls signal names from the PlayerRegistry and stores them centrally, ensuring signal names are consistent and reducing typos.

#### Usage

1. **Create the SignalEnum:**
   The SignalEnum is created by passing the PlayerRegistry into the SignalEnum class. This will automatically generate an enum with all signal names based on the registry.

    ```lua
    local SignalEnum = require(game:GetService("ReplicatedStorage").utils.signal.SignalEnum)
    local PlayerRegistry = require(game:GetService("ReplicatedStorage").signaling.PlayerRegistry)

    local signalEnumInstance = SignalEnum.new(PlayerRegistry)
    signalEnumInstance:initialize()  -- Automatically generates the enum from the registry
    ```

2. **Access Enum Values:**
   After initialization, the SignalEnum instance contains all signal names, accessible by category and signal name.

    ```lua
    print(SignalEnum.Health.OnDamageTaken)  -- Output: "OnDamageTaken"
    ```

---

### PlayerRegistry
**PlayerRegistry** is a centralized registry of signals related to various aspects of the player (e.g., health, gold, inventory). It organizes signals into categories for easy access and management.

#### Usage

1. **Adding Signals to the Registry:**
   Signals are added to the registry by defining them in categories. Each category can have multiple signals.

    ```lua
    local Signal = require(game:GetService("ReplicatedStorage").utils.signal.Signal)

    local PlayerRegistry = {
      Health = { 
        OnDamageTaken = Signal.new(), 
        OnHealthChanged = Signal.new(),
      },
      Gold = {
        OnGoldGained = Signal.new(),
        OnGoldSpent = Signal.new(),
      },
      EXP = {
        OnEXPChanged = Signal.new(),
        OnLevelUp = Signal.new(),
      },
      Inventory = {
        OnItemAdded = Signal.new(),
        OnItemRemoved = Signal.new(),
      }
    }

    return PlayerRegistry
    ```

2. **Adding New Entries:**
   To add a new signal, simply create a new entry in the appropriate category of PlayerRegistry.

    ```lua
    PlayerRegistry.EXP.OnEXPGain = Signal.new()  -- Adds a new signal
    ```

---

### SignalHelper
**SignalHelper** provides an automatic way to connect signals from the PlayerRegistry to handler methods in your modules, such as `PlayerManager`.

#### Usage

1. **Setup the Handler Module:**
   Your handler module should have methods corresponding to the signals you want to connect to. For example, a `PlayerManager` module could look like this:

    ```lua
    local PlayerManager = {}

    function PlayerManager:OnDamageTaken(damage)
      print("Damage taken: " .. damage)
    end

    function PlayerManager:OnGoldGained(amount)
      print("Gold gained: " .. amount)
    end

    return PlayerManager
    ```

2. **Auto-Connect Signals:**
   To automatically connect the signals defined in `PlayerRegistry` to methods in `PlayerManager`, use `SignalHelper.AutoConnect`.

    ```lua
    local SignalHelper = require(game:GetService("ReplicatedStorage").utils.signal.SignalHelper)
    local PlayerRegistry = require(game:GetService("ReplicatedStorage").signaling.PlayerRegistry)
    local PlayerManager = require(game:GetService("ReplicatedStorage").managers.PlayerManager)

    -- Automatically connect all signals in the registry to PlayerManager methods
    SignalHelper.AutoConnect(PlayerRegistry, PlayerManager)
    ```

This will connect signals like `OnDamageTaken` from `PlayerRegistry` to `PlayerManager:OnDamageTaken` automatically.

---

## Conclusion

This system provides an organized, flexible, and maintainable way to handle signals and events in your project. Here’s a summary of the key components:

- **SignalService**: Manages, registers, and fires signals.
- **SignalEnum**: Automatically generates a central list of all signal names for consistent usage.
- **PlayerRegistry**: Organizes signals into categories for easy access and management.
- **SignalHelper**: Automatically connects signals from the registry to handler methods in your modules.

With this system in place, your project will be better structured and maintainable, with clear communication between components through signals.

---
