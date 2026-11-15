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
ns.L = setmetatable({}, { __index = function(_, key) return key end })

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
