-- Daylight Fishing: a DaylightUI plugin.
-- Fishing Mode, turned on and off from a data text (any DaylightUI data text slot, or any other
-- broker display) or /dui fish:
--   on:  your best fishing pole goes on (what you held is remembered), the sound is set for
--        fishing (effects up, music and ambience down, sound in the background, soft interact),
--        and a small menu shows under your character: your baits (click one to put it on the
--        pole) and the cast button. One key casts, and hooks the fish once the bobber is out.
--   off: the sound goes back to how you had it, the menu and the key are let go, and your
--        weapons go back on. Taking the pole off yourself turns Fishing Mode off too (your
--        weapons are left as you put them).
-- The settings are on its page in DaylightUI's options (Plugins). Built on DaylightUI.API only.

local ADDON = ...

local DUI = _G.DaylightUI
local API = DUI and DUI.API
if not API or API.major ~= 1 then return end

local me = API.For(ADDON)

-- ---------------------------------------------------------------------------------------------
-- Settings
-- ---------------------------------------------------------------------------------------------

local DEFAULTS = {
	key = "SPACE",
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
}

local function Get(path)
	local ok, value = pcall(API.GetSetting, ADDON, path)
	if ok and value ~= nil then return value end
	return DEFAULTS[path]
end

local db, char     -- DaylightFishingDB (account), and this character's part of it

local function Print(msg)
	DEFAULT_CHAT_FRAME:AddMessage("|cff66ccffDaylight Fishing|r: " .. msg)
end

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

