-- DisenchantValue: settings window (/dv), chat commands and the Settings > AddOns entry, on EverlookUI.
local ADDON = ...
local DV = DisenchantValue
local UI = LibStub("EverlookUI-1")
local Esc = UI.Util.Escape

local app = UI:NewApp({
    name = "DisenchantValue",
    addon = ADDON,
    slash = "/dv",
    tagline = "What an item disenchants into, priced from your EverlookDB Auctions or Auctionator scans, plus a log of every disenchant you do.",
    accent = { 0.639, 0.208, 0.933 }, -- epic purple, as in its chat lines
    position = function() return DisenchantValueDB end,
    onHide = function() DV.TrimLog() end,
})
DV.app = app

local function db() return DisenchantValueDB end

-- the shared EverlookTooltip switch: an opaque tooltip background
local Tip = LibStub("EverlookTooltip-1", true)
if Tip and Tip.SolidSetting then Tip:SolidSetting(app, db) end

app:Setting({
    key = "tooltip", type = "bool", label = "Show the disenchant value on item tooltips", keywords = { "price", "value", "worth" },
    get = function() return db().tooltip end, set = function(v) db().tooltip = v end,
})
app:Setting({
    key = "breakdown", type = "choice", label = "What each material is worth, on the tooltip", keywords = { "breakdown", "materials", "mats", "shift", "detail" }, width = 300,
    choices = {
        { value = "shift", text = "While Shift is held" },
        { value = "always", text = "Always" },
        { value = "never", text = "Never" },
    },
    get = function() return db().breakdown end, set = function(v) db().breakdown = v end,
    disabled = function() return not db().tooltip end,
})
app:Setting({
    key = "observed", type = "bool", label = "Show your own results on tooltips", keywords = { "history", "observed", "my results", "statistics" },
    desc = "\"Your disenchants of this item\" and \"Your disenchants, item level x-y\": what your characters actually got, priced the same way.",
    get = function() return db().observed end, set = function(v) db().observed = v end,
    disabled = function() return not db().tooltip end,
})
app:Setting({
    key = "essencecap", type = "bool", label = "Price lesser essences at a third of a greater one at most", keywords = { "cap", "essence", "combine" },
    desc = "Three lesser essences combine into one greater, so a lesser essence is never worth more than a third of it.",
    get = function() return db().essenceCap end, set = function(v) db().essenceCap = v end,
})
app:Setting({
    key = "announce", type = "bool", label = "Chat line after each disenchant", keywords = { "announce", "message", "notify", "quiet", "spam" },
    get = function() return db().announce ~= false end, set = function(v) db().announce = v end,
})
app:Setting({
    key = "logcap", type = "number", label = "Disenchants kept in the log", keywords = { "limit", "history", "size", "max", "trim" }, min = 1000, max = 50000, step = 1000,
    desc = "The oldest go first, when you close this window (so dragging the slider down and back loses nothing). The per-item results on tooltips are kept no matter what.",
    get = function() return db().logCap end, set = function(v) db().logCap = v end,
    after = function() if not app:IsShown() then DV.TrimLog() end end, -- from chat: now; from the window: on close
})

-- Where prices come from: EverlookDB Auctions first, then Auctionator; either is enough.
local function PriceStatus()
    local edba = EverlookDBAuctionsAPI ~= nil
    local auc = Auctionator and Auctionator.API and Auctionator.API.v1 and true
    if edba and auc then return "|cff62cf88EverlookDB Auctions and Auctionator|r: EverlookDB Auctions first, Auctionator for the rest." end
    if edba then return "|cff62cf88EverlookDB Auctions|r: prices come from its scans." end
    if auc then return "|cff62cf88Auctionator|r: prices come from its scans." end
    return "|cffef5d5dnone loaded|r: install EverlookDB Auctions or Auctionator and scan the auction house."
end

local function Summary()
    local total, items, chars = DV.Summary()
    return ("%d disenchants logged, %d different items, %d characters."):format(total, items, chars)
end

local function Recent(n)
    local log, out = db().log, {}
    for i = #log, math.max(1, #log - n + 1), -1 do out[#out + 1] = log[i] end
    return out
end

