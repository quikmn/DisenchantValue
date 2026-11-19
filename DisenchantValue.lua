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

local function GetPrice(itemID)
    if not (Auctionator and Auctionator.API and Auctionator.API.v1) then return nil end
    return Auctionator.API.v1.GetAuctionPriceByItemID("DisenchantValue", itemID)
end

-- Days since Auctionator last saw the item; false when it is older than Auctionator tracks (3 weeks).
local function GetAge(itemID)
    local api = Auctionator and Auctionator.API and Auctionator.API.v1
    if not (api and api.GetAuctionAgeByItemID) then return nil end
    local ok, days = pcall(api.GetAuctionAgeByItemID, "DisenchantValue", itemID)
    if not ok then return nil end
    return days or false
end

-- Lesser essences can be combined 3:1 into greater ones, so a lesser is worth at least greater/3.
-- Returns the price and the item whose scan it came from.
local function GetMatPrice(itemID)
    local price = GetPrice(itemID)
    local greater = Opt("essenceCap", true) and DATA.DisenchantingMatMapping[itemID]
    if greater then
        local gp = GetPrice(greater)
        if price and gp and price * 3 > gp then
            return math.floor(gp / 3), greater
        end
    end
    return price, itemID
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

local function AddObserved(t, link, classID, rarity, itemLevel, entry)
    if not DisenchantValue.Observed or not Opt("observed", true) then return end
    local itemID = C_Item.GetItemInfoInstant(link)

    local mine = DisenchantValue.Observed(function(id) return id == itemID end)
    if mine then ObservedLine(t, "this item", mine) end

    if entry then
        local low, high = entry[KEYS.LOW], entry[KEYS.HIGH]
        local bracket = DisenchantValue.Observed(function(_, e)
            return e.classID == classID and e.quality == rarity and e.ilvl and e.ilvl >= low and e.ilvl <= high
        end)
        if bracket and (not mine or bracket.count > mine.count) then
            ObservedLine(t, ("item level %d-%d"):format(low, high), bracket)
        end
    end
end

-- t: the shared layout's line collector. Your own results are a separate contribution (Tip.ORDER.disenchantOwn), so
-- they come after every addon's value lines.
local function AddLines(t, link)
    if not link or not Opt("tooltip", true) then return end
    local _, _, rarity, _, _, _, _, _, equipLoc, _, _, classID, subclassID = C_Item.GetItemInfo(link)
    if not rarity or not IsDisenchantable(classID, rarity) then return end

    local itemLevel = (C_Item.GetDetailedItemLevelInfo or GetDetailedItemLevelInfo)(link)
    local entry = itemLevel and FindEntry(classID, rarity, itemLevel, subclassID, equipLoc)
    if not entry then
        t:Line("Disenchant", "no data", { note = "classic-db", stale = true })
        return
    end

    -- entry = { lowIlvl, highIlvl, pct, count, matID, pct, count, matID, ... }
    local total, missing, oldest = 0, false, nil
    for i = 3, #entry, 3 do
        local pct, count, matID = entry[i], entry[i + 1], entry[i + 2]
        if pct > 0 then
            local price, from = GetMatPrice(matID)
            if price then
                total = total + pct * count * price
                oldest = Older(oldest, GetAge(from))
            else
                missing = true
            end
        end
    end
    total = math.floor(total / 100)

    if total > 0 then
        t:Line("Disenchant", Money(total, { approx = true }), {
            note = Tip.Join("Auctionator", missing and "partial" or nil, AgeText(oldest)),
            stale = oldest == false or (oldest or 0) > 0,
        })
    else
        t:Line("Disenchant", "no prices", { note = "scan the AH with Auctionator", stale = true })
    end

    if ShowBreakdown() then
        for i = 3, #entry, 3 do
            local pct, count, matID = entry[i], entry[i + 1], entry[i + 2]
            if pct > 0 then
                local price = GetMatPrice(matID)
                t:Detail(("%g%%  %gx %s"):format(math.floor(pct * 100) / 100, count, MatName(matID)),
                    price and (Money(price) .. " each") or "?", { always = true })
            end
        end
    end
end

-- The tooltip's item link, unless the game hid it; only the main and the linked-item tooltips.
local function LinkOf(ctx)
    if ctx.tooltip ~= GameTooltip and ctx.tooltip ~= ItemRefTooltip then return nil end
    return ctx.link
end

Tip:Register({ id = "DisenchantValue.value", kind = "item", order = Tip.ORDER.disenchant, add = function(t, ctx)
    AddLines(t, LinkOf(ctx))
end })
Tip:Register({ id = "DisenchantValue.observed", kind = "item", order = Tip.ORDER.disenchantOwn, add = function(t, ctx)
    local link = LinkOf(ctx)
    if not link or not Opt("tooltip", true) then return end
    local _, _, rarity, _, _, _, _, _, equipLoc, _, _, classID, subclassID = C_Item.GetItemInfo(link)
    if not rarity or not IsDisenchantable(classID, rarity) then return end
    local itemLevel = (C_Item.GetDetailedItemLevelInfo or GetDetailedItemLevelInfo)(link)
    AddObserved(t, link, classID, rarity, itemLevel, itemLevel and FindEntry(classID, rarity, itemLevel, subclassID, equipLoc))
end })
