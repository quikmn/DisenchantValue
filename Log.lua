-- Records every disenchant on every character into one account-wide DB (DisenchantValueDB).
--
-- DisenchantValueDB = {
--   version = 2,
--   items = { [itemID] = { name, ilvl, quality, classID, count, mats = { [matID] = { total, hits, qty = { [n] = times } } } } },
--   log   = { { t, char, itemID, link, ilvl, mats = { [matID] = n } }, ... }   -- newest last, capped
-- }

local DV = DisenchantValue
local DISENCHANT_SPELL = 13262
local LOG_CAP = 10000 -- default; the "Disenchants kept in the log" option (db.logCap) overrides it
local LOOT_WINDOW = 5 -- seconds between the cast finishing and the loot window

local pending      -- item being disenchanted: { link, itemID, ilvl, quality, classID }
local awaitingLoot -- pending item whose cast has succeeded, waiting for the loot window

local function IsDisenchant(spellID)
    if spellID == DISENCHANT_SPELL then return true end
    local name = (C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spellID))
        or (GetSpellInfo and GetSpellInfo(spellID))
    local deName = (C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(DISENCHANT_SPELL))
        or (GetSpellInfo and GetSpellInfo(DISENCHANT_SPELL))
    return name ~= nil and name == deName
end

-- Item quality from the link's colour, for items the game hasn't cached yet.
local QUALITY_BY_COLOR = { ["9d9d9d"] = 0, ffffff = 1, ["1eff00"] = 2, ["0070dd"] = 3, a335ee = 4, ff8000 = 5 }
local function QualityFromLink(link)
    local c = link:match("|c%x%x(%x%x%x%x%x%x)")
    return c and QUALITY_BY_COLOR[c:lower()]
end

-- What we know about an item: class from GetItemInfoInstant (always there), quality from the link's colour when the
-- item isn't cached yet, so an uncached item is still logged with its class and quality.
local function Describe(link)
    if not link then return end
    local itemID, _, _, _, _, instantClass = C_Item.GetItemInfoInstant(link)
    local name, _, quality, _, _, _, _, _, _, _, _, classID = C_Item.GetItemInfo(link)
    local ilvl = (C_Item.GetDetailedItemLevelInfo or GetDetailedItemLevelInfo)(link)
    return {
        link = link, itemID = itemID, name = name or link:match("|h%[(.-)%]|h"),
        quality = quality or QualityFromLink(link), classID = classID or instantClass, ilvl = ilvl,
    }
end

-- Only weapons and armour of uncommon to epic quality can be disenchanted. Unknown (nil) counts as possible.
local function CanDisenchant(item)
    if item.classID ~= nil and item.classID ~= 2 and item.classID ~= 4 then return false end
    if item.quality ~= nil and (item.quality < 2 or item.quality > 4) then return false end
    return true
end
DV.CanDisenchant = CanDisenchant

-- Primary: the bag slot clicked while the Disenchant cursor is up.
hooksecurefunc(C_Container, "UseContainerItem", function(bag, slot)
    if SpellIsTargeting and SpellIsTargeting() then
        local item = Describe(C_Container.GetContainerItemLink(bag, slot))
        pending = item and CanDisenchant(item) and item or nil
    end
end)

-- Fallback: UNIT_SPELLCAST_SENT carries the target's name; find it in the bags.
local function FindInBags(itemName)
    if not itemName or itemName == "" then return end
    for bag = 0, (NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4) do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local link = C_Container.GetContainerItemLink(bag, slot)
            if link and C_Item.GetItemInfo(link) == itemName then
                return link
            end
        end
    end
end

