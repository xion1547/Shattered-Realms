-- src/gameModes/dungeon/client/playback/conductor/Baseline.luau
--
-- WHO OWNS A PROPERTY, AND WHAT IT LOOKED LIKE BEFORE ANYONE TOUCHED IT.
--
-- Shared across every running Playback, refcounted:
--
--     the FIRST Score to touch a property captures the original
--     the LAST one to let go puts it back
--
-- ============================================================================
-- THE BUG THIS EXISTS FOR, WHICH WAS REAL AND WAS REACHABLE
-- ============================================================================
--
-- Baseline capture started out per-playback: each one read the current value
-- when it began and restored that value when it stopped. That is correct for
-- one Score at a time and quietly destructive the moment two overlap.
--
--     A starts     baseline = red         nothing has written yet, so correct
--     A runs       property is now ORANGE mid-fade
--
--     B starts     baseline = ORANGE      <- reads A's IN-FLIGHT value
--                  writes green
--
--     A finishes   restores red           invisible; B overwrites it next frame
--     B finishes   restores ORANGE        <- stuck at a mid-animation value
--
-- So the mechanism that exists to prevent permanent debris CREATED permanent
-- debris. And the trigger is not exotic -- it is spam-clicking one attack,
-- which is the first thing anyone does in a test session.
--
-- ============================================================================
-- WHY REFCOUNTING RATHER THAN ONE-OWNER-PER-PROPERTY
-- ============================================================================
--
-- The simpler rule -- a property may have only one Score on it, and starting a
-- second stops the first -- was considered and is too coarse. A hit-flash and a
-- swing on the same blade touch DIFFERENT properties and are legitimately
-- concurrent; stopping the swing to play a flash would be wrong.
--
-- Refcounting handles both: overlapping Scores on disjoint properties never
-- interact, and overlapping Scores on the SAME property share one original.
--
-- ============================================================================
-- WHAT IT STILL DOES NOT SOLVE, STATED SO IT IS NOT ASSUMED
-- ============================================================================
--
-- If something OUTSIDE the Conductor writes to a property while a Score owns
-- it, the release will stomp that write. That is inherent to any restore
-- mechanism -- it cannot tell a foreign write from its own -- and the answer
-- is the same as everywhere else here: the Conductor is the single door for
-- client-side animation, so nothing else should be writing.

local Evaluate = require(script.Parent:WaitForChild("Evaluate"))

local Baseline = {}

-- instance -> property -> { value = the original, count = how many hold it }
--
-- WEAK KEYS. A destroyed instance must not be pinned in memory by a table that
-- only exists to remember what colour it used to be.
local owned: { [Instance]: { [string]: { value: any, count: number } } } =
    setmetatable({}, { __mode = "k" }) :: any

-- What one Playback is holding. Returned by `acquire` and handed back to
-- `release` -- the Playback never needs to know about the registry.
export type Claim = { instance: Instance, property: string }

-- Claims every property a Score's tracks touch.
--
-- READS THE ORIGINAL ONLY ON THE FIRST CLAIM. A second claimant gets the same
-- stored value, which is the whole point: it must not read what the first one
-- has since written.
function Baseline.acquire(score: any, root: Instance): { Claim }
    local claims: { Claim } = {}

    for _, track in ipairs(score.tracks) do
        local instance = Evaluate.resolve(root, track.target)
        if not instance then
            continue
        end

        local properties = owned[instance]
        if not properties then
            properties = {}
            owned[instance] = properties
        end

        local entry = properties[track.property]
        if not entry then
            local ok, current = pcall(Evaluate.read, instance, track.property)
            if not ok then
                -- A property that cannot be read cannot be restored either.
                -- Skipping the claim means `release` will not try.
                continue
            end
            entry = { value = current, count = 0 }
            properties[track.property] = entry
        end

        entry.count += 1
        table.insert(claims, { instance = instance, property = track.property })
    end

    return claims
end

-- Releases a Playback's claims, restoring anything that nobody else holds.
--
-- NOT RESTORING WHILE SOMEONE ELSE IS STILL DRIVING is the point. A Score
-- ending while a longer one is mid-flight over the same property must leave it
-- alone -- writing the original there would be a visible flicker that the other
-- Score then overwrites, which is exactly the artefact this whole module exists
-- to remove.
function Baseline.release(claims: { Claim })
    for _, claim in ipairs(claims) do
        local properties = owned[claim.instance]
        local entry = properties and properties[claim.property]
        if not entry then
            continue
        end

        entry.count -= 1
        if entry.count > 0 then
            continue
        end

        -- pcall'd because the instance may have been destroyed while the Score
        -- was playing, which is a normal way for this to end rather than a
        -- fault worth reporting.
        pcall(Evaluate.assign, claim.instance, claim.property, entry.value)
        properties[claim.property] = nil

        if next(properties) == nil then
            owned[claim.instance] = nil
        end
    end
end

-- Diagnostics. Answers "is anything still holding a property it should have let
-- go of" without exposing the registry itself.
function Baseline.heldCount(): number
    local total = 0
    for _, properties in pairs(owned) do
        for _, entry in pairs(properties) do
            total += entry.count
        end
    end
    return total
end

return Baseline
