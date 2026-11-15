-- Daylight Fishing: a DaylightUI plugin.
-- Fishing Mode, turned on and off from a data text (any DaylightUI data text slot, or any other
-- broker display) or /dui fish:
--   on:  your best fishing pole goes on (what you held is remembered), the sound is set for
--        fishing (effects up, music and ambience down, sound in the background, soft interact),
--        and a small menu shows under your character: your baits (click one to put it on the
--        pole) and the cast button. One key casts, and hooks the fish once the bobber is out.
--   off: the sound goes back to how you had it, the menu and the key are let go, and your
--        weapons go back on. Taking the pole off yourself turns Fishing Mode off too (your
--        weapons go back on unless you put others on), and putting one on turns it on (a
--        setting). A fight turns it off and it stays off ("Combat Detected, Exiting Fishing
--        Mode" shows where the menu was).
-- A button in its settings makes a "Fishing Mode" macro (/dui fish) with the Fishing icon.
-- The settings are on its page in DaylightUI's options (Plugins). Built on DaylightUI.API only.

local ADDON, ns = ...
local L, Plural = ns.L, ns.Plural

local DUI = _G.DaylightUI
local API = DUI and DUI.API
if not API or API.major ~= 1 then return end

local me = API.For(ADDON)

-- ---------------------------------------------------------------------------------------------
-- Settings
-- ---------------------------------------------------------------------------------------------

local DEFAULTS = {
	key = "SPACE",
	autoMode = true,
	equipPole = true,
	restoreWeapons = true,
	sound = true,
	sfxVolume = 1,
	musicVolume = 0,
	ambienceVolume = 0.2,
	backgroundSound = true,
	softInteract = true,
	autoLoot = true,
	showMenu = true,
	fadeUI = true,
	fadeAlpha = 0,
	fadeDelay = 2,
	hideWater = true,
	keepMinimap = true,
	keepChat = true,
	catchPopup = true,
	menuScale = 1,
	duiOpacity = true,
	opacity = 0.85,
	mastercraftFights = true,
}

-- Read once and kept until a setting of ours changes: the quiet screen asks several of them every
-- frame while you fish. Nothing is kept before login (the settings aren't there yet).
local settings, settingsReady = {}, false
local NONE = {}
local function Get(path)
	local v = settings[path]
	if v ~= nil then
		if v == NONE then return nil end
		return v
	end
	local ok, value = pcall(API.GetSetting, ADDON, path)
	if not ok or value == nil then value = DEFAULTS[path] end
	if settingsReady then settings[path] = value == nil and NONE or value end
	return value
end
me.On("Login", function()
	settingsReady = true
	wipe(settings)
end)
me.On("SettingChanged", function(scope)
	if scope == ADDON then wipe(settings) end
end)

local db, char     -- DaylightFishingDB (account), and this character's part of it

local function Print(msg)
	DEFAULT_CHAT_FRAME:AddMessage("|cff66ccffDaylight Fishing|r: " .. msg)
end

-- Our menu and boxes in DaylightUI's window shell. The background follows DaylightUI's window
-- opacity, or with "Use DaylightUI's opacity" off, the one on our page. Each frame is remembered
-- (weakly) so a change to either, or to DaylightUI's look, dresses them all again at once.
local shells = setmetatable({}, { __mode = "k" })
local function SkinWindow(frame)
	shells[frame] = true
	if Get("duiOpacity") == false then
		API.Skin(frame, { window = true, bgAlpha = Get("opacity") })
	else
		API.Skin(frame, { window = true })
	end
end
local function ReskinWindows()
	for frame in pairs(shells) do SkinWindow(frame) end
end
me.On("SettingChanged", function(scope, path)
	if scope == ADDON and (path == "duiOpacity" or path == "opacity") then ReskinWindows() end
end)
me.On("StyleChanged", function() ReskinWindows() end)

-- ---------------------------------------------------------------------------------------------
-- The game: the Fishing spell, poles, baits
-- ---------------------------------------------------------------------------------------------

local FISHING_IDS = { [7620] = true, [131474] = true, [131476] = true }
local POLE_ICON = "Interface\\Icons\\Trade_Fishing"

-- The baits a fishing pole takes (the classic ones, best last).
local BAITS = { 6529, 6530, 6811, 6532, 7307, 6533 }

local function SpellName(id)
	if C_Spell and C_Spell.GetSpellName then
		local name = C_Spell.GetSpellName(id)
		if name then return name end
	end
	if GetSpellInfo then return (GetSpellInfo(id)) end
end

local function FishingName()
	return SpellName(7620) or SpellName(131474) or "Fishing"
end

local function FishingIcon()
	if C_Spell and C_Spell.GetSpellTexture then
		local icon = C_Spell.GetSpellTexture(7620) or C_Spell.GetSpellTexture(131474)
		if icon then return icon end
	end
	return POLE_ICON
end

local WEAPON = Enum and Enum.ItemClass and Enum.ItemClass.Weapon or 2
local POLE = Enum and Enum.ItemWeaponSubclass and Enum.ItemWeaponSubclass.Fishingpole or 20

local Equip = (C_Item and C_Item.EquipItemByName) or EquipItemByName
local ItemCount = (C_Item and C_Item.GetItemCount) or GetItemCount

local function IsPole(item)
	if not item then return false end
	local _, _, _, _, _, classID, subclassID = C_Item.GetItemInfoInstant(item)
	return classID == WEAPON and subclassID == POLE
end

local function PoleEquipped()
	return IsPole(GetInventoryItemID("player", 16))
end

-- The best pole in your bags (the highest item level), as an item link.
local function FindPole()
	local best, bestLevel
	for bag = 0, NUM_BAG_SLOTS or 4 do
		for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
			local id = C_Container.GetContainerItemID(bag, slot)
			if id and IsPole(id) then
				local link = C_Container.GetContainerItemLink(bag, slot)
				local level = select(4, C_Item.GetItemInfo(link or id)) or 0
				if not best or level > bestLevel then best, bestLevel = link or id, level end
			end
		end
	end
	return best
end

local function BaitsInBags()
	local list = {}
	for _, id in ipairs(BAITS) do
		local count = ItemCount(id) or 0
		if count > 0 then list[#list + 1] = { id = id, count = count } end
	end
	return list
end

-- Seconds of bait left on the pole, or nil.
local function BaitLeft()
	local has, ms = GetWeaponEnchantInfo()
	if has and ms then return ms / 1000 end
end

-- ---------------------------------------------------------------------------------------------
-- Sound and game settings while fishing. What was there before is kept in the saved variables, so
-- a disconnect in Fishing Mode still gets it back at the next login.
-- ---------------------------------------------------------------------------------------------

-- Work that waits for the end of a fight (secure frames, bindings, settings the game refuses).
local later = {}

local function Wanted()
	local want = {}
	if Get("sound") then
		want.Sound_EnableAllSound = "1"
		want.Sound_EnableSFX = "1"
		want.Sound_SFXVolume = tostring(Get("sfxVolume"))
		want.Sound_MusicVolume = tostring(Get("musicVolume"))
		want.Sound_AmbienceVolume = tostring(Get("ambienceVolume"))
		if Get("backgroundSound") then want.Sound_EnableSoundWhenGameIsInBG = "1" end
	end
	if Get("softInteract") then want.SoftTargetInteract = "3" end
	if Get("autoLoot") then want.autoLootDefault = "1" end
	return want
end

local function ApplySettings()
	db.saved = db.saved or {}
	local want = Wanted()
	-- A setting turned off since: back to what it was.
	for name, old in pairs(db.saved) do
		if want[name] == nil then
			pcall(SetCVar, name, old)
			db.saved[name] = nil
		end
	end
	for name, value in pairs(want) do
		if db.saved[name] == nil then
			local ok, old = pcall(GetCVar, name)
			if ok and old ~= nil then db.saved[name] = old end
		end
		pcall(SetCVar, name, value)
	end
end

local function SameValue(a, b)
	if a == nil or b == nil then return false end
	if tostring(a) == tostring(b) then return true end
	local x, y = tonumber(a), tonumber(b)
	return x ~= nil and y ~= nil and math.abs(x - y) < 1e-4
end

-- Each saved setting back to how it was. Never in a fight: the game blocks SetCVar there (a
-- blocked-action error, which pcall doesn't stop), so it waits for the fight's end. One the game
-- didn't take is kept and tried again later: it is never forgotten before it is back.
local RestoreSettings
local restoreQueued = false
function RestoreSettings()
	if InCombatLockdown() then
		if not restoreQueued then
			restoreQueued = true
			later[#later + 1] = RestoreSettings
		end
		return
	end
	restoreQueued = false
	if type(db.saved) ~= "table" then return end
	for name, old in pairs(db.saved) do
		pcall(SetCVar, name, old)
		local ok, now = pcall(GetCVar, name)
		if not ok or now == nil or SameValue(now, old) then db.saved[name] = nil end
	end
	if next(db.saved) == nil then db.saved = nil end
end

-- ---------------------------------------------------------------------------------------------
-- Out of combat only: the secure buttons, the menu that holds them and the key binding
-- ---------------------------------------------------------------------------------------------

local function OutOfCombat(fn)
	if InCombatLockdown() then later[#later + 1] = fn else fn() end
end

-- The key's owner lets go of it by itself the moment a fight starts.
local owner = CreateFrame("Frame", nil, UIParent, "SecureHandlerStateTemplate")
owner:SetAttribute("_onstate-combat", [[ if newstate == "combat" then self:ClearBindings() end ]])
RegisterStateDriver(owner, "combat", "[combat] combat; peace")

local active = false        -- Fishing Mode
local equipping = false     -- the pole is on its way on
local channeling = false    -- a line is out

local menu, cast, baitButtons = nil, nil, {}
local UpdateBroker, UpdateMenu, UpdateCatch, RefreshPanel, UpdateSkill

local function UpdateBinding()
	if InCombatLockdown() then return end
	ClearOverrideBindings(owner)
	if not active or not cast then return end
	local key = Get("key")
	if not key or key == "NONE" then return end
	if channeling then
		-- The bobber is out: the same key hooks it (it is the soft interact target).
		SetOverrideBinding(owner, true, key, "INTERACTTARGET")
	else
		SetOverrideBindingClick(owner, true, key, cast:GetName(), "LeftButton")
	end
end

-- ---------------------------------------------------------------------------------------------
-- The menu under the character
-- ---------------------------------------------------------------------------------------------

local SIZE, CAST_SIZE, GAP, PAD = 32, 44, 6, 10
-- The menu and the panels that open from it (the trainer box, the catch list) share one width;
-- the menu only grows past it when its baits need the room, and the panels follow.
local WIDTH = 300
local SKILL_H = 30   -- the fishing skill row on top of the menu

local function TextColor(name)
	local c = API.Colors()[name] or API.Colors().VALUE
	return c[1], c[2], c[3]
end

-- A secure icon button. DaylightUI's shell is a frame of its own, drawn over the button's own
-- textures: so the shell is a border only, and the icon, its text and its hover light sit on a
-- layer (b.top) above it. tooltip(self) fills GameTooltip on hover.
local function IconButton(name, parent, size, tooltip)
	local b = CreateFrame("Button", name, parent, "SecureActionButtonTemplate")
	b:SetSize(size, size)
	b:RegisterForClicks("AnyUp")
	b:SetAttribute("useOnKeyDown", false)
	API.Skin(b, { noBevel = true, noBackground = true })
	local top = CreateFrame("Frame", nil, b)
	top:SetAllPoints()
	top:SetFrameLevel(b:GetFrameLevel() + 10)
	b.top = top
	b.icon = top:CreateTexture(nil, "ARTWORK")
	b.icon:SetPoint("TOPLEFT", 2, -2)
	b.icon:SetPoint("BOTTOMRIGHT", -2, 2)
	b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	local hl = top:CreateTexture(nil, "OVERLAY")
	hl:SetAllPoints(b.icon)
	hl:SetColorTexture(1, 1, 1, 0.15)
	hl:Hide()
	b:SetScript("OnEnter", function(self)
		hl:Show()
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		if tooltip then tooltip(self) end
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function()
		hl:Hide()
		GameTooltip:Hide()
	end)
	return b
end

local function BaitButton(i)
	local b = baitButtons[i]
	if b then return b end
	b = IconButton(nil, menu, SIZE, function(self)
		if self.itemID then GameTooltip:SetItemByID(self.itemID) end
		GameTooltip:AddLine(L["Click to put it on your fishing pole."], TextColor("TEXT"))
	end)
	b.count = API.Text(b.top, "tiny", "RIGHT")
	b.count:SetPoint("BOTTOMRIGHT", -3, 3)
	baitButtons[i] = b
	return b
end

local function KeyText()
	local key = Get("key")
	if not key or key == "NONE" then return nil end
	return GetBindingText and GetBindingText(key) or key
end

local function BuildMenu()
	if menu then return end
	menu = CreateFrame("Frame", "DaylightFishingMenu", UIParent)
	menu:SetFrameStrata("MEDIUM")
	menu:SetIgnoreParentAlpha(true)   -- it stays while the rest of the UI fades
	menu:SetClampedToScreen(true)
	menu:SetPoint("CENTER", UIParent, "CENTER", 0, -190)
	menu:Hide()

	-- Fishing skill on top: a bar to this rank's cap, a mark where the next rank can be trained.
	-- Click it: where to train next.
	-- "Fishing Skill" on the left, "135 / 150" on the right, both in the same small label ink.
	menu.skillText = API.Text(menu, "tiny", "LEFT")
	menu.skillText:SetPoint("TOPLEFT", PAD, -9)
	menu.skillMax = API.Text(menu, "tiny", "RIGHT")
	menu.skillMax:SetPoint("TOPRIGHT", -PAD - 20, -9)
	menu.skillBar = API.Bar(menu)
	menu.skillBar:SetPoint("TOPLEFT", PAD, -25)
	menu.skillBar:SetPoint("TOPRIGHT", -PAD, -25)
	menu.skillBar:SetHeight(6)
	menu.skillBar:SetMinMaxValues(0, 1)
	menu.skillMark = menu.skillBar:CreateTexture(nil, "OVERLAY")
	menu.skillMark:SetSize(2, 10)
	menu.skillMark:Hide()
	menu.skillBar:SetScript("OnSizeChanged", function() if UpdateSkill then UpdateSkill() end end)
	menu.skillButton = CreateFrame("Button", nil, menu)
	menu.skillButton:SetPoint("TOPLEFT", menu, "TOPLEFT", 4, -4)
	menu.skillButton:SetPoint("BOTTOMRIGHT", menu, "TOPRIGHT", -26, -SKILL_H + 2)
	menu.skillButton:SetScript("OnEnter", function(self)
		menu.skillText:SetAlpha(0.8)
		_G.DaylightFishing.SkillTooltip(self)
	end)
	menu.skillButton:SetScript("OnLeave", function()
		menu.skillText:SetAlpha(1)
		GameTooltip:Hide()
	end)
	menu.skillButton:SetScript("OnClick", function()
		GameTooltip:Hide()
		_G.DaylightFishing.ToggleTrainers()
	end)

	menu.title = API.Text(menu, "small", "LEFT")
	menu.title:SetPoint("TOPLEFT", PAD, -8 - SKILL_H)
	menu.title:SetText(L["Fishing Mode"])
	menu.title:SetTextColor(API.Accent())

	menu.lure = API.Text(menu, "tiny", "RIGHT")
	menu.lure:SetPoint("TOPRIGHT", -PAD, -9 - SKILL_H)

	menu.close = API.Close(menu, function()
		if InCombatLockdown() then
			Print(L["Fishing Mode is off. The menu goes away when the fight ends."])
		end
		_G.DaylightFishing.Toggle(false)
	end, 14)
	menu.close:SetPoint("TOPRIGHT", -8, -7)

	cast = IconButton("DaylightFishingCast", menu, CAST_SIZE, function()
		GameTooltip:SetText(L["Cast"])
		local key = KeyText()
		local r, g, b = TextColor("TEXT")
		if key then
			GameTooltip:AddLine(L["%s casts, and hooks the fish."]:format(key), r, g, b)
		else
			GameTooltip:AddLine(L["Pick a fishing key in the options to fish with one key."], r, g, b, true)
		end
	end)
	cast:SetAttribute("type", "macro")
	cast:SetAttribute("macrotext", "/cast " .. FishingName())
	cast.icon:SetTexture(FishingIcon())
	cast.key = API.Text(cast.top, "tiny", "CENTER")
	cast.key:SetPoint("BOTTOM", cast, "BOTTOM", 0, 3)
	cast.state = API.Text(menu, "tiny", "CENTER")
	cast.state:SetPoint("TOP", cast, "BOTTOM", 0, -3)

	-- The line's time in the water: a thin bar along the bottom while the bobber is out.
	menu.bar = API.Bar(menu)
	menu.bar:SetPoint("BOTTOMLEFT", 6, 4)
	menu.bar:SetPoint("BOTTOMRIGHT", -6, 4)
	menu.bar:SetHeight(3)
	menu.bar:SetMinMaxValues(0, 1)
	menu.bar:Hide()

	menu.empty = API.Text(menu, "small", "LEFT")
	menu.empty:SetText(L["No bait in your bags"])
	menu.empty:SetTextColor(TextColor("OFF"))

	-- This session's catch: hover for all of it.
	menu.catch = CreateFrame("Frame", nil, menu)
	menu.catch:SetPoint("BOTTOMLEFT", PAD, 9)
	menu.catch:SetSize(90, 14)
	menu.catch:EnableMouse(true)
	menu.catch.text = API.Text(menu.catch, "tiny", "LEFT")
	menu.catch.text:SetPoint("LEFT")
	menu.catch:SetScript("OnEnter", function(self)
		menu.catch.text:SetTextColor(API.Accent())
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		_G.DaylightFishing.CatchTooltip(GameTooltip, true)
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine(L["Click: the catch list, fish by fish"], 0.8, 0.8, 0.8)
		GameTooltip:Show()
	end)
	menu.catch:SetScript("OnLeave", function()
		GameTooltip:Hide()
		UpdateCatch()
	end)
	menu.catch:SetScript("OnMouseUp", function(_, button)
		if button == "LeftButton" then
			GameTooltip:Hide()
			_G.DaylightFishing.ToggleCatchPanel()
		end
	end)

	me.RegisterMover(menu, "menu", L["Fishing menu"], { "CENTER", UIParent, "CENTER", 0, -190 })

	-- The bait left on the pole, every second while the menu shows.
	local tick = 1
	menu:SetScript("OnUpdate", function(_, elapsed)
		local name, startMS, endMS
		if channeling then
			local _
			name, _, _, startMS, endMS = UnitChannelInfo("player")
			if issecretvalue and (issecretvalue(startMS) or issecretvalue(endMS)) then name = nil end
		end
		if name and startMS and endMS and endMS > startMS then
			local now = GetTime() * 1000
			menu.bar:SetMinMaxValues(0, endMS - startMS)
			menu.bar:SetValue(math.max(0, endMS - now))
			menu.bar:Show()
		elseif menu.bar:IsShown() then
			menu.bar:Hide()
		end
		tick = tick + elapsed
		if tick < 1 then return end
		tick = 0
		local left = BaitLeft()
		if left then
			menu.lure:SetText(string.format(L["Bait %d:%02d"], math.floor(left / 60), math.floor(left) % 60))
			menu.lure:SetTextColor(TextColor(left < 60 and "WARN" or "VALUE"))
		else
			menu.lure:SetText(L["No bait on"])
			menu.lure:SetTextColor(TextColor("OFF"))
		end
	end)
end

-- The baits, the cast button and the menu's size. Out of combat (the buttons are secure).
function UpdateMenu()
	if not menu or InCombatLockdown() then return end
	menu:SetScale(Get("menuScale") or 1)
	local baits = BaitsInBags()
	local x = PAD
	local top = -26 - SKILL_H
	for i, bait in ipairs(baits) do
		local b = BaitButton(i)
		b.itemID = bait.id
		b:SetAttribute("type", "macro")
		b:SetAttribute("macrotext", "/use item:" .. bait.id .. "\n/use 16")
		b.icon:SetTexture(C_Item.GetItemIconByID(bait.id))
		b.count:SetText(bait.count > 1 and bait.count or "")
		b:ClearAllPoints()
		b:SetPoint("TOPLEFT", menu, "TOPLEFT", x, top - (CAST_SIZE - SIZE) / 2)
		b:Show()
		x = x + SIZE + GAP
	end
	for i = #baits + 1, #baitButtons do baitButtons[i]:Hide() end
	if #baits == 0 then
		menu.empty:ClearAllPoints()
		menu.empty:SetPoint("LEFT", menu, "TOPLEFT", x, top - CAST_SIZE / 2)
		menu.empty:Show()
		x = x + math.ceil(menu.empty:GetStringWidth()) + GAP
	else
		menu.empty:Hide()
	end
	x = x + GAP
	cast:ClearAllPoints()
	cast:SetPoint("TOPLEFT", menu, "TOPLEFT", x, top)
	cast:SetAttribute("macrotext", "/cast " .. FishingName())
	cast.key:SetText(KeyText() or "")
	cast.state:SetText(channeling and L["Hook"] or L["Cast"])
	UpdateCatch()
	UpdateSkill()
	local width = math.max(x + CAST_SIZE + PAD, WIDTH)
	menu:SetSize(width, -top + CAST_SIZE + 26)
	SkinWindow(menu)
end

local function ShowMenu(show)
	OutOfCombat(function()
		BuildMenu()
		if show and active and Get("showMenu") then
			UpdateMenu()
			menu:Show()
		else
			menu:Hide()
		end
		UpdateBinding()
	end)
end

-- ---------------------------------------------------------------------------------------------
-- The quiet screen: while you fish, the rest of the UI fades away the way DaylightUI's soft AFK
-- screen fades it (through UIParent's alpha, which is allowed in a fight and moves nothing), and
-- the fishing menu, the minimap and the chat stay. It comes back while you move or fight, and
-- when Fishing Mode ends. It leaves the UI to DaylightUI's AFK screen while that is up, and adds
-- nothing to the world: DaylightUI's own "Fishing water" is its setting (Quality of Life).
-- ---------------------------------------------------------------------------------------------

local fader = CreateFrame("Frame")
fader:Hide()
local fade = 0             -- 0: the UI as it is, 1: faded as far as the setting says
local stillSince           -- when you last stood still with nothing open
local FADE_OUT, FADE_IN = 0.6, 0.2

-- What stays while the UI is faded: the game tooltip, the loot window and the game's popups
-- (so a catch never brings the UI back), and, by their settings, the minimap and the chat. Each
-- is taken out of the fade with what it held before, and given that back after.
local lifted = {}          -- frame -> its ignore-parent-alpha before
local liftedOn = false

-- A frame's outermost frame under UIParent (the holder DaylightUI may put it in), or itself.
local function Holder(f)
	if type(f) ~= "table" or not f.GetParent then return nil end
	local parent = f:GetParent()
	while parent and parent ~= UIParent do
		f = parent
		parent = f:GetParent()
	end
	if parent == UIParent then return f end
end

local function Lift(f)
	if type(f) ~= "table" or not f.SetIgnoreParentAlpha or lifted[f] ~= nil then return end
	-- Already out of it (DaylightUI's chat does that itself): not ours to give back.
	if f.IsIgnoringParentAlpha and f:IsIgnoringParentAlpha() then return end
	lifted[f] = true
	f:SetIgnoreParentAlpha(true)
end

local function DropAll()
	for f in pairs(lifted) do f:SetIgnoreParentAlpha(false) end
	wipe(lifted)
	liftedOn = false
end

-- The frames' names, made once (LiftAll runs four times a second while the UI is faded).
local POPUP_NAMES, CHAT_NAMES, BAG_NAMES = {}, {}, {}
for i = 1, 4 do POPUP_NAMES[i] = "StaticPopup" .. i end
for i = 1, NUM_CHAT_WINDOWS or 10 do
	CHAT_NAMES[#CHAT_NAMES + 1] = "ChatFrame" .. i
	CHAT_NAMES[#CHAT_NAMES + 1] = "ChatFrame" .. i .. "EditBox"
	CHAT_NAMES[#CHAT_NAMES + 1] = "ChatFrame" .. i .. "Tab"
end
for i = 1, 13 do BAG_NAMES[i] = "ContainerFrame" .. i end

local function LiftAll()
	liftedOn = true
	Lift(GameTooltip)
	Lift(LootFrame)
	for i = 1, #POPUP_NAMES do Lift(_G[POPUP_NAMES[i]]) end
	if Get("keepMinimap") ~= false then Lift(Holder(_G.Minimap)) end
	if Get("keepChat") ~= false then
		-- DaylightUI's chat draws in its own frames and keeps the game's windows hidden, so
		-- lifting only the game's would leave the chat you see fading.
		Lift(_G.DaylightUIChat)
		Lift(_G.DaylightUIChatSide)
		for i = 1, #CHAT_NAMES do Lift(Holder(_G[CHAT_NAMES[i]])) end
		Lift(Holder(_G.GeneralDockManager))
	end
	-- Your bags and bank: DaylightUI's windows and the game's, open now or opened later.
	Lift(_G.DaylightUIBag)
	Lift(_G.DaylightUIBank)
	Lift(_G.ContainerFrameCombinedBags)
	Lift(_G.BankFrame)
	for i = 1, #BAG_NAMES do Lift(_G[BAG_NAMES[i]]) end
end

-- The game draws the minimap's dots (your arrow, nodes, party) at full strength whatever its
-- parents' alpha, so fading UIParent leaves them up. With "Keep the minimap" off, once the UI is
-- all the way out the map's own alpha goes to 0, through DaylightUI's Fade.MapAway (shared with its
-- AFK screen and info panel, so whoever lets go last gives the map back). Never hidden: a hidden
-- minimap came back blank. If DaylightUI renames it, the map's alpha is set here instead.
local mapAway, mapAlphaBefore = false, nil
local function MapAway(on)
	if on == mapAway then return end
	mapAway = on
	local F = DUI and DUI.Fade
	if type(F) == "table" and type(F.MapAway) == "function" then
		pcall(F.MapAway, "fishing", on)
		return
	end
	local map = _G.Minimap
	if type(map) ~= "table" or not map.SetAlpha then return end
	if on then
		mapAlphaBefore = map:GetAlpha() or 1
		map:SetAlpha(0)
	else
		map:SetAlpha(mapAlphaBefore or 1)
		mapAlphaBefore = nil
	end
end

local function UpdateMapAway()
	local low = tonumber(Get("fadeAlpha")) or 0
	MapAway(fade >= 1 and low <= 0.001 and Get("keepMinimap") == false)
end

local function SetFade(p)
	fade = p
	local low = tonumber(Get("fadeAlpha")) or 0
	UIParent:SetAlpha(1 - p * (1 - low))
	if p > 0 and not liftedOn then
		LiftAll()
	elseif p <= 0 and liftedOn then
		DropAll()
	end
	UpdateMapAway()
end

-- Straight back, at once (a fight, or Fishing Mode ending).
local function Unfade()
	stillSince = nil
	if fade > 0 or liftedOn then SetFade(0) end
	MapAway(false)
end

local function AfkScreen()
	local afk = _G.DaylightUIAfkScreen
	return afk and afk:IsShown()
end

local function WantFade()
	if not active or not Get("fadeUI") or InCombatLockdown() then return false end
	if (GetUnitSpeed("player") or 0) > 0 or IsFalling()
		or (Get("keepChat") == false and ChatEdit_GetActiveWindow and ChatEdit_GetActiveWindow()) then
		stillSince = nil
		return false
	end
	stillSince = stillSince or GetTime()
	return GetTime() - stillSince >= (tonumber(Get("fadeDelay")) or 2)
end

-- DaylightUI's "Fishing water" (its Quality of Life module): the water along the bottom of the
-- screen while a line is in. DaylightUI has no call to change its settings, so while Fishing Mode
-- is on the water's frame is kept see-through instead, and given back as it was when Fishing Mode
-- ends. DaylightUI only shows and hides that frame, never sets its alpha, so the two never fight.
-- Found by its name: if a DaylightUI update renames it, this does nothing.
local WATER = "DaylightUIFishScene"
local waterHidden = false

local function KeepWater()
	local scene = _G[WATER]
	if type(scene) ~= "table" or not scene.SetAlpha then return end
	local hide = active and Get("hideWater") ~= false
	if hide ~= waterHidden then
		waterHidden = hide
		scene:SetAlpha(hide and 0 or 1)
	end
end

local relift = 0
fader:SetScript("OnUpdate", function(_, elapsed)
	KeepWater()
	-- DaylightUI's AFK screen has the UI then, and gives it back whole: nothing of ours stays over it.
	if AfkScreen() then
		if liftedOn then DropAll() end
		fade, stillSince = 0, nil
		MapAway(false)
		return
	end
	if liftedOn then
		relift = relift + elapsed
		if relift > 0.25 then
			relift = 0
			LiftAll()
		end
	end
	local target = WantFade() and 1 or 0
	if target == fade then return end
	if target > fade then
		SetFade(math.min(1, fade + elapsed / FADE_OUT))
	else
		SetFade(math.max(0, fade - elapsed / FADE_IN))
	end
end)

-- ---------------------------------------------------------------------------------------------
-- Fishing Mode
-- ---------------------------------------------------------------------------------------------

local enterSerial = 0

-- Your weapons. char.weapons = { main hand, off hand } (item links) are the ones Fishing Mode owes
-- you: saved as it starts, and kept (in the saved variables, so a /reload keeps them too) until
-- they are back in your hands, whichever way it ends. They are never the pole: they are only taken
-- while no pole is in your main hand. Kept while a pole is in hand (put back on by you or by
-- another addon after a fight), and let go once they are back on, or once you put other weapons
-- on yourself. char.lastWeapons: what you held last with no pole in hand and nothing owed, for a
-- pole you put on by hand (Fishing Mode then turns on with the pole already in hand).

-- The item in a slot is this one (by item, whatever its enchant).
local function InSlot(slot, link)
	if not link then return false end
	local id = C_Item.GetItemInfoInstant(link)
	return id ~= nil and GetInventoryItemID("player", slot) == id
end

local function HandsNow()
	local main, off = GetInventoryItemLink("player", 16), GetInventoryItemLink("player", 17)
	if IsPole(main) or not (main or off) then return nil end
	return { main, off }
end

-- After any change to your hands while Fishing Mode is off: weapons owed and back on are let go,
-- and so are they when you put another weapon in your main hand. With a pole or nothing in hand,
-- they stay owed.
local function SettleWeapons()
	if active or not char then return end
	local mainID = GetInventoryItemID("player", 16)
	if IsPole(mainID) then return end
	local w = char.weapons
	if type(w) == "table" then
		local back = (not w[1] or InSlot(16, w[1])) and (not w[2] or InSlot(17, w[2]))
		if back or (mainID and not InSlot(16, w[1])) then char.weapons = nil end
	elseif w ~= nil then
		char.weapons = nil
	end
	if not char.weapons then char.lastWeapons = HandsNow() end
end

-- What you hold now, to put back when Fishing Mode ends. Weapons still owed stay as they were while
-- your hands hold only part of them (a fight ended Fishing Mode: the main hand is back, the off
-- hand not yet) or nothing.
local function SaveWeapons()
	local w = char.weapons
	if type(w) == "table" then
		local main, off = GetInventoryItemID("player", 16), GetInventoryItemID("player", 17)
		if (not main or InSlot(16, w[1])) and (not off or InSlot(17, w[2])) then return end
	end
	char.weapons = HandsNow()
end

-- The owed weapons back in their own slots. The game blocks an addon equipping in a fight
-- (ADDON_ACTION_BLOCKED: /equip is one of its secure commands), so in one they wait for its end.
-- PLAYER_REGEN_DISABLED comes just before that lock, so a fight's first moment still takes the
-- main hand. The off hand waits for the main hand to replace the two-handed pole, and goes on only
-- with no pole in hand: on top of one it would take the pole off and leave the main hand empty.
local weaponsQueued = false
local RestoreWeapons, RestoreOffHand

function RestoreOffHand()
	local w = char and char.weapons
	if active or type(w) ~= "table" or not w[2] then return end
	if InCombatLockdown() then
		if not weaponsQueued then
			weaponsQueued = true
			later[#later + 1] = RestoreWeapons
		end
		return
	end
	if IsPole(GetInventoryItemID("player", 16)) or InSlot(17, w[2]) then return end
	if (ItemCount(w[2]) or 0) > 0 then Equip(w[2], 17) end
end

function RestoreWeapons()
	weaponsQueued = false
	local w = char and char.weapons
	if active or type(w) ~= "table" then return end
	if InCombatLockdown() then
		weaponsQueued = true
		later[#later + 1] = RestoreWeapons
		return
	end
	if w[1] and not InSlot(16, w[1]) and (ItemCount(w[1]) or 0) > 0 then Equip(w[1], 16) end
	if w[2] then C_Timer.After(0.4, RestoreOffHand) end
	SettleWeapons()
end

-- The note that takes the fishing menu's place when a fight ends Fishing Mode: "Combat Detected,
-- Exiting Fishing Mode" for a moment, then it fades away. It is no secure frame, so it shows and
-- fades in a fight. If the game kept the menu up (its buttons are secure, and the menu goes once
-- the fight ends), the menu fades with it, and the note keeps the mouse off its buttons until then.
local notice
local NOTICE_IN, NOTICE_HOLD, NOTICE_OUT = 0.15, 2.5, 0.8

local function MenuKept()
	return menu ~= nil and menu:IsShown() and not active
end

local function HideNotice()
	if notice then notice:Hide() end
	if menu then menu:SetAlpha(1) end
end

local function BuildNotice()
	if notice then return end
	notice = CreateFrame("Frame", "DaylightFishingNotice", UIParent)
	notice:SetIgnoreParentAlpha(true)   -- it stays while the rest of the UI fades
	notice:SetFrameStrata("MEDIUM")
	notice:SetFrameLevel(60)
	notice:SetClampedToScreen(true)
	notice:Hide()
	notice.text = API.Text(notice, "body", "CENTER")
	notice.text:SetPoint("CENTER")
	notice.text:SetWordWrap(false)
	notice:SetScript("OnUpdate", function(self, elapsed)
		self.age = self.age + elapsed
		local a
		if self.age < NOTICE_IN then
			a = self.age / NOTICE_IN
		elseif self.age < NOTICE_IN + NOTICE_HOLD then
			a = 1
		else
			a = 1 - (self.age - NOTICE_IN - NOTICE_HOLD) / NOTICE_OUT
		end
		if MenuKept() then menu:SetAlpha(math.max(0, self.age < NOTICE_IN + NOTICE_HOLD and 1 or a)) end
		if a > 0 then
			self:SetAlpha(a)
			return
		end
		self:SetAlpha(0)
		if MenuKept() then return end
		HideNotice()
	end)
end

local function ShowNotice()
	BuildNotice()
	notice.text:SetText(L["Combat Detected, Exiting Fishing Mode"])
	notice.text:SetTextColor(TextColor("WARN"))
	notice:SetScale(Get("menuScale") or 1)
	-- As wide as the menu, or as its text needs (never cut off).
	local w, h = math.ceil(notice.text:GetStringWidth()) + 2 * PAD + 8, 44
	notice:ClearAllPoints()
	if menu then
		if menu:GetWidth() > w then w = menu:GetWidth() end
		if menu:GetHeight() > h then h = menu:GetHeight() end
		notice:SetPoint("CENTER", menu, "CENTER")
	else
		notice:SetPoint("CENTER", UIParent, "CENTER", 0, -190)
	end
	notice:SetSize(w, h)
	notice:EnableMouse(MenuKept())
	SkinWindow(notice)
	notice.age = 0
	notice:SetAlpha(0)
	notice:Show()
end

-- A fight that ended Fishing Mode: a pole going on during it or just after (another addon may put
-- your fishing gear back on as it ends) doesn't turn Fishing Mode back on by itself.
local AUTO_HOLD = 5
local fightEnded, holdUntil = false, 0

local function AutoHeld()
	return fightEnded or GetTime() < holdUntil
end

local function Enter(resuming)
	if active then return end
	if InCombatLockdown() then
		Print(L["Not in a fight."])
		return
	end
	HideNotice()
	fightEnded, holdUntil = false, 0
	if PoleEquipped() then
		-- The pole is in hand already (put on by hand, after a /reload, or after a fight): the
		-- weapons still owed stay, else the ones you held before the pole went on.
		if type(char.weapons) ~= "table" and type(char.lastWeapons) == "table" then
			char.weapons = { char.lastWeapons[1], char.lastWeapons[2] }
		end
	else
		if resuming or not Get("equipPole") then
			if not resuming then Print(L["Equip a fishing pole first."]) end
			return
		end
		local pole = FindPole()
		if not pole then
			Print(L["No fishing pole in your bags."])
			return
		end
		SaveWeapons()
		equipping = true
		Equip(pole)
		enterSerial = enterSerial + 1
		local serial = enterSerial
		C_Timer.After(3, function()
			if serial == enterSerial and equipping then
				equipping = false
				if active and not PoleEquipped() then
					Print(L["The fishing pole couldn't go on."])
					_G.DaylightFishing.Toggle(false)
				end
			end
		end)
	end
	active = true
	char.active = true
	BuildMenu()
	ApplySettings()
	ShowMenu(true)
	fader:Show()
	UpdateBroker()
end

-- reason: "toggle" (the button), "combat" (a fight started: Fishing Mode ends and stays off, the
-- main hand goes on at once and the off hand as the fight ends) or "unequipped" (you took the pole
-- off: your weapons go back on if your main hand is empty or holds your own main hand again, else
-- what you put on stays). With "Put my weapons back on" off, the weapons stay as they are.
local function Leave(reason)
	if not active then return end
	active, equipping, channeling = false, false, false
	char.active = nil
	fader:Hide()
	Unfade()
	KeepWater()
	RestoreSettings()
	ShowMenu(false)
	if reason == "combat" then
		fightEnded = true
		ShowNotice()
	end
	if not Get("restoreWeapons") then
		char.weapons = nil
	elseif type(char.weapons) == "table" then
		local w = char.weapons
		if reason ~= "unequipped" or not GetInventoryItemID("player", 16) or InSlot(16, w[1]) then
			RestoreWeapons()
		end
	end
	SettleWeapons()
	UpdateBroker()
end

local Fishing = {}
_G.DaylightFishing = Fishing

function Fishing.Toggle(on)
	if on == nil then on = not active end
	if on then Enter() else Leave("toggle") end
end

function Fishing.IsActive()
	return active
end

-- A "Fishing Mode" macro (/dui fish) with the Fishing icon, made or brought up to date, and put on
-- the cursor to drop on an action bar. An account macro when there's room, else this character's.
local MACRO_NAME = "Fishing Mode"
local MACRO_BODY = "/dui fish"

-- The Fishing icon as a macro takes it: a file id (the spell's), else the icon's name.
local function MacroIcon()
	local icon = FishingIcon()
	if type(icon) == "number" then return icon end
	if GetFileIDFromPath then
		local id = GetFileIDFromPath(POLE_ICON)
		if id then return id end
	end
	return "Trade_Fishing"
end

function Fishing.MakeMacro()
	if InCombatLockdown() then
		Print(L["Macros can't be made in a fight."])
		return
	end
	local icon = MacroIcon()
	local index = GetMacroIndexByName(MACRO_NAME)
	local made = false
	if index and index > 0 then
		EditMacro(index, MACRO_NAME, icon, MACRO_BODY)
	else
		local account, perChar = GetNumMacros()
		local maxAccount = MAX_ACCOUNT_MACROS or 120
		local maxChar = MAX_CHARACTER_MACROS or 18
		if (account or 0) < maxAccount then
			index = CreateMacro(MACRO_NAME, icon, MACRO_BODY, false)
		elseif (perChar or 0) < maxChar then
			index = CreateMacro(MACRO_NAME, icon, MACRO_BODY, true)
		else
			Print(L["Your macros are full: delete one and try again."])
			return
		end
		made = true
	end
	if not index or index <= 0 then
		Print(L["The macro couldn't be made."])
		return
	end
	PickupMacro(index)
	Print(made and L["Made the \"Fishing Mode\" macro. It's on your cursor: drop it on an action bar (it's in your macros too)."]
		or L["Updated the \"Fishing Mode\" macro. It's on your cursor: drop it on an action bar (it's in your macros too)."])
end

-- ---------------------------------------------------------------------------------------------
-- The data text
-- ---------------------------------------------------------------------------------------------

local LDB = LibStub and LibStub("LibDataBroker-1.1", true)
local broker

-- ---------------------------------------------------------------------------------------------
-- This session's catch: every fishing loot since you logged in (a /reload keeps it), kept per
-- character. caught = the catches (each loot from the water), items = what was in them.
-- ---------------------------------------------------------------------------------------------

local MAX_LINES = 20

local function Session()
	char.session = char.session or { caught = 0, items = {} }
	return char.session
end

local function Caught()
	return char and Session().caught or 0
end

function UpdateCatch()
	if menu and menu.catch then
		local n = Caught()
		menu.catch.text:SetText(L["Caught %d"]:format(n))
		menu.catch.text:SetTextColor(TextColor(n > 0 and "VALUE" or "OFF"))
		menu.catch:SetWidth(math.max(40, math.ceil(menu.catch.text:GetStringWidth()) + 4))
	end
	RefreshPanel()
end

function Fishing.ResetCatch()
	if not char then return end
	char.session = { caught = 0, items = {} }
	UpdateCatch()
	UpdateBroker()
end

-- What came up this session, the most first.
function Fishing.SortedCatch()
	local list = {}
	if not char then return list end
	for _, item in pairs(Session().items) do list[#list + 1] = item end
	table.sort(list, function(x, y)
		if x.count ~= y.count then return x.count > y.count end
		return (x.name or "") < (y.name or "")
	end)
	return list
end

-- ---------------------------------------------------------------------------------------------
-- The catch list: opened by clicking the menu's "Caught" count, at the menu's right
-- ---------------------------------------------------------------------------------------------

local panel
local ROW, MAX_ROWS = 20, 25

local function PanelRow(i)
	local row = panel.rows[i]
	if row then return row end
	row = CreateFrame("Button", nil, panel)
	row:SetHeight(ROW)
	row:SetFrameLevel(panel:GetFrameLevel() + 10)
	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(16, 16)
	row.icon:SetPoint("LEFT", 0, 0)
	row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	row.count = API.Text(row, "small", "RIGHT")
	row.count:SetPoint("RIGHT", 0, 0)
	row.name = API.Text(row, "small", "LEFT")
	row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
	row.name:SetPoint("RIGHT", row.count, "LEFT", -6, 0)
	row.name:SetWordWrap(false)
	local hl = row:CreateTexture(nil, "HIGHLIGHT")
	hl:SetAllPoints()
	hl:SetColorTexture(1, 1, 1, 0.06)
	row:SetScript("OnEnter", function(self)
		if not self.link then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetHyperlink(self.link)
		GameTooltip:Show()
	end)
	row:SetScript("OnLeave", function() GameTooltip:Hide() end)
	-- Shift-click: the item's link into chat, as everywhere in the game.
	row:SetScript("OnClick", function(self)
		if self.link and IsModifiedClick("CHATLINK") then ChatEdit_InsertLink(self.link) end
	end)
	panel.rows[i] = row
	return row
end

function RefreshPanel()
	if not panel or not panel:IsShown() then return end
	local list = Fishing.SortedCatch()
	local n = Caught()
	local items = 0
	for _, item in ipairs(list) do items = items + item.count end
	panel.total:SetText(L["%s, %s"]:format(Plural(n, L["%d catch"], L["%d catches"], L["%d catches#few"]),
		Plural(items, L["%d item"], L["%d items"], L["%d items#few"])))
	panel.total:SetTextColor(TextColor("TEXT"))
	local top = -46
	local shown = math.min(#list, MAX_ROWS)
	for i = 1, shown do
		local item, row = list[i], PanelRow(i)
		row.link = item.link
		row.icon:SetTexture(item.icon or 134400)
		row.name:SetText(item.link or item.name or "?")
		row.count:SetText(item.count)
		row.count:SetTextColor(API.Accent())
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, top - (i - 1) * ROW)
		row:SetPoint("RIGHT", panel, "RIGHT", -PAD, 0)
		row:Show()
	end
	for i = shown + 1, #panel.rows do panel.rows[i]:Hide() end
	local bottom = top - shown * ROW
	if #list == 0 then
		panel.empty:SetText(L["Nothing caught yet."])
		panel.empty:Show()
		bottom = bottom - 18
	elseif #list > MAX_ROWS then
		panel.empty:SetText(string.format(L["and %d more"], #list - MAX_ROWS))
		panel.empty:Show()
		bottom = bottom - 18
	else
		panel.empty:Hide()
	end
	panel.empty:ClearAllPoints()
	panel.empty:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, top - shown * ROW - 2)
	panel:SetSize(math.max(WIDTH, math.floor(menu:GetWidth() + 0.5)), -bottom + 38)
	SkinWindow(panel)
end

local function BuildPanel()
	if panel or not menu then return end
	panel = CreateFrame("Frame", "DaylightFishingCatch", menu)
	panel:SetPoint("TOPLEFT", menu, "TOPRIGHT", 6, 0)
	panel:SetClampedToScreen(true)
	panel:EnableMouse(true)
	panel:Hide()
	panel.rows = {}
	panel.title = API.Text(panel, "small", "LEFT")
	panel.title:SetPoint("TOPLEFT", PAD, -8)
	panel.title:SetText(L["Catch this session"])
	panel.title:SetTextColor(API.Accent())
	panel.total = API.Text(panel, "tiny", "LEFT")
	panel.total:SetPoint("TOPLEFT", panel.title, "BOTTOMLEFT", 0, -4)
	panel.close = API.Close(panel, function() panel:Hide() end, 14)
	panel.close:SetPoint("TOPRIGHT", -8, -7)
	panel.empty = API.Text(panel, "small", "LEFT")
	panel.empty:SetTextColor(TextColor("OFF"))
	panel.clear = API.Button(panel, L["Clear"], 20)
	panel.clear:SetSize(70, 20)
	panel.clear:SetPoint("BOTTOMRIGHT", -8, 8)
	panel.clear:SetFrameLevel(panel:GetFrameLevel() + 10)
	panel.clear:SetScript("OnClick", function() Fishing.ResetCatch() end)
	panel:SetScript("OnShow", RefreshPanel)
end

function Fishing.ToggleCatchPanel(show)
	BuildPanel()
	if not panel then return end
	if show == nil then show = not panel:IsShown() end
	panel:SetShown(show)
end

-- ---------------------------------------------------------------------------------------------
-- Fishing skill and where to train the next rank
-- ---------------------------------------------------------------------------------------------

-- How each rank is learned, from Wowhead's WoW: Forever pages (checked 2026-11-12): Apprentice and
-- Journeyman from any fishing trainer, Expert from a book sold in Booty Bay, Artisan from Nat
-- Pagle's quest in Dustwallow Marsh. trainAt is the fishing skill a rank can be learned at, level
-- the character level it asks for (nil where the page doesn't say; Journeyman's 50 is the game's
-- usual "25 before your cap").
local TOP_CAP = 300
local RANKS = {
	{ name = "Apprentice", title = L["Apprentice Fishing - Up to %d"], cap = 75, trainAt = 0, how = "trainer" },
	{ name = "Journeyman", title = L["Journeyman Fishing - Up to %d"], cap = 150, trainAt = 50, how = "trainer" },
	{ name = "Expert", title = L["Expert Fishing - Up to %d"], cap = 225, trainAt = 125, level = 20, how = "book",
	  item = 16083, itemName = "Expert Fishing - The Bass and You", price = 10000, who = "Old Man Heming",
	  spot = { map = 1434, x = 27.4, y = 77.0, zone = "Booty Bay", area = 35 } },
	{ name = "Artisan", title = L["Artisan Fishing - Up to %d"], cap = 300, trainAt = 225, level = 35, how = "quest",
	  quest = 6607, questName = "Nat Pagle, Angler Extreme", who = "Nat Pagle",
	  spot = { map = 1445, x = 58.6, y = 60.0, zone = "Dustwallow Marsh", onMap = true } },
}

-- The fishing trainers (Apprentice and Journeyman), from the same pages. side: "A", "H", or nil for
-- neutral. map: the zone's map (Riverglades, a Forever zone, is 2548: its Powderfuse Port area 16727
-- sits on that map in the game's area-to-map table). zone: the place's English name; area: its area
-- number, or onMap when the place is the whole map, so other languages get the game's own name.
local TRAINERS = {
	{ name = "Androl Oakhand", side = "A", map = 1438, x = 56.0, y = 93.6, zone = "Rut'theran Village", area = 702 },
	{ name = "Arnold Leland", side = "A", map = 1453, x = 55.0, y = 69.6, zone = "Stormwind", onMap = true },
	{ name = "Astaia", side = "A", map = 1457, x = 47.6, y = 56.6, zone = "Darnassus", onMap = true },
	{ name = "Brannock", side = "A", map = 1444, x = 32.2, y = 41.6, zone = "Feathermoon Stronghold", area = 1116 },
	{ name = "Donald Rabonne", side = "A", map = 1424, x = 50.6, y = 61.0, zone = "Southshore", area = 271 },
	{ name = "Grimnur Stonebrand", side = "A", map = 1455, x = 48.4, y = 6.4, zone = "Ironforge", onMap = true },
	{ name = "Harold Riggs", side = "A", map = 1437, x = 8.2, y = 58.6, zone = "Menethil Harbor", area = 150 },
	{ name = "Lee Brown", side = "A", map = 1429, x = 47.6, y = 62.2, zone = "Goldshire", area = 87 },
	{ name = "Matthew Hooper", side = "A", map = 1433, x = 26.8, y = 50.4, zone = "Lakeshire", area = 69 },
	{ name = "Paxton Ganter", side = "A", map = 1426, x = 35.6, y = 40.4, zone = "Brewnall Village", area = 137 },
	{ name = "Warg Deepwater", side = "A", map = 1432, x = 40.6, y = 39.6, zone = "Thelsamar", area = 144 },
	{ name = "Armand Cromwell", side = "H", map = 1458, x = 80.8, y = 31.2, zone = "Undercity", onMap = true },
	{ name = "Clyde Kellen", side = "H", map = 1420, x = 67.2, y = 51.0, zone = "Brightwater Lake", area = 162 },
	{ name = "Kah Mistrunner", side = "H", map = 1456, x = 56.0, y = 46.8, zone = "Thunder Bluff", onMap = true },
	{ name = "Katoom the Angler", side = "H", map = 1425, x = 80.2, y = 81.4, zone = "Revantusk Village", area = 3317 },
	{ name = "Kil'Hiwana", side = "H", map = 1440, x = 10.8, y = 33.6, zone = "Ashenvale", onMap = true },
	{ name = "Lau'Tiki", side = "H", map = 1411, x = 53.2, y = 81.6, zone = "Sen'jin Village", area = 367 },
	{ name = "Lui'Mala", side = "H", map = 1443, x = 22.6, y = 72.6, zone = "Shadowprey Village", area = 2408 },
	{ name = "Lumak", side = "H", map = 1454, x = 69.8, y = 29.6, zone = "Orgrimmar", onMap = true },
	{ name = "Uthan Stillwater", side = "H", map = 1412, x = 44.6, y = 60.6, zone = "Bloodhoof Village", area = 222 },
	{ name = "Myizz Luckycatch", map = 1434, x = 27.6, y = 77.0, zone = "Booty Bay", area = 35 },
	{ name = "Fenn Fairweather", map = 2521, x = 45.0, y = 48.4, zone = "Shen'dar Village", area = 16624 },
	{ name = "Baelann Swiftcurrent", map = 2521, x = 63.2, y = 75.6, zone = "Valanaar", area = 16638 },
	{ name = "Krix", map = 2548, x = 79.2, y = 54.6, zone = "Powderfuse Port", area = 16727 },
}

-- skill, cap (nil, nil when Fishing isn't learned).
local function FishingSkill()
	if GetProfessions and GetProfessionInfo then
		local _, _, _, fishing = GetProfessions()
		if fishing then
			local _, _, rank, cap = GetProfessionInfo(fishing)
			if type(rank) == "number" then return rank, cap end
		end
	end
	if GetNumSkillLines and GetSkillLineInfo then
		local want = FishingName()
		for i = 1, GetNumSkillLines() do
			local name, header, _, rank, _, _, cap = GetSkillLineInfo(i)
			if not header and name == want then return rank, cap end
		end
	end
end

-- The next rank (a RANKS entry), nil at the top.
local function NextRank(skill, cap)
	if not skill then return RANKS[1] end
	for _, rank in ipairs(RANKS) do
		if rank.cap > (cap or 0) then return rank end
	end
end

-- Whether the next rank can be learned now (skill, and level where it asks).
local function CanLearn(rank, skill)
	if not rank then return false end
	if (skill or 0) < rank.trainAt then return false end
	return not rank.level or (UnitLevel("player") or 0) >= rank.level
end

function UpdateSkill()
	if not menu or not menu.skillBar then return end
	local skill, cap = FishingSkill()
	local bar, mark = menu.skillBar, menu.skillMark
	if not skill then
		menu.skillText:SetText(L["Fishing Skill"])
		menu.skillText:SetTextColor(TextColor("LABEL"))
		menu.skillMax:SetText(L["not learned"])
		menu.skillMax:SetTextColor(TextColor("LABEL"))
		bar:SetMinMaxValues(0, 1)
		bar:SetValue(0)
		mark:Hide()
		return
	end
	-- At the top rank there's nothing left to train: it says so instead.
	menu.skillText:SetText((cap and cap >= TOP_CAP) and L["Maximum Fishing Trained"] or L["Fishing Skill"])
	menu.skillText:SetTextColor(TextColor("LABEL"))
	menu.skillMax:SetText(skill .. " / " .. (cap or skill))
	menu.skillMax:SetTextColor(TextColor("LABEL"))
	bar:SetMinMaxValues(0, math.max(1, cap or skill))
	bar:SetValue(skill)
	local rank = NextRank(skill, cap)
	local width = bar:GetWidth()
	if rank and cap and cap > 0 and rank.trainAt <= cap and type(width) == "number" and width > 0 then
		mark:ClearAllPoints()
		mark:SetPoint("CENTER", bar, "LEFT", math.min(width - 1, width * rank.trainAt / cap), 0)
		mark:SetColorTexture(TextColor(CanLearn(rank, skill) and "GOOD" or "VALUE"))
		mark:Show()
	else
		mark:Hide()
	end
end

-- An amount of money as plain short text: "1g", "1g 50s", "75s" (the game's own letters).
local GOLD, SILVER, COPPER = GOLD_AMOUNT_SYMBOL or "g", SILVER_AMOUNT_SYMBOL or "s", COPPER_AMOUNT_SYMBOL or "c"
local function MoneyText(copper)
	local g, s, c = math.floor(copper / 10000), math.floor(copper % 10000 / 100), copper % 100
	local parts = {}
	if g > 0 then parts[#parts + 1] = g .. GOLD end
	if s > 0 then parts[#parts + 1] = s .. SILVER end
	if c > 0 or #parts == 0 then parts[#parts + 1] = c .. COPPER end
	return table.concat(parts, " ")
end

-- Names in the game's language. On an English client the names written above stay as they are;
-- elsewhere the place comes from its area (or map) number, the book and the quest from their
-- numbers, and the English name stands in until the game has loaded the item or quest (its answer
-- redraws the box).
local ENGLISH = not GetLocale or GetLocale():sub(1, 2) == "en"

local function PlaceName(spot)
	if ENGLISH then return spot.zone end
	local name
	if spot.area and C_Map.GetAreaInfo then
		name = C_Map.GetAreaInfo(spot.area)
	elseif spot.onMap and spot.map then
		local info = C_Map.GetMapInfo(spot.map)
		name = info and info.name
	end
	return (type(name) == "string" and name ~= "") and name or spot.zone
end

local function BookName(rank)
	if ENGLISH or not C_Item then return rank.itemName end
	local name = C_Item.GetItemNameByID and C_Item.GetItemNameByID(rank.item)
	if name and name ~= "" then return name end
	if C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(rank.item) end
	return rank.itemName
end

local function QuestName(rank)
	if ENGLISH or not C_QuestLog then return rank.questName end
	local name = C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(rank.quest)
	if name and name ~= "" then return name end
	if C_QuestLog.RequestLoadQuestByID then C_QuestLog.RequestLoadQuestByID(rank.quest) end
	return rank.questName
end

-- A rank's heading: "Expert Fishing - Up to 225".
local function RankTitle(rank)
	return rank.title:format(rank.cap)
end

-- Two whole sentences, one after the other (Chinese puts no space between them).
local function Then(first, second)
	return L["%s %s"]:format(first, second)
end

-- What the next rank takes, short: where to get it, then the skill it's usable at. The level only
-- when you're under it.
local function HowText(rank)
	local text
	if rank.how == "book" then
		text = L["Purchase \"%s\" from %s in %s for %s."]:format(BookName(rank), rank.who, PlaceName(rank.spot), MoneyText(rank.price))
	elseif rank.how == "quest" then
		text = L["Complete \"%s\" from %s in %s."]:format(QuestName(rank), rank.who, PlaceName(rank.spot))
	else
		text = L["Train with any fishing trainer."]
	end
	-- The book is usable at a skill, a trainer's rank trainable at it, the quest obtainable at it
	-- (with its level, which it always names).
	if rank.how == "quest" then
		text = Then(text, L["Obtainable at %d Fishing and Level %d."]:format(rank.trainAt, rank.level))
		return text
	elseif rank.trainAt > 0 then
		text = Then(text, (rank.how == "book" and L["Usable at %d Fishing."] or L["Trainable at %d Fishing."]):format(rank.trainAt))
	end
	if rank.level and (UnitLevel("player") or 0) < rank.level then
		text = Then(text, L["Needs level %d."]:format(rank.level))
	end
	return text
end

-- Kept short: the next rank as the title, what it takes (wrapped), whether you can learn it, the
-- click. The skill itself is on the bar already.
function Fishing.SkillTooltip(anchor)
	local skill, cap = FishingSkill()
	local rank = NextRank(skill, cap)
	GameTooltip:SetOwner(anchor, "ANCHOR_TOP")
	if not rank then
		GameTooltip:SetText(L["Fishing - Maximum Trained"])
		GameTooltip:Show()
		return
	end
	GameTooltip:SetText(RankTitle(rank))
	-- (Colors are passed apart: a call that returns three values only gives its first when another
	-- argument follows it.)
	local r, g, b = TextColor("TEXT")
	GameTooltip:AddLine(HowText(rank), r, g, b, true)
	if CanLearn(rank, skill) then
		r, g, b = TextColor("GOOD")
		GameTooltip:AddLine(L["You can learn it now."], r, g, b)
	end
	r, g, b = TextColor("OFF")
	GameTooltip:AddLine(L["Click: where to go"], r, g, b)
	GameTooltip:Show()
end

-- ---------------------------------------------------------------------------------------------
-- The box: where to learn the next rank, closest first
-- ---------------------------------------------------------------------------------------------

local box
local RefreshBox

-- A spot's map, when the game has it (Riverglades only exists on Forever).
local function MapOf(spot)
	local map = spot.map
	if not map or not C_Map.GetMapInfo then return map end
	return C_Map.GetMapInfo(map) and map or nil
end

-- Where you are, in world terms: continent, x, y.
local function Here()
	local map = C_Map.GetBestMapForUnit("player")
	local pos = map and C_Map.GetPlayerMapPosition(map, "player")
	if not pos then return nil end
	local continent, world = C_Map.GetWorldPosFromMapPos(map, pos)
	if not continent or not world then return nil end
	return continent, world.x, world.y
end

-- Yards between you and a spot, or nil when it's on another continent (or its map isn't known).
local function Distance(spot, continent, px, py)
	local map = MapOf(spot)
	if not map or not continent or not CreateVector2D then return nil end
	local c, world = C_Map.GetWorldPosFromMapPos(map, CreateVector2D(spot.x / 100, spot.y / 100))
	if c ~= continent or not world then return nil end
	return math.sqrt((world.x - px) ^ 2 + (world.y - py) ^ 2)
end

local function Waypoint(name, spot)
	local map = MapOf(spot)
	local where = ("%s, %s (%d, %d)"):format(name, PlaceName(spot), spot.x + 0.5, spot.y + 0.5)
	if not map then
		Print(L["%s."]:format(where))
		return false
	end
	local tomtom = _G.TomTom
	if type(tomtom) == "table" and type(tomtom.AddWaypoint) == "function" then
		pcall(tomtom.AddWaypoint, tomtom, map, spot.x / 100, spot.y / 100, { title = name, from = "Daylight Fishing" })
	elseif C_Map.SetUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates then
		if C_Map.CanSetUserWaypointOnMap and not C_Map.CanSetUserWaypointOnMap(map) then
			Print(L["%s. The map there takes no pins."]:format(where))
			return false
		end
		pcall(C_Map.SetUserWaypoint, UiMapPoint.CreateFromCoordinates(map, spot.x / 100, spot.y / 100))
		if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then pcall(C_SuperTrack.SetSuperTrackedUserWaypoint, true) end
	end
	Print(L["Waypoint: %s."]:format(where))
	return true
end

local BOX_ROWS, BOX_ROW = 8, 30

-- A pin went down: the box's bottom line says so, in green, for a few seconds (RefreshBox reads
-- pinnedUntil, so a redraw in between keeps it).
local PINNED_FOR = 3
local pinnedUntil = 0
local function ShowPinned()
	pinnedUntil = GetTime() + PINNED_FOR
	RefreshBox()
	C_Timer.After(PINNED_FOR + 0.05, function() RefreshBox() end)
end

local function BoxRow(i)
	local row = box.rows[i]
	if row then return row end
	row = CreateFrame("Button", nil, box)
	row:SetHeight(BOX_ROW)
	row:SetFrameLevel(box:GetFrameLevel() + 10)
	row.name = API.Text(row, "small", "LEFT")
	row.name:SetPoint("TOPLEFT", 0, -2)
	row.dist = API.Text(row, "small", "RIGHT")
	row.dist:SetPoint("TOPRIGHT", 0, -2)
	row.name:SetPoint("RIGHT", row.dist, "LEFT", -6, 0)
	row.name:SetWordWrap(false)
	row.place = API.Text(row, "tiny", "LEFT")
	row.place:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -3)
	row.place:SetPoint("RIGHT", 0, 0)
	row.place:SetWordWrap(false)
	local hl = row:CreateTexture(nil, "HIGHLIGHT")
	hl:SetAllPoints()
	hl:SetColorTexture(1, 1, 1, 0.06)
	row:SetScript("OnEnter", function(self)
		if not self.spot then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		if self.item then
			GameTooltip:SetItemByID(self.item)
			GameTooltip:AddLine(L["Sold by %s, %s (%d, %d)"]:format(self.who, PlaceName(self.spot), self.spot.x + 0.5, self.spot.y + 0.5), 1, 1, 1)
		else
			GameTooltip:SetText(self.who)
			GameTooltip:AddLine(("%s (%d, %d)"):format(PlaceName(self.spot), self.spot.x + 0.5, self.spot.y + 0.5), 1, 1, 1)
		end
		GameTooltip:AddLine(L["Click for a waypoint."], TextColor("LABEL"))
		GameTooltip:Show()
	end)
	row:SetScript("OnLeave", function() GameTooltip:Hide() end)
	row:SetScript("OnClick", function(self)
		if self.spot and Waypoint(self.who, self.spot) then ShowPinned() end
	end)
	box.rows[i] = row
	return row
end

-- Your faction's trainers and the neutral ones.
local function Allowed(side)
	if not side then return true end
	return side == (UnitFactionGroup("player") == "Horde" and "H" or "A")
end

local SIDE_WORDS = { A = FACTION_ALLIANCE or "Alliance", H = FACTION_HORDE or "Horde" }

local function YardsText(d)
	return d and L["%d yd"]:format(math.floor(d / 10 + 0.5) * 10) or ""
end

function RefreshBox()
	if not box or not box:IsShown() then return end
	local skill, cap = FishingSkill()
	local rank = NextRank(skill, cap)
	local continent, px, py = Here()
	-- The places to go: the closest trainers, or the one seller or quest giver.
	local list = {}
	if not rank then
		box.title:SetText(L["Fishing - Maximum Trained"])
		box.sub:SetText(L["You have the highest rank of Fishing."])
	elseif rank.how == "trainer" then
		box.title:SetText(RankTitle(rank))
		box.sub:SetText(HowText(rank))
		for _, t in ipairs(TRAINERS) do
			if Allowed(t.side) then
				list[#list + 1] = { who = t.name, spot = t, dist = Distance(t, continent, px, py),
					side = SIDE_WORDS[t.side] or FACTION_NEUTRAL or "Neutral", place = PlaceName(t) }
			end
		end
		table.sort(list, function(a, b)
			if a.dist and b.dist then return a.dist < b.dist end
			if a.dist or b.dist then return a.dist ~= nil end
			if a.place ~= b.place then return a.place < b.place end
			return a.who < b.who
		end)
	else
		box.title:SetText(RankTitle(rank))
		box.sub:SetText(HowText(rank))
		list[1] = { who = rank.who, spot = rank.spot, dist = Distance(rank.spot, continent, px, py),
			item = rank.item }
	end
	-- As wide as the menu under it. The width goes on first, so the wrapped text is measured at it.
	local width = math.max(WIDTH, math.floor(menu:GetWidth() + 0.5))
	box:SetWidth(width)
	box.sub:SetWidth(width - PAD * 2 - 16)
	local top = -8 - math.ceil(box.title:GetStringHeight()) - 4 - math.ceil(box.sub:GetStringHeight()) - 10
	local shown = math.min(#list, BOX_ROWS)
	for i = 1, shown do
		local e, row = list[i], BoxRow(i)
		row.who, row.spot, row.item = e.who, e.spot, e.item
		row.name:SetText(e.who)
		row.name:SetTextColor(TextColor("VALUE"))
		row.dist:SetText(YardsText(e.dist))
		row.dist:SetTextColor(TextColor("LABEL"))
		local place = ("%s (%d, %d)"):format(PlaceName(e.spot), e.spot.x + 0.5, e.spot.y + 0.5)
		row.place:SetText(e.side and (place .. "  ·  " .. e.side) or place)
		row.place:SetTextColor(API.Accent())
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", box, "TOPLEFT", PAD, top - (i - 1) * (BOX_ROW + 4))
		row:SetPoint("RIGHT", box, "RIGHT", -PAD, 0)
		row:Show()
	end
	for i = shown + 1, #box.rows do box.rows[i]:Hide() end
	local bottom = top - shown * (BOX_ROW + 4) + (shown > 0 and 4 or 6)
	box.note:SetTextColor(TextColor("OFF"))
	if GetTime() < pinnedUntil then
		box.note:SetText(L["Location Pinned"])
		box.note:SetTextColor(TextColor("GOOD"))
	elseif not rank then
		box.note:SetText("")
	elseif rank.how == "trainer" then
		box.note:SetText(#list == 0 and L["No fishing trainer found for your faction."] or L["Closest first. Click one for a waypoint."])
	else
		box.note:SetText(L["Click for a waypoint."])
	end
	box.note:ClearAllPoints()
	box.note:SetPoint("TOPLEFT", box, "TOPLEFT", PAD, bottom - 4)
	box.note:SetPoint("RIGHT", box, "RIGHT", -PAD, 0)
	if box.note:GetText() and box.note:GetText() ~= "" then
		bottom = bottom - 4 - math.ceil(box.note:GetStringHeight())
	end
	box:SetHeight(-bottom + 10)
	SkinWindow(box)
end

local function BuildBox()
	if box or not menu then return end
	box = CreateFrame("Frame", "DaylightFishingTrainers", menu)
	box:SetPoint("BOTTOMLEFT", menu, "TOPLEFT", 0, 6)
	box:SetClampedToScreen(true)
	box:EnableMouse(true)
	box:Hide()
	box.rows = {}
	box.title = API.Text(box, "small", "LEFT")
	box.title:SetPoint("TOPLEFT", PAD, -8)
	box.title:SetTextColor(API.Accent())
	box.sub = API.Text(box, "tiny", "LEFT")
	box.sub:SetPoint("TOPLEFT", box.title, "BOTTOMLEFT", 0, -4)
	box.sub:SetPoint("RIGHT", box, "RIGHT", -PAD - 16, 0)
	box.sub:SetJustifyH("LEFT")
	box.sub:SetWordWrap(true)
	box.sub:SetTextColor(TextColor("TEXT"))
	box.close = API.Close(box, function() box:Hide() end, 14)
	box.close:SetPoint("TOPRIGHT", -8, -7)
	box.note = API.Text(box, "tiny", "LEFT")
	box.note:SetTextColor(TextColor("OFF"))
	box:SetScript("OnShow", RefreshBox)
end

function Fishing.ToggleTrainers(show)
	BuildBox()
	if not box then return end
	if show == nil then show = not box:IsShown() end
	box:SetShown(show)
end

-- The catch's lines on a tooltip: the count, then what came up, the most first.
function Fishing.CatchTooltip(tip, title)
	local s = char and Session()
	local n = s and s.caught or 0
	if title then tip:SetText(L["This session's catch"]) end
	tip:AddDoubleLine(L["Fish caught"], tostring(n), 1, 1, 1, API.Accent())
	if n == 0 then
		tip:AddLine(L["Nothing caught yet."], TextColor("OFF"))
		return
	end
	local list = Fishing.SortedCatch()
	for i = 1, math.min(#list, MAX_LINES) do
		local item = list[i]
		local icon = item.icon and ("|T" .. item.icon .. ":14:14:0:0:64:64:5:59:5:59|t ") or ""
		tip:AddDoubleLine(icon .. (item.link or item.name or "?"), "x" .. item.count, 1, 1, 1, TextColor("VALUE"))
	end
	if #list > MAX_LINES then
		tip:AddLine(string.format(L["and %d more"], #list - MAX_LINES), TextColor("OFF"))
	end
end

-- ---------------------------------------------------------------------------------------------
-- The catch popup, at the fishing menu's left: "Fish Caught!" with what came up, or "Fish Got
-- Away". It shows for a few seconds and fades out (held while the mouse is on it), and stays
-- while the rest of the UI is faded.
-- ---------------------------------------------------------------------------------------------

local popup
local POPUP_W, POPUP_ROW, POPUP_ROWS = 210, 18, 4
local POPUP_IN, POPUP_HOLD, POPUP_OUT = 0.15, 3, 0.6

local function BuildPopup()
	if popup then return end
	popup = CreateFrame("Frame", "DaylightFishingPopup", UIParent)
	popup:SetIgnoreParentAlpha(true)
	popup:SetFrameStrata("MEDIUM")
	popup:SetClampedToScreen(true)
	popup:Hide()
	popup.title = API.Text(popup, "body", "LEFT")
	popup.title:SetPoint("TOPLEFT", PAD, -9)
	popup.rows = {}
	popup:SetScript("OnUpdate", function(self, elapsed)
		self.age = self.age + elapsed
		if self:IsMouseOver() and self.age > POPUP_IN then self.age = math.min(self.age, POPUP_IN + POPUP_HOLD) end
		local a
		if self.age < POPUP_IN then
			a = self.age / POPUP_IN
		elseif self.age < POPUP_IN + POPUP_HOLD then
			a = 1
		else
			a = 1 - (self.age - POPUP_IN - POPUP_HOLD) / POPUP_OUT
		end
		if a <= 0 then
			self:Hide()
			return
		end
		self:SetAlpha(a)
	end)
end

local function PopupRow(i)
	local row = popup.rows[i]
	if row then return row end
	row = {}
	row.icon = popup:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(14, 14)
	row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	row.text = API.Text(popup, "small", "LEFT")
	row.text:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
	row.text:SetPoint("RIGHT", popup, "RIGHT", -PAD, 0)
	row.text:SetWordWrap(false)
	popup.rows[i] = row
	return row
end

-- caught: true with this loot's items ({ icon, link, count }), or false for one that got away.
local function ShowPopup(caught, items)
	if not active or not Get("catchPopup") then return end
	BuildPopup()
	if caught then
		popup.title:SetText(L["Fish Caught!"])
		popup.title:SetTextColor(TextColor("GOOD"))
	else
		popup.title:SetText(L["Fish Got Away"])
		popup.title:SetTextColor(TextColor("BAD"))
	end
	items = items or {}
	local shown = math.min(#items, POPUP_ROWS)
	for i = 1, shown do
		local item, row = items[i], PopupRow(i)
		row.icon:SetTexture(item.icon or 134400)
		row.icon:ClearAllPoints()
		row.icon:SetPoint("TOPLEFT", popup, "TOPLEFT", PAD, -32 - (i - 1) * POPUP_ROW)
		row.text:SetText((item.link or "?") .. (item.count > 1 and (" x" .. item.count) or ""))
		row.icon:Show()
		row.text:Show()
	end
	for i = shown + 1, #popup.rows do
		popup.rows[i].icon:Hide()
		popup.rows[i].text:Hide()
	end
	popup:SetSize(POPUP_W, 34 + shown * POPUP_ROW + (shown > 0 and 6 or 0))
	popup:SetScale(Get("menuScale") or 1)
	popup:ClearAllPoints()
	if menu and menu:IsShown() then
		popup:SetPoint("TOPRIGHT", menu, "TOPLEFT", -6, 0)
	else
		popup:SetPoint("CENTER", UIParent, "CENTER", -240, -190)
	end
	SkinWindow(popup)
	popup.age = 0
	popup:SetAlpha(0)
	popup:Show()
end

-- Whether the last line in the water came back with a fish. A line that comes in with no fishing
-- loot soon after (and wasn't ended by moving or a new cast) got away; the game's own "got away"
-- and "no fish are hooked" messages say so at once.
local ESCAPE_WAIT = 2.5
local castSerial, pendingCast, castMoved = 0, nil, false
local resolvedCast = 0      -- the last cast that already had its popup

local function GotAway()
	if not pendingCast then return end
	resolvedCast = pendingCast
	pendingCast = nil
	ShowPopup(false)
end

-- One loot from the water: counted once, however many times the loot events come.
local looting = false
local function TakeCatch()
	if looting or not char then return end
	if not (IsFishingLoot and IsFishingLoot()) then return end
	looting = true
	pendingCast = nil
	resolvedCast = castSerial
	local s = Session()
	s.caught = s.caught + 1
	local this = {}
	local ITEM = Enum and Enum.LootSlotType and Enum.LootSlotType.Item or 1
	for i = 1, GetNumLootItems() do
		local kind = GetLootSlotType and GetLootSlotType(i) or ITEM
		local link = GetLootSlotLink(i)
		if kind == ITEM and link then
			local icon, name, quantity = GetLootSlotInfo(i)
			local id = C_Item.GetItemInfoInstant(link) or name
			local item = s.items[id]
			if not item then
				item = { count = 0 }
				s.items[id] = item
			end
			item.link, item.name, item.icon = link, name, icon
			local n = (quantity and quantity > 0) and quantity or 1
			item.count = item.count + n
			this[#this + 1] = { icon = icon, link = link, count = n }
		end
	end
	UpdateCatch()
	UpdateBroker()
	ShowPopup(true, this)
end

function UpdateBroker()
	if not broker then return end
	local n = Caught()
	local count = n > 0 and (" · " .. n) or ""
	if active then
		broker.text = L["On"] .. count
	else
		local r, g, b = TextColor("OFF")
		broker.text = string.format("|cff%02x%02x%02x%s|r", r * 255, g * 255, b * 255, L["Off"]) .. count
	end
end

if LDB then
	broker = LDB:NewDataObject("Daylight Fishing", {
		type = "data source",
		label = L["Fishing Mode"],
		text = L["Off"],
		icon = "Interface\\AddOns\\DaylightFishing\\Media\\icon.png",
		OnClick = function(_, button)
			if button == "RightButton" then
				if IsShiftKeyDown() then
					Fishing.ResetCatch()
					Print(L["This session's catch is cleared."])
				end
				return
			end
			Fishing.Toggle()
		end,
		OnTooltipShow = function(tip)
			tip:AddLine(active and L["Fishing Mode: on"] or L["Fishing Mode: off"])
			local key = KeyText()
			if key then tip:AddLine(L["Fishing key: %s"]:format(key), 1, 1, 1) end
			local left = BaitLeft()
			if active and left then tip:AddLine(string.format(L["Bait on the pole: %d:%02d"], left / 60, left % 60), 1, 1, 1) end
			tip:AddLine(" ")
			Fishing.CatchTooltip(tip)
			tip:AddLine(active and L["Click: turn Fishing Mode off"] or L["Click: turn Fishing Mode on"], 0.8, 0.8, 0.8)
			tip:AddLine(L["Shift-right-click: clear this session's catch"], 0.8, 0.8, 0.8)
		end,
	})
end

-- ---------------------------------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------------------------------

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
events:RegisterEvent("BAG_UPDATE_DELAYED")
events:RegisterEvent("LOOT_READY")
events:RegisterEvent("LOOT_OPENED")
events:RegisterEvent("LOOT_CLOSED")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("UI_ERROR_MESSAGE")
events:RegisterEvent("UI_INFO_MESSAGE")
events:RegisterEvent("PLAYER_STARTED_MOVING")
events:RegisterEvent("SKILL_LINES_CHANGED")
events:RegisterEvent("CHAT_MSG_SKILL")
events:RegisterUnitEvent("UNIT_SPELLCAST_SENT", "player")
events:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", "player")
events:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", "player")
if not ENGLISH then
	events:RegisterEvent("GET_ITEM_INFO_RECEIVED")
	events:RegisterEvent("QUEST_DATA_LOAD_RESULT")
end

local function IsFishing(spellID)
	if spellID == nil or (issecretvalue and issecretvalue(spellID)) then return false end
	if FISHING_IDS[spellID] then return true end
	return spellID and SpellName(spellID) == FishingName()
end

-- Logging in (not a /reload) starts a new session's catch.
local freshLogin = false
local bagsQueued = false

-- 4: after a hook, the key goes back to casting only once it is let go: the release of the press
-- that hooked would otherwise reach the cast button and cast again.
local MOUSE = { BUTTON3 = "MiddleButton", BUTTON4 = "Button4", BUTTON5 = "Button5" }
local function KeyHeld()
	local key = Get("key")
	if not key or key == "NONE" then return false end
	if MOUSE[key] then return IsMouseButtonDown and IsMouseButtonDown(MOUSE[key]) or false end
	return IsKeyDown and IsKeyDown(key) or false
end

local function BindWhenReleased(tries)
	tries = tries or 0
	if not channeling and KeyHeld() and tries < 60 then
		C_Timer.After(0.05, function() BindWhenReleased(tries + 1) end)
		return
	end
	UpdateBinding()
end

-- DaylightUI is ready (its settings too): the saved variables, and Fishing Mode carried over.
-- Mastercraft (another author's addon) has its own "After the fight: your fishing gear back on"
-- (on by default): when a fight that came while you held your pole ends, it puts the pole back on.
-- That fights Fishing Mode ending in a fight. As with every such overlap, the DaylightUI side
-- wins by default: "Fights while fishing" (mastercraftFights) on switches that one Mastercraft
-- setting off and records what it was; off gives the recorded value back. Its setting is read live
-- from its saved settings, so the change holds at once. Asked once, the first time both are loaded.
local function MastercraftSettings()
	if not (C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("Mastercraft")) then return nil end
	local mdb = _G.MastercraftDB
	return type(mdb) == "table" and type(mdb.settings) == "table" and mdb.settings or nil
end

local function ApplyMastercraft()
	local ms = MastercraftSettings()
	if not ms or not db then return end
	if Get("mastercraftFights") ~= false then
		if db.mastercraftWas == nil then db.mastercraftWas = ms.fishAfterFight ~= false end
		ms.fishAfterFight = false
	elseif db.mastercraftWas ~= nil then
		ms.fishAfterFight = db.mastercraftWas
		db.mastercraftWas = nil
	end
end

local function AskMastercraft()
	if not MastercraftSettings() or db.mastercraftAsked then return end
	db.mastercraftAsked = true
	StaticPopupDialogs.DAYLIGHTFISHING_MASTERCRAFT = {
		text = L["Mastercraft puts your fishing pole back on after every fight, and Daylight Fishing ends Fishing Mode in a fight. Which one handles fights while you fish?\n\nDaylight Fishing turns off Mastercraft's \"After the fight: your fishing gear back on\". You can change this any time: Fishing > Fights while fishing."],
		button1 = L["Daylight Fishing"],
		button2 = L["Mastercraft"],
		OnAccept = function() DUI:Set(ADDON, "mastercraftFights", true) end,
		OnCancel = function(_, _, reason)
			if reason == "clicked" then DUI:Set(ADDON, "mastercraftFights", false) end
		end,
		timeout = 0, whileDead = true, hideOnEscape = false, preferredIndex = 3,
	}
	StaticPopup_Show("DAYLIGHTFISHING_MASTERCRAFT")
end

me.On("SettingChanged", function(scope, path)
	if scope == ADDON and path == "mastercraftFights" then ApplyMastercraft() end
end)

local function Login()
	DaylightFishingDB = DaylightFishingDB or {}
	db = DaylightFishingDB
	db.chars = db.chars or {}
	local who = (UnitName("player") or "?") .. "-" .. (GetRealmName() or "?")
	db.chars[who] = db.chars[who] or {}
	char = db.chars[who]
	-- A new session at each login (a /reload keeps the catch).
	if freshLogin then
		freshLogin = false
		char.session = nil
	end
	-- Fishing Mode was on for this character at the last logout or /reload: back on with the pole
	-- still in hand, else the sound goes back to how it was. (Out of combat: a /reload in a fight
	-- waits for its end.)
	db.active = nil   -- (account-wide before 1.5.0)
	OutOfCombat(function()
		if char.active and PoleEquipped() then
			db.saved = db.saved or {}
			Enter(true)
		else
			char.active = nil
			RestoreSettings()
			-- (Weapons still owed with a pole in hand stay owed: they go back on when Fishing Mode
			-- next ends.)
			SettleWeapons()
		end
		UpdateBroker()
	end)
	UpdateBroker()
	ApplyMastercraft()
	AskMastercraft()
	if C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("ForeverFishing") then
		Print(L["Forever Fishing is loaded too: give the two different keys, or turn one off."])
	end
end
me.On("Login", Login)

events:SetScript("OnEvent", function(_, event, a, b, c, d)
	if event == "PLAYER_ENTERING_WORLD" then
		if a then
			if char then Fishing.ResetCatch() else freshLogin = true end
		end
		return
	end
	if not db then return end
	if event == "GET_ITEM_INFO_RECEIVED" or event == "QUEST_DATA_LOAD_RESULT" then
		-- The book's or the quest's name in the game's language came in: the box shows it.
		-- (Only when it loaded: a failed load would ask again, and again.)
		if (a == 16083 or a == 6607) and b and RefreshBox then RefreshBox() end
		return
	end
	if event == "LOOT_READY" or event == "LOOT_OPENED" then
		TakeCatch()
	elseif event == "LOOT_CLOSED" then
		looting = false
	elseif event == "PLAYER_REGEN_DISABLED" then
		Unfade()
		-- A fight while fishing: Fishing Mode ends, and stays off after it. The weapons it took off
		-- go back on (with "Put my weapons back on").
		if active then Leave("combat") end
	elseif event == "PLAYER_REGEN_ENABLED" then
		-- A fight that ended Fishing Mode is over: a pole that goes on now (another addon putting
		-- your fishing gear back on) leaves it off for a few seconds more. Set before the work that
		-- waited for the fight, which may turn Fishing Mode on for a pole.
		if fightEnded then
			fightEnded = false
			holdUntil = GetTime() + AUTO_HOLD
		end
		local list = later
		later = {}
		for i = 1, #list do pcall(list[i]) end
		UpdateBinding()
		-- (The note lets go of the mouse: the menu it kept off is gone with the fight.)
		if notice and notice:IsShown() then notice:EnableMouse(MenuKept()) end
	elseif event == "PLAYER_EQUIPMENT_CHANGED" then
		if a ~= 16 and a ~= 17 then return end
		if not active then SettleWeapons() end
		if a ~= 16 then return end
		if not active then
			-- A pole put on by hand turns Fishing Mode on (after a fight, if it's still in hand), but
			-- not one that goes on in or right after a fight that ended it.
			if Get("autoMode") and char and PoleEquipped() and not AutoHeld() then
				OutOfCombat(function()
					if not active and PoleEquipped() and not AutoHeld() then Enter(true) end
				end)
			end
			return
		end
		if PoleEquipped() then
			equipping = false
		elseif not equipping then
			Leave("unequipped")
		end
	elseif event == "BAG_UPDATE_DELAYED" then
		if active and menu and not bagsQueued then
			bagsQueued = true
			OutOfCombat(function()
				bagsQueued = false
				if active and menu and menu:IsShown() then UpdateMenu() end
			end)
		end
	elseif event == "UNIT_SPELLCAST_CHANNEL_START" then
		if active and IsFishing(c) then
			channeling = true
			castSerial = castSerial + 1
			pendingCast, castMoved = nil, false
			UpdateBinding()
			if cast then cast.state:SetText(L["Hook"]) end
		end
	elseif event == "UNIT_SPELLCAST_CHANNEL_STOP" then
		if channeling then
			channeling = false
			BindWhenReleased()
			if cast then cast.state:SetText(L["Cast"]) end
			if IsFalling() then castMoved = true end
			if not castMoved and resolvedCast ~= castSerial then
				local serial = castSerial
				pendingCast = serial
				C_Timer.After(ESCAPE_WAIT, function()
					if pendingCast == serial then GotAway() end
				end)
			end
		end
	elseif event == "SKILL_LINES_CHANGED" or event == "CHAT_MSG_SKILL" then
		-- A skill point or a new rank: the bar, its mark and the trainer box follow.
		if menu and menu:IsShown() then UpdateSkill() end
		if RefreshBox then RefreshBox() end
	elseif event == "PLAYER_STARTED_MOVING" then
		if channeling then castMoved = true end
	elseif event == "UNIT_SPELLCAST_SENT" then
		if channeling and not IsFishing(d) then castMoved = true end
	elseif event == "UI_ERROR_MESSAGE" or event == "UI_INFO_MESSAGE" then
		if b and (b == _G.ERR_FISH_ESCAPED or b == _G.ERR_FISH_NOT_HOOKED) and (channeling or pendingCast) then
			pendingCast = pendingCast or castSerial
			GotAway()
		end
	end
end)

-- ---------------------------------------------------------------------------------------------
-- DaylightUI: plugin, options page, command
-- ---------------------------------------------------------------------------------------------

-- The fishing key: set in a small box that takes the next key or mouse button pressed (out of a
-- fight), the way Daylight Essentials' Halo sets its key. Space to start; Clear leaves no key (the
-- cast button is clicked instead). Shift, Alt and Ctrl alone can't be it, and neither can Escape
-- (it closes the box) or the left and right mouse buttons (they're for the box itself).
-- (All of it inside one function: Core.lua is near Lua's limit of 200 locals in a file's main
-- function, and none of these is needed outside it.)
Fishing.SetKey = (function()
	local MODIFIERS = { LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true, LALT = true, RALT = true,
		LMETA = true, RMETA = true, SHIFT = true, CTRL = true, ALT = true, META = true }
	local BOX_MOUSE = { MiddleButton = "BUTTON3", Button4 = "BUTTON4", Button5 = "BUTTON5" }

	local keyBox

	local function KeyName(key)
		if type(key) ~= "string" or key == "" or key == "NONE" then return nil end
		if GetBindingText then
			local ok, text = pcall(GetBindingText, key)
			if ok and type(text) == "string" and text ~= "" then return text end
		end
		return key
	end

	local function BoxInk(fs, name)
		local ok, colors = pcall(API.Colors)
		local c = ok and type(colors) == "table" and colors[name]
		if type(c) == "table" then fs:SetTextColor(c[1], c[2], c[3]) end
	end

	local function KeyBoxLayout()
		local kb = keyBox
		kb.now:SetText(L["Now: %s"]:format(KeyName(Get("key")) or L["no key (click the cast button)"]))
		kb.clear:SetShown(KeyName(Get("key")) ~= nil)
		-- Tall enough for every line at its width: nothing is cut short.
		local w = kb:GetWidth() - 24
		local h = 40
		for _, fs in ipairs({ kb.now, kb.help, kb.msg }) do
			fs:SetWidth(w)
			local text = fs:GetText()
			if text and text ~= "" then h = h + math.ceil(fs:GetStringHeight() or 14) + 6 end
		end
		kb:SetHeight(h + 40)
		SkinWindow(kb)
	end

	local function ShowKeyBox(show)
		if show and InCombatLockdown() then
			Print(L["The fishing key can be set out of a fight."])
			return
		end
		local kb = keyBox
		if show then
			kb.msg:SetText("")
			KeyBoxLayout()
			-- Takes every key while it's open (Escape included), so none of them does anything else.
			kb:EnableKeyboard(true)
			kb:SetPropagateKeyboardInput(false)
			kb:Show()
		elseif kb and kb:IsShown() then
			kb:Hide()
			if not InCombatLockdown() then kb:EnableKeyboard(false) end
		end
	end

	local function SaveFishingKey(key)
		if InCombatLockdown() then return end
		local ok = pcall(DUI.Set, DUI, ADDON, "key", key)
		if not ok then
			Print(L["The fishing key couldn't be saved."])
			return
		end
		Print(KeyName(key) and L["The fishing key is now %s."]:format(KeyName(key))
			or L["No fishing key: click the cast button to fish."])
		ShowKeyBox(false)
	end

	local function TakeKey(key)
		if MODIFIERS[key] then
			keyBox.msg:SetText(L["Shift, Alt and Ctrl can't be the fishing key on their own."])
			BoxInk(keyBox.msg, "WARN")
			KeyBoxLayout()
			return
		end
		SaveFishingKey(key)
	end

	local function BuildKeyBox()
		if keyBox then return end
		local kb = CreateFrame("Frame", "DaylightFishingKeyBox", UIParent)
		keyBox = kb
		kb:SetFrameStrata("FULLSCREEN_DIALOG")
		kb:SetToplevel(true)
		kb:SetSize(320, 150)
		kb:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
		kb:SetClampedToScreen(true)
		kb:EnableMouse(true)
		local head = API.Text(kb, "head", "LEFT")
		head:SetPoint("TOPLEFT", kb, "TOPLEFT", 12, -12)
		head:SetText(L["Fishing key"])
		BoxInk(head, "TITLE")
		kb.now = API.Text(kb, "body", "LEFT")
		kb.now:SetPoint("TOPLEFT", kb, "TOPLEFT", 12, -40)
		BoxInk(kb.now, "VALUE")
		kb.help = API.Text(kb, "small", "LEFT")
		kb.help:SetPoint("TOPLEFT", kb.now, "BOTTOMLEFT", 0, -6)
		kb.help:SetText(L["Press the key you want, or click here with the mouse's middle or a side button. Escape cancels."])
		BoxInk(kb.help, "TEXT")
		kb.msg = API.Text(kb, "small", "LEFT")
		kb.msg:SetPoint("TOPLEFT", kb.help, "BOTTOMLEFT", 0, -6)
		for _, fs in ipairs({ kb.now, kb.help, kb.msg }) do fs:SetWordWrap(true) end
		local close = API.Close(kb, function() ShowKeyBox(false) end)
		if close then close:SetPoint("TOPRIGHT", kb, "TOPRIGHT", -6, -6) end
		kb.clear = API.Button(kb, L["Clear"], 24)
		kb.clear:SetWidth(90)
		kb.clear:SetPoint("BOTTOMRIGHT", kb, "BOTTOMRIGHT", -12, 12)
		kb.clear:SetScript("OnClick", function() SaveFishingKey("NONE") end)
		kb.space = API.Button(kb, L["Space"], 24)
		kb.space:SetWidth(90)
		kb.space:SetPoint("RIGHT", kb.clear, "LEFT", -8, 0)
		kb.space:SetScript("OnClick", function() SaveFishingKey("SPACE") end)
		kb:SetScript("OnKeyDown", function(_, key)
			if key == "ESCAPE" then ShowKeyBox(false) else TakeKey(key) end
		end)
		kb:SetScript("OnMouseDown", function(_, which)
			if BOX_MOUSE[which] then TakeKey(BOX_MOUSE[which]) end
		end)
		kb:Hide()
		if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, "DaylightFishingKeyBox") end
	end

	return function()
		BuildKeyBox()
		ShowKeyBox(true)
	end
end)()

local function NotSound(get) return get("sound") == false end

local pages = {
	{ id = "fishing", label = ns.GameText("PROFESSIONS_FISHING", L["Fishing"]),
	  desc = L["Fishing Mode: put \"Fishing Mode\" in a data text slot (Info Panel, Data texts) and click it, or type /dui fish."],
	  groups = {
		{ label = L["Fishing Mode"], items = {
			{ type = "button", label = L["Turn Fishing Mode on or off"], func = function() Fishing.Toggle() end },
			{ type = "button", label = L["Make a Fishing Mode macro"], func = function() Fishing.MakeMacro() end,
			  desc = L["A \"Fishing Mode\" macro with the Fishing icon that turns Fishing Mode on and off. It goes on your cursor: drop it on an action bar."] },
			{ type = "toggle", key = "autoMode", label = L["Turn on when I equip a pole"],
			  desc = L["Putting a fishing pole on turns Fishing Mode on, and taking it off turns it off."] },
			{ type = "button", label = L["Set Fishing Key"], func = function() Fishing.SetKey() end,
			  desc = L["Opens a small box: press any key you want (a mouse's middle or side button works too). Space to start. While Fishing Mode is on, this key casts, and hooks the fish once your bobber is out. It is yours again when Fishing Mode ends, or a fight starts."] },
			{ type = "button", label = L["Clear this session's catch"], func = function() Fishing.ResetCatch() end },
			{ type = "toggle", key = "equipPole", label = L["Put my fishing pole on"],
			  desc = L["Fishing Mode puts on the best fishing pole in your bags."] },
			{ type = "toggle", key = "restoreWeapons", label = L["Put my weapons back on"],
			  desc = L["When you turn Fishing Mode off or get into a fight, the weapons you held go back on."] },
		} },
		{ label = L["Fights while fishing"], items = {
			{ type = "toggle", key = "mastercraftFights", label = L["Daylight Fishing handles fights"],
			  desc = L["With Mastercraft loaded: on, its \"After the fight: your fishing gear back on\" is off, so your pole stays off after a fight. Off gives Mastercraft its own setting back."] },
		} },
		{ label = L["Fishing menu"], items = {
			{ type = "toggle", key = "showMenu", label = L["Show the fishing menu"],
			  desc = L["Your baits and the cast button under your character. Move it with /dui unlock."] },
			{ type = "slider", key = "menuScale", label = L["Menu size"], min = 0.7, max = 1.6, step = 0.05, unit = "%",
			  desc = L["How big the fishing menu is."] },
		} },
		{ label = L["Look"], items = {
			{ type = "toggle", key = "duiOpacity", label = L["Use DaylightUI's opacity"],
			  desc = L["The fishing menu and its boxes follow DaylightUI's window opacity."] },
			{ type = "slider", key = "opacity", label = L["Window opacity"], min = 0.1, max = 1, step = 0.05, unit = "%",
			  desc = L["How solid their backgrounds are, with DaylightUI's opacity off."],
			  disabled = function(get) return get("duiOpacity") ~= false end },
		} },
		{ label = L["Quiet screen"], items = {
			{ type = "toggle", key = "fadeUI", label = L["Fade the UI while fishing"],
			  desc = L["Like DaylightUI's soft AFK screen: the rest of the UI fades away while you stand and fish, and only the fishing menu stays. It comes back while you move, chat, loot by hand or fight, and when Fishing Mode ends."] },
			{ type = "slider", key = "fadeAlpha", label = L["Faded UI opacity"], min = 0, max = 0.6, step = 0.05, unit = "%",
			  desc = L["How much of the UI still shows while faded. 0 hides it."],
			  disabled = function(get) return get("fadeUI") == false end },
			{ type = "slider", key = "fadeDelay", label = L["Fade after standing still"], min = 0, max = 10, step = 0.5, unit = "s",
			  desc = L["Seconds of standing still before the UI fades."],
			  disabled = function(get) return get("fadeUI") == false end },
			{ type = "toggle", key = "keepMinimap", label = L["Keep the minimap"],
			  desc = L["The minimap stays while the rest of the UI fades."],
			  disabled = function(get) return get("fadeUI") == false end },
			{ type = "toggle", key = "keepChat", label = L["Keep the chat"],
			  desc = L["Your chat windows, their tabs and the chat box stay while the rest of the UI fades."],
			  disabled = function(get) return get("fadeUI") == false end },
			{ type = "toggle", key = "catchPopup", label = L["Catch popup"],
			  desc = L["A note at the fishing menu's left after each cast: \"Fish Caught!\" with what came up, or \"Fish Got Away\"."] },
			{ type = "toggle", key = "hideWater", label = L["Hide DaylightUI's fishing water"],
			  desc = L["The water and bobber DaylightUI draws along the bottom of the screen while your line is in. Hidden while Fishing Mode is on, and back as it was when it ends. DaylightUI's own switch for it stays in Quality of Life."] },
		} },
		{ label = L["Sound while fishing"], items = {
			{ type = "toggle", key = "sound", label = L["Set the sound for fishing"],
			  desc = L["Sound effects up so you hear the splash, music and ambience down. Your own sound settings come back when Fishing Mode ends."] },
			{ type = "slider", key = "sfxVolume", label = L["Effects volume"], min = 0, max = 1, step = 0.05, unit = "%",
			  desc = L["The splash of a bite is an effect."], disabled = NotSound },
			{ type = "slider", key = "musicVolume", label = L["Music volume"], min = 0, max = 1, step = 0.05, unit = "%",
			  disabled = NotSound },
			{ type = "slider", key = "ambienceVolume", label = L["Ambience volume"], min = 0, max = 1, step = 0.05, unit = "%",
			  disabled = NotSound },
			{ type = "toggle", key = "backgroundSound", label = L["Sound when the game is in the background"],
			  desc = L["Hear a bite while you are in another window."], disabled = NotSound },
		} },
		{ label = L["While fishing"], items = {
			{ type = "toggle", key = "softInteract", label = L["Soft interact"],
			  desc = L["Lets the fishing key hook the bobber without clicking it. Set back when Fishing Mode ends."] },
			{ type = "toggle", key = "autoLoot", label = L["Auto loot"],
			  desc = L["Your catch goes straight into your bags. Set back when Fishing Mode ends."] },
		} },
	  } },
}

pcall(function()
	DUI:RegisterPlugin(ADDON, {
		icon = "Interface\\AddOns\\" .. ADDON .. "\\Media\\icon-glyph.png",
		needs = { 1, 1 },
		short = L["Fishing"],
		color = { 0.4, 0.8, 1 },
		blurb = L["Fishing Mode: your pole, your bait and one key to fish."],
	})
	DUI:RegisterModule(ADDON, { plugin = ADDON, label = ns.GameText("PROFESSIONS_FISHING", L["Fishing"]), defaults = DEFAULTS, options = { pages = pages } })
end)

me.RegisterCommand("fish", function() Fishing.Toggle() end, L["Turn Fishing Mode on or off."])

me.On("SettingChanged", function(scope, path)
	if scope ~= ADDON or not active then return end
	if path == "key" then
		OutOfCombat(function() UpdateBinding(); UpdateMenu() end)
	elseif path == "fadeAlpha" then
		if fade > 0 then SetFade(fade) end
	elseif path == "keepMinimap" or path == "keepChat" then
		if liftedOn then
			DropAll()
			LiftAll()
		end
		UpdateMapAway()
	elseif path == "showMenu" or path == "menuScale" then
		ShowMenu(true)
	elseif path == "sound" or path == "sfxVolume" or path == "musicVolume" or path == "ambienceVolume"
		or path == "backgroundSound" or path == "softInteract" or path == "autoLoot" then
		OutOfCombat(function() if active then ApplySettings() end end)
	end
end)

me.On("StyleChanged", function()
	if menu then
		menu.title:SetTextColor(API.Accent())
		OutOfCombat(UpdateMenu)
	end
	UpdateBroker()
end)
