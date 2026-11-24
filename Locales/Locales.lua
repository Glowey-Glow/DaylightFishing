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

local ADDON, ns = ...

-- The language of the addon's own text, ns.LOCALE: Daylight UI's own pick while it runs (its Home >
-- Language, since 2.2.5), else the Language picked on the General page of Glowey's Plugins window
-- (Host.lua), else the game's. One of the seven there are files for; enGB reads enUS, esMX esES.
-- The game's own words (GAME below, ns.GameText) stay in the game's language.
local CLIENT = GetLocale and GetLocale() or "enUS"
local FOLD = { enGB = "enUS", esMX = "esES" }
local HAVE = { enUS = true, deDE = true, esES = true, frFR = true, ruRU = true, koKR = true, zhCN = true }
local function Picked()
	local D = rawget(_G, "DaylightUI")
	if type(D) == "table" and type(D.API) == "table" and D.API.major == 1 then
		-- (Its pick is on from its own ADDON_LOADED, which comes before any addon loading after it:
		-- DaylightUI/Locales/Locales.lua:16-20, Core.lua:984-992. Its saved pick, should it not be.)
		local pick = D.LOCALE
		local db = rawget(_G, "DaylightUIDB")
		local saved = type(db) == "table" and db.language
		if type(saved) == "string" and saved ~= "auto" and pick == D.CLIENT_LOCALE then pick = saved end
		return pick
	end
	-- (Kept in every Glowey addon's <Addon>Settings, the newest counting. Ours can be read this early
	-- because the .toc loads the saved variables first: LoadSavedVariablesFirst.)
	local best, at
	local own = rawget(_G, ADDON .. "Settings")
	if type(own) == "table" and type(own.general) == "table" then best, at = own.general.language, own.generalAt or 0 end
	local host = rawget(_G, "GloweyHost")
	local S = type(host) == "table" and host.state
	if type(S) == "table" and type(S.general) == "table" and (S.generalAt or -1) >= (at or -1) then best = S.general.language end
	return best
end
local pick = Picked()
pick = type(pick) == "string" and (FOLD[pick] or pick) or nil
ns.LOCALE = (pick and HAVE[pick]) and pick or (FOLD[CLIENT] or CLIENT)
-- CLIENT_ENGLISH: the game runs in English. ENGLISH: the game's words don't stand in for ours (an
-- English game, or our text picked in another language than the game's).
local CLIENT_ENGLISH = CLIENT:sub(1, 2) == "en"
local ENGLISH = CLIENT_ENGLISH or ns.LOCALE ~= (FOLD[CLIENT] or CLIENT)

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
	if not CLIENT_ENGLISH then
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
