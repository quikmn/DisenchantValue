if DisenchantValue.merged then return end -- EverlookDB Auctions does this now (Namespace.lua)
-- DisenchantValue: "Disenchant: ~Xg" on item tooltips, using Classic disenchant odds (classic-db) and Auctionator prices.
-- Hold Shift to see the possible results and their odds.

local DATA = DisenchantValueData
local KEYS = DATA.DisenchantingProbabilityKeys

-- Settings live in DisenchantValueDB (filled with defaults in Log.lua); nil-safe before it loads.
local function Opt(key, default)
    local db = DisenchantValueDB
    local v = db and db[key]
    if v == nil then return default end
    return v
end

-- The per-material breakdown: with Shift held (default), always, or never.
local function ShowBreakdown()
    local mode = Opt("breakdown", "shift")
    return mode == "always" or (mode == "shift" and IsShiftKeyDown())
end

-- Prices come from EverlookDB Auctions' scans when it is loaded and knows the item, else from Auctionator's.
-- Both are optional (## OptionalDeps); with neither, the tooltip says "no prices".
local function EDBA()
    local api = EverlookDBAuctionsAPI
    if api and (tonumber(api.version) or 0) >= 1 then return api end
end

local function AuctionatorAPI()
    return Auctionator and Auctionator.API and Auctionator.API.v1
end

-- Days since Auctionator last saw the item; false when it is older than Auctionator tracks (3 weeks).
local function AuctionatorAge(itemID)
    local api = AuctionatorAPI()
    if not (api and api.GetAuctionAgeByItemID) then return nil end
    local ok, days = pcall(api.GetAuctionAgeByItemID, "DisenchantValue", itemID)
    if not ok then return nil end
    return days or false
end

-- One material: price in copper, age in days (nil = unknown, false = 3+ weeks), and where it came from.
local function GetPrice(itemID)
    local api = EDBA()
    if api and api.price then
        local ok, low, age = pcall(api.price, itemID)
        if ok and low then return low, age and math.floor(age / 86400), "EverlookDB" end
    end
    local a = AuctionatorAPI()
    if a and a.GetAuctionPriceByItemID then
        local price = a.GetAuctionPriceByItemID("DisenchantValue", itemID)
        if price then return price, AuctionatorAge(itemID), "Auctionator" end
    end
end

-- Lesser essences can be combined 3:1 into greater ones, so a lesser is worth at least greater/3.
-- Returns the price, its age and its source (those of the greater essence when the cap applies).
local function GetMatPrice(itemID)
    local price, age, source = GetPrice(itemID)
    local greater = Opt("essenceCap", true) and DATA.DisenchantingMatMapping[itemID]
    if greater then
        local gp, gage, gsource = GetPrice(greater)
        if price and gp and price * 3 > gp then
            return math.floor(gp / 3), gage, gsource
        end
    end
    return price, age, source
end

-- EverlookDB Auctions draws its own "Disenchant" line whenever it can price the item (its "disenchant" tooltip
-- setting, on unless turned off). Then this addon adds no second one: only the breakdown and your own results.
local function EDBAShowsLine(link)
    local api = EDBA()
    if not (api and api.disenchant) then return false end
    local saved = EverlookAuctionsDB
    local tip = type(saved) == "table" and saved.tip
    if type(tip) == "table" and tip.disenchant == false then return false end
    local ok, value = pcall(api.disenchant, link)
    return ok and value ~= nil
end

-- The oldest scan behind a price, as words: "scanned today", "scanned 3 days ago".
local function AgeText(oldest)
    if oldest == nil then return nil end
    if oldest == false then return "scanned 3+ weeks ago" end
    if oldest == 0 then return "scanned today" end
    if oldest == 1 then return "scanned yesterday" end
    return ("scanned %d days ago"):format(oldest)
end

-- Keeps the oldest of several ages (false = older than Auctionator tracks, the oldest of all).
local function Older(a, b)
    if a == false or b == false then return false end
    if a == nil then return b end
    if b == nil then return a end
    return math.max(a, b)
end

-- Shields and held-in-off-hand items use the weapon tables (classic-db); subclassID/equipLoc may be nil.
local function TableClass(classID, subclassID, equipLoc)
    if classID == 4 and (subclassID == 6 or equipLoc == "INVTYPE_HOLDABLE") then return 2 end
    return classID
end

local function FindEntry(classID, rarity, itemLevel, subclassID, equipLoc)
    local byClass = DATA.DisenchantingProbability and DATA.DisenchantingProbability[TableClass(classID, subclassID, equipLoc)]
    for _, entry in pairs((byClass and byClass[rarity]) or {}) do
        if itemLevel >= entry[KEYS.LOW] and itemLevel <= entry[KEYS.HIGH] then
            return entry
        end
    end
end

local function IsDisenchantable(classID, rarity)
    return (classID == 2 or classID == 4)
        and rarity >= 2 and rarity <= 4
end

local function MatName(itemID)
    return C_Item.GetItemInfo(itemID) or DATA.DisenchantingItemName[itemID] or ("item " .. itemID)
end

-- The shared tooltip layout (Libs/EverlookUI/EverlookTooltip.lua): labels left, values right, the same order and
-- money format as the other EverlookDB addons.
local Tip = LibStub("EverlookTooltip-1")
local Money = Tip.Money

-- Your logged results (all characters): this exact item, plus every item in the same
-- class / quality / item-level bracket, which is what actually decides the outcome.
local function ObservedLine(t, which, obs)
    local value, missing = 0, false
    for matID, m in pairs(obs.mats) do
        local price = GetMatPrice(matID)
        if price then value = value + price * m.total / obs.count else missing = true end
    end
    local note = Tip.Join(which, obs.count .. (obs.count == 1 and " disenchant" or " disenchants"), missing and value > 0 and "partial" or nil)
    if value > 0 then
        t:Line("Your disenchants", Money(math.floor(value), { approx = true }), { note = note })
    else
        t:Line("Your disenchants", "no prices", { note = note, stale = true })
    end

    if ShowBreakdown() then
        for matID, m in pairs(obs.mats) do
            t:Detail(("%d%%  %s"):format(math.floor(m.hits / obs.count * 100 + 0.5), MatName(matID)),
                ("%.1f avg when it drops"):format(m.total / m.hits), { always = true })
        end
    end
end

-- info: Analyze(link). The sums are kept on info until a new disenchant is logged, so a tooltip refreshing
-- several times a second doesn't go through the whole log each time.
local function AddObserved(t, info)
    if not DisenchantValue.ObservedFor or not Opt("observed", true) then return end
    local obs = info.observed
    if not obs or obs.generation ~= DisenchantValue.generation then
        local entry = info.entry
        local low, high = entry and entry[KEYS.LOW], entry and entry[KEYS.HIGH]
        local mine, bracket = DisenchantValue.ObservedFor(info.itemID, info.classID, info.rarity, low, high)
        obs = { generation = DisenchantValue.generation, mine = mine, bracket = bracket, low = low, high = high }
        info.observed = obs
    end
    if obs.mine then ObservedLine(t, "this item", obs.mine) end
    if obs.bracket and (not obs.mine or obs.bracket.count > obs.mine.count) then
        ObservedLine(t, ("item level %d-%d"):format(obs.low, obs.high), obs.bracket)
    end
end

-- What the tooltip contributions need to know about an item, worked out once per link: every contribution (and
-- every tooltip refresh of the same item) reuses it. nil when the item can't be disenchanted.
local cache = { link = nil, info = nil }
local function Analyze(link)
    if cache.link == link and cache.info then return cache.info end
    local _, _, rarity, _, _, _, _, _, equipLoc, _, _, classID, subclassID = C_Item.GetItemInfo(link)
    if not rarity or not IsDisenchantable(classID, rarity) then return nil end -- not cached yet: ask again next time
    local itemLevel = (C_Item.GetDetailedItemLevelInfo or GetDetailedItemLevelInfo)(link)
    local info = {
        itemID = C_Item.GetItemInfoInstant(link), classID = classID, rarity = rarity, itemLevel = itemLevel,
        entry = itemLevel and FindEntry(classID, rarity, itemLevel, subclassID, equipLoc),
    }
    cache.link, cache.info = link, info
    return info
end

local hintItem -- the one item this session that showed the "no prices" hint

-- The "Disenchant" value line (t: the shared layout's line collector). Skipped when EverlookDB Auctions shows its own.
local function AddLines(t, link)
    if not link or not Opt("tooltip", true) then return end
    local info = Analyze(link)
    if not info then return end
    info.lineShown = false
    if EDBAShowsLine(link) then info.lineShown = true return end
    local entry = info.entry
    if not entry then
        t:Line("Disenchant", "no data", { note = "classic-db", stale = true })
        return
    end

    -- entry = { lowIlvl, highIlvl, pct, count, matID, pct, count, matID, ... }
    local total, missing, oldest, sources, seen = 0, false, nil, {}, {}
    for i = 3, #entry, 3 do
        local pct, count, matID = entry[i], entry[i + 1], entry[i + 2]
        if pct > 0 then
            local price, age, source = GetMatPrice(matID)
            if price then
                total = total + pct * count * price
                oldest = Older(oldest, age)
                if not seen[source] then seen[source] = true; sources[#sources + 1] = source end
            else
                missing = true
            end
        end
    end
    total = math.floor(total / 100)

    if total > 0 then
        t:Line("Disenchant", Money(total, { approx = true }), {
            note = Tip.Join(table.concat(sources, " + "), missing and "partial" or nil, AgeText(oldest)),
            stale = oldest == false or (oldest or 0) > 0,
        })
    elseif not hintItem or hintItem == info.itemID then
        -- no prices at all: say how to get them once a session (on the first such item), not on every green item
        hintItem = info.itemID
        t:Line("Disenchant", "no prices", { note = "scan the auction house with EverlookDB Auctions or Auctionator", stale = true })
    else
        return
    end
    info.lineShown = true
end

-- The per-material breakdown, right under whichever "Disenchant" line is shown (this addon's or EverlookDB Auctions').
local function AddBreakdown(t, link)
    if not link or not Opt("tooltip", true) or not ShowBreakdown() then return end
    local info = Analyze(link)
    local entry = info and info.lineShown and info.entry
    if not entry then return end
    for i = 3, #entry, 3 do
        local pct, count, matID = entry[i], entry[i + 1], entry[i + 2]
        if pct > 0 then
            local price = GetMatPrice(matID)
            -- the price alone on the right (its coins line up with the other prices), "each" as the note
            t:Detail(("%g%%  %gx %s"):format(math.floor(pct * 100) / 100, count, MatName(matID)),
                price and Money(price) or "no price", { always = true, note = price and "each" or nil, stale = not price })
        end
    end
end

-- The tooltip's item link, unless the game hid it; only the main and the linked-item tooltips.
local function LinkOf(ctx)
    if ctx.tooltip ~= GameTooltip and ctx.tooltip ~= ItemRefTooltip then return nil end
    return ctx.link
end

-- Three contributions: the value line, then (after EverlookDB Auctions' line, which has the same order) the breakdown,
-- and your own results after every addon's value lines (Tip.ORDER.disenchantOwn).
Tip:Register({ id = "DisenchantValue.value", kind = "item", order = Tip.ORDER.disenchant, add = function(t, ctx)
    AddLines(t, LinkOf(ctx))
end })
Tip:Register({ id = "DisenchantValue.breakdown", kind = "item", order = Tip.ORDER.disenchant + 0.5, add = function(t, ctx)
    AddBreakdown(t, LinkOf(ctx))
end })
Tip:Register({ id = "DisenchantValue.observed", kind = "item", order = Tip.ORDER.disenchantOwn, add = function(t, ctx)
    local link = LinkOf(ctx)
    if not link or not Opt("tooltip", true) then return end
    local info = Analyze(link)
    if not info then return end
    AddObserved(t, info)
end })
