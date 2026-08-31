-- src/gameModes/dungeon/server/boot/DefinitionLoader.luau
--
-- WALKS THE CONTENT LAYER AT BOOT and hands back one registry per kind.
--
-- THE LOADER IS THE LOAD-BEARING PART OF THE WHOLE RESTRUCTURE. Rojo turns a
-- directory into a Folder Instance, so `GetChildren()` on it is the list of
-- content -- which makes adding an enemy ONE FILE and ZERO code edits. An index
-- module listing every enemy would be the same problem in more files: a second
-- place to forget, and forgetting is silent.
--
-- `BootValidation` already walks `definitions/` generically for effect
-- coverage; this is the same discipline, one layer up.
--
-- ============================================================================
-- WHY THIS LIVES IN PLACE CODE AND THE DEFINITIONS DO NOT
-- ============================================================================
--
--   definitions   serverShared/   -> ServerStorage.Shared    every place
--   this file     dungeon server/ -> ServerScriptService     this place only
--   HitVolume     dungeon server/ -> ServerScriptService     this place only
--
-- A skill definition holds a volume as a PLAIN TABLE and never calls
-- `HitVolume.resolve`, because requiring upward from shared-between-places code
-- into one place's code is the direction Architecture Part 13 forbids. The Hub
-- has no `HitVolume` at all, so such a require would fail on LOAD there and
-- take the entire definitions tree with it -- not just the one row.
--
-- So resolution happens HERE, at the layer that is allowed to know what a
-- HitVolume is. The guarantee is unchanged: a malformed volume is still a boot
-- failure naming the file, it is just collected somewhere legal.
--
-- ============================================================================
-- FAIL AT BOOT, LOUDLY, ALL AT ONCE
-- ============================================================================
--
-- Every problem is collected and reported together rather than thrown on the
-- first. Fixing one typo, restarting, and finding the next is the workflow this
-- avoids -- the same aggregate-and-fail-once discipline as
-- `SignalService.validate` and the place manifest check.
--
-- A broken stat block discovered when a boss spawns is far worse than one
-- discovered before gameplay begins.

local ServerStorage = game:GetService("ServerStorage")

local definitionsFolder = ServerStorage:WaitForChild("Shared"):WaitForChild("definitions")

local targeting = script.Parent.Parent:WaitForChild("resolution"):WaitForChild("targeting")
local HitVolume = require(targeting:WaitForChild("HitVolume"))

local DefinitionLoader = {}

-- Loaded once and cached. Content is read-only after boot (Architecture Part
-- 6), so re-walking the folder per lookup would be work with no possible
-- different answer.
local cache = nil

-- ============================================================================
-- WHY SKILLS ARE FLAT AND UNGROUPED
-- ============================================================================
--
-- One file per skill, no `skills/Warrior/` or `skills/melee/`. That was tried
-- (grouped by class) and reversed on 2026-08-23, because the game design
-- already breaks every grouping axis available:
--
--   by class      a sword-mage has melee AND magic skills
--   by weapon     a magic sword is both
--   by mechanic   a skill that parries and redirects is both
--
-- And the deciding evidence is sharper than "classes blend". Gameplay-Design's
-- mitigation table keys availability on things that are not class at all:
-- *"Physical (heavy/momentum): parryable only by a HEAVY WEAPON with a parry
-- ability"* is weapon weight, while *"only the Mage's redirect can interact
-- with magical"* is class. Availability is already many-to-many across two
-- axes, and a folder can encode exactly one of them.
--
-- **The id is the only stable key.** So the folder is flat, and WHO MAY USE A
-- SKILL is a separate list living on whatever owns that relationship -- a class
-- or a weapon naming skill ids. That keeps a many-to-many as data instead of
-- smuggling it into a filename.
--
-- Note what is NOT here: "can this weapon parry this attack category" is a
-- mitigation PREDICATE, not an availability list, and it belongs to the
-- INTERCEPT phase of damage resolution. Different job, deliberately absent.
--
-- ============================================================================
-- WALKING
-- ============================================================================

