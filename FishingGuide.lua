-- Glowey's Fishing's welcome, what's new and tour (the engine: Guide.lua). Loaded before Core.lua,
-- so its options can show the Help card; everything of Core.lua's is looked up when it's needed,
-- through the DaylightFishing table.
-- luacheck: read globals C_AddOns UnitChannelInfo
local ADDON, ns = ...
local Guide = ns.Guide
if not Guide then return end
local L = ns.L
local DUI = _G.DaylightUI
local Pop = Guide.Pop

local function Fishing() return _G.DaylightFishing end
local function Active() local F = Fishing() return F and F.IsActive and F.IsActive() end
local function Parts()
	local F = Fishing()
	if not (F and F.TourParts) then return nil, {}, nil, nil end
	return F.TourParts()
end
local function MastercraftLoaded()
	return C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("Mastercraft") or false
end

-- What changed, newest first: shown once after an update ("What's new" in the options shows them again).
local NEWS = {
	{ version = "1.8.0", lines = {
		L["Controller support: the catch list, the trainer box, the tours and Set Fishing Key work with a controller."],
		L["For controller players: Catch List Always On and Trainer Box Always On keep them open while you fish, without taking the cursor."],
	} },
	{ version = "1.7.0", lines = {
		L["Weapon Swap on the menu: the weapons that go back on when Fishing Mode ends."],
		L["Stay faded while moving (on to start): walking about keeps the UI faded."],
		L["While faded, Polestar's target faces, Daylight UI's portraits and the tooltips of windows out of sight stay hidden."],
	} },
	{ version = "1.6.14", lines = {
		L["On the first start you pick your fishing key, before the welcome."],
	} },
	{ version = "1.6.13", lines = {
		L["With Mastercraft installed, its \"Hide the game's interface\" stays on Never while Fade the UI While Fishing is on, so the UI can't stay faded."],
	} },
	{ version = "1.6.12", lines = {
		L["A short tour of Fishing Mode, the first time it turns on. Retake Tour in the options shows it again."],
		L["A note like this one after each update, with what changed."],
		L["Tells you when a newer version is out (once a session; switch it off under Updates)."],
		L["Revert to Mastercraft in the options gives Mastercraft its fight setting back."],
	} },
	{ version = "1.6.11", lines = {
		L["A fight puts your one-hand weapon and your shield back on together, right as it starts."],
	} },
}

-- (Kept on ns: Core.lua reads wasExisting, which the guide sets on it, for its first-start key pick.)
ns.GuideSpec = {
	name = "Glowey's Fishing",
	db = function() return _G.DaylightFishingDB end,
	-- (A player from before the guide: anything saved besides the guide's own.)
	existing = function()
		local db = _G.DaylightFishingDB
		if type(db) ~= "table" then return false end
		for k in pairs(db) do
			if k ~= "guide" and k ~= "updateCheck" then return true end
		end
		return false
	end,
	intro = L["Fishing Mode puts your pole on, sets the sound for fishing and gives you one key to cast and hook. Turn it on from the Glowey's Fishing data text or /fish."],
	takes = function()
		local list = {
			L["Your weapons, while Fishing Mode is on: your best fishing pole goes on, and your weapons come back when it ends."],
			L["Sound, soft interact and auto loot, while Fishing Mode is on: set back as they were when it ends."],
			L["One key, while you fish: it casts, then hooks the fish. Pick it with Set Fishing Key."],
			L["Fights: a fight ends Fishing Mode and puts your weapons back on."],
		}
		local ok, ours = pcall(_G.DaylightUI.API.GetSetting, ADDON, "mastercraftFights")
		if MastercraftLoaded() and not (ok and ours == false) then
			list[#list + 1] = L["Mastercraft's \"After the fight: your fishing gear back on\" is switched off, so your pole stays off after a fight."]
		end
		return list
	end,
	tour = "fishing",
	news = NEWS,
	-- (2026-11-16: everyone gets the welcome and the tour once more with this release.)
	reset = "2026-11-16",
	revert = {
		label = L["Fights While Fishing"],
		text = L["Revert to Mastercraft"],
		desc = L["Mastercraft handles fights again: its \"After the fight: your fishing gear back on\" comes back as it was."]
			.. " " .. L["So does its \"Hide the game's interface\"."],
		available = MastercraftLoaded,
		fn = function() pcall(DUI.Set, DUI, ADDON, "mastercraftFights", false) end,
	},
}
Guide.Setup(ns.GuideSpec)

Guide.AddTour("fishing", {
	-- (The menu shows for the tour even with Fishing Mode off, and goes again after.)
	start = function() local F = Fishing() if F and F.TourPreview then F.TourPreview(true) end end,
	finished = function() local F = Fishing() if F and F.TourPreview then F.TourPreview(false) end end,
	steps = {
	{ title = L["Fishing Mode"],
	  text = function()
		if Active() then
			return string.format(L["This is Fishing Mode: your pole is in hand and the sound is set for fishing. Turn it off with the X, the data text or %s, and your weapons go back on."], Pop("/fish"))
		end
		return string.format(L["Turn Fishing Mode on from the Glowey's Fishing data text, %s or the Fishing Mode macro: your pole goes on and this menu shows under your character."], Pop("/fish"))
	  end,
	  part = function() local menu = Parts() return menu end },
	{ title = L["Baits"],
	  text = L["Click a bait to put it on your pole. The time it has left shows at the top right of the menu."],
	  part = function()
		local menu, baits = Parts()
		if #baits > 0 then return baits end
		return menu
	  end },
	{ title = L["One Key"],
	  text = function()
		local _, _, _, key = Parts()
		if key and Active() then
			return string.format(L["%s casts. When the bobber splashes, press it again to hook the fish. Try it now: the tour goes on once you cast."], Pop(key))
		elseif key then
			return string.format(L["While Fishing Mode is on, %s casts. When the bobber splashes, press it again to hook the fish."], Pop(key))
		end
		return string.format(L["Click this button to cast, or pick one key for it with %s in the options."], Pop(L["Set Fishing Key"]))
	  end,
	  -- (Trying it only with Fishing Mode on: the pole in hand and the key bound.)
	  through = Active,
	  done = function() return Active() and UnitChannelInfo and UnitChannelInfo("player") ~= nil end,
	  part = function() local _, _, cast = Parts() return cast end },
	{ title = L["Skill and Catch"],
	  text = L["The bar on top shows your fishing skill: click it to see where to train next. Your catch this session is counted at the bottom: click it for the list."],
	  part = function() local menu = Parts() return menu end },
	{ title = L["Fights"],
	  text = L["A fight ends Fishing Mode at once and your weapons go back on, shield and all. Turn it on again once the fight is over."] },
	{ title = L["Settings"],
	  text = function()
		return string.format(L["Your key, the sound and a Fishing Mode macro are in Daylight UI's options: %s. %s there shows this tour again."],
			Pop(L["Plugins > Fishing"]), Pop(L["Retake Tour"]))
	  end },
} })