-- The chat line, once every material has a name: from the game's cache or the bundled names at once, otherwise
-- after the game has loaded the item (5 seconds at most; then "item 12345" stands in).
local function Announce(link, mats)
    local waiting = {}
    for matID in pairs(mats) do
        if not (C_Item.GetItemInfo(matID) or DisenchantValueData.DisenchantingItemName[matID]) then waiting[#waiting + 1] = matID end
    end
    local said = false
    local function say()
        if said then return end
        said = true
        print(("|cffa335eeDisenchantValue|r: %s -> %s"):format(link, DV.MatsText(mats)))
    end
    if #waiting == 0 or not (Item and Item.CreateFromItemID) then say() return end
    local left = #waiting
    for _, matID in ipairs(waiting) do
        Item:CreateFromItemID(matID):ContinueOnItemLoad(function()
            left = left - 1
            if left == 0 then say() end
        end)
    end
    C_Timer.After(5, say)
end

local function Record(item, mats)
    -- by now the game has usually cached the item: fill in what was missing when the cast started
    local fresh = Describe(item.link)
    if fresh then
        for k, v in pairs(fresh) do if item[k] == nil then item[k] = v end end
    end
    if not CanDisenchant(item) then return end -- a crate or bag opened right after the cast, not a disenchant

    local db = DisenchantValueDB
    local char = UnitName("player") .. "-" .. (GetNormalizedRealmName() or GetRealmName() or "?")

    local entry = db.items[item.itemID]
    if not entry then
        entry = { count = 0, mats = {} }
        db.items[item.itemID] = entry
    end
    entry.name, entry.ilvl, entry.quality, entry.classID = item.name, item.ilvl, item.quality, item.classID
    entry.count = entry.count + 1

    for matID, n in pairs(mats) do
        local m = entry.mats[matID]
        if not m then
            m = { total = 0, hits = 0, qty = {} }
            entry.mats[matID] = m
        end
        m.total = m.total + n
        m.hits = m.hits + 1
        m.qty[n] = (m.qty[n] or 0) + 1
    end

    DV.Changed()
    table.insert(db.log, { t = time(), char = char, itemID = item.itemID, link = item.link, ilvl = item.ilvl, mats = mats })
    DV.TrimLog()

    if db.announce == true then Announce(item.link, mats) end
end

local function ReadLoot()
    if not awaitingLoot or GetTime() - awaitingLoot.at > LOOT_WINDOW then
        awaitingLoot = nil
        return
    end
    local item = awaitingLoot.item
    awaitingLoot = nil

    local mats = {}
    for i = 1, GetNumLootItems() do
        local link = GetLootSlotLink(i)
        local itemID = link and C_Item.GetItemInfoInstant(link)
        if itemID then
            local _, _, quantity = GetLootSlotInfo(i)
            mats[itemID] = (mats[itemID] or 0) + (quantity or 1)
        end
    end
    if next(mats) then
        Record(item, mats)
    end
end

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterUnitEvent("UNIT_SPELLCAST_SENT", "player")
f:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
f:RegisterUnitEvent("UNIT_SPELLCAST_FAILED", "player")
f:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED", "player")
f:RegisterEvent("LOOT_READY")
f:RegisterEvent("LOOT_OPENED")
f:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        if ... ~= "DisenchantValue" then return end
        DV.InitDB()
    elseif event == "UNIT_SPELLCAST_SENT" then
        local _, target, _, spellID = ...
        if IsDisenchant(spellID) then
            local fromBags = FindInBags(target)
            if not pending or (fromBags and pending.name ~= target) then
                pending = Describe(fromBags)
            end
        end
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        local _, _, spellID = ...
        if IsDisenchant(spellID) and pending and pending.itemID then
            awaitingLoot = { item = pending, at = GetTime() }
            pending = nil
        end
    elseif event == "UNIT_SPELLCAST_FAILED" or event == "UNIT_SPELLCAST_INTERRUPTED" then
        local _, _, spellID = ...
        if IsDisenchant(spellID) then pending = nil end
    else -- LOOT_READY / LOOT_OPENED: whichever comes first reads the window
        ReadLoot()
    end
end)

-- Aggregate observations into { count, mats = { [matID] = { total, hits } } }; nil when there are none.
local function Add(out, entry)
    out.count = out.count + entry.count
    for matID, m in pairs(entry.mats) do
        local o = out.mats[matID] or { total = 0, hits = 0 }
        o.total, o.hits = o.total + m.total, o.hits + m.hits
        out.mats[matID] = o
    end
