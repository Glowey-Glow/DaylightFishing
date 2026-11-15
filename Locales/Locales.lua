-- The addon's text in the game's language.
--
-- The English text is the key: L["Cast"] is "Cast" on an English client, and on any other client
-- whose file has no line for it, so a missing line only shows English. Nothing is ever written to
-- L on a miss.
--
-- One file per language sits next to this one and returns at once on any other client:
--   local _, ns = ...
--   if ns.LOCALE ~= "deDE" then return end
--   local L = ns.L
--   L["Cast"] = "Auswerfen"
-- Sentences are whole format strings ("%d yd"), never glued from pieces, so each language can put
-- the words in its own order. What is saved or typed stays English: setting keys, dropdown keys,
-- slash words, the macro's name.
--
-- Counted words go through ns.Plural(n, one, many, few):
--   ns.Plural(n, L["%d catch"], L["%d catches"], L["%d catches#few"])
-- Russian has three forms; its third ("few": 2-4, 22-24, ...) is a key ending in "#few" that only
-- ruRU.lua carries. French uses "one" for 0 and 1, Korean and Chinese have a single form.

local _, ns = ...

ns.LOCALE = GetLocale and GetLocale() or "enUS"
local ENGLISH = ns.LOCALE:sub(1, 2) == "en"

-- Keys whose English is word for word one of the game's global strings (same case, punctuation
-- and holes), in the same sense: on a non-English client the game's own translation stands in
-- for ours, which stays as the fallback when the client lacks the global. English clients keep
-- ours. The named fishing keys (Space, Backspace, ...) take the game's names in Core.lua, and
-- "Fishing" stays ours for the plugin's short name on DaylightUI's rail.
local GAME = {
	["%s, %s"] = "LIST_DELIMITER",
	["Fishing Skill"] = "ITEM_MOD_FISHING_SHORT",
	["Off"] = "OFF",
}

-- The game's text for a key in GAME, on a non-English client that has it; else nil.
local function Game(key)
	local global = not ENGLISH and GAME[key]
	local v = global and _G[global]
	if type(v) == "string" and v ~= "" then return v end
	return nil
end

-- A language file's line for a key in GAME is kept only where the game has no text for it.
ns.L = setmetatable({}, {
	__index = function(_, key) return Game(key) or key end,
	__newindex = function(t, key, value) rawset(t, key, Game(key) or value) end,
})

-- The game's own string (a global such as PROFESSIONS_FISHING) on a non-English client, when it
-- has it; else ours (an L[...] value). English clients always keep ours.
function ns.GameText(global, ours)
	if not ENGLISH then
		local v = _G[global]
		if type(v) == "string" and v ~= "" then return v end
	end
	return ours
end

local FORM
if ns.LOCALE == "ruRU" then
	FORM = function(n)
		local ten, hundred = n % 10, n % 100
		if ten == 1 and hundred ~= 11 then return "one" end
		if ten >= 2 and ten <= 4 and (hundred < 12 or hundred > 14) then return "few" end
		return "many"
	end
elseif ns.LOCALE == "frFR" then
	FORM = function(n) return n <= 1 and "one" or "many" end
elseif ns.LOCALE == "koKR" or ns.LOCALE == "zhCN" then
	FORM = function() return "many" end
else
	FORM = function(n) return n == 1 and "one" or "many" end
end

-- The form for n, formatted with n (a whole number).
function ns.Plural(n, one, many, few)
	n = tonumber(n) or 0
	local form = FORM(math.floor(math.abs(n)))
	local text = form == "one" and one or (form == "few" and few) or many
	return text:format(n)
end
