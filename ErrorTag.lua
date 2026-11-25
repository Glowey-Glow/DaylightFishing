-- ErrorTag.lua: adds "[<Addon> <Version>]" to the end of this addon's errors in BugGrabber, so a
-- BugSack report says which version threw them. Listed first in the .toc, so errors thrown while
-- the other files load are tagged too. Does nothing without BugGrabber, and leaves other addons'
-- errors alone. (From a snippet shared free to copy, no credit needed; the same file in each of
-- our plugins.)
-- Read from BugGrabber (!BugGrabber\BugGrabber.lua, v12.1.1): every error it catches ends with
-- EventRegistry:TriggerEvent("BugGrabber.BugGrabbed", tostring(errorObject)) (:421-422). It finds
-- repeats by comparing the message (fetchFromDatabase), so the tag goes on err.stack, never on
-- err.message. Its GetErrorByID reads `db`, nil until its saved variables load (:455-463), so the
-- error is looked for in GetDB() instead (`db or loadErrors`, :465). A stack it reads again (a new
-- session, or after two minutes) is tagged again: the event comes after that too.
-- luacheck: read globals EventRegistry C_AddOns BugGrabber

local addonName = ...
if not (EventRegistry and C_AddOns and C_AddOns.GetAddOnMetadata) then return end

local version = C_AddOns.GetAddOnMetadata(addonName, "Version") or "?"
-- (A copy run from the repo carries the packager's placeholder: it is a dev copy.)
if version:find("@", 1, true) then version = "dev" end
local tag = "[" .. addonName .. " " .. version .. "]"
-- Paths can be long ("Interface/AddOns/<Addon>/x.lua") or short ("[<Addon>/x.lua]").
local needles = {
	"/" .. addonName .. "/",
	"[" .. addonName .. "/",
	"'" .. addonName .. "'",
}

local function MentionsUs(text)
	if text:sub(1, #addonName + 1) == addonName .. "/" then return true end
	for i = 1, #needles do
		if text:find(needles[i], 1, true) then return true end
	end
	return false
end

local function FindError(id)
	local db = BugGrabber and BugGrabber.GetDB and BugGrabber:GetDB()
	if type(db) ~= "table" then return end
	for i = #db, 1, -1 do
		if tostring(db[i]) == id then return db[i] end
	end
end

EventRegistry:RegisterCallback("BugGrabber.BugGrabbed", function(_, id)
	local err = FindError(id)
	if not err or type(err.message) ~= "string" then return end
	local stack = type(err.stack) == "string" and err.stack or ""
	if stack:find(tag, 1, true) then return end
	if MentionsUs(err.message) or MentionsUs(stack) then
		err.stack = (stack ~= "" and stack .. "\n" or "") .. tag
	end
end, {})