-- /dv status: the version, the totals and where prices come from (/dv summary still works).
app:StatusLines(function()
    local out = { Summary(), "Prices: " .. PriceStatus() }
    local nameless = DV.NamelessLogged()
    if nameless > 0 then
        out[#out + 1] = nameless .. " disenchants were logged without the realm (the game didn't say it); they are kept as they are."
    end
    return out
end)
app:Command("summary", "summary", "how much is logged", function()
    app:Print(Summary())
end).hidden = true
app:Command("recent", "recent", "your last 10 disenchants in chat", function()
    local list = Recent(10)
    if #list == 0 then app:Print("nothing logged yet.") return end
    for i = #list, 1, -1 do
        local e = list[i]
        DEFAULT_CHAT_FRAME:AddMessage(("%s  %s  %s -> %s"):format(date("%m-%d %H:%M", e.t), Esc(e.char), e.link or tostring(e.itemID), DV.MatsText(e.mats)))
    end
end)
-- the old name for "/dv announce toggle"
app:Command("quiet", "quiet", "switch the chat line after each disenchant on or off", function()
    local def = app:GetSetting("announce")
    app:Apply(def, not def.get())
    app:Print("chat line " .. (def.get() and "on" or "off"))
end).hidden = true

app:Section("overview", "Overview", function(stack)
    UI.Header(stack, "Overview", "Item tooltips get \"Disenchant ~Xg\": the classic disenchant odds times auction house prices. With EverlookDB Auctions' own disenchant line on, that line is the one you see, with this addon's breakdown and your own results under it.")
    UI.Stat(stack, "Prices", PriceStatus)
    UI.Stat(stack, "Logged", Summary)
    UI.Stat(stack, "Latest", function()
        local e = db().log[#db().log]
        return e and (date("%Y-%m-%d %H:%M", e.t) .. "  " .. (e.link or tostring(e.itemID))) or "nothing yet"
    end)
    stack:Space(6)
    UI.Note(stack, "Every disenchant on every character goes into one account-wide log, kept only on this computer. Tooltips then also show what your characters actually got, for that item and for its item-level bracket (which is what decides the outcome).")
    UI.Header(stack, "Chat commands")
    UI.Note(stack, "/dv  this window\n/dv status, /dv recent  totals and the last 10 in chat\n/dv announce off  no chat line after each disenchant\n/dv breakdown always  change a setting (/dv get lists them)\n/dv search <words>  find a setting\n/dv help  all of this in chat")
end)

app:Section("recent", "Recent", function(stack)
    UI.Header(stack, "Recent disenchants", "Newest first. Hover one for the item.")
    UI.List(stack, {
        items = function() return Recent(100) end,
        empty = "Nothing logged yet. Disenchant something!",
        rowHeight = 40,
        title = function(e) return e.link or ("item " .. tostring(e.itemID)) end,
        detail = function(e) return date("%Y-%m-%d %H:%M", e.t) .. "  " .. Esc(e.char or "?") .. "  ->  " .. DV.MatsText(e.mats) end,
        tooltip = function(e, row)
            if e.link then
                GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
                GameTooltip:SetHyperlink(e.link)
                GameTooltip:Show()
            end
        end,
        max = 100,
    })
end)

app:Section("options", "Options", function(stack)
    UI.Header(stack, "Tooltip")
    app:Widget(stack, "tooltip")
    app:Widget(stack, "breakdown")
    app:Widget(stack, "observed")
    if app:GetSetting("tipsolid") then app:Widget(stack, "tipsolid") end
    app:Widget(stack, "essencecap")
    UI.Header(stack, "Log")
    app:Widget(stack, "announce")
    app:Widget(stack, "logcap")
    UI.ButtonRow(stack, {
        { label = "Forget every disenchant", width = 220, confirm = true, onClick = function()
            local d = db()
            d.items, d.log = {}, {}
            DV.Changed()
            app:Refresh()
            app:Print("the log is empty.")
        end, desc = "Empties the log and the per-item results on every character. Can't be undone.",
        keywords = { "reset", "clear", "delete", "wipe", "history" } },
    })
end)

app:RegisterSlash("DISENCHANTVALUE") -- /dv
