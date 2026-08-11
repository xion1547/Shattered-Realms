-- src/shared/utils/signal/SignalService.luau
--
-- The Fact broker. See Architecture-Reference.md Part 11.5.
--
-- Four jobs, and deliberately nothing else:
--
--   init(vocabularies)  establishes which fact names are legal in THIS place.
--                       First step of boot, before anything declares or
--                       subscribes.
--   declare(name)       the owning Service claims a fact and receives the
--                       ONLY fire-capable reference to it. Access control is
--                       the return value: nothing else can ever obtain it,
--                       because nothing else is ever handed it.
--   on(name, fn)        anything subscribes BY NAME, never by module
--                       reference. Legal before the owner has declared, and
--                       legal in a place where the owner does not exist.
--   validate()          boot gate. Two-way: every subscription resolves, and
--                       every name in the vocabulary has an owner.
--                       Aggregated, loud, fatal.
--
-- Subscribing by name rather than by module reference is load-bearing for
-- place separation (Part 13), not a stylistic choice: AchievementService
-- cannot require(CombatService) in order to subscribe to Combat.OnKill,
-- because CombatService is not in the Hub build at all.
--
-- There is deliberately no get(name). Handing back the Signal object would
-- hand back Fire, which is the one thing this module exists to withhold.

local Signal = require(script.Parent.Signal)

local SignalService = {}

-- One place's legal fact names. Arrays, not sets -- the split between them is
-- what lets the Hub legally know nothing about Combat.OnKill.
export type Vocabulary = { string }

-- What on() hands back. It is NOT always a Signal.Connection: subscribing
-- before the owner declares returns a stand-in that behaves identically, so
-- the contract callers can rely on is this shape, not the concrete class.
export type Subscription = {
    Connected: boolean,
    Disconnect: (any) -> (),
}

-- Buffered subscription, held only until the owner declares.
type PendingEntry = {
    fn: Signal.Listener,
    cancelled: boolean,
    connection: Signal.Connection?,
}

local legal: { [string]: boolean } = {}
local declared: { [string]: Signal.Signal } = {}
local pending: { [string]: { PendingEntry } } = {}
local subscribed: { [string]: boolean } = {}
local initialized = false

local function assertInitialized(caller: string)
    if not initialized then
        error(string.format(
            "[SignalService] %s() called before init(). Call " ..
            "SignalService.init({ ... }) with this place's signal " ..
            "vocabularies as the first step of boot.", caller), 3)
    end
end

local function assertLegal(name: any, caller: string)
    if type(name) ~= "string" or name == "" then
        error(string.format(
            "[SignalService] %s() expects a non-empty fact name, got %s",
            caller, tostring(name)), 3)
    end
    if not legal[name] then
        error(string.format(
            "[SignalService] %s('%s'): not in this place's signal vocabulary. " ..
            "Add it to the vocabulary file, or fix the name -- facts are not " ..
            "created ad hoc.", caller, name), 3)
    end
end

-- `vocabularies` is an array of arrays of fact-name strings, e.g.
-- { GlobalSignals, DungeonSignals }. Splitting them per place is what lets
-- the Hub legally know nothing about Combat.OnKill.
function SignalService.init(vocabularies: { Vocabulary })
    if type(vocabularies) ~= "table" then
        error("[SignalService] init() expects an array of vocabulary tables", 2)
    end

    legal, declared, pending, subscribed = {}, {}, {}, {}

    local duplicates = {}
    for _, vocabulary in ipairs(vocabularies) do
        if type(vocabulary) ~= "table" then
            error(string.format(
                "[SignalService] init(): expected a vocabulary table, got %s",
                typeof(vocabulary)), 2)
        end
        for _, name in ipairs(vocabulary) do
            if type(name) ~= "string" or name == "" then
                error(string.format(
                    "[SignalService] init(): vocabulary contains a non-string " ..
                    "entry: %s", tostring(name)), 2)
            end
            if legal[name] then
                table.insert(duplicates, name)
            end
            legal[name] = true
        end
    end

    -- A name in two vocabularies means two places both claim to own the same
    -- fact, which makes "exactly one owner" unenforceable.
    if #duplicates > 0 then
        table.sort(duplicates)
        error(string.format(
            "[SignalService] %d fact name(s) appear in more than one " ..
            "vocabulary:\n  - %s", #duplicates, table.concat(duplicates, "\n  - ")), 2)
    end

    initialized = true
end

-- Claim ownership of a fact. Returns the fire-capable Signal -- keep it in a
-- local or a private field, never somewhere another module can reach it.
function SignalService.declare(name: string): Signal.Signal
    assertInitialized("declare")
    assertLegal(name, "declare")

    if declared[name] then
        error(string.format(
            "[SignalService] declare('%s'): already declared. A fact has " ..
            "exactly one owner.", name), 2)
    end

    local signal = Signal.new(name)
    declared[name] = signal

    -- Flush anything that subscribed before this owner booted.
    local buffered = pending[name]
    if buffered then
        for _, entry in ipairs(buffered) do
            if not entry.cancelled then
                entry.connection = signal:Connect(entry.fn)
            end
        end
        pending[name] = nil
    end

    return signal
end

-- Subscribe by name. Returns a handle carrying :Disconnect(), which behaves
-- identically whether it is cancelled before or after the owner declares.
--
-- Subscribing before declaration is legal on purpose: boot order between
-- Services is not something a listener should have to know or depend on.
function SignalService.on(name: string, listener: Signal.Listener): Subscription
    assertInitialized("on")
    assertLegal(name, "on")

    if type(listener) ~= "function" then
        error(string.format(
            "[SignalService] on('%s'): expects a function, got %s",
            name, typeof(listener)), 2)
    end

    subscribed[name] = true

    local signal = declared[name]
    if signal then
        return signal:Connect(listener)
    end

    local entry: PendingEntry = { fn = listener, cancelled = false, connection = nil }
    local buffered = pending[name]
    if not buffered then
        buffered = {}
        pending[name] = buffered
    end
    table.insert(buffered, entry)

    local handle = { Connected = true }
    function handle:Disconnect()
        entry.cancelled = true
        if entry.connection then
            entry.connection:Disconnect()
            entry.connection = nil
        end
        self.Connected = false
    end
    return handle
end

-- Boot gate. Call once, after every Service has booted, before gameplay.
--
-- Both directions are checked, the same two-way discipline Part 13 applies
-- to place manifests: a subscription with no owner is a listener waiting on
-- something that will never fire, and a vocabulary entry with no owner is
-- the vocabulary claiming a fact exists in this place when nothing produces
-- it. Neither should be discoverable by a player noticing something missing.
function SignalService.validate()
    assertInitialized("validate")

    local failures: { string } = {}

    for name in pairs(legal) do
        if not declared[name] then
            if subscribed[name] then
                table.insert(failures, string.format(
                    "'%s': subscribed to by at least one listener, but no " ..
                    "Service declared it", name))
            else
                table.insert(failures, string.format(
                    "'%s': in this place's vocabulary, but no Service " ..
                    "declared it here", name))
            end
        end
    end

    table.sort(failures)

    if #failures > 0 then
        error(string.format(
            "[SignalService] %d signal problem(s) at boot:\n  - %s",
            #failures, table.concat(failures, "\n  - ")), 0)
    end
end

return SignalService