-- "BasicSwing" -> "BASIC_SWING". "Goblin" -> "GOBLIN".
--
-- ONE RULE FOR BOTH FOLDERS rather than uppercase-for-enemies and something
-- else for skills. Two conventions for one idea is how the next folder gets a
-- third.
--
-- A `_` goes before every capital that follows a lowercase or a digit, then the
-- whole thing is uppercased. Consecutive capitals are left alone -- "AOEBlast"
-- becomes "AOEBLAST", not "A_O_E_BLAST" -- so an acronym-led name needs an
-- explicit `id` and will be told so by the mismatch check rather than silently
-- getting a name nobody expected.
local function idFromFileName(fileName: string): string
    local spaced = string.gsub(fileName, "([%l%d])(%u)", "%1_%2")
    return string.upper(spaced)
end

-- Requires every ModuleScript directly inside a named subfolder.
--
-- `GetChildren` and not `GetDescendants`: a subfolder inside `enemies/` is a
-- grouping someone made for their own reasons, and recursing would silently
-- turn it into content. Flat is what the walk promises.
--
-- A MISSING FOLDER IS NOT AN ERROR. A place may legitimately ship without
-- enemies; the Hub will. It returns empty and the caller decides whether that
-- matters.
local function loadFolder(name: string, problems: { string })
    local folder = definitionsFolder:FindFirstChild(name)
    if not folder then
        return {}
    end

    local loaded = {}

    for _, module in ipairs(folder:GetChildren()) do
        if module:IsA("ModuleScript") then
            local ok, result = pcall(require, module)

            if not ok then
                table.insert(problems, string.format(
                    "%s/%s failed to load: %s", name, module.Name, tostring(result)))
            elseif type(result) ~= "table" then
                table.insert(problems, string.format(
                    "%s/%s must return a table, got %s",
                    name, module.Name, typeof(result)))
            else
                loaded[module.Name] = result
            end
        end
    end

    return loaded
end

-- ============================================================================
-- ENEMIES -- one file, one enemy, keyed by its own declared id
-- ============================================================================
--
-- KEYED BY `id` RATHER THAN BY FILENAME, and then checked that the two agree.
-- The id is what everything else references, so it has to be the key; the
-- filename check is what stops `Goblin.luau` quietly declaring `id = "GOBLIN2"`
-- after a copy-paste. Two names for one thing that nothing compares is how a
-- spawner ends up requesting an enemy that exists in the folder and not in the
-- registry.
local function buildEnemies(problems: { string })
    local files = loadFolder("enemies", problems)
    local enemies = {}

    for fileName, definition in pairs(files) do
        local id = definition.id

        if type(id) ~= "string" or id == "" then
            table.insert(problems, string.format(
                "enemies/%s is missing a string `id`", fileName))
            continue
        end

        if enemies[id] then
            table.insert(problems, string.format(
                "enemies/%s declares id '%s', which is already taken", fileName, id))
            continue
        end

        local expected = idFromFileName(fileName)
        if id ~= expected then
            table.insert(problems, string.format(
                "enemies/%s declares id '%s' -- the file name and the id must "
                    .. "match (expected '%s')", fileName, id, expected))
        end

        if type(definition.hp) ~= "number" or definition.hp <= 0 then
            table.insert(problems, string.format(
                "enemies/%s: hp must be a positive number", fileName))
        end

        if definition.hurtbox ~= nil and type(definition.hurtbox) ~= "string" then
            table.insert(problems, string.format(
                "enemies/%s: hurtbox must be the NAME of a HurtboxDefinitions "
                    .. "entry, not a zone list", fileName))
        end

        enemies[id] = definition
    end

    return enemies
end