-- Each saved setting back to how it was. One the game didn't take (it can refuse some in a fight)
-- is kept, and tried again when the fight ends: it is never forgotten before it is back.
local RestoreSettings
function RestoreSettings()
	if type(db.saved) ~= "table" then return end
	for name, old in pairs(db.saved) do
		pcall(SetCVar, name, old)
		local ok, now = pcall(GetCVar, name)
		if not ok or now == nil or SameValue(now, old) then db.saved[name] = nil end
	end
	if next(db.saved) == nil then
		db.saved = nil
	elseif InCombatLockdown() then
		later[#later + 1] = RestoreSettings
	end
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
local UpdateBroker, UpdateMenu, UpdateCatch, RefreshPanel

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
		GameTooltip:AddLine("Click to put it on your fishing pole.", TextColor("TEXT"))
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

	menu.title = API.Text(menu, "small", "LEFT")
	menu.title:SetPoint("TOPLEFT", PAD, -8)
	menu.title:SetText("Fishing Mode")
	menu.title:SetTextColor(API.Accent())

	menu.lure = API.Text(menu, "tiny", "RIGHT")
	menu.lure:SetPoint("TOPRIGHT", -PAD - 22, -9)

	menu.close = API.Close(menu, function()
		if InCombatLockdown() then
			Print("Fishing Mode is off. The menu goes away when the fight ends.")
		end
		_G.DaylightFishing.Toggle(false)
	end, 14)
	menu.close:SetPoint("TOPRIGHT", -8, -7)

	cast = IconButton("DaylightFishingCast", menu, CAST_SIZE, function()
		GameTooltip:SetText("Cast")
		local key = KeyText()
		if key then
			GameTooltip:AddLine("Press " .. key .. " to cast, then " .. key .. " again to hook the fish.", TextColor("TEXT"))
		else
			GameTooltip:AddLine("Pick a key on Daylight Fishing's options page to fish with one key.", TextColor("TEXT"))
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
	menu.empty:SetText("No bait in your bags")
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
		GameTooltip:AddLine("Click: the catch list, fish by fish", 0.8, 0.8, 0.8)
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

	me.RegisterMover(menu, "menu", "Fishing menu", { "CENTER", UIParent, "CENTER", 0, -190 })

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
			menu.lure:SetText(string.format("Bait %d:%02d", math.floor(left / 60), math.floor(left) % 60))
			menu.lure:SetTextColor(TextColor(left < 60 and "WARN" or "VALUE"))
		else
			menu.lure:SetText("No bait on")
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
	local top = -26
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
	cast.state:SetText(channeling and "Hook" or "Cast")
	UpdateCatch()
	local width = math.max(x + CAST_SIZE + PAD, 180)
	menu:SetSize(width, -top + CAST_SIZE + 26)
	API.Skin(menu, { window = true })
end

local function ShowMenu(show)
	OutOfCombat(function()
		BuildMenu()
		if show and Get("showMenu") then
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

local function LiftAll()
	liftedOn = true
	Lift(GameTooltip)
	Lift(LootFrame)
	for i = 1, 4 do Lift(_G["StaticPopup" .. i]) end
	if Get("keepMinimap") ~= false then Lift(Holder(_G.Minimap)) end
	if Get("keepChat") ~= false then
		for i = 1, NUM_CHAT_WINDOWS or 10 do
			Lift(Holder(_G["ChatFrame" .. i]))
			Lift(Holder(_G["ChatFrame" .. i .. "EditBox"]))
			Lift(Holder(_G["ChatFrame" .. i .. "Tab"]))
		end
		Lift(Holder(_G.GeneralDockManager))
	end
	-- Your bags and bank: DaylightUI's windows and the game's, open now or opened later.
	Lift(_G.DaylightUIBag)
	Lift(_G.DaylightUIBank)
	Lift(_G.ContainerFrameCombinedBags)
	Lift(_G.BankFrame)
	for i = 1, 13 do Lift(_G["ContainerFrame" .. i]) end
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
end

-- Straight back, at once (a fight, or Fishing Mode ending).
local function Unfade()
	stillSince = nil
	if fade > 0 or liftedOn then SetFade(0) end
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

local function Enter(resuming)
	if active then return end
	if InCombatLockdown() then
		Print("Not in a fight.")
		return
	end
	if not PoleEquipped() then
		if resuming or not Get("equipPole") then
			if not resuming then Print("Equip a fishing pole first.") end
			return
		end
		local pole = FindPole()
		if not pole then
			Print("No fishing pole in your bags.")
			return
		end
		-- What you held, to put back when Fishing Mode ends.
		char.weapons = { GetInventoryItemLink("player", 16), GetInventoryItemLink("player", 17) }
		equipping = true
		Equip(pole)
		enterSerial = enterSerial + 1
		local serial = enterSerial
		C_Timer.After(3, function()
			if serial == enterSerial and equipping then
				equipping = false
				if active and not PoleEquipped() then
					Print("The fishing pole couldn't go on.")
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

-- reason: "toggle" (the button: your weapons go back on) or "unequipped" (you took the pole off).
local function Leave(reason)
	if not active then return end
	active, equipping, channeling = false, false, false
	char.active = nil
	fader:Hide()
	Unfade()
	KeepWater()
	RestoreSettings()
	ShowMenu(false)
	local weapons = char.weapons
	char.weapons = nil
	if reason == "toggle" and Get("restoreWeapons") and type(weapons) == "table" and (weapons[1] or weapons[2]) then
		OutOfCombat(function()
			if weapons[1] then Equip(weapons[1], 16) end
			if weapons[2] then
				C_Timer.After(0.4, function()
					if not InCombatLockdown() then Equip(weapons[2], 17) end
				end)
			end
		end)
	end
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
		menu.catch.text:SetText("Caught " .. n)
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
local ROW, MAX_ROWS, PANEL_WIDTH = 20, 25, 240

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
	panel.total:SetText(string.format("%d %s, %d %s", n, n == 1 and "catch" or "catches",
		items, items == 1 and "item" or "items"))
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
		panel.empty:SetText("Nothing caught yet.")
		panel.empty:Show()
		bottom = bottom - 18
	elseif #list > MAX_ROWS then
		panel.empty:SetText(string.format("and %d more", #list - MAX_ROWS))
		panel.empty:Show()
		bottom = bottom - 18
	else
		panel.empty:Hide()
	end
	panel.empty:ClearAllPoints()
	panel.empty:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, top - shown * ROW - 2)
	panel:SetSize(PANEL_WIDTH, -bottom + 38)
	API.Skin(panel, { window = true })
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
	panel.title:SetText("Catch this session")
	panel.title:SetTextColor(API.Accent())
	panel.total = API.Text(panel, "tiny", "LEFT")
	panel.total:SetPoint("TOPLEFT", panel.title, "BOTTOMLEFT", 0, -4)
	panel.close = API.Close(panel, function() panel:Hide() end, 14)
	panel.close:SetPoint("TOPRIGHT", -8, -7)
	panel.empty = API.Text(panel, "small", "LEFT")
	panel.empty:SetTextColor(TextColor("OFF"))
	panel.clear = API.Button(panel, "Clear", 20)
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

-- The catch's lines on a tooltip: the count, then what came up, the most first.
function Fishing.CatchTooltip(tip, title)
	local s = char and Session()
	local n = s and s.caught or 0
	if title then tip:SetText("This session's catch") end
	tip:AddDoubleLine("Fish caught", tostring(n), 1, 1, 1, API.Accent())
	if n == 0 then
		tip:AddLine("Nothing caught yet.", TextColor("OFF"))
		return
	end
	local list = Fishing.SortedCatch()
	for i = 1, math.min(#list, MAX_LINES) do
		local item = list[i]
		local icon = item.icon and ("|T" .. item.icon .. ":14:14:0:0:64:64:5:59:5:59|t ") or ""
		tip:AddDoubleLine(icon .. (item.link or item.name or "?"), "x" .. item.count, 1, 1, 1, TextColor("VALUE"))
	end
	if #list > MAX_LINES then
		tip:AddLine(string.format("and %d more", #list - MAX_LINES), TextColor("OFF"))
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
		popup.title:SetText("Fish Caught!")
		popup.title:SetTextColor(TextColor("GOOD"))
	else
		popup.title:SetText("Fish Got Away")
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
	API.Skin(popup, { window = true })
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
		broker.text = "On" .. count
	else
		local r, g, b = TextColor("OFF")
		broker.text = string.format("|cff%02x%02x%02xOff|r", r * 255, g * 255, b * 255) .. count
	end
end

if LDB then
	broker = LDB:NewDataObject("Daylight Fishing", {
		type = "data source",
		label = "Fishing Mode",
		text = "Off",
		icon = POLE_ICON,
		OnClick = function(_, button)
			if button == "RightButton" then
				if IsShiftKeyDown() then
					Fishing.ResetCatch()
					Print("This session's catch is cleared.")
				end
				return
			end
			Fishing.Toggle()
		end,
		OnTooltipShow = function(tip)
			tip:AddLine("Fishing Mode: " .. (active and "on" or "off"))
			local key = KeyText()
			if key then tip:AddLine("Fishing key: " .. key, 1, 1, 1) end
			local left = BaitLeft()
			if active and left then tip:AddLine(string.format("Bait on the pole: %d:%02d", left / 60, left % 60), 1, 1, 1) end
			tip:AddLine(" ")
			Fishing.CatchTooltip(tip)
			tip:AddLine(" ")
			tip:AddLine("Click: turn Fishing Mode " .. (active and "off" or "on"), 0.8, 0.8, 0.8)
			tip:AddLine("Shift-right-click: clear this session's catch", 0.8, 0.8, 0.8)
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
events:RegisterUnitEvent("UNIT_SPELLCAST_SENT", "player")
events:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", "player")
events:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", "player")

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
			char.weapons = nil
		end
		UpdateBroker()
	end)
	UpdateBroker()
	if C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("ForeverFishing") then
		Print("Forever Fishing is loaded too: give the two different keys, or turn one off.")
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
	if event == "LOOT_READY" or event == "LOOT_OPENED" then
		TakeCatch()
	elseif event == "LOOT_CLOSED" then
		looting = false
	elseif event == "PLAYER_REGEN_DISABLED" then
		Unfade()
	elseif event == "PLAYER_REGEN_ENABLED" then
		local list = later
		later = {}
		for i = 1, #list do pcall(list[i]) end
		UpdateBinding()
	elseif event == "PLAYER_EQUIPMENT_CHANGED" then
		if a ~= 16 or not active then return end
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
			if cast then cast.state:SetText("Hook") end
		end
	elseif event == "UNIT_SPELLCAST_CHANNEL_STOP" then
		if channeling then
			channeling = false
			BindWhenReleased()
			if cast then cast.state:SetText("Cast") end
			if IsFalling() then castMoved = true end
			if not castMoved and resolvedCast ~= castSerial then
				local serial = castSerial
				pendingCast = serial
				C_Timer.After(ESCAPE_WAIT, function()
					if pendingCast == serial then GotAway() end
				end)
			end
		end
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

local KEYS = {
	NONE = "No key (click the cast button)",
	SPACE = "Space",
	BUTTON3 = "Middle mouse button",
	BUTTON4 = "Mouse button 4",
	BUTTON5 = "Mouse button 5",
	F = "F", G = "G", R = "R", T = "T", Z = "Z", X = "X", C = "C", V = "V",
	BACKSPACE = "Backspace",
	["`"] = "` (backquote)",
}

local function NotSound(get) return get("sound") == false end

local pages = {
	{ id = "fishing", label = "Fishing",
	  desc = "Fishing Mode: put \"Fishing Mode\" in a data text slot (Info Panel, Data texts) and click it, or type /dui fish.",
	  groups = {
		{ label = "Fishing Mode", items = {
			{ type = "button", label = "Turn Fishing Mode on or off", func = function() Fishing.Toggle() end },
			{ type = "dropdown", key = "key", label = "Fishing key", values = KEYS,
			  desc = "While Fishing Mode is on, this key casts, and hooks the fish once your bobber is out. It is yours again when Fishing Mode ends, or a fight starts." },
			{ type = "button", label = "Clear this session's catch", func = function() Fishing.ResetCatch() end },
			{ type = "toggle", key = "equipPole", label = "Put my fishing pole on",
			  desc = "Fishing Mode puts on the best fishing pole in your bags." },
			{ type = "toggle", key = "restoreWeapons", label = "Put my weapons back on",
			  desc = "When you turn Fishing Mode off, the weapons you held go back on." },
		} },
		{ label = "Fishing menu", items = {
			{ type = "toggle", key = "showMenu", label = "Show the fishing menu",
			  desc = "Your baits and the cast button under your character. Move it with /dui unlock." },
			{ type = "slider", key = "menuScale", label = "Menu size", min = 0.7, max = 1.6, step = 0.05, unit = "%",
			  desc = "How big the fishing menu is." },
		} },
		{ label = "Quiet screen", items = {
			{ type = "toggle", key = "fadeUI", label = "Fade the UI while fishing",
			  desc = "Like DaylightUI's soft AFK screen: the rest of the UI fades away while you stand and fish, and only the fishing menu stays. It comes back while you move, chat, loot by hand or fight, and when Fishing Mode ends." },
			{ type = "slider", key = "fadeAlpha", label = "Faded UI opacity", min = 0, max = 0.6, step = 0.05, unit = "%",
			  desc = "How much of the UI still shows while faded. 0 hides it.",
			  disabled = function(get) return get("fadeUI") == false end },
			{ type = "slider", key = "fadeDelay", label = "Fade after standing still", min = 0, max = 10, step = 0.5, unit = "s",
			  desc = "Seconds of standing still before the UI fades.",
			  disabled = function(get) return get("fadeUI") == false end },
			{ type = "toggle", key = "keepMinimap", label = "Keep the minimap",
			  desc = "The minimap stays while the rest of the UI fades.",
			  disabled = function(get) return get("fadeUI") == false end },
			{ type = "toggle", key = "keepChat", label = "Keep the chat",
			  desc = "Your chat windows, their tabs and the chat box stay while the rest of the UI fades.",
			  disabled = function(get) return get("fadeUI") == false end },
			{ type = "toggle", key = "catchPopup", label = "Catch popup",
			  desc = "A note at the fishing menu's left after each cast: \"Fish Caught!\" with what came up, or \"Fish Got Away\"." },
			{ type = "toggle", key = "hideWater", label = "Hide DaylightUI's fishing water",
			  desc = "The water and bobber DaylightUI draws along the bottom of the screen while your line is in. Hidden while Fishing Mode is on, and back as it was when it ends. DaylightUI's own switch for it stays in Quality of Life." },
		} },
		{ label = "Sound while fishing", items = {
			{ type = "toggle", key = "sound", label = "Set the sound for fishing",
			  desc = "Sound effects up so you hear the splash, music and ambience down. Your own sound settings come back when Fishing Mode ends." },
			{ type = "slider", key = "sfxVolume", label = "Effects volume", min = 0, max = 1, step = 0.05, unit = "%",
			  desc = "The splash of a bite is an effect.", disabled = NotSound },
			{ type = "slider", key = "musicVolume", label = "Music volume", min = 0, max = 1, step = 0.05, unit = "%",
			  disabled = NotSound },
			{ type = "slider", key = "ambienceVolume", label = "Ambience volume", min = 0, max = 1, step = 0.05, unit = "%",
			  disabled = NotSound },
			{ type = "toggle", key = "backgroundSound", label = "Sound when the game is in the background",
			  desc = "Hear a bite while you are in another window.", disabled = NotSound },
		} },
		{ label = "While fishing", items = {
			{ type = "toggle", key = "softInteract", label = "Soft interact",
			  desc = "Lets the fishing key hook the bobber without clicking it. Set back when Fishing Mode ends." },
			{ type = "toggle", key = "autoLoot", label = "Auto loot",
			  desc = "Your catch goes straight into your bags. Set back when Fishing Mode ends." },
		} },
	  } },
}

pcall(function()
	DUI:RegisterPlugin(ADDON, {
		needs = { 1, 1 },
		short = "Fishing",
		color = { 0.4, 0.8, 1 },
		blurb = "Fishing Mode: your pole, your bait and one key to fish.",
	})
	DUI:RegisterModule(ADDON, { plugin = ADDON, label = "Fishing", defaults = DEFAULTS, options = { pages = pages } })
end)

me.RegisterCommand("fish", function() Fishing.Toggle() end, "Turn Fishing Mode on or off.")

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
