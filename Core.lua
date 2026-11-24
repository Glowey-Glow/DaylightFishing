-- Glowey's Fishing: a DaylightUI plugin.
-- Fishing Mode, turned on and off from a data text (any DaylightUI data text slot, or any other
-- broker display) or /fish:
--   on:  your best fishing pole goes on (what you held is remembered), the sound is set for
--        fishing (effects up, music and ambience down, sound in the background, soft interact),
--        and a small menu shows under your character: your baits (click one to put it on the
--        pole) and the cast button. One key casts, and hooks the fish once the bobber is out.
--   off: the sound goes back to how you had it, the menu and the key are let go, and your
--        weapons go back on. Taking the pole off yourself turns Fishing Mode off too (your
--        weapons go back on unless you put others on), and putting one on turns it on (a
--        setting). A fight turns it off and it stays off ("Combat Detected, Exiting Fishing
--        Mode" shows where the menu was).
-- A button in its settings makes a "Fishing Mode" macro (/fish) with the Fishing icon.
-- The settings are on its page in DaylightUI's options (Plugins), or /glowey without it. Built on DaylightUI.API, or without Daylight UI on Host.lua's stand-in for it.

local ADDON, ns = ...
local L, Plural = ns.L, ns.Plural

local DUI = ns.DUI or _G.DaylightUI   -- (ns.DUI: Host.lua; the global only in the offline tests)
local API = ns.API or (DUI and DUI.API)   -- Daylight UI's, or without it Host.lua's stand-in
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
	fadeMoving = true,
	hideWater = true,
	keepMinimap = true,
	keepChat = true,
	catchPopup = true,
	menuScale = 1,
	duiOpacity = true,
	opacity = 0.85,
	mastercraftFights = true,
	padCatchList = false,
	padTrainerBox = false,
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
	DEFAULT_CHAT_FRAME:AddMessage("|cff66ccffGlowey's Fishing|r: " .. msg)
end

-- Our menu and boxes in DaylightUI's window shell. The background follows DaylightUI's window
-- opacity, or with "Use DaylightUI's opacity" off, the one on our page. Each frame is remembered
-- (weakly) so a change to either, or to DaylightUI's look, dresses them all again at once.
-- A window is dressed when it is built, and again only when its size or scale changed (the
-- shell is laid out for them) or the look or the opacity did (again: ReskinWindows). Dressing is
-- the dearest part of a redraw, and every catch used to dress three windows.
local shells = setmetatable({}, { __mode = "k" })
local function SkinWindow(frame, again)
	local w, h = frame:GetSize()
	local k = frame:GetEffectiveScale()
	if not again and shells[frame] and frame.dfDressed == w .. ":" .. h .. ":" .. k then return end
	frame.dfDressed = w .. ":" .. h .. ":" .. k
	shells[frame] = true
	if Get("duiOpacity") == false then
		API.Skin(frame, { window = true, bgAlpha = Get("opacity") })
	else
		API.Skin(frame, { window = true })
	end
end
local function ReskinWindows()
	for frame in pairs(shells) do SkinWindow(frame, true) end
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

local function SameValue(a, b)
	if a == nil or b == nil then return false end
	if tostring(a) == tostring(b) then return true end
	local x, y = tonumber(a), tonumber(b)
	return x ~= nil and y ~= nil and math.abs(x - y) < 1e-4
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
	-- One that is already as wanted is left alone, and not saved: only what was changed is
	-- given back when Fishing Mode ends.
	for name, value in pairs(want) do
		local ok, now = pcall(GetCVar, name)
		now = ok and now or nil
		if not SameValue(now, value) then
			if db.saved[name] == nil and now ~= nil then db.saved[name] = now end
			pcall(SetCVar, name, value)
		end
	end
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
local weaponButtons = {}   -- the menu's Weapon Swap: the weapons Fishing Mode puts back on
local UpdateBroker, UpdateMenu, UpdateCatch, RefreshPanel, UpdateSkill
-- For Controller Only (below the trainer box): Sync(ending) opens or closes the sub menus Always
-- On keeps open, Back(frame) is B on one.
local SubMenus = {}

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
	-- (Host.Skin: API.Skin, drawn again after every look change, Host.lua)
	ns.Host.Skin(b, { noBevel = true, noBackground = true })
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

-- Weapon Swap: the weapons owed back (char.weapons), shown at the menu's right. Only to look at
-- (hover for the item); they go back on by themselves when Fishing Mode ends.
local function WeaponButton(i)
	local b = weaponButtons[i]
	if b then return b end
	b = IconButton(nil, menu, SIZE, function(self)
		if self.link then GameTooltip:SetHyperlink(self.link) end
		GameTooltip:AddLine(L["Goes back on when Fishing Mode ends."], TextColor("TEXT"))
	end)
	weaponButtons[i] = b
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
	-- Menu Size times Daylight UI's own scale (general.scale, DaylightUI/DB.lua:43), as its windows
	-- are: Host.Scaled, applied out of a fight (Host.lua). The catch list and the trainer box are
	-- the menu's children and take its scale.
	ns.Host.Scaled(menu, { own = function() return Get("menuScale") or 1 end })

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

	cast = IconButton("DaylightFishingCast", menu, CAST_SIZE, function(self)
		-- (Host.Tip: the title in TITLE, the line in TEXT, owned and shown again here: Host.lua)
		local key = KeyText()
		ns.Host.Tip(self, L["Cast"], key and L["%s casts, and hooks the fish."]:format(key)
			or L["Pick a fishing key in the options to fish with one key."], nil, "ANCHOR_TOP")
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

	menu.swap = API.Text(menu, "tiny", "CENTER")
	menu.swap:SetText(L["Weapon Swap"])
	ns.Host.Ink(menu.swap, "LABEL")
	menu.swap:Hide()

	menu.empty = API.Text(menu, "small", "LEFT")
	menu.empty:SetText(L["No bait in your bags"])
	ns.Host.Ink(menu.empty, "OFF")

	-- This session's catch: hover for all of it.
	menu.catch = CreateFrame("Frame", nil, menu)
	menu.catch:SetPoint("BOTTOMLEFT", PAD, 9)
	menu.catch:SetSize(90, 14)
	menu.catch:EnableMouse(true)
	menu.catch.text = API.Text(menu.catch, "tiny", "LEFT")
	menu.catch.text:SetPoint("LEFT")
	menu.catch:SetScript("OnEnter", function(self)
		menu.catch.text:SetTextColor(API.Accent())
		ns.Host.TipLines(self, function(t)
			_G.DaylightFishing.CatchTooltip(GameTooltip, true)
			t.Blank()
			t.Line(L["Click: the catch list, fish by fish"], "TEXT")
		end, "ANCHOR_TOP")
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

	me.RegisterMover(menu, "menu", L["Fishing Menu"], { "CENTER", UIParent, "CENTER", 0, -190 })

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
-- fromBags: called for a bag event, which comes after every catch: when the baits, their counts
-- and the weapons owed are what the menu already shows, nothing is done (no secure attributes
-- set again, no layout, no catch list).
function UpdateMenu(fromBags)
	if not menu or InCombatLockdown() then return end
	local baits = BaitsInBags()
	local owed = {}
	local w = char and Get("restoreWeapons") and char.weapons
	if type(w) == "table" then
		for _, link in ipairs({ w[1], w[2] }) do
			if type(link) == "string" then owed[#owed + 1] = link end
		end
	end
	local sig = {}
	for i, bait in ipairs(baits) do sig[i] = bait.id .. "x" .. bait.count end
	sig = table.concat(sig, ",") .. "|" .. table.concat(owed, ",")
	if fromBags == true and sig == menu.drawn then return end
	menu.drawn = sig
	ns.Host.Rescale(menu)
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
	-- Weapon Swap, at the right: the weapons that go back on when Fishing Mode ends (owed, above).
	local swapW = 0
	if #owed > 0 then
		swapW = math.max(#owed * SIZE + (#owed - 1) * GAP, math.ceil(menu.swap:GetStringWidth()))
	end
	local width = math.max(x + CAST_SIZE + PAD + (swapW > 0 and GAP * 3 + swapW or 0), WIDTH)
	local right = width - PAD - swapW / 2      -- the middle of the Weapon Swap block
	local wx = right - (#owed * SIZE + (#owed - 1) * GAP) / 2
	for i, link in ipairs(owed) do
		local b = WeaponButton(i)
		b.link = link
		b.icon:SetTexture(C_Item.GetItemIconByID(link) or (GetItemIcon and GetItemIcon(link)))
		b:ClearAllPoints()
		b:SetPoint("TOPLEFT", menu, "TOPLEFT", wx + (i - 1) * (SIZE + GAP), top - (CAST_SIZE - SIZE) / 2)
		b:Show()
	end
	for i = #owed + 1, #weaponButtons do weaponButtons[i]:Hide() end
	menu.swap:ClearAllPoints()
	menu.swap:SetPoint("TOP", menu, "TOPLEFT", right, top - CAST_SIZE - 3)
	menu.swap:SetShown(#owed > 0)
	UpdateCatch(true)
	UpdateSkill()
	menu:SetSize(width, -top + CAST_SIZE + 26)
	SkinWindow(menu)
	-- (The catch list beside it, once the menu has its size: only when that or the catch changed.)
	RefreshPanel(true)
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
-- the fishing menu, the minimap and the chat stay. It comes back in a fight (and as you move, with
-- "Stay faded while moving" off), and when Fishing Mode ends. It leaves the UI to DaylightUI's
-- AFK screen while that is up, and adds nothing to the world: DaylightUI's own "Fishing water"
-- is its setting (Quality of Life).
-- ---------------------------------------------------------------------------------------------

local fader = CreateFrame("Frame")
fader:Hide()
-- The addon's events (registered under Events, below; made here so Fishing Mode can reach it).
local events = CreateFrame("Frame")
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

-- The frames' names, made once (LiftAll runs once a second while the UI is faded).
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

-- 3D models draw at full strength whatever their parents' alpha, so a faded UI would leave them
-- floating on the screen. DaylightUI's own (the unit frames' portraits) follow its UIAlpha signal,
-- which Fade.SetUIAlpha sends. Other addons' models are given their frame's alpha here while the
-- UI is faded, and what they had before after: Polestar's target button faces.
local followed = {}        -- model -> its alpha before

-- (The rows' names are made once each, and kept: this runs every frame while the UI fades.)
local FollowModels
do
	local names = {}
	function FollowModels()
		local i = 1
		while true do
			local name = names[i]
			if not name then
				name = "PolestarTargetRow" .. i
				names[i] = name
			end
			local row = _G[name]
			if not row then break end
			local m = row.Model
			if type(m) == "table" and m.SetAlpha and row.GetEffectiveAlpha then
				if followed[m] == nil then followed[m] = m:GetAlpha() or 1 end
				local a = row:GetEffectiveAlpha()
				if type(a) == "number" then m:SetAlpha(followed[m] * a) end
			end
			i = i + 1
		end
	end
end

local function ReleaseModels()
	for m, a in pairs(followed) do m:SetAlpha(a) end
	wipe(followed)
end

-- A faded window still answers the mouse, so passing over one out of sight (Polestar's guide)
-- showed its tooltip, which stays out of the fade for the catch's. A tooltip whose owner is out of
-- sight is hidden. Not one owned by the screen itself (the bobber's, a mob's in the world).
local function TipFromFaded()
	if fade <= 0 or not GameTooltip:IsShown() then return end
	local owner = GameTooltip:GetOwner()
	if not owner or owner == UIParent or owner == WorldFrame or not owner.GetEffectiveAlpha then return end
	local a = owner:GetEffectiveAlpha()
	if type(a) == "number" and a < 0.05 then GameTooltip:Hide() end
end
GameTooltip:HookScript("OnShow", TipFromFaded)
-- A popup or a bag opening while the UI is faded comes out of the fade on the next frame.
for _, name in ipairs({ "StaticPopup_Show", "OpenAllBags", "ToggleAllBags", "ToggleBackpack", "ToggleBag", "OpenBag" }) do
	if type(_G[name]) == "function" then _G.hooksecurefunc(name, function() fader.relift = true end) end
end

-- UIParent's alpha, DaylightUI's way, so its portraits fade with the rest; else UIParent's own.
-- DaylightUI 1.9.5+ keeps one alpha per owner (its AFK screen "afk", its NPC scene "npc") and
-- shows the lowest, so ours is "fishing" and only we let it go (1); older ones take one alpha
-- and ignore the owner.
function ns.UIAlpha(a)
	local F = DUI and DUI.Fade
	if not (type(F) == "table" and type(F.SetUIAlpha) == "function" and pcall(F.SetUIAlpha, a, "fishing")) then
		UIParent:SetAlpha(a)
	end
end

local function SetFade(p)
	fade = p
	local low = tonumber(Get("fadeAlpha")) or 0
	local a = 1 - p * (1 - low)
	ns.UIAlpha(a)
	if p > 0 and not liftedOn then
		LiftAll()
	elseif p <= 0 and liftedOn then
		DropAll()
	end
	if p > 0 then FollowModels() else ReleaseModels() end
	UpdateMapAway()
end

-- Straight back, at once (a fight, or Fishing Mode ending).
local function Unfade()
	stillSince = nil
	if fade > 0 or liftedOn then SetFade(0) end
	MapAway(false)
end

-- Daylight UI's public check (API.IsAfkScreen, DaylightUI/API.lua:868); its frame itself, checked,
-- on one without that call.
local function AfkScreen()
	if type(API.IsAfkScreen) == "function" then
		local ok, up = pcall(API.IsAfkScreen)
		if ok then return up == true end
	end
	local afk = _G.DaylightUIAfkScreen
	return type(afk) == "table" and type(afk.IsShown) == "function" and afk:IsShown() == true
end

local function WantFade()
	if not active or not Get("fadeUI") or InCombatLockdown() then return false end
	-- (Not while a tour explains the screen: Guide.lua.)
	if ns.Guide and ns.Guide.Running() then
		stillSince = nil
		return false
	end
	if Get("keepChat") == false and ChatEdit_GetActiveWindow and ChatEdit_GetActiveWindow() then
		stillSince = nil
		return false
	end
	if (GetUnitSpeed("player") or 0) > 0 or IsFalling() then
		stillSince = nil
		-- "Stay faded while moving": a faded UI stays out of sight as you walk (it only starts
		-- fading once you stand still).
		return Get("fadeMoving") ~= false and fade > 0
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

-- The watcher. It stops by itself when it has nothing to do: Fade the UI and the water's setting
-- both off, and nothing of ours faded, lifted or held (a setting turned on starts it again:
-- SettingChanged, below). While the UI is faded, what must stay out of the fade (a popup, a bag,
-- the loot window) is looked for once a second, and at once when one of them opens (fader.relift).
local relift = 0
fader:SetScript("OnUpdate", function(_, elapsed)
	if not Get("fadeUI") and Get("hideWater") == false and fade <= 0 and not liftedOn and not fader.afkHeld then
		KeepWater()
		fader:Hide()
		return
	end
	KeepWater()
	-- DaylightUI's AFK screen has the UI then, and gives it back whole: nothing of ours stays over it.
	if AfkScreen() then
		if liftedOn then DropAll() end
		ReleaseModels()
		fade, stillSince = 0, nil
		MapAway(false)
		fader.afkHeld = true
		return
	end
	-- Once it's gone our own fade is let go too: on DaylightUI 1.9.5+ it's kept apart from the
	-- AFK screen's and would hold the UI faded after the AFK screen gave its own back.
	if fader.afkHeld then
		fader.afkHeld = nil
		ns.UIAlpha(1)
	end
	if liftedOn then
		relift = relift + elapsed
		if relift > 1 or fader.relift then
			relift, fader.relift = 0, nil
			LiftAll()
			FollowModels()
			TipFromFaded()
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

-- The owed weapons back in their own slots, both at once, the way a macro of two lines does it
-- ("/equip <main hand>" then "/equip <off hand>"): main hand first, then the off hand, in the same
-- moment. The game takes them in that order, so the off hand never waits for the two-handed pole to
-- leave. A fight ends Fishing Mode from PLAYER_REGEN_DISABLED, which comes just before the game
-- locks an addon's equipping for the fight (ADDON_ACTION_BLOCKED on EquipItemByName, /equip's own
-- call): both go on right there. Already in the lock (the pole taken off by hand mid-fight), each
-- weapon goes through the cursor instead (picked up from its bag slot, dropped on its hand's
-- slot), and whatever didn't make it goes on as the fight ends.
local weaponsQueued = false
local RestoreWeapons

-- `link` from your bags onto inventory `slot` through the cursor. True once the swap is sent (or
-- there was nothing to do: the item isn't in your bags).
local function SwapIn(link, slot)
	if not link or InSlot(slot, link) then return true end
	if GetCursorInfo() then return false end
	local id = C_Item.GetItemInfoInstant(link)
	local bagAt, slotAt
	for bag = 0, NUM_BAG_SLOTS or 4 do
		for i = 1, C_Container.GetContainerNumSlots(bag) or 0 do
			local here = C_Container.GetContainerItemLink(bag, i)
			if here == link then
				bagAt, slotAt = bag, i
				break
			elseif not bagAt and here and C_Container.GetContainerItemID(bag, i) == id then
				bagAt, slotAt = bag, i
			end
		end
		if bagAt and C_Container.GetContainerItemLink(bagAt, slotAt) == link then break end
	end
	if not bagAt then return true end
	local info = C_Container.GetContainerItemInfo(bagAt, slotAt)
	if info and info.isLocked then return false end
	C_Container.PickupContainerItem(bagAt, slotAt)
	PickupInventoryItem(slot)
	-- (Anything left on the cursor, the swap didn't take: back where it came from.)
	if GetCursorInfo() then ClearCursor() end
	return true
end

-- One weapon onto its slot: /equip's way out of the lock, the cursor's in it.
local function PutOn(link, slot)
	if not link or InSlot(slot, link) or (ItemCount(link) or 0) < 1 then return true end
	if not InCombatLockdown() then
		Equip(link, slot)
		return true
	end
	return SwapIn(link, slot)
end

function RestoreWeapons()
	weaponsQueued = false
	local w = char and char.weapons
	if active or type(w) ~= "table" then return end
	local main, off = PutOn(w[1], 16), PutOn(w[2], 17)
	-- (Still owed after the swaps have landed: once more as the fight ends.)
	if InCombatLockdown() or not (main and off) then
		C_Timer.After(1, function()
			local o = char and char.weapons
			if active or type(o) ~= "table" then return end
			if (o[1] and not InSlot(16, o[1])) or (o[2] and not InSlot(17, o[2])) then
				if InCombatLockdown() then
					if not weaponsQueued then
						weaponsQueued = true
						later[#later + 1] = RestoreWeapons
					end
				else
					RestoreWeapons()
				end
			end
		end)
	end
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
	-- (The menu's scale: Menu Size times Daylight UI's, Host.Scaled.)
	ns.Host.Scaled(notice, { own = function() return Get("menuScale") or 1 end })
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
	ns.Host.Rescale(notice)
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
	events.Fishing(true)
	BuildMenu()
	ApplySettings()
	ShowMenu(true)
	SubMenus.Sync()
	fader:Show()
	UpdateBroker()
	-- (The first time, on this account: the tour of the menu that just showed. Guide.lua)
	if ns.Guide then ns.Guide.Offer("fishing") end
end

-- reason: "toggle" (the button), "combat" (a fight started: Fishing Mode ends and stays off, the
-- weapons go back on at once, the off hand right after the main hand) or "unequipped" (you took the pole
-- off: your weapons go back on if your main hand is empty or holds your own main hand again, else
-- what you put on stays). With "Put my weapons back on" off, the weapons stay as they are.
local function Leave(reason)
	if not active then return end
	active, equipping, channeling = false, false, false
	char.active = nil
	events.Fishing(false)
	fader:Hide()
	Unfade()
	KeepWater()
	RestoreSettings()
	ShowMenu(false)
	SubMenus.Sync(true)
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

-- The tour shows the fishing menu while it runs, Fishing Mode on or not (FishingGuide.lua): built and
-- filled as Fishing Mode shows it, but nothing else of Fishing Mode (no pole, sound or fade). Taken
-- away when the tour ends, unless Fishing Mode came on meanwhile. Out of a fight only (the menu
-- holds secure buttons).
function Fishing.TourPreview(on)
	if InCombatLockdown() then return end
	BuildMenu()
	if on then
		if not menu:IsShown() then
			UpdateMenu()
			menu:Show()
			menu.tourPreview = true
		end
	elseif menu.tourPreview then
		menu.tourPreview = nil
		if not (active and Get("showMenu")) then menu:Hide() end
	end
end

-- What the tour lights (FishingGuide.lua): the menu, its baits shown, the cast button, the fishing
-- key's name (nil: none).
function Fishing.TourParts()
	local shown = {}
	for _, b in ipairs(baitButtons) do if b:IsShown() then shown[#shown + 1] = b end end
	return menu, shown, cast, KeyText()
end

-- A "Fishing Mode" macro (/fish) with the Fishing icon, made or brought up to date, and put on
-- the cursor to drop on an action bar. An account macro when there's room, else this character's.
local MACRO_NAME = "Fishing Mode"
local MACRO_BODY = "/fish"

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

-- noPanel: the menu's own count only (UpdateMenu draws the catch list after it has its size).
function UpdateCatch(noPanel)
	if menu and menu.catch then
		local n = Caught()
		menu.catch.text:SetText(L["Caught %d"]:format(n))
		menu.catch.text:SetTextColor(TextColor(n > 0 and "VALUE" or "OFF"))
		menu.catch:SetWidth(math.max(40, math.ceil(menu.catch.text:GetStringWidth()) + 4))
	end
	if noPanel ~= true then RefreshPanel() end
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
		if not (self.link and IsModifiedClick("CHATLINK")) then return end
		-- ChatFrameUtil.InsertLink is the game's call; ChatEdit_InsertLink only lives in its
		-- deprecated-API addon.
		local U = _G.ChatFrameUtil
		if U and type(U.InsertLink) == "function" then U.InsertLink(self.link)
		elseif type(_G.ChatEdit_InsertLink) == "function" then _G.ChatEdit_InsertLink(self.link) end
	end)
	panel.rows[i] = row
	return row
end

-- ifChanged: only when the catch, or the menu's width or place, changed since it was drawn.
function RefreshPanel(ifChanged)
	if not panel or not panel:IsShown() then return end
	local n = Caught()
	local drawn = n .. ":" .. math.floor(menu:GetWidth() + 0.5) .. ":" .. math.floor((menu:GetLeft() or 0) + 0.5)
	if ifChanged == true and panel.drawn == drawn then return end
	panel.drawn = drawn
	local list = Fishing.SortedCatch()
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
	-- (A controller: its cursor finds the rows just drawn. Guide.lua's Pad)
	if ns.Pad then ns.Pad.Settle() end
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
	-- At the menu's right; at its left where the screen ends first, so it never slides over the
	-- menu (it's clamped to the screen). It has the menu's scale: their sides compare as they are.
	local right, left = menu:GetRight(), menu:GetLeft()
	local screen = UIParent:GetRight()
	local scale = menu:GetEffectiveScale()
	panel.onLeft = false
	if right and left and screen and scale and scale > 0 then
		screen = screen * UIParent:GetEffectiveScale() / scale
		panel.onLeft = right + 6 + panel:GetWidth() > screen and left - 6 - panel:GetWidth() >= 0
	end
	panel:ClearAllPoints()
	if panel.onLeft then
		panel:SetPoint("TOPRIGHT", menu, "TOPLEFT", -6, 0)
	else
		panel:SetPoint("TOPLEFT", menu, "TOPRIGHT", 6, 0)
	end
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
	panel.title:SetText(L["Catch This Session"])
	ns.Host.Ink(panel.title, "pop")
	panel.total = API.Text(panel, "tiny", "LEFT")
	panel.total:SetPoint("TOPLEFT", panel.title, "BOTTOMLEFT", 0, -4)
	panel.close = API.Close(panel, function() panel:Hide() end, 14)
	panel.close:SetPoint("TOPRIGHT", -8, -7)
	panel.empty = API.Text(panel, "small", "LEFT")
	ns.Host.Ink(panel.empty, "OFF")
	panel.clear = API.Button(panel, L["Clear"], 20)
	panel.clear:SetSize(70, 20)
	panel.clear:SetPoint("BOTTOMRIGHT", -8, 8)
	panel.clear:SetFrameLevel(panel:GetFrameLevel() + 10)
	panel.clear:SetScript("OnClick", function() Fishing.ResetCatch() end)
	panel:SetScript("OnShow", RefreshPanel)
	-- A controller (Guide.lua's Pad): the cursor moves over the catch (each fish's tooltip) and
	-- Clear, starting on the first fish; A presses, B closes the list (kept open by Catch List
	-- Always On, B only gives the cursor back to the game).
	if ns.Pad then
		panel.padFirst = function()
			local first = panel.rows[1]
			if first and first:IsShown() then return first end
			return panel.clear
		end
		ns.Pad.Follow(panel, function()
			if not SubMenus.Back(panel) then panel:Hide() end
		end)
	end
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
	return rank.itemName, true   -- (true: the game's own name is still on its way)
end

local function QuestName(rank)
	if ENGLISH or not C_QuestLog then return rank.questName end
	local name = C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(rank.quest)
	if name and name ~= "" then return name end
	if C_QuestLog.RequestLoadQuestByID then C_QuestLog.RequestLoadQuestByID(rank.quest) end
	return rank.questName, true
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
	-- (Host.TipLines: each line in a role of the look, owned and shown there: Host.lua)
	ns.Host.TipLines(anchor, function(t)
		if not rank then
			t.Line(L["Fishing - Maximum Trained"], "TITLE")
			return
		end
		t.Line(RankTitle(rank), "TITLE")
		t.Line(HowText(rank), "TEXT", true)
		if CanLearn(rank, skill) then t.Line(L["You can learn it now."], "GOOD") end
		t.Line(L["Click: where to go"], "OFF")
	end, "ANCHOR_TOP")
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
		pcall(tomtom.AddWaypoint, tomtom, map, spot.x / 100, spot.y / 100, { title = name, from = "Glowey's Fishing" })
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
		-- (The book's own item tip stays; our lines in the look's roles, Host.Color.)
		local r, g, b = ns.Host.Color("TEXT")
		if self.item then
			GameTooltip:SetItemByID(self.item)
			GameTooltip:AddLine(L["Sold by %s, %s (%d, %d)"]:format(self.who, PlaceName(self.spot), self.spot.x + 0.5, self.spot.y + 0.5), r, g, b)
		else
			GameTooltip:SetText(self.who, ns.Host.Color("TITLE"))
			GameTooltip:AddLine(("%s (%d, %d)"):format(PlaceName(self.spot), self.spot.x + 0.5, self.spot.y + 0.5), r, g, b)
		end
		GameTooltip:AddLine(L["Click for a waypoint."], ns.Host.Color("LABEL"))
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
	if ns.Pad then ns.Pad.Settle() end
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
	-- Above the menu; under it where the screen's top is too close, so it never slides over the
	-- menu (it's clamped to the screen). It has the menu's scale: their edges compare as they are.
	local menuTop, menuLow = menu:GetTop(), menu:GetBottom()
	local screen = UIParent:GetTop()
	local scale = menu:GetEffectiveScale()
	local under = false
	if menuTop and menuLow and screen and scale and scale > 0 then
		screen = screen * UIParent:GetEffectiveScale() / scale
		under = menuTop + 6 + box:GetHeight() > screen and menuLow - 6 - box:GetHeight() >= 0
	end
	box:ClearAllPoints()
	if under then
		box:SetPoint("TOPLEFT", menu, "BOTTOMLEFT", 0, -6)
	else
		box:SetPoint("BOTTOMLEFT", menu, "TOPLEFT", 0, 6)
	end
	SkinWindow(box)
	-- (Not English: the name events are heard while the book's or quest's name is missing.)
	if not ENGLISH then
		local missing = false
		if rank and rank.how == "book" then
			missing = select(2, BookName(rank)) == true
		elseif rank and rank.how == "quest" then
			missing = select(2, QuestName(rank)) == true
		end
		events.Names(missing)
	end
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
	ns.Host.Ink(box.title, "pop")
	box.sub = API.Text(box, "tiny", "LEFT")
	box.sub:SetPoint("TOPLEFT", box.title, "BOTTOMLEFT", 0, -4)
	box.sub:SetPoint("RIGHT", box, "RIGHT", -PAD - 16, 0)
	box.sub:SetJustifyH("LEFT")
	box.sub:SetWordWrap(true)
	ns.Host.Ink(box.sub, "TEXT")
	box.close = API.Close(box, function() box:Hide() end, 14)
	box.close:SetPoint("TOPRIGHT", -8, -7)
	box.note = API.Text(box, "tiny", "LEFT")
	box.note:SetTextColor(TextColor("OFF"))
	box:SetScript("OnShow", RefreshBox)
	box:HookScript("OnHide", function() events.Names(false) end)
	-- A controller (Guide.lua's Pad): the cursor moves over the places, closest first; A sets the
	-- waypoint, B closes the box (kept open by Trainer Box Always On, B only gives the cursor back
	-- to the game).
	if ns.Pad then
		box.padFirst = function()
			local first = box.rows[1]
			if first and first:IsShown() then return first end
			return nil
		end
		ns.Pad.Follow(box, function()
			if not SubMenus.Back(box) then box:Hide() end
		end)
	end
end

function Fishing.ToggleTrainers(show)
	BuildBox()
	if not box then return end
	if show == nil then show = not box:IsShown() end
	box:SetShown(show)
end

-- ---------------------------------------------------------------------------------------------
-- For Controller Only: the catch list and the trainer box always on
-- The fishing menu never takes the controller cursor (a window that has it holds the D-pad and
-- the face buttons, abilities included), so its sub menus only open with a mouse. With the game's
-- controller interface on, "Catch List Always On" / "Trainer Box Always On" open them with
-- Fishing Mode and keep them open until it ends. They never take the cursor as they show: they go
-- on the game's list of open windows as windows that don't focus by themselves (the game's own
-- way for popups nobody asked for), so the buttons keep fishing, and the player brings the cursor
-- to them the way they reach any open window (the game's button for it, or LT / RT from another).
-- B gives the cursor back to the game and leaves them open; another window closing never drops
-- the cursor onto them. Every call to the game's list is checked and out of a fight only (Fishing
-- Mode ends as a fight starts). Nothing runs while nothing changes.
-- ---------------------------------------------------------------------------------------------

do
	local KEEP = { { key = "padCatchList" }, { key = "padTrainerBox" } }
	local kept = setmetatable({}, { __mode = "k" })     -- frame -> held open by Always On
	local listed = setmetatable({}, { __mode = "k" })   -- frame -> put on the game's list by us
	local prepared = setmetatable({}, { __mode = "k" })

	local function PadOn() return ns.Pad ~= nil and ns.Pad.On() end
	-- The options' switches, grayed while the controller interface is off (read as the page is drawn).
	function SubMenus.PadOff() return not PadOn() end

	-- The game's list of open windows (GamepadMode.FrameControlsManager), when it's there.
	local function Manager()
		local G = _G.GamepadMode
		local m = type(G) == "table" and G.FrameControlsManager or nil
		if type(m) == "table" and type(m.FrameShown) == "function" and type(m.FrameHidden) == "function" then return m end
		return nil
	end

	-- Daylight UI's controller kit (Leaving / Returning keep its own note of the list right), through
	-- Guide.lua's guarded ns.Pad (type-checked and pcall'd there, for a window it follows).
	local function Kit(name, frame)
		local fn = ns.Pad and ns.Pad[name]
		if type(fn) == "function" then fn(frame) end
	end

	-- On the game's list without the cursor: a popup that doesn't focus by itself. (Daylight UI's own
	-- announcement comes a frame later and finds it listed already.) Leaving it, it hands the cursor
	-- back to the game.
	local function ListQuietly(f)
		if not kept[f] or InCombatLockdown() or not f:IsVisible() or not PadOn() then return end
		local m = Manager()
		if not m then return end
		f.skipGamepadAutoFocus = true
		f.returnToPlayerControl = true
		if pcall(m.FrameShown, m, f, true, false) then listed[f] = true end
	end

	-- The cursor back to the game, the window still open and still reachable.
	local function GiveBack(f)
		if InCombatLockdown() then return end
		local m = Manager()
		if not m then return end
		f.returnToPlayerControl = true
		Kit("Leaving", f)
		pcall(m.FrameHidden, m, f)   -- (nothing when Daylight UI took it off already)
		ListQuietly(f)
		Kit("Returning", f)
	end

	-- B on a kept sub menu: true when it was one (the cursor goes back to the game, it stays open).
	function SubMenus.Back(f)
		if not kept[f] then return false end
		GiveBack(f)
		return true
	end

	-- (Another window closing can hand the game's cursor to one of these: B gives it back. Not hooked
	-- on the game's window manager: no hooksecurefunc on the game's objects on this client, it breaks
	-- the game's own protected calls, as Daylight UI's CONTRIBUTING says.)

	local function Prepare(f)
		if prepared[f] then return end
		prepared[f] = true
		-- Shown again (with the menu): on the list without the cursor, before Daylight UI's turn.
		f:HookScript("OnShow", function(self) if kept[self] then ListQuietly(self) end end)
		f:HookScript("OnHide", function(self)
			if not listed[self] then return end
			listed[self] = nil
			if not InCombatLockdown() then
				local m = Manager()
				if m then pcall(m.FrameHidden, m, self) end
			end
		end)
		-- The cursor coming to it: leaving it later goes back to the game (the game clears that as the
		-- triggers step away).
		local focus = f.FocusGamepad
		if type(focus) == "function" then
			f.FocusGamepad = function(self, ...)
				if kept[self] then
					self.returnToPlayerControl = true
				end
				return focus(self, ...)
			end
		end
	end

	local function Let(f)
		-- (Closed with the cursor in it, the cursor goes back to the game.)
		if kept[f] then f.returnToPlayerControl = true end
		kept[f] = nil
		if f:IsShown() then f:Hide() end
		f.skipGamepadAutoFocus, f.returnToPlayerControl = nil, nil
	end

	-- ending: Fishing Mode just ended. On a controller every sub menu closes with it then: one left
	-- open, hidden with the menu, would be put back on the game's list after the fight that ended it
	-- and take the cursor while nothing shows.
	function SubMenus.Sync(ending)
		local pad = PadOn()
		local on = active and pad and menu ~= nil and menu:IsShown() and not InCombatLockdown()
		KEEP[1].frame, KEEP[2].frame = panel, box
		for i, k in ipairs(KEEP) do
			local f = k.frame
			if on and Get(k.key) == true then
				if i == 1 then BuildPanel(); f = panel else BuildBox(); f = box end
				if f and not kept[f] then
					Prepare(f)
					kept[f] = true
					if f:IsShown() then GiveBack(f) else f:Show() end
				end
			elseif f and (kept[f] or (ending and pad)) then
				Let(f)
			end
		end
	end

	-- The game's controller interface turned on or off (after Daylight UI's own handling of it), and
	-- once after a login or /reload (Fishing Mode back on before the game's controller code is ready).
	local padWatch = CreateFrame("Frame")
	padWatch:SetScript("OnEvent", function(_, event, name)
		if event == "CVAR_UPDATE" and name ~= "GamePadEnable" then return end
		C_Timer.After(event == "PLAYER_ENTERING_WORLD" and 1 or 0, function() SubMenus.Sync() end)
	end)
	for _, e in ipairs({ "INPUT_DEVICE_INTERFACE_TRANSITION", "CVAR_UPDATE", "PLAYER_ENTERING_WORLD" }) do
		pcall(padWatch.RegisterEvent, padWatch, e)
	end
end

-- The catch's lines on a tooltip: the count, then what came up, the most first.
function Fishing.CatchTooltip(tip, title)
	local s = char and Session()
	local n = s and s.caught or 0
	-- (Any tooltip, a broker display's too: the lines in the look's roles, Host.Color.)
	if title then tip:SetText(L["This Session's Catch"], ns.Host.Color("TITLE")) end
	local r, g, b = ns.Host.Color("TEXT")
	tip:AddDoubleLine(L["Fish Caught"], tostring(n), r, g, b, API.Accent())
	if n == 0 then
		tip:AddLine(L["Nothing caught yet."], TextColor("OFF"))
		return
	end
	local list = Fishing.SortedCatch()
	for i = 1, math.min(#list, MAX_LINES) do
		local item = list[i]
		local icon = item.icon and ("|T" .. item.icon .. ":14:14:0:0:64:64:5:59:5:59|t ") or ""
		tip:AddDoubleLine(icon .. (item.link or item.name or "?"), "x" .. item.count, r, g, b, TextColor("VALUE"))
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
	-- (The menu's scale: Menu Size times Daylight UI's, Host.Scaled.)
	ns.Host.Scaled(popup, { own = function() return Get("menuScale") or 1 end })
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
	ns.Host.Rescale(popup)
	popup:ClearAllPoints()
	if panel and panel:IsVisible() and panel.onLeft then
		-- (The catch list took the menu's left: the note goes beside it.)
		popup:SetPoint("TOPRIGHT", panel, "TOPLEFT", -6, 0)
	elseif menu and menu:IsShown() then
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
	-- (Its broker name is still the old one: Daylight UI saves data text slots by it.)
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
			-- (The display's own tooltip: the lines in the look's roles, Host.Color.)
			tip:AddLine(active and L["Fishing Mode: On"] or L["Fishing Mode: Off"], ns.Host.Color("TITLE"))
			local r, g, b = ns.Host.Color("TEXT")
			local key = KeyText()
			if key then tip:AddLine(L["Fishing Key: %s"]:format(key), r, g, b) end
			local left = BaitLeft()
			if active and left then tip:AddLine(string.format(L["Bait on the Pole: %d:%02d"], left / 60, left % 60), r, g, b) end
			tip:AddLine(" ")
			Fishing.CatchTooltip(tip)
			tip:AddLine(active and L["Click: turn Fishing Mode off"] or L["Click: turn Fishing Mode on"], r, g, b)
			tip:AddLine(L["Shift-right-click: clear this session's catch"], r, g, b)
		end,
	})
end

-- ---------------------------------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------------------------------

events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
events:RegisterEvent("LOOT_READY")
events:RegisterEvent("LOOT_OPENED")
events:RegisterEvent("LOOT_CLOSED")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("SKILL_LINES_CHANGED")
events:RegisterEvent("CHAT_MSG_SKILL")

-- Only while Fishing Mode is on (Enter and Leave): the line's own events, moving, the game's "got
-- away" messages, and the bags (the menu's baits; a bag opening, for the quiet screen). The loot
-- and skill events stay: a catch counts, and the trainer box follows, with Fishing Mode off too.
events.fishingOnly = { "BAG_UPDATE_DELAYED", "BAG_OPEN", "UI_ERROR_MESSAGE", "UI_INFO_MESSAGE",
	"PLAYER_STARTED_MOVING" }
events.fishingUnit = { "UNIT_SPELLCAST_SENT", "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_STOP" }
function events.Fishing(on)
	for _, e in ipairs(events.fishingOnly) do
		if on then pcall(events.RegisterEvent, events, e) else pcall(events.UnregisterEvent, events, e) end
	end
	for _, e in ipairs(events.fishingUnit) do
		if on then events:RegisterUnitEvent(e, "player") else events:UnregisterEvent(e) end
	end
end

-- The book's and the quest's names in the game's language (not English): heard only while the
-- trainer box shows and one of them is still missing (RefreshBox), not for every item the game
-- loads anywhere.
function events.Names(on)
	on = on == true and not ENGLISH
	if on == (events.namesOn == true) then return end
	events.namesOn = on
	for _, e in ipairs({ "GET_ITEM_INFO_RECEIVED", "QUEST_DATA_LOAD_RESULT" }) do
		if on then events:RegisterEvent(e) else events:UnregisterEvent(e) end
	end
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
	-- Its "Hide the game's interface" (fishHideUI) and our "Fade the UI while fishing" both set the
	-- UI's opacity and put back what they found, so with both on the UI can stay faded. While our
	-- fade is on (and we handle the overlaps), its hiding is held at "never", what it was recorded;
	-- turning our fade off, or Revert to Mastercraft, gives it back.
	if Get("fadeUI") ~= false and Get("mastercraftFights") ~= false then
		if db.mastercraftHideWas == nil then db.mastercraftHideWas = ms.fishHideUI or "never" end
		ms.fishHideUI = "never"
	elseif db.mastercraftHideWas ~= nil then
		ms.fishHideUI = db.mastercraftHideWas
		db.mastercraftHideWas = nil
	end
end

local function AskMastercraft()
	if not MastercraftSettings() or db.mastercraftAsked then return end
	-- (A first launch: the welcome says it instead, and Revert in the options gives it back.)
	if ns.Guide and not (type(db.guide) == "table" and db.guide.welcomed) then
		db.mastercraftAsked = true
		return
	end
	db.mastercraftAsked = true
	StaticPopupDialogs.DAYLIGHTFISHING_MASTERCRAFT = {
		text = L["Mastercraft puts your fishing pole back on after every fight, and Glowey's Fishing ends Fishing Mode in a fight. Which one handles fights while you fish?\n\nGlowey's Fishing turns off Mastercraft's \"After the fight: your fishing gear back on\". You can change this any time: Fishing > Fights While Fishing."],
		button1 = L["Glowey's Fishing"],
		button2 = L["Mastercraft"],
		-- (Guarded: a failed save never breaks the game's popup.)
		OnAccept = function() pcall(DUI.Set, DUI, ADDON, "mastercraftFights", true) end,
		OnCancel = function(_, _, reason)
			if reason == "clicked" then pcall(DUI.Set, DUI, ADDON, "mastercraftFights", false) end
		end,
		timeout = 0, whileDead = true, hideOnEscape = false, preferredIndex = 3,
	}
	StaticPopup_Show("DAYLIGHTFISHING_MASTERCRAFT")
end

me.On("SettingChanged", function(scope, path)
	if scope == ADDON and (path == "mastercraftFights" or path == "fadeUI") then ApplyMastercraft() end
end)

-- ---------------------------------------------------------------------------------------------
-- This character's record in a table kept by "Name-Realm". On 2026-11-20 the game stopped giving
-- realm names on this client (GetRealmName() is ""; Daylight UI 2.1.2 DB.lua:226-238), so every
-- character's key turned into "Name-" and what it had saved looked gone. Now:
--   1. The key this character was given before (owners: GUID -> key) is its key: the GUID stays the
--      same whatever the game says the realm is, so this can't happen again.
--   2. Else the key the game gives now, "Name-Realm" or "Name-"; a key another character holds
--      (two characters share a first name) is left to it, and this one is kept by its GUID.
--   3. A record that is new or empty, with no realm name to go by, takes a copy of what the
--      character had before: the "Name-Realm" record Daylight UI finds for it (DB.ShortKey gives
--      the same key from its own saved characters, DB.lua:181-249), else the only "Name-<realm>"
--      record there is, else the record it shared until now. Two to choose from: none is taken.
-- Nothing is deleted and no record is written over: the old ones stay where they were.
-- nil while the game doesn't know the character yet (the caller then waits, or uses nothing).
-- ---------------------------------------------------------------------------------------------
do
	local function EmptyRecord(t)
		for _, v in pairs(t) do
			if type(v) ~= "table" or not EmptyRecord(v) then return false end
		end
		return true
	end

	local function CopyRecord(v)
		if type(v) ~= "table" then return v end
		local out = {}
		for k, x in pairs(v) do out[k] = CopyRecord(x) end
		return out
	end

	function Fishing.CharKey(records, owners)
		local guid, name = UnitGUID("player"), UnitName("player")
		if type(guid) ~= "string" or guid == "" or type(name) ~= "string" or name == "" or name == (UNKNOWNOBJECT or "Unknown") then
			return nil
		end
		local kept = owners[guid]
		if type(kept) == "string" and type(records[kept]) == "table" then return kept end
		local realm = GetRealmName()
		if type(realm) ~= "string" then realm = "" end
		local bare = name .. "-"
		local key = bare .. realm
		local taken = {}
		for g, k in pairs(owners) do
			if g ~= guid then taken[k] = true end
		end
		local shared
		if taken[key] then key, shared = guid, key end
		if type(records[key]) ~= "table" then records[key] = {} end
		owners[guid] = key
		if realm ~= "" or not EmptyRecord(records[key]) then return key end
		-- (What it had before.)
		local old
		local D = _G.DaylightUI
		local short = type(D) == "table" and type(D.DB) == "table" and D.DB.ShortKey
		if type(short) == "function" then
			local ok, k = pcall(short)
			if ok and type(k) == "string" and #k > #bare and k:sub(1, #bare) == bare and type(records[k]) == "table" then old = k end
		end
		if not old then
			local n = 0
			for k, v in pairs(records) do
				if type(k) == "string" and type(v) == "table" and #k > #bare and k:sub(1, #bare) == bare and owners[k] == nil
					and k ~= key then
					n = n + 1
					old = k
				end
			end
			if n ~= 1 then old = nil end
		end
		old = old or shared
		if old and old ~= key and type(records[old]) == "table" then
			for k, v in pairs(records[old]) do records[key][k] = CopyRecord(v) end
		end
		return key
	end
end

local function Login()
	DaylightFishingDB = DaylightFishingDB or {}
	db = DaylightFishingDB
	db.chars = db.chars or {}
	-- (db.charOwners: GUID -> this character's key in db.chars.)
	if type(db.charOwners) ~= "table" then db.charOwners = {} end
	local who = Fishing.CharKey(db.chars, db.charOwners) or ((UnitName("player") or "?") .. "-" .. (GetRealmName() or "?"))
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
	-- (Before the welcome, which comes 4 seconds after login and waits while the key box is open.)
	C_Timer.After(2, Fishing.FirstKey)
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
		-- (The loot window comes out of the faded UI on the next frame, not at the next look.)
		if event == "LOOT_OPENED" then fader.relift = true end
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
				if active and menu and menu:IsShown() then UpdateMenu(true) end
			end)
		end
	elseif event == "BAG_OPEN" then
		fader.relift = true
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
-- fight), the way Glowey's Essentials' Halo sets its key. Space by default; Clear leaves no key (the
-- cast button is clicked instead). Shift, Alt and Ctrl alone can't be it, and neither can Escape
-- (it closes the box) or the left and right mouse buttons (they're for the box itself).
-- (All of it inside one function: Core.lua is near Lua's limit of 200 locals in a file's main
-- function, and none of these is needed outside it.)
Fishing.SetKey = (function()
	local MODIFIERS = { LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true, LALT = true, RALT = true,
		LMETA = true, RMETA = true, SHIFT = true, CTRL = true, ALT = true, META = true }
	local BOX_MOUSE = { MiddleButton = "BUTTON3", Button4 = "BUTTON4", Button5 = "BUTTON5" }

	local keyBox
	-- The first start: the box asks for a key before the welcome (which waits while it's open).
	local first = false

	local function KeyName(key)
		if type(key) ~= "string" or key == "" or key == "NONE" then return nil end
		if GetBindingText then
			local ok, text = pcall(GetBindingText, key)
			if ok and type(text) == "string" and text ~= "" then return text end
		end
		return key
	end

	-- A role's ink, kept through every look change (Host.Ink, Host.lua).
	local function BoxInk(fs, name)
		ns.Host.Ink(fs, name)
	end

	local function KeyBoxLayout()
		local kb = keyBox
		kb.now:SetText(L["Now: %s"]:format(KeyName(Get("key")) or L["no key (click the cast button)"]))
		kb.clear:SetShown(KeyName(Get("key")) ~= nil)
		-- The first start: what the key is for, and Forever Fishing's key when it's loaded too.
		local lead = ""
		if first then
			lead = L["Pick the key that casts and hooks while Fishing Mode is on. You can change it any time with Set Fishing Key in the options."]
			local ffdb = C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("ForeverFishing")
				and _G.ForeverFishingDB
			local theirs = type(ffdb) == "table" and KeyName(ffdb.key or "SPACE")
			if theirs then
				lead = lead .. "\n\n" .. L["Forever Fishing uses %s: pick a different key so the two don't fight over it."]:format(theirs)
			end
		end
		kb.lead:SetText(lead)
		-- (The controller interface on: its D-pad, A and B work the box, so they can't be the key.)
		local help = L["Press the key you want, or click here with the mouse's middle or a side button. Escape cancels."]
		if ns.Pad and ns.Pad.On() then
			help = help .. "\n" .. L["Controller: the D-pad and the select and back buttons work this box. Any other button becomes the fishing key."]
		end
		kb.help:SetText(help)
		kb.now:ClearAllPoints()
		if lead ~= "" then
			kb.now:SetPoint("TOPLEFT", kb.lead, "BOTTOMLEFT", 0, -8)
		else
			kb.now:SetPoint("TOPLEFT", kb, "TOPLEFT", 12, -40)
		end
		-- Tall enough for every line at its width: nothing is cut short.
		local w = kb:GetWidth() - 24
		local h = 40
		for _, fs in ipairs({ kb.lead, kb.now, kb.help, kb.msg }) do
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
			-- A controller's buttons too (the game's own key picker takes them the same way).
			if kb.EnableGamePadButton then kb:EnableGamePadButton(true) end
			kb:Show()
		elseif kb and kb:IsShown() then
			kb:Hide()
			if not InCombatLockdown() then
				kb:EnableKeyboard(false)
				if kb.EnableGamePadButton then kb:EnableGamePadButton(false) end
			end
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
		-- (A free box on the screen: Daylight UI's scale, as its own windows, Host.Scaled.)
		ns.Host.Scaled(kb, { own = 1 })
		local head = API.Text(kb, "head", "LEFT")
		head:SetPoint("TOPLEFT", kb, "TOPLEFT", 12, -12)
		head:SetText(L["Fishing Key"])
		BoxInk(head, "TITLE")
		kb.lead = API.Text(kb, "body", "LEFT")
		kb.lead:SetPoint("TOPLEFT", kb, "TOPLEFT", 12, -40)
		BoxInk(kb.lead, "TEXT")
		kb.now = API.Text(kb, "body", "LEFT")
		kb.now:SetPoint("TOPLEFT", kb, "TOPLEFT", 12, -40)
		BoxInk(kb.now, "VALUE")
		kb.help = API.Text(kb, "small", "LEFT")
		kb.help:SetPoint("TOPLEFT", kb.now, "BOTTOMLEFT", 0, -6)
		BoxInk(kb.help, "TEXT")
		kb.msg = API.Text(kb, "small", "LEFT")
		kb.msg:SetPoint("TOPLEFT", kb.help, "BOTTOMLEFT", 0, -6)
		for _, fs in ipairs({ kb.lead, kb.now, kb.help, kb.msg }) do fs:SetWordWrap(true) end
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
		-- A controller button is taken as the key; the one that opens the game menu (Start, by
		-- default) closes the box, as Escape does.
		-- With the controller interface on, the D-pad, A and B go on to the game's cursor, which
		-- works the box (Clear, Space; B closes it: Guide.lua's Pad): true lets a press through.
		local NAV = {}
		for name, fallback in pairs({ GAMEPAD_DPAD_TOP = "PADDUP", GAMEPAD_DPAD_BOTTOM = "PADDDOWN",
			GAMEPAD_DPAD_LEFT = "PADDLEFT", GAMEPAD_DPAD_RIGHT = "PADDRIGHT",
			GAMEPAD_FACE_BOTTOM = "PAD1", GAMEPAD_FACE_RIGHT = "PAD2" }) do
			local k = _G[name]
			NAV[type(k) == "string" and k or fallback] = true
		end
		kb:SetScript("OnGamePadButtonDown", function(_, key)
			if NAV[key] and ns.Pad and ns.Pad.On() then return true end
			if GetBindingAction and GetBindingAction(key) == "TOGGLEGAMEMENU" then ShowKeyBox(false) else TakeKey(key) end
		end)
		if ns.Pad then
			kb.padFirst = function() return kb.space end
			ns.Pad.Follow(kb, function() ShowKeyBox(false) end)
		end
		kb:SetScript("OnMouseDown", function(_, which)
			if BOX_MOUSE[which] then TakeKey(BOX_MOUSE[which]) end
		end)
		-- (However it closes, Escape included: the first-start question is answered, and the
		-- welcome may come.)
		kb:SetScript("OnHide", function()
			if not first then return end
			first = false
			if type(db) == "table" then db.keyAsked = true end
			if type(_G.DaylightGuides) == "table" then _G.DaylightGuides.DaylightFishingKey = nil end
		end)
		kb:Hide()
		if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, "DaylightFishingKeyBox") end
	end

	-- firstStart: asked once on the plugin's first start, before the welcome.
	return function(firstStart)
		BuildKeyBox()
		if firstStart and not InCombatLockdown() then
			first = true
			_G.DaylightGuides = type(_G.DaylightGuides) == "table" and _G.DaylightGuides or {}
			_G.DaylightGuides.DaylightFishingKey = true
		end
		ShowKeyBox(true)
	end
end)()

-- The first start (a new player, not one from before the welcome came): the key is picked first.
-- Waits for a fight, DaylightUI's own setup guide, or another Daylight plugin's welcome or tour.
function Fishing.FirstKey()
	if type(db) ~= "table" or db.keyAsked then return end
	local spec = ns.GuideSpec
	if not (ns.Guide and ns.Guide.Welcoming and ns.Guide.Welcoming()) or (spec and spec.wasExisting) then
		db.keyAsked = true
		return
	end
	local busy = InCombatLockdown()
	for _, name in ipairs({ "DaylightUIInstaller", "DaylightUITour", "DaylightUITourAsk" }) do
		local f = _G[name]
		if type(f) == "table" and f.IsShown and f:IsShown() and (f:GetAlpha() or 0) > 0.05 then busy = true end
	end
	if type(_G.DaylightGuides) == "table" then
		for _, on in pairs(_G.DaylightGuides) do
			if on then busy = true end
		end
	end
	if busy then
		C_Timer.After(5, Fishing.FirstKey)
		return
	end
	Fishing.SetKey(true)
end

local function NotSound(get) return get("sound") == false end
-- Rows about Daylight UI's own look and frames: not there without it (Host.lua). Without it the
-- menu's opacity is the Glowey window opacity (General in /glowey).
local function NoDaylight() return ns.standalone == true end

local pages = {
	{ id = "fishing", label = ns.GameText("PROFESSIONS_FISHING", L["Fishing"]),
	  desc = L["Fishing Mode: put \"Fishing Mode\" in a data text slot (Info Panel, Data texts) and click it, or type /fish."],
	  groups = {
		{ label = L["Fishing Mode"], items = {
			{ type = "button", label = L["Turn Fishing Mode On or Off"], func = function() Fishing.Toggle() end },
			{ type = "button", label = L["Make a Fishing Mode Macro"], func = function() Fishing.MakeMacro() end,
			  desc = L["A \"Fishing Mode\" macro with the Fishing icon that turns Fishing Mode on and off. It goes on your cursor: drop it on an action bar."] },
			{ type = "toggle", key = "autoMode", label = L["Turn On When I Equip a Pole"],
			  desc = L["Putting a fishing pole on turns Fishing Mode on, and taking it off turns it off."] },
			{ type = "button", label = L["Set Fishing Key"], func = function() Fishing.SetKey() end,
			  desc = L["Opens a small box: press any key you want (a mouse's middle or side button works too). Space by default. While Fishing Mode is on, this key casts, and hooks the fish once your bobber is out. It is yours again when Fishing Mode ends, or a fight starts."] },
			{ type = "button", label = L["Clear This Session's Catch"], func = function() Fishing.ResetCatch() end },
			{ type = "toggle", key = "equipPole", label = L["Put My Fishing Pole On"],
			  desc = L["Fishing Mode puts on the best fishing pole in your bags."] },
			{ type = "toggle", key = "restoreWeapons", label = L["Put My Weapons Back On"],
			  desc = L["When you turn Fishing Mode off or get into a fight, the weapons you held go back on."] },
		} },
		{ label = L["Fights While Fishing"], items = {
			{ type = "toggle", key = "mastercraftFights", label = L["Glowey's Fishing Handles Fights"],
			  desc = L["With Mastercraft loaded: on, its \"After the fight: your fishing gear back on\" is off, so your pole stays off after a fight. Off gives Mastercraft its own setting back."] },
		} },
		{ label = L["Fishing Menu"], items = {
			{ type = "toggle", key = "showMenu", label = L["Show the Fishing Menu"],
			  desc = L["Your baits and the cast button under your character. Move it with /dui unlock."] },
			{ type = "slider", key = "menuScale", label = L["Menu Size"], min = 0.7, max = 1.6, step = 0.05, unit = "%",
			  desc = L["How big the fishing menu is."] },
		} },
		{ label = L["For Controller Only"], desc = L["Only with the game's controller interface on."], items = {
			{ type = "toggle", key = "padCatchList", label = L["Catch List Always On"],
			  desc = L["The catch list opens with Fishing Mode and stays open until it ends."] .. " " .. L["It never takes the controller cursor, so your buttons keep fishing: bring the cursor to it as to any open window, and B gives it back to the game."],
			  disabled = SubMenus.PadOff },
			{ type = "toggle", key = "padTrainerBox", label = L["Trainer Box Always On"],
			  desc = L["The trainer box (where to learn your next Fishing rank) opens with Fishing Mode and stays open until it ends."] .. " " .. L["It never takes the controller cursor, so your buttons keep fishing: bring the cursor to it as to any open window, and B gives it back to the game."],
			  disabled = SubMenus.PadOff },
		} },
		{ label = L["Look"], items = {
			{ type = "toggle", key = "duiOpacity", label = L["Use Daylight UI's Opacity"], hidden = NoDaylight,
			  desc = L["The fishing menu and its boxes follow Daylight UI's window opacity."] },
			{ type = "slider", key = "opacity", label = L["Window Opacity"], min = 0.1, max = 1, step = 0.05, unit = "%",
			  desc = L["How solid their backgrounds are, with Daylight UI's opacity off."], hidden = NoDaylight,
			  disabled = function(get) return get("duiOpacity") ~= false end },
		} },
		{ label = L["Quiet Screen"], items = {
			{ type = "toggle", key = "fadeUI", label = L["Fade the UI While Fishing"],
			  desc = L["Like Daylight UI's soft AFK screen: the rest of the UI fades away while you stand and fish, and only the fishing menu stays. It comes back while you chat, loot by hand or fight, and when Fishing Mode ends."]
				.. " " .. L["With Mastercraft loaded, its \"Hide the game's interface\" stays on Never while this is on; turning this off gives it back."] },
			{ type = "slider", key = "fadeAlpha", label = L["Faded UI Opacity"], min = 0, max = 0.6, step = 0.05, unit = "%",
			  desc = L["How much of the UI still shows while faded. 0 hides it."],
			  disabled = function(get) return get("fadeUI") == false end },
			{ type = "slider", key = "fadeDelay", label = L["Fade After Standing Still"], min = 0, max = 10, step = 0.5, unit = "s",
			  desc = L["Seconds of standing still before the UI fades."],
			  disabled = function(get) return get("fadeUI") == false end },
			{ type = "toggle", key = "fadeMoving", label = L["Stay Faded While Moving"],
			  desc = L["Walking about while you fish keeps the UI faded. Off: it comes back as you move."],
			  disabled = function(get) return get("fadeUI") == false end },
			{ type = "toggle", key = "keepMinimap", label = L["Keep the Minimap"],
			  desc = L["The minimap stays while the rest of the UI fades."],
			  disabled = function(get) return get("fadeUI") == false end },
			{ type = "toggle", key = "keepChat", label = L["Keep the Chat"],
			  desc = L["Your chat windows, their tabs and the chat box stay while the rest of the UI fades."],
			  disabled = function(get) return get("fadeUI") == false end },
			{ type = "toggle", key = "catchPopup", label = L["Catch Popup"],
			  desc = L["A note at the fishing menu's left after each cast: \"Fish Caught!\" with what came up, or \"Fish Got Away\"."] },
			{ type = "toggle", key = "hideWater", label = L["Hide Daylight UI's Fishing Water"], hidden = NoDaylight,
			  desc = L["The water and bobber Daylight UI draws along the bottom of the screen while your line is in. Hidden while Fishing Mode is on, and back as it was when it ends. Daylight UI's own switch for it stays in Quality of Life."] },
		} },
		{ label = L["Sound While Fishing"], items = {
			{ type = "toggle", key = "sound", label = L["Set the Sound for Fishing"],
			  desc = L["Sound effects up so you hear the splash, music and ambience down. Your own sound settings come back when Fishing Mode ends."] },
			{ type = "slider", key = "sfxVolume", label = L["Effects Volume"], min = 0, max = 1, step = 0.05, unit = "%",
			  desc = L["The splash of a bite is an effect."], disabled = NotSound },
			{ type = "slider", key = "musicVolume", label = L["Music Volume"], min = 0, max = 1, step = 0.05, unit = "%",
			  disabled = NotSound },
			{ type = "slider", key = "ambienceVolume", label = L["Ambience Volume"], min = 0, max = 1, step = 0.05, unit = "%",
			  disabled = NotSound },
			{ type = "toggle", key = "backgroundSound", label = L["Sound When the Game Is in the Background"],
			  desc = L["Hear a bite while you are in another window."], disabled = NotSound },
		} },
		{ label = L["While Fishing"], items = {
			{ type = "toggle", key = "softInteract", label = L["Soft Interact"],
			  desc = L["Lets the fishing key hook the bobber without clicking it. Set back when Fishing Mode ends."] },
			{ type = "toggle", key = "autoLoot", label = L["Auto Loot"],
			  desc = L["Your catch goes straight into your bags. Set back when Fishing Mode ends."] },
		} },
	  } },
}

-- The "Tell me when a newer version is out" switch (Update.lua), on the first page.
if ns.UpdateGroup and pages[1] then table.insert(pages[1].groups, ns.UpdateGroup()) end
-- Help: Retake Tour, What's new, Revert to Mastercraft (Guide.lua, FishingGuide.lua).
if ns.Guide and ns.Guide.HelpGroup and pages[1] then table.insert(pages[1].groups, ns.Guide.HelpGroup()) end

pcall(function()
	DUI:RegisterPlugin(ADDON, {
		title = "Glowey's Fishing",
		icon = "Interface\\AddOns\\" .. ADDON .. "\\Media\\icon-glyph.png",
		needs = { 1, 1 },
		short = L["Fishing"],
		color = { 0.4, 0.8, 1 },
		blurb = L["Fishing Mode: your pole, your bait and one key to fish."],
	})
	DUI:RegisterModule(ADDON, { plugin = ADDON, label = ns.GameText("PROFESSIONS_FISHING", L["Fishing"]), defaults = DEFAULTS, options = { pages = pages } })
end)

me.RegisterCommand("fish", function() Fishing.Toggle() end, L["Turn Fishing Mode on or off."])
-- Its own command too, with no "/dui" in front (the /dui one stays for macros made before).
_G.SLASH_GLOWEYFISH1 = "/fish"
_G.SLASH_GLOWEYFISH2 = "/fishing"
_G.SlashCmdList.GLOWEYFISH = function() Fishing.Toggle() end

me.On("SettingChanged", function(scope, path)
	if scope ~= ADDON or not active then return end
	-- (The quiet screen's watcher stops when it has nothing to do: a change may give it work.)
	if path == nil or path == "fadeUI" or path == "hideWater" then fader:Show() end
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
		SubMenus.Sync()
	elseif path == "padCatchList" or path == "padTrainerBox" then
		SubMenus.Sync()
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
	-- (The trainer box's places and note, colored as it draws: drawn again while it shows.)
	RefreshBox()
	UpdateBroker()
end)