-- ============================================================================
-- SKILLS -- one file per owner, many skills inside
-- ============================================================================
--
-- One file, one skill, keyed by its own declared id -- structurally identical
-- to `buildEnemies`, which is the point. Two content kinds walked two different
-- ways is a difference someone has to remember.
--
-- A skill id is GLOBAL. Callers ask "what is BASIC_SWING", never "what is
-- Warrior's BASIC_SWING", which is also what makes a duplicate a real collision
-- worth reporting rather than a shadowing nobody notices.
--
-- THE VOLUME IS RESOLVED AND VALIDATED HERE, once, at boot. Resolving per swing
-- would do identical work sixty times a second to reach the same answer, and
-- `HitVolume.resolve` freezes its result -- so doing it once also means nothing
-- can mutate a volume at runtime and have the change survive into the next
-- attack.
local function buildSkills(problems: { string })
    local files = loadFolder("skills", problems)
    local skills = {}

    for fileName, skill in pairs(files) do
        local id = skill.id

        if type(id) ~= "string" or id == "" then
            table.insert(problems, string.format(
                "skills/%s is missing a string `id`", fileName))
            continue
        end

        if skills[id] then
            table.insert(problems, string.format(
                "skills/%s declares id '%s', which is already taken", fileName, id))
            continue
        end

        local expected = idFromFileName(fileName)
        if id ~= expected then
            table.insert(problems, string.format(
                "skills/%s declares id '%s' -- the file name and the id must "
                    .. "match (expected '%s')", fileName, id, expected))
        end

        -- PLANNED ROWS ARE NAMES, NOT CONTENT. They exist so an id is settled
        -- and greppable before the workflow that produces its numbers has been
        -- run. Validating a volume they deliberately do not have would make
        -- declaring an intention impossible.
        if skill.planned then
            skills[id] = table.freeze({
                id = id,
                displayName = skill.displayName or id,
                planned = true,
            })
            continue
        end

        if type(skill.volume) ~= "table" then
            table.insert(problems, string.format(
                "skills/%s has no `volume` table (mark it `planned = true` if "
                    .. "that is deliberate)", fileName))
            continue
        end

        local resolved
        local resolveOk, resolveErr = pcall(function()
            resolved = HitVolume.resolve(skill.volume)
        end)

        if not resolveOk then
            table.insert(problems, string.format(
                "skills/%s has an invalid volume: %s", fileName, tostring(resolveErr)))
            continue
        end

        local valid, reason = HitVolume.validate(resolved)
        if not valid then
            table.insert(problems, string.format(
                "skills/%s has an invalid volume: %s", fileName, tostring(reason)))
            continue
        end

        skills[id] = table.freeze({
            id = id,
            displayName = skill.displayName or id,
            volume = resolved,

            -- CAPTURED LATER, NOT AUTHORED NOW. A clip name and a score name
            -- are the output of the animation workflow -- animate, build the
            -- hitbox, run it, read the diagnostics, capture the numbers, THEN
            -- write the row. Carried through as nil so the fields exist in the
            -- shape without being invented.
            clip = skill.clip,
            score = skill.score,
        })
    end

    return skills
end

-- ============================================================================
-- THE ENTRY POINT
-- ============================================================================

function DefinitionLoader.load()
    if cache then
        return cache
    end

    local problems = {}

    local loaded = {
        enemies = buildEnemies(problems),
        skills = buildSkills(problems),
    }

    if #problems > 0 then
        table.sort(problems)
        error(string.format(
            "[DefinitionLoader] %d content problem(s):\n  - %s",
            #problems, table.concat(problems, "\n  - ")), 0)
    end

    cache = loaded
    return cache
end

-- Fails loudly on an unknown id rather than returning nil.
--
-- A nil skill travels: it becomes a nil volume, becomes a resolution that finds
-- nothing, and surfaces as "that attack does nothing" several layers from the
-- typo. The id is content and content is checked at boot, so reaching here with
-- an unknown one is a programmer error, not a runtime condition.
function DefinitionLoader.skill(id: string)
    local loaded = DefinitionLoader.load()
    local skill = loaded.skills[id]

    assert(skill, string.format(
        "[DefinitionLoader] unknown skill '%s'", tostring(id)))
    assert(not skill.planned, string.format(
        "[DefinitionLoader] skill '%s' is PLANNED and has no volume yet -- it "
            .. "is a reserved name, not content", tostring(id)))

    return skill
end

function DefinitionLoader.enemy(id: string)
    local loaded = DefinitionLoader.load()
    local enemy = loaded.enemies[id]

    assert(enemy, string.format(
        "[DefinitionLoader] unknown enemy '%s'", tostring(id)))

    return enemy
end

function DefinitionLoader.enemies()
    return DefinitionLoader.load().enemies
end

function DefinitionLoader.skills()
    return DefinitionLoader.load().skills
end

return DefinitionLoader