end

-- For a tooltip, in one pass over the items: this item's results, and its class/quality/item-level bracket's
-- (low..high; nil = no bracket).
function DV.ObservedFor(itemID, classID, quality, low, high)
    local db = DisenchantValueDB
    if not db then return end
    local mine, bracket = { count = 0, mats = {} }, { count = 0, mats = {} }
    for id, entry in pairs(db.items) do
        if id == itemID then Add(mine, entry) end
        if low and entry.classID == classID and entry.quality == quality and entry.ilvl
            and entry.ilvl >= low and entry.ilvl <= high then
            Add(bracket, entry)
        end
    end
    return mine.count > 0 and mine or nil, bracket.count > 0 and bracket or nil
end

-- Goes up whenever the logged results change, so tooltips can keep their sums until then.
DV.generation = 0
function DV.Changed() DV.generation = DV.generation + 1 end

DV.DEFAULTS = {
    announce = false,      -- chat line after each disenchant (off by default since version 2 of the saved data)
    tooltip = true,        -- "Disenchant ~Xg" on item tooltips
    breakdown = "shift",   -- the per-material lines: "shift" (hold Shift), "always" or "never"
    observed = true,       -- your own logged results on tooltips
    essenceCap = true,     -- price a lesser essence at no more than a third of the greater one
    logCap = LOG_CAP,      -- disenchants kept in the log (the per-item totals are kept forever)
}

-- Set up DisenchantValueDB: data tables, then any missing setting from DV.DEFAULTS (saved ones are kept).
function DV.InitDB()
    local db = type(DisenchantValueDB) == "table" and DisenchantValueDB or {}
    DisenchantValueDB = db
    -- version 1 (v0.1.0) saved the chat line as on for everyone; turn it off once, as the new default
    if db.version == 1 and db.announce == true then db.announce = false end
    db.version = 2
    db.items = db.items or {}
    db.log = db.log or {}
    for k, v in pairs(DV.DEFAULTS) do
        if db[k] == nil then db[k] = v end
    end
    DV.ForgetNonGear(db)
    DV.Changed()
    return db
end

-- v0.1.0 could log an item that can't be disenchanted (a crate opened right after a cast). Those entries go.
function DV.ForgetNonGear(db)
    local gone
    for itemID, entry in pairs(db.items) do
        if not CanDisenchant(entry) then
            gone = gone or {}
            gone[itemID] = true
            db.items[itemID] = nil
        end
    end
    if not gone then return end
    local kept = {}
    for _, e in ipairs(db.log) do if not gone[e.itemID] then kept[#kept + 1] = e end end
    db.log = kept
end

function DV.TrimLog()
    local db = DisenchantValueDB
    local cap = db.logCap or LOG_CAP
    local log = db.log
    local n = #log
    local over = n - cap
    if over > 0 then
        -- shift once instead of table.remove(log, 1) per entry (that is slow on a 50,000-entry log)
        for i = 1, n - over do log[i] = log[i + over] end
        for i = n - over + 1, n do log[i] = nil end
    end
end

-- "3x Strange Dust, 1x Lesser Magic Essence"
function DV.MatsText(mats)
    local parts = {}
    for matID, n in pairs(mats or {}) do
        parts[#parts + 1] = n .. "x " .. (C_Item.GetItemInfo(matID) or DisenchantValueData.DisenchantingItemName[matID] or ("item " .. matID))
    end
    table.sort(parts)
    return table.concat(parts, ", ")
end

-- Totals for the window and /dv summary: disenchants, different items, characters.
function DV.Summary()
    local db = DisenchantValueDB
    local items, total, chars, nChars = 0, 0, {}, 0
    for _, entry in pairs(db.items) do items, total = items + 1, total + entry.count end
    for _, e in ipairs(db.log) do
        if not chars[e.char] then chars[e.char] = true; nChars = nChars + 1 end
    end
    return total, items, nChars
end