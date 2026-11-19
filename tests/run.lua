-- Offline tests for DisenchantValue against wowmock.lua: settings defaults and old saved data, tooltip
-- lines in each mode, logging a disenchant, the log cap, every slash command and the window.
local ROOT = ...
local ADDON = "DisenchantValue"
local failures, passes = {}, 0

local function step(name, fn)
	local ok, err = pcall(fn)
	if ok then
		passes = passes + 1
		print("  ok   " .. name)
	else
		failures[#failures + 1] = name .. ": " .. tostring(err)
		print("  FAIL " .. name .. "\n         " .. tostring(err))
	end
end
local function check(cond, msg) if not cond then error(msg, 2) end end
local function last() return MOCK.log[#MOCK.log] or "" end

-- Extra API
time, date = os.time, os.date
GetNormalizedRealmName = function() return "MockRealm" end
local ITEM = "|cff1eff00|Hitem:1234::::::::20:::::|h[Test Sword]|h|r"
C_Item = {
	GetItemInfo = function(x)
		if x == ITEM or x == 1234 then return "Test Sword", ITEM, 2, 20, 15, "Weapon", "One-Handed Swords", 1, "", 0, 0, 2 end
		if type(x) == "number" then return "Mat " .. x end
	end,
	GetItemInfoInstant = function(x) if x == ITEM then return 1234 end local id = tostring(x):match("item:(%d+)"); return tonumber(id) end,
	GetDetailedItemLevelInfo = function() return 20 end,
}
C_Container = {
	UseContainerItem = function() end,
	GetContainerItemLink = function(bag, slot) if bag == 0 and slot == 1 then return ITEM end end,
	GetContainerNumSlots = function() return 4 end,
}
SpellIsTargeting = function() return MOCK.targeting end
C_Spell.GetSpellName = function(id) if id == 13262 then return "Disenchant" end return "Other" end
local loot = {}
GetNumLootItems = function() return #loot end
GetLootSlotLink = function(i) return loot[i] and ("|Hitem:" .. loot[i][1] .. "|h") end
GetLootSlotInfo = function(i) return nil, nil, loot[i][2] end
GetMoneyString = function(c) return c .. "c" end
Auctionator = { API = { v1 = { GetAuctionPriceByItemID = function() return 100 end } } }
local tipLines = {}
ItemRefTooltip = CreateFrame("GameTooltip", "ItemRefTooltip")
rawset(GameTooltip, "AddDoubleLine", function(_, l, r) tipLines[#tipLines + 1] = { l, r } end)
local postCall
Enum.TooltipDataType = { Item = 0, Unit = 2 }
TooltipDataProcessor = { AddTooltipPostCall = function(typ, fn) if typ == 0 then postCall = fn end end }

local globalWrites = {}
local addonEnv = setmetatable({}, { __index = _G, __newindex = function(_, k, v) globalWrites[k] = true; _G[k] = v end })

local function tooltip(shift, data)
	tipLines = {}
	MOCK.mods.shift = shift
	postCall(GameTooltip, data or { hyperlink = ITEM })
	MOCK.mods.shift = false
	return tipLines
end

step("load TOC files; old saved data keeps its values and gets the new settings", function()
	DisenchantValueDB = { version = 1, announce = false, items = { [99] = { count = 2, mats = {} } }, log = { { t = 1, char = "Old-Realm", itemID = 99, mats = {} } } }
	local toc = assert(io.open(ROOT .. "/" .. ADDON .. ".toc")):read("*a")
	for line in toc:gmatch("[^\r\n]+") do
		if not line:match("^%s*#") and line:match("%.lua%s*$") then
			local chunk, err = loadfile(ROOT .. "/" .. line:gsub("\\", "/"):gsub("%s+$", ""))
			if not chunk then error("syntax: " .. err) end
			setfenv(chunk, addonEnv)
			chunk(ADDON, {})
		end
	end
	MOCK.Fire("ADDON_LOADED", ADDON)
	local db = DisenchantValueDB
	check(db.announce == false, "announce=false lost")
	check(db.items[99] and #db.log == 1, "data lost")
	check(db.tooltip == true and db.breakdown == "shift" and db.observed == true and db.essenceCap == true and db.logCap == 10000, "new defaults missing")
	check(postCall, "tooltip hook missing")
end)

step("a fresh install gets every default, with the chat line on", function()
	local keep = DisenchantValueDB
	DisenchantValueDB = nil
	DisenchantValue.InitDB()
	check(DisenchantValueDB.announce == true and DisenchantValueDB.logCap == 10000 and #DisenchantValueDB.log == 0, "fresh defaults")
	DisenchantValueDB = keep
end)

step("tooltip: value line; breakdown with Shift, always or never; off", function()
	local l = tooltip(false)
	check(#l >= 1 and l[1][1]:find("Disenchant", 1, true) and l[1][2]:find("c", 1, true), "no value line")
	local plain = #l
	check(#tooltip(true) > plain, "no breakdown with Shift")
	SlashCmdList.DISENCHANTVALUE("breakdown always")
	check(DisenchantValueDB.breakdown == "always" and #tooltip(false) > plain, "always")
	SlashCmdList.DISENCHANTVALUE("breakdown never")
	check(#tooltip(true) == plain, "never")
	SlashCmdList.DISENCHANTVALUE("breakdown shift")
	SlashCmdList.DISENCHANTVALUE("tooltip off")
	check(#tooltip(true) == 0, "tooltip off still adds lines")
	SlashCmdList.DISENCHANTVALUE("tooltip on")
end)

step("a disenchant is logged and announced; your result shows on the tooltip", function()
	DisenchantValueDB.announce = true
	local realPrint = print
	print = function(s) MOCK.log[#MOCK.log + 1] = s end -- in game print() goes to chat
	MOCK.targeting = true
	C_Container.UseContainerItem(0, 1) -- the hook was installed on the mock table by hooksecurefunc
	MOCK.targeting = false
	MOCK.Fire("UNIT_SPELLCAST_SENT", "player", "Test Sword", nil, 13262)
	MOCK.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", nil, 13262)
	loot = { { 10940, 3 } }
	MOCK.Fire("LOOT_READY")
	loot = {}
	print = realPrint
	check(DisenchantValueDB.items[1234] and DisenchantValueDB.items[1234].count == 1, "not recorded")
	check(last():find("3x Mat 10940", 1, true), "no chat line: " .. last())
	local found
	for _, line in ipairs(tooltip(false)) do if line[1]:find("Your disenchants", 1, true) and line[1]:find("this item", 1, true) then found = true end end
	check(found, "own results missing on the tooltip")
	SlashCmdList.DISENCHANTVALUE("observed off")
	for _, line in ipairs(tooltip(false)) do check(not line[1]:find("Your disenchants", 1, true), "own results with observed off") end
	SlashCmdList.DISENCHANTVALUE("observed on")
end)

step("the log cap trims the oldest entries", function()
	local db = DisenchantValueDB
	for i = 1, 1500 do db.log[#db.log + 1] = { t = i, char = "X-Y", itemID = 1, mats = {} } end
	SlashCmdList.DISENCHANTVALUE("logcap 1000")
	check(db.logCap == 1000 and #db.log == 1000, "not trimmed to 1000: " .. #db.log)
	SlashCmdList.DISENCHANTVALUE("logcap 50")
	check(db.logCap == 1000 and last():find("1000 to 50000", 1, true), "range reply: " .. last())
	SlashCmdList.DISENCHANTVALUE("logcap 10000")
end)

step("every slash command", function()
	SlashCmdList.DISENCHANTVALUE("summary")
	check(last():find("disenchants logged", 1, true), "summary: " .. last())
	MOCK.log = {}
	SlashCmdList.DISENCHANTVALUE("recent")
	check(#MOCK.log == 10, "recent lines: " .. #MOCK.log)
	SlashCmdList.DISENCHANTVALUE("quiet")
	check(DisenchantValueDB.announce == false and last():find("off", 1, true), "quiet off")
	SlashCmdList.DISENCHANTVALUE("quiet")
	check(DisenchantValueDB.announce == true and last():find("on", 1, true), "quiet on")
	SlashCmdList.DISENCHANTVALUE("announce off")
	check(DisenchantValueDB.announce == false, "announce off")
	SlashCmdList.DISENCHANTVALUE("announce maybe")
	check(last():find("Example: /dv announce", 1, true), "bad value reply: " .. last())
	SlashCmdList.DISENCHANTVALUE("essencecap off")
	check(DisenchantValueDB.essenceCap == false, "essencecap")
	MOCK.log = {}
	SlashCmdList.DISENCHANTVALUE("help")
	local s = table.concat(MOCK.log, "\n")
	check(s:find("/dv recent", 1, true) and s:find("/dv status", 1, true) and s:find("/dv get [setting]", 1, true)
		and s:find("/dv search <words>", 1, true), "help: " .. s)
	check(not s:find("/dv summary", 1, true) and not s:find("/dv quiet", 1, true), "old names listed in help: " .. s)
	SlashCmdList.DISENCHANTVALUE("settings")
	SlashCmdList.DISENCHANTVALUE("zzz")
	check(last():find("/dv help", 1, true), "unknown")
end)

step("chat commands follow the shared pattern: status, get/set, on/off a setting, suggestions", function()
	MOCK.log = {}
	SlashCmdList.DISENCHANTVALUE("status")
	local s = table.concat(MOCK.log, "\n")
	check(s:find("v0.1.0-test", 1, true) and s:find("disenchants logged", 1, true) and s:find("Auctionator", 1, true), "status: " .. s)
	SlashCmdList.DISENCHANTVALUE("set breakdown always")
	check(DisenchantValueDB.breakdown == "always", "set")
	SlashCmdList.DISENCHANTVALUE("get breakdown")
	check(last():find("always", 1, true), "get: " .. last())
	SlashCmdList.DISENCHANTVALUE("breakdown shift")
	SlashCmdList.DISENCHANTVALUE("off announce")
	check(DisenchantValueDB.announce == false, "off <setting>")
	SlashCmdList.DISENCHANTVALUE("announce toggle")
	check(DisenchantValueDB.announce == true, "<setting> toggle")
	SlashCmdList.DISENCHANTVALUE("off")
	check(last():find("no on/off switch", 1, true) and last():find("/dv get", 1, true), "off without a switch: " .. last())
	SlashCmdList.DISENCHANTVALUE("tooltp off")
	check(last():find("Did you mean /dv tooltip off?", 1, true), "typo: " .. last())
	SlashCmdList.DISENCHANTVALUE("mats")
	check(last():find("Did you mean /dv breakdown?", 1, true), "keyword: " .. last())
	SlashCmdList.DISENCHANTVALUE("recnt")
	check(last():find("Did you mean /dv recent?", 1, true), "command typo: " .. last())
end)

step("window: bare /dv toggles it; every section builds; Escape closes", function()
	SlashCmdList.DISENCHANTVALUE("")
	local f = DisenchantValueOptionsWindow
	check(f and f:IsShown() and f.navButtons, "window with sidebar")
	for _, id in ipairs({ "overview", "recent", "options", "overview" }) do DisenchantValue.app:Open(id) end
	DisenchantValue.app:Open("recent")
	local list
	for _, w in ipairs(DisenchantValue.app.sections.recent.stack.widgets) do if w.rows then list = w end end
	check(list and #list.rows == 100, "recent list rows")
	list.rows[1]:GetScript("OnEnter")(list.rows[1])
	f:GetScript("OnKeyDown")(f, "ESCAPE")
	check(not f:IsShown(), "escape")
end)

step("no taint: only our own globals", function()
	local allowed = { DisenchantValueDB = true, DisenchantValueData = true, DisenchantValue = true, SLASH_DISENCHANTVALUE1 = true, LibStub = true }
	for k in pairs(globalWrites) do check(allowed[k], "addon assigned the global " .. tostring(k)) end
end)

step("the value says how old its prices are", function()
	local v1 = Auctionator.API.v1
	v1.GetAuctionAgeByItemID = function() return 3 end
	local l = tooltip(false)
	check(l[1][1]:find("scanned 3 days ago", 1, true), "no age: " .. tostring(l[1][1]))
	v1.GetAuctionAgeByItemID = function() return 0 end
	check(tooltip(false)[1][1]:find("scanned today", 1, true), "today")
	v1.GetAuctionAgeByItemID = function() return nil end -- older than Auctionator keeps
	check(tooltip(false)[1][1]:find("3+ weeks", 1, true), "old scan shown as fresh")
	v1.GetAuctionAgeByItemID = nil
	check(not tooltip(false)[1][1]:find("scanned", 1, true), "age shown without the API")
end)

step("shared layout: label left and money right, value before your own results, details keep their own setting", function()
	local Tip = LibStub("EverlookTooltip-1")
	local function strip(x) return (x:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T[^|]-UI%-(%a)%a+Icon[^|]*|t", function(c) return c:lower() end)) end
	local l = tooltip(false)
	check(strip(l[1][1]):find("^Disenchant  Auctionator"), "label and note left: " .. strip(l[1][1]))
	check(strip(l[1][2]):find("^~%d+[gsc]"), "approximate money with coins right: " .. strip(l[1][2]))
	local own
	for i, line in ipairs(l) do if line[1]:find("Your disenchants", 1, true) then own = own or i end end
	check(own and own > 1, "your own results come after the value line")
	Tip:SetDetail("shift")
	SlashCmdList.DISENCHANTVALUE("breakdown always")
	local n = #tooltip(false)
	SlashCmdList.DISENCHANTVALUE("breakdown never")
	check(n > #tooltip(false), "breakdown 'always' hidden by the shared Shift setting")
	SlashCmdList.DISENCHANTVALUE("breakdown shift")
	Tip:SetDetail("always")
end)

step("EverlookDB Auctions: its own Disenchant line wins (one line only); its prices come first; Auctionator optional", function()
	local Tip = LibStub("EverlookTooltip-1")
	local function strip(x) return (x:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
	local function count(lines, word)
		local n = 0
		for _, line in ipairs(lines) do if strip(line[1]):find("^" .. word) then n = n + 1 end end
		return n
	end
	-- a stand-in for EverlookDB Auctions: its API and its line at the same order
	EverlookDBAuctionsAPI = { version = 1,
		price = function(id) return 300, 2 * 86400 end,
		disenchant = function(item) return 999, 0 end }
	EverlookAuctionsDB = { tip = {} }
	Tip:Register({ id = "EDBA.test", kind = "item", order = Tip.ORDER.disenchant, add = function(t)
		if EverlookAuctionsDB.tip.disenchant ~= false and EverlookDBAuctionsAPI.disenchant(1) then t:Line("Disenchant", "EDBA") end
	end })
	local l = tooltip(true)
	check(count(l, "Disenchant") == 1, "two Disenchant lines")
	local at
	for i, line in ipairs(l) do if line[2] == "EDBA" then at = i end end
	check(at and l[at + 1] and strip(l[at + 1][1]):find("%%"), "breakdown not right under EverlookDB Auctions' line")
	-- its line turned off: ours is back, priced from its scans
	EverlookAuctionsDB.tip.disenchant = false
	l = tooltip(false)
	check(count(l, "Disenchant") == 1 and strip(l[1][1]):find("EverlookDB", 1, true) and strip(l[1][1]):find("2 days ago", 1, true), "our line with its prices: " .. strip(l[1][1]))
	-- it has no prices: Auctionator's
	EverlookDBAuctionsAPI.price = function() return nil end
	EverlookDBAuctionsAPI.disenchant = function() return nil end
	EverlookAuctionsDB.tip.disenchant = nil
	l = tooltip(false)
	check(count(l, "Disenchant") == 1 and strip(l[1][1]):find("Auctionator", 1, true), "Auctionator fallback: " .. strip(l[1][1]))
	-- without Auctionator: EverlookDB alone is enough
	local auc = Auctionator
	Auctionator = nil
	EverlookDBAuctionsAPI.price = function() return 50, 0 end
	EverlookAuctionsDB.tip.disenchant = false
	l = tooltip(false)
	check(strip(l[1][1]):find("EverlookDB", 1, true) and not strip(l[1][2]):find("no prices", 1, true), "no Auctionator: " .. strip(l[1][1]))
	Auctionator = auc
	Tip:Unregister("EDBA.test")
	EverlookDBAuctionsAPI, EverlookAuctionsDB = nil, nil
	local toc = assert(io.open(ROOT .. "/" .. ADDON .. ".toc")):read("*a")
	check(not toc:find("## Dependencies", 1, true) and toc:find("## OptionalDeps: Auctionator", 1, true), "Auctionator still required in the TOC")
end)

step("a secret item link adds nothing and raises no error", function()
	local errs = #MOCK.errors
	local l = tooltip(false, { hyperlink = MOCK.Secret(ITEM) })
	-- GameTooltip:GetItem in the mock may still give the link; the hook never passes on a secret one
	for _, line in ipairs(l) do check(not MOCK.isSecret(line[1]) and not MOCK.isSecret(line[2]), "secret value on the tooltip") end
	check(#MOCK.errors == errs, table.concat(MOCK.errors, " | "))
end)

step("the log cap set in the open window trims on close, not while dragging", function()
	local db = DisenchantValueDB
	db.log = {}
	for i = 1, 3000 do db.log[i] = { t = i, char = "X-Y", itemID = 1, mats = {} } end
	DisenchantValue.app:Open("options")
	local def = DisenchantValue.app:GetSetting("logcap")
	def.set(1000); def.after(1000)
	check(#db.log == 3000, "trimmed while the window is open")
	def.set(5000); def.after(5000)
	DisenchantValue.app:Close()
	check(#db.log == 3000, "trimmed below the final cap")
	def.set(1000)
	DisenchantValue.app:Open("options"); DisenchantValue.app:Close()
	check(#db.log == 1000 and db.log[1].t == 2001 and db.log[1000].t == 3000, "close didn't keep the newest 1000")
	def.set(10000)
end)

step("no Lua errors reported", function()
	check(#MOCK.errors == 0, table.concat(MOCK.errors, "\n"))
end)

print(("\n%d passed, %d failed"):format(passes, #failures))
return #failures
