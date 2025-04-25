Signal System Documentation
Overview
This documentation describes how to use the signal system implemented in this project. The system is made up of the following key components:

SignalService – A singleton service to manage and fire signals.

SignalEnum – An automatically-generated list of signal names, allowing for a clean, centralized way to reference signals.

PlayerRegistry – A registry that groups signals for different aspects of the player, like health, inventory, gold, etc.

SignalHelper – A helper to automatically connect signals to the corresponding handler methods.

SignalService
Purpose
SignalService is a singleton class that manages signals across the application. It stores signals, allows registering new signals, and facilitates firing them by name. This ensures signals are properly managed and allows you to dynamically add and use signals throughout your code.

Usage
Initialize the SignalService: The SignalService is a singleton, meaning it should be accessed through SignalService.getInstance(). The instance should only be created once, ensuring consistency across the entire project.

lua
Copy
Edit
local SignalService = require(game:GetService("ReplicatedStorage").utils.signal.SignalService)
local signalServiceInstance = SignalService.getInstance()
Register Signals: Signals are registered by name to the SignalService. You can register any signal (e.g., Signal.new()).

lua
Copy
Edit
You won't need to do this, but if you ever have to, because the SignalHelper:AutoConnect should register every signal for you.
local signal = Signal.new()
signalServiceInstance:registerSignal("OnDamageTaken", signal)
Fire Signals: To fire a signal, use the fireSignal function, which triggers the signal by its registered name.

lua
Copy
Edit
signalServiceInstance:fireSignal(SignalEnum:getEnums().Healthbar.OnDamageTaken, 10)  -- Firing with 10 damage as an argument
Access a Signal: If you need to directly access a signal object, use the getSignal function.

lua
Copy
Edit
local signal = signalServiceInstance:getSignal("OnDamageTaken")
SignalEnum
Purpose
SignalEnum is an automatically generated enumeration of all available signals in the project. It pulls signal names from the PlayerRegistry and stores them in a central location. This ensures that signal names are consistent across the code and reduces the likelihood of typos.

Usage
Create the SignalEnum: The SignalEnum is created by passing the PlayerRegistry into the SignalEnum class. This will automatically generate an enum with all signal names based on the registry.

lua
Copy
Edit
local SignalEnum = require(game:GetService("ReplicatedStorage").utils.signal.SignalEnum)
local PlayerRegistry = require(game:GetService("ReplicatedStorage").signaling.PlayerRegistry)

-- Creating an instance of SignalEnum and generating the signal names
local signalEnumInstance = SignalEnum.new(PlayerRegistry)
signalEnumInstance:initialize()  -- Automatically generates the enum from the registry
Accessing Enum Values: After initialization, the SignalEnum instance will contain all signal names, which can be accessed by their category and signal name.

lua
Copy
Edit
print(SignalEnum.Health.OnDamageTaken)  -- Output: "OnDamageTaken"
You can now use these enum values for consistent signal name references throughout your code.

PlayerRegistry
Purpose
The PlayerRegistry is a centralized registry of signals related to various aspects of the player (e.g., health, gold, inventory). It organizes signals into categories for easy access and management.

Usage
Adding Signals to the Registry: Signals are added to the registry by defining them in categories. Each category can have multiple signals.

Example PlayerRegistry:

lua
Copy
Edit
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
In this example, each category (e.g., Health, Gold, etc.) contains signals related to that category.

Adding New Entries: To add a new signal, simply create a new entry in the appropriate category of PlayerRegistry. For example, to add a signal for when a player earns experience:

lua
Copy
Edit
PlayerRegistry.EXP.OnEXPGain = Signal.new()  -- Adds a new signal
Register Signals in SignalService: After defining the signals in the registry, you can use SignalHelper to automatically register them in the SignalService and connect the corresponding methods on your handler.

Automatically Connecting Signals
Purpose
You can automatically connect signals from the PlayerRegistry to methods in a handler module (e.g., PlayerManager) using the SignalHelper.

Usage
Setup the Handler Module: The handler module should have methods corresponding to the signals you want to connect to. For example, a PlayerManager module could look like this:

lua
Copy
Edit
local PlayerManager = {}

function PlayerManager:OnDamageTaken(damage)
    print("Damage taken: " .. damage)
end

function PlayerManager:OnGoldGained(amount)
    print("Gold gained: " .. amount)
end

return PlayerManager
Auto-Connect Signals: To automatically connect the signals defined in PlayerRegistry to the handler methods in PlayerManager, use SignalHelper.AutoConnect.

lua
Copy
Edit
local SignalHelper = require(game:GetService("ReplicatedStorage").utils.signal.SignalHelper)
local PlayerRegistry = require(game:GetService("ReplicatedStorage").signaling.PlayerRegistry)
local PlayerManager = require(game:GetService("ReplicatedStorage").managers.PlayerManager)

-- Automatically connect all signals in the registry to the PlayerManager methods
SignalHelper.AutoConnect(PlayerRegistry, PlayerManager)
This will automatically connect signals like OnDamageTaken from PlayerRegistry to PlayerManager:OnDamageTaken. If a matching method exists in PlayerManager, the signal will be connected automatically.

Conclusion
This system allows for easy signal management and automatic connections between signals and handler methods. Here's a quick summary of the steps:

SignalService:

Manage, register, and fire signals.

SignalEnum:

Automatically generate a central list of all signal names for consistent usage across the project.

PlayerRegistry:

Organize signals into categories for easy access and management.

SignalHelper:

Automatically connect signals from the registry to handler methods in your module.

With this system, your project will have a well-organized, flexible, and maintainable approach to handling events and signal-based communication between components.