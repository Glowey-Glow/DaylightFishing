-- Host.lua: shared by Glowey's plugins. The same file is in each (GloweyGear, DaylightRecipes,
-- DaylightFishing, DaylightEssentials): keep the copies the same, and raise MINOR with any change.
--
-- With Daylight UI loaded, a plugin runs on it as before: ns.DUI and ns.API are Daylight UI's own
-- (DaylightUI, DaylightUI.API), and this file only keeps a copy of the plugin's settings in its own
-- saved variable (<Addon>Settings), so a player who takes Daylight UI out keeps their choices.
--
-- Without Daylight UI, this file stands in for the part of Daylight UI the plugins use:
--   settings   DUI:RegisterPlugin / RegisterModule / Get / Set and API.GetSetting, saved in
--              <Addon>Settings; the same option pages, drawn in one window for every Glowey
--              plugin (/glowey, or Options > AddOns);
--   events     Login, SettingChanged(scope, path, value), StyleChanged, UnlockChanged(on);
--   commands   me.RegisterCommand(word): /glowey <word>, and /<word> when no other addon has it;
--   movers     me.RegisterMover: /glowey unlock shows a handle on each (drag; right-click resets);
--   widgets    API.Skin, Text, Bar, Button, MainButton, Close, Switch, Input, Menu, GlowAround,
--              Fade, Accent, Colors, Font, FontRow, FontFile, ClassColor, Speed;
--   looks      the windows in Glowey's own look, Blizzard Style (the client's own frame art and
--              widgets: "Blizzard Style" below; saved as "game"), or Polestar's: painted by
--              Polestar itself (its public Polestar.Theme.Skin) in whatever look the player picked
--              there, so nothing of Polestar's is copied;
--   minimap    a button on the minimap's edge and a line in the game's addon menu that open the
--              settings;
--   language   a Language row on the General page: the plugins' own text in a language other than
--              the game's (each Locales.lua reads the pick as it loads: LoadSavedVariablesFirst).
-- ns.Host (both modes, MINOR 5): Ink / Tint / Skin (colors and shells that follow a look change),
-- Tip (hover tooltips in the look's roles), Scale (Daylight UI's global scale on a free window),
-- Window / Open / Close / Shown / Moved (Escape, open and close sounds, a fade, the controller, and
-- Daylight UI's window room), Spot (a window's spot in the settings, so in Daylight UI's profiles),
-- AlertChoices / PlayAlert (alert sounds), Sound; MINOR 6, Blizzard Style's parts without Daylight UI
-- (Blizzard, Chrome, Retitle, Dress, Tab, Inset, ScrollArt, Atlas, Looked: see H.Blizzard); MINOR 9,
-- option rows of type "custom" in the settings window (I.CustomRow) and CustomRows / RefreshOptions;
-- MINOR 11, a look change and the settings page drawn again at most once a frame (I.StyleSoon,
-- I.RepaintSoon). With Daylight UI they use its public API first,
-- and a few of its inside parts (Motion, Sound, Pad, Win.Feel / Win.Room) only after a type check,
-- a version check (I.DuiAtLeast) and a pcall, with a fallback of the game's own.
-- What only Daylight UI has (its own frames, tooltips, bags, profession window, test mode, fade,
-- paint) answers false or nil, the way DaylightUI.API answers while that part of it is switched
-- off, so each plugin's own fallback runs. Original code: only the documented call shapes of
-- DaylightUI.API (its API.md) are kept, nothing of its code or art.
--
-- More than one plugin loads this file. The first makes the shared table _G.GloweyHost; the copy
-- with the highest MINOR provides the code, and everything is called through lib.impl at the time
-- of the call, so the newest copy serves every plugin. _G.DaylightUI is never made: other addons
-- must still see that Daylight UI is not there.

-- luacheck: globals SlashCmdList StaticPopupDialogs
-- luacheck: read globals CreateFrame UIParent geterrorhandler SOUNDKIT PlaySound GetCursorPosition
-- luacheck: read globals UISpecialFrames HideUIPanel C_AddOns time YES NO InCombatLockdown ReloadUI
-- luacheck: read globals StaticPopup_Show DEFAULT_CHAT_FRAME GameTooltip PlaySoundFile GetLocale C_Timer

local ADDON, ns = ...
local MINOR = 11

local lib = _G.GloweyHost
if type(lib) ~= "table" then
	lib = { minor = 0 }
	_G.GloweyHost = lib
end
lib.state = lib.state or {}

if (lib.minor or 0) < MINOR then
lib.minor = MINOR
lib.impl = (function()
	local S = lib.state
	S.addons = S.addons or {}          -- [addon] = record (below)
	S.order = S.order or {}            -- the addons in load order
	S.handlers = S.handlers or {}      -- [event] = { { fn, owner }, ... }
	S.commands = S.commands or {}      -- [word] = { fn, help, owner }
	S.movers = S.movers or {}          -- ["plugin.<addon>.<key>"] = mover
	S.moverOrder = S.moverOrder or {}
	S.shells = S.shells or setmetatable({}, { __mode = "k" })
	S.fades = S.fades or {}
	S.glows = S.glows or setmetatable({}, { __mode = "k" })
	S.general = S.general or { accent = { 0.38, 0.66, 1 }, opacity = 0.92 }
	if S.general.look == nil then S.general.look = "glowey" end
	if type(S.general.minimap) ~= "table" then S.general.minimap = { angle = 200 } end
	S.buttons = S.buttons or setmetatable({}, { __mode = "k" })
	S.switches = S.switches or setmetatable({}, { __mode = "k" })
	S.inks = S.inks or setmetatable({}, { __mode = "k" })       -- [region] = { role, alpha, how }
	S.skinned = S.skinned or setmetatable({}, { __mode = "k" }) -- [frame] = Skin's opts
	S.scaled = S.scaled or setmetatable({}, { __mode = "k" })   -- [frame] = { own, docked }
	S.wins = S.wins or setmetatable({}, { __mode = "k" })       -- [frame] = Window's opts
	S.restylers = S.restylers or {}                             -- OnStyle's functions
	-- Blizzard Style's parts (MINOR 6): titled windows (Host.Chrome's opts), close buttons, insets,
	-- and the painters of the parts a plugin dressed (Host.Dress, Host.Tab, Host.Looked).
	S.chrome = S.chrome or setmetatable({}, { __mode = "k" })
	S.closers = S.closers or setmetatable({}, { __mode = "k" })
	S.insets = S.insets or setmetatable({}, { __mode = "k" })
	S.bars = S.bars or setmetatable({}, { __mode = "k" })
	S.looked = S.looked or setmetatable({}, { __mode = "k" })

	local I = { api = {}, me = {}, host = {} }
	local A = I.api
	-- Nothing, for a list that may be missing to be gone through as empty (only read, never filled).
	local EMPTY = {}
	I.EMPTY = EMPTY

	local function T(key)
		local L = S.L
		local v = type(L) == "table" and L[key]
		return type(v) == "string" and v or key
	end
	I.T = T

	function I.Print(msg)
		if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage("|cff61a8ffGlowey|r: " .. tostring(msg)) end
	end

	local function Safe(fn, ...)
		local ok, err = pcall(fn, ...)
		if not ok and geterrorhandler then geterrorhandler()(err) end
		return ok, err
	end

	-- ---------------------------------------------------------------------------------------------
	-- Tables and paths
	-- ---------------------------------------------------------------------------------------------

	local function Copy(v)
		if type(v) ~= "table" then return v end
		local out = {}
		for k, x in pairs(v) do out[k] = Copy(x) end
		return out
	end
	I.Copy = Copy

	local function Same(a, b)
		if a == b then return true end
		if type(a) ~= "table" or type(b) ~= "table" then return false end
		for k, v in pairs(a) do if not Same(v, b[k]) then return false end end
		for k in pairs(b) do if a[k] == nil then return false end end
		return true
	end
	I.Same = Same

	-- A table that is one value (a color { r, g, b }, a list) rather than a group of settings.
	local function IsValue(t) return type(t) == "table" and t[1] ~= nil end

	local function Key(t, part)
		if t[part] ~= nil then return part end
		local n = tonumber(part)
		if n and t[n] ~= nil then return n end
		return part
	end

	local function GetPath(t, path)
		if type(t) ~= "table" then return nil end
		if path == nil or path == "" then return t end
		for part in tostring(path):gmatch("[^%.]+") do
			if type(t) ~= "table" then return nil end
			t = t[Key(t, part)]
		end
		return t
	end
	I.GetPath = GetPath

	local function SetPath(t, path, value)
		local parts = {}
		for part in tostring(path):gmatch("[^%.]+") do parts[#parts + 1] = part end
		if #parts == 0 then return false end
		for i = 1, #parts - 1 do
			local k = Key(t, parts[i])
			if type(t[k]) ~= "table" then t[k] = {} end
			t = t[k]
		end
		t[Key(t, parts[#parts])] = value
		return true
	end
	I.SetPath = SetPath

	local function Fill(dst, defaults)
		if type(defaults) ~= "table" then return end
		for k, v in pairs(defaults) do
			if dst[k] == nil then
				dst[k] = Copy(v)
			elseif type(v) == "table" and type(dst[k]) == "table" and not IsValue(v) then
				Fill(dst[k], v)
			end
		end
	end

	local function Strip(dst, defaults)
		if type(defaults) ~= "table" then return end
		for k, v in pairs(defaults) do
			local d = dst[k]
			if type(v) == "table" and type(d) == "table" then
				if IsValue(v) then
					if Same(d, v) then dst[k] = nil end
				else
					Strip(d, v)
					if next(d) == nil then dst[k] = nil end
				end
			elseif d == v then
				dst[k] = nil
			end
		end
	end

	-- Every saved value under t, as path -> value (a color or a list is one value).
	local function Leaves(t, prefix, out)
		out = out or {}
		for k, v in pairs(t) do
			local path = prefix and (prefix .. "." .. tostring(k)) or tostring(k)
			if type(v) == "table" and not IsValue(v) and next(v) ~= nil then
				Leaves(v, path, out)
			else
				out[path] = v
			end
		end
		return out
	end

	-- ---------------------------------------------------------------------------------------------
	-- Events
	-- ---------------------------------------------------------------------------------------------

	function I.On(event, fn, owner)
		if type(event) ~= "string" or type(fn) ~= "function" then return nil end
		local list = S.handlers[event]
		if not list then
			list = {}
			S.handlers[event] = list
		end
		local h = { event = event, fn = fn, owner = owner }
		list[#list + 1] = h
		return h
	end

	function I.Off(h)
		local list = type(h) == "table" and S.handlers[h.event]
		if not list then return false end
		for i = #list, 1, -1 do
			if list[i] == h then
				table.remove(list, i)
				return true
			end
		end
		return false
	end

	function I.Fire(event, ...)
		local list = S.handlers[event]
		if not list then return end
		local copy = {}
		for i, h in ipairs(list) do copy[i] = h end
		for _, h in ipairs(copy) do Safe(h.fn, ...) end
	end

	-- ---------------------------------------------------------------------------------------------
	-- Settings
	-- ---------------------------------------------------------------------------------------------

	local function Rec(scope) return type(scope) == "string" and S.addons[scope] or nil end

	-- The saved table of an addon: its <Addon>Settings once loaded, a holding table until then.
	local function Store(rec)
		if not rec.store then rec.store = { values = {}, movers = {} } end
		return rec.store
	end
	I.Store = Store

	local function Defaults(rec) return rec.module and rec.module.defaults or nil end

	function I.Get(scope, path)
		local rec = Rec(scope)
		if not rec or not rec.module or not rec.standalone then return nil end
		local v = GetPath(Store(rec).values, path)
		if v == nil then
			v = GetPath(Defaults(rec), path)
			if type(v) == "table" then
				v = Copy(v)
				SetPath(Store(rec).values, path, v)
			end
		end
		return v
	end

	function I.Set(scope, path, value)
		local rec = Rec(scope)
		if not rec or not rec.module or not rec.standalone or type(path) ~= "string" then return false end
		SetPath(Store(rec).values, path, value)
		I.Fire("SettingChanged", scope, path, value)
		I.RepaintSoon()
		return true
	end

	function I.RegisterPlugin(name, info)
		local rec = Rec(name)
		if not rec then return false end
		rec.plugin = type(info) == "table" and info or {}
		return true
	end

	function I.RegisterModule(name, def)
		local rec = Rec(type(def) == "table" and def.plugin or name) or Rec(name)
		if not rec or type(def) ~= "table" then return false end
		def.name = name
		rec.module = def
		if rec.loaded then Fill(Store(rec).values, def.defaults) end
		return def
	end

	function I.GetModule(name)
		local rec = Rec(name)
		return rec and rec.standalone and rec.module or nil
	end

	-- The shared look (the accent, window opacity), kept in every plugin's saved table: the newest wins.
	local function SaveGeneral()
		local now = time and time() or 0
		for _, rec in pairs(S.addons) do
			if rec.loaded then
				local st = Store(rec)
				st.general = Copy(S.general)
				st.generalAt = now
			end
		end
	end

	function I.SetGeneral(key, value)
		local was = S.general[key]
		S.general[key] = value
		SaveGeneral()
		if key == "minimap" then
			I.MapButton()
			return I.RepaintSoon()
		end
		-- (The language each plugin's text is in was picked as it loaded: a reload shows a new one.)
		if key == "language" then
			if I.LangFile(value) ~= I.LangFile(S.locale) then S.needReload = true end
			return I.RepaintSoon()
		end
		-- (A plugin colors much of its own text once, as it draws it: a new look shows there in full
		-- after a reload.)
		if key == "look" and was ~= value then S.needReload = true end
		S.colors = nil
		I.StyleSoon()
	end

	-- A look change drawn: every shell, button and switch again, then StyleChanged (every ink, shell
	-- and restyler a plugin asked for). At most once a frame, as Daylight UI does (DaylightUI/Core.lua:
	-- NotifyStyleChanged): the color picker sets the accent at every move of the mouse, the opacity
	-- slider at every step. While a slider is held it waits for the slider to be let go (MAKE.slider).
	-- The value itself is saved at once (SaveGeneral); only the drawing waits.
	function I.StyleSoon()
		S.styleWanted = true
		if S.sliding or S.stylePending then return end
		if not (C_Timer and C_Timer.After) then return I.StyleNow() end
		S.stylePending = true
		C_Timer.After(0, function()
			S.stylePending = nil
			if not S.sliding then lib.impl.StyleNow() end
		end)
	end

	function I.StyleNow()
		if not S.styleWanted then return end
		S.styleWanted = nil
		I.RepaintAll()
		I.Fire("StyleChanged")
	end

	-- Every shell, button and switch drawn again (the look or its colors changed).
	function I.RepaintAll()
		for frame in pairs(S.shells) do Safe(I.PaintShell, frame) end
		for b in pairs(S.buttons) do Safe(I.PaintButton, b) end
		for sw in pairs(S.switches) do if sw.Paint then Safe(sw.Paint) end end
		if S.mapButton then I.MapPaint() end
		I.RepaintBlizzard()
		I.RepaintSoon()
	end

	-- Polestar changed its look: ours follows while it is Polestar's.
	function I.PolestarChanged()
		S.colors = nil
		if I.Look() ~= "polestar" then return end
		I.StyleSoon()
	end

	-- ---------------------------------------------------------------------------------------------
	-- The minimap button, and the game's addon menu (the button under the minimap)
	-- ---------------------------------------------------------------------------------------------

	local MAP_ICON = "Interface\\Icons\\INV_Misc_Gear_01"

	function I.ToggleWindow()
		if S.win and S.win:IsShown() then S.win:Hide() else I.OpenOptions() end
	end

	function I.MapButton()
		local map = _G.Minimap
		if not map then return end
		local b = S.mapButton
		if not b then
			b = CreateFrame("Button", "GloweyHostMinimapButton", map)
			S.mapButton = b
			b:SetSize(31, 31)
			b:SetFrameStrata("MEDIUM")
			b:SetFrameLevel((map:GetFrameLevel() or 1) + 8)
			b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
			b:RegisterForDrag("LeftButton")
			local bg = b:CreateTexture(nil, "BACKGROUND")
			bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
			bg:SetSize(20, 20)
			bg:SetPoint("CENTER")
			b.icon = b:CreateTexture(nil, "ARTWORK")
			b.icon:SetTexture(MAP_ICON)
			b.icon:SetSize(18, 18)
			b.icon:SetPoint("CENTER")
			b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
			local ring = b:CreateTexture(nil, "OVERLAY")
			ring:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
			ring:SetSize(53, 53)
			ring:SetPoint("TOPLEFT")
			b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
			b:SetScript("OnClick", function(_, which)
				if which == "RightButton" then lib.impl.Unlock(not S.unlocked) else lib.impl.ToggleWindow() end
			end)
			b:SetScript("OnEnter", function(self) lib.impl.MapTip(self) end)
			b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
			b:SetScript("OnDragStart", function(self)
				self:SetScript("OnUpdate", function() lib.impl.MapDrag() end)
			end)
			b:SetScript("OnDragStop", function(self)
				self:SetScript("OnUpdate", nil)
				SaveGeneral()
			end)
		end
		I.MapPlace()
		b:SetShown(not S.general.minimap.hide)
	end

	function I.MapTip(b)
		if not GameTooltip then return end
		GameTooltip:SetOwner(b, "ANCHOR_LEFT")
		GameTooltip:AddLine(T("Glowey's Plugins"))
		GameTooltip:AddLine(T("Click: open the settings"), 1, 1, 1)
		GameTooltip:AddLine(T("Right-click: move frames"), 1, 1, 1)
		GameTooltip:AddLine(T("Drag: move this button"), 1, 1, 1)
		GameTooltip:Show()
	end

	function I.MapPaint() end   -- (the game's own minimap art: nothing to follow a look)

	-- Round the minimap's edge at the saved angle (degrees, 0 = east); out to its corners on a
	-- square minimap.
	function I.MapPlace()
		local b, map = S.mapButton, _G.Minimap
		if not (b and map) then return end
		local angle = math.rad(tonumber(S.general.minimap.angle) or 200)
		local x, y = math.cos(angle), math.sin(angle)
		local shape = _G.GetMinimapShape and _G.GetMinimapShape() or "ROUND"
		if shape ~= "ROUND" then
			x = math.max(-1, math.min(1, x * 1.4142))
			y = math.max(-1, math.min(1, y * 1.4142))
		end
		local w, h = (map:GetWidth() or 140) / 2 + 5, (map:GetHeight() or 140) / 2 + 5
		b:ClearAllPoints()
		b:SetPoint("CENTER", map, "CENTER", x * w, y * h)
	end

	function I.MapDrag()
		local map = _G.Minimap
		local mx, my = map:GetCenter()
		if not mx then return end
		local cx, cy = GetCursorPosition()
		local scale = map:GetEffectiveScale()
		S.general.minimap.angle = math.deg(math.atan2(cy / scale - my, cx / scale - mx)) % 360
		I.MapPlace()
	end

	-- One line in the game's addon menu (Blizzard_Minimap\Camelot\AddonCompartment.lua's
	-- RegisterAddon), for every Glowey plugin together.
	function I.Compartment()
		if S.compartment then return end
		local C = _G.AddonCompartmentFrame
		if type(C) ~= "table" or type(C.RegisterAddon) ~= "function" then return end
		S.compartment = true
		pcall(C.RegisterAddon, C, { text = T("Glowey's Plugins"), icon = MAP_ICON, notCheckable = true,
			func = function() lib.impl.ToggleWindow() end })
	end

	-- ---------------------------------------------------------------------------------------------
	-- Daylight UI loaded: keep a copy of the plugin's settings, and bring a copy made without it in
	-- ---------------------------------------------------------------------------------------------

	local function Mirror(rec, top)
		local real = _G.DaylightUI
		local mod = real and real.GetModule and real:GetModule(rec.name)
		local defaults = type(mod) == "table" and mod.defaults
		if type(defaults) ~= "table" then return end
		local values = Store(rec).values
		if top then
			if defaults[top] ~= nil then values[top] = Copy(real:Get(rec.name, top)) end
			return
		end
		for k in pairs(defaults) do values[k] = Copy(real:Get(rec.name, k)) end
	end

	local function TakeIn(rec)
		local real = _G.DaylightUI
		local st = Store(rec)
		if st.from ~= "standalone" or type(st.values) ~= "table" then return end
		local mod = real.GetModule and real:GetModule(rec.name)
		local defaults = type(mod) == "table" and mod.defaults
		if type(defaults) ~= "table" then return end
		-- (Only the plugin's own settings: a key its defaults no longer have stays out.)
		for path, value in pairs(Leaves(st.values)) do
			if defaults[path:match("^[^%.]+")] ~= nil then
				local okGet, cur = pcall(real.Get, real, rec.name, path)
				if okGet and not Same(cur, value) then pcall(real.Set, real, rec.name, path, Copy(value)) end
			end
		end
	end

	function I.WatchDaylight(rec)
		local api = _G.DaylightUI.API
		pcall(api.On, "Login", function()
			if not rec.loaded then return end
			Safe(TakeIn, rec)
			Safe(Mirror, rec)
			Store(rec).from = "dui"
		end, rec.name)
		pcall(api.On, "SettingChanged", function(scope, path)
			if scope ~= rec.name or not rec.loaded or type(path) ~= "string" then return end
			Mirror(rec, path:match("^[^%.]+"))
		end, rec.name)
	end

	-- ---------------------------------------------------------------------------------------------
	-- Look: colors, fonts, text
	-- ---------------------------------------------------------------------------------------------

	local INK = {
		TITLE = { 1, 1, 1 }, VALUE = { 1, 1, 1 }, TEXT = { 0.86, 0.86, 0.84 }, LABEL = { 0.86, 0.76, 0.58 },
		OFF = { 0.52, 0.52, 0.52 }, GOOD = { 0.42, 0.86, 0.45 }, WARN = { 1, 0.76, 0.28 }, BAD = { 1, 0.38, 0.32 },
		DAMAGE = { 1, 0.55, 0.25 }, MONEY = { 1, 0.86, 0.4 },
	}
	I.INK = INK
	local SIZES = { tiny = 10, small = 12, body = 13, head = 15, title = 18 }
	local WHITE = "Interface\\Buttons\\WHITE8X8"
	local FONTS = {
		{ "general", "Daylight" }, { "friz", "Friz Quadrata", "Fonts\\FRIZQT__.TTF" },
		{ "arial", "Arial Narrow", "Fonts\\ARIALN.TTF" }, { "skurri", "Skurri", "Fonts\\SKURRI.TTF" },
		{ "morpheus", "Morpheus", "Fonts\\MORPHEUS.TTF" },
	}

	-- The game's own colors: gold titles and labels (its GameFontNormal), white values.
	local GAME_INK = {
		TITLE = { 1, 0.82, 0 }, VALUE = { 1, 1, 1 }, TEXT = { 0.9, 0.9, 0.9 }, LABEL = { 1, 0.82, 0 },
		OFF = { 0.5, 0.5, 0.5 }, GOOD = { 0.1, 1, 0.1 }, WARN = { 1, 0.5, 0.25 }, BAD = { 1, 0.13, 0.13 },
		DAMAGE = { 1, 0.5, 0.25 }, MONEY = { 1, 0.82, 0 },
	}
	-- Each ink's name in Polestar's palette (its Theme.Color), read each time: it follows Polestar.
	local POLESTAR_INK = { TITLE = "title", VALUE = "text", TEXT = "textDim", LABEL = "textDim", OFF = "textMuted",
		GOOD = "success", WARN = "warning", BAD = "danger", DAMAGE = "warning", MONEY = "quest" }

	-- Polestar's Theme while Polestar is loaded with the calls used here, else nil. Only its public
	-- table (the global Polestar, its Theme: Skin, Color, Accent, OnChanged).
	local function Polestar()
		local P = rawget(_G, "Polestar")
		local th = type(P) == "table" and P.Theme
		if type(th) == "table" and type(th.Skin) == "function" and type(th.Color) == "function"
			and type(th.Accent) == "function" then return th end
		return nil
	end
	I.Polestar = Polestar

	-- The look drawn now: the player's pick; Polestar's only while Polestar is there.
	function I.Look()
		local look = S.general.look
		if look == "game" then return "game" end
		if look == "polestar" and Polestar() then return "polestar" end
		return "glowey"
	end

	function I.InkOf(key)
		local look = I.Look()
		if look == "game" then return GAME_INK[key] or GAME_INK.TEXT end
		if look == "polestar" then
			local ok, r, g, b = pcall(Polestar().Color, POLESTAR_INK[key] or "text")
			if ok and type(r) == "number" then return { r, g, b } end
		end
		return INK[key] or INK.TEXT
	end

	function A.Accent()
		local look = I.Look()
		if look == "game" then return 1, 0.82, 0 end
		if look == "polestar" then
			local ok, r, g, b = pcall(Polestar().Accent)
			if ok and type(r) == "number" then return r, g, b end
		end
		local c = S.general.accent
		return c[1], c[2], c[3]
	end
	function A.Colors()
		local out = {}
		for k in pairs(INK) do
			local c = I.InkOf(k)
			out[k] = { c[1], c[2], c[3] }
		end
		return out
	end
	-- The languages the plugins' text comes in, each named in its own words (the same seven as
	-- Daylight UI's, DaylightUI/Locales/Locales.lua:34-39), and the clients that share a file.
	local LANGS = { { "enUS", "English" }, { "deDE", "Deutsch" }, { "esES", "Español" }, { "frFR", "Français" },
		{ "ruRU", "Русский" }, { "koKR", "한국어" }, { "zhCN", "简体中文" } }
	local LANG_FILE = { enGB = "enUS", esMX = "esES" }
	-- The game's own font for a language's letters, for a language picked on a client in another one
	-- (an English client's fonts have no Korean or Chinese letters, its Friz Quadrata no Russian ones).
	-- The client's font files, as Daylight UI uses them too (DaylightUI/Style.lua:3094-3097).
	local LANG_FONT = { ruRU = "Fonts\\FRIZQT___CYR.TTF", koKR = "Fonts\\2002.ttf", zhCN = "Fonts\\ARKai_T.ttf" }
	I.LANGS = LANGS

	local function Client() return GetLocale and GetLocale() or "enUS" end
	function I.LangFile(locale)
		if locale == nil or locale == "auto" then locale = Client() end
		return LANG_FILE[locale] or locale
	end
	-- The font a language's text needs here, or nil when the client's own has its letters.
	function I.LangFont(locale)
		local file = I.LangFile(locale)
		if file == I.LangFile(nil) then return nil end
		return LANG_FONT[file]
	end

	function A.Font() return I.LangFont(S.locale) or _G.STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF" end
	function A.FontFile(key)
		if I.LangFont(S.locale) then return A.Font() end
		for _, f in ipairs(FONTS) do
			if f[1] == key and f[3] then return f[3] end
		end
		return A.Font()
	end
	function A.FontRow(key, label, desc)
		if type(key) ~= "string" or type(label) ~= "string" then return nil end
		local values, order = {}, {}
		for _, f in ipairs(FONTS) do
			values[f[1]] = f[1] == "general" and T("Standard") or f[2]
			order[#order + 1] = f[1]
		end
		return { type = "dropdown", key = key, label = label, desc = desc, values = values, order = order }
	end
	function A.ClassColor(token)
		local c = (_G.CUSTOM_CLASS_COLORS or _G.RAID_CLASS_COLORS or EMPTY)[token]
		if type(c) == "table" and c.r then return c.r, c.g, c.b end
		return 1, 1, 1
	end
	A.Speed = { FAST = 0.12, NORMAL = 0.2, SLOW = 0.4 }

	local function Ink(fs, key)
		local c = I.InkOf(key)
		fs:SetTextColor(c[1], c[2], c[3])
	end
	I.Ink = Ink

	function A.Text(parent, size, justify)
		local fs = parent:CreateFontString(nil, "OVERLAY")
		fs:SetFont(A.Font(), SIZES[size] or SIZES.body, "")
		fs:SetShadowOffset(1, -1)
		fs:SetShadowColor(0, 0, 0, 0.9)
		fs:SetJustifyH(justify or "LEFT")
		Ink(fs, "TEXT")
		return fs
	end

	local function Px(region, w, h)
		local P = _G.PixelUtil
		if P and P.SetWidth and w then P.SetWidth(region, w) elseif w then region:SetWidth(w) end
		if P and P.SetHeight and h then P.SetHeight(region, h) elseif h then region:SetHeight(h) end
	end

	-- ---------------------------------------------------------------------------------------------
	-- The window shell
	-- ---------------------------------------------------------------------------------------------

	function A.Skin(frame, opts)
		if type(frame) ~= "table" or type(frame.CreateTexture) ~= "function" then return nil end
		local s = frame.__gloweySkin
		if not s then
			s = { edges = {} }
			frame.__gloweySkin = s
			s.shadow = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
			s.shadow:SetPoint("TOPLEFT", -3, 3)
			s.shadow:SetPoint("BOTTOMRIGHT", 3, -3)
			s.bg = frame:CreateTexture(nil, "BACKGROUND", nil, -7)
			s.bg:SetAllPoints()
			for i = 1, 4 do s.edges[i] = frame:CreateTexture(nil, "BORDER", nil, 7) end
			local e = s.edges
			e[1]:SetPoint("TOPLEFT"); e[1]:SetPoint("TOPRIGHT")
			e[2]:SetPoint("BOTTOMLEFT"); e[2]:SetPoint("BOTTOMRIGHT")
			e[3]:SetPoint("TOPLEFT"); e[3]:SetPoint("BOTTOMLEFT")
			e[4]:SetPoint("TOPRIGHT"); e[4]:SetPoint("BOTTOMRIGHT")
			-- (Shown and hidden by itself, as Daylight UI's shell is.)
			s.Show = function() s.hidden = nil; lib.impl.PaintShell(frame) end
			s.Hide = function() s.hidden = true; lib.impl.PaintShell(frame) end
			s.SetShown = function(a, b)
				local on = b
				if type(a) ~= "table" then on = a end
				if on then s.Show() else s.Hide() end
			end
			s.IsShown = function() return not s.hidden end
		end
		local o = {}
		if type(opts) == "table" then for k, v in pairs(opts) do o[k] = v end end
		s.opts = o
		S.shells[frame] = true
		I.PaintShell(frame)
		return s
	end

	-- The look a shell is drawn in. (o.own: always ours, a color swatch; a frame Polestar couldn't
	-- paint stays ours too.)
	local function ShellLook(s)
		local look = (s.opts and s.opts.own) and "glowey" or I.Look()
		if look == "polestar" and s.psFailed then look = "glowey" end
		return look
	end

	function I.PaintShell(frame)
		local s = frame.__gloweySkin
		if not s then return end
		local o = s.opts or {}
		local look = ShellLook(s)
		s.paintedLook = look   -- (what I.Lit's quick way checks)
		local own = look == "glowey"
		local a = type(o.bgAlpha) == "number" and o.bgAlpha or (o.window and S.general.opacity) or 0.92
		local c = type(o.color) == "table" and o.color
		if c then s.bg:SetColorTexture(c[1] or 1, c[2] or 1, c[3] or 1, 1) else s.bg:SetColorTexture(0.07, 0.07, 0.085, a) end
		s.bg:SetShown(own and not o.noBackground and not s.hidden)
		s.shadow:SetColorTexture(0, 0, 0, o.noBackground and 0 or 0.3 * a)
		s.shadow:SetShown(own and not s.hidden)
		local px = type(o.borderPx) == "number" and o.borderPx or 1
		local r, g, b = 0.24, 0.24, 0.27
		if s.lit then r, g, b = A.Accent() end
		for i, e in ipairs(s.edges) do
			e:SetColorTexture(r, g, b, 1)
			if i <= 2 then Px(e, nil, px) else Px(e, px, nil) end
			e:SetShown(own and not o.noBorder and not s.hidden)
		end
		-- Another look: drawn on a layer frame of its own under the frame (one per look, so
		-- going back and forth leaves nothing of one on the other), and lit by a wash on top.
		for key, layer in pairs(s.layers or EMPTY) do
			if key ~= look then layer:Hide() end
		end
		if own then
			if s.hi then s.hi:Hide() end
			-- (Blizzard Style's title bar and the close button it moved: put back in another look.)
			if S.chrome[frame] then I.ChromeParts(frame, false) end
			if s.onLook then Safe(s.onLook, look) end
			return
		end
		local layer = I.Layer(frame, s, look)
		local kind = o.kind or (o.window and "window") or "panel"
		layer.opts = o
		if layer.kind ~= kind then
			layer.kind = kind
			if look == "game" then
				I.PaintGame(layer, kind)
			elseif not pcall(Polestar().Skin, layer, I.POLESTAR_KIND[kind] or "panel") then
				-- (Polestar refused it: this frame keeps Glowey's look.)
				s.psFailed = true
				layer:Hide()
				return I.PaintShell(frame)
			end
		end
		-- (Blizzard Style is opaque, as Blizzard's frames are: Glowey's window opacity is its own
		-- look's. The art is fitted again each time: a window can become a titled one, Host.Chrome.)
		if look == "game" then I.GameFit(layer) end
		layer:SetShown(not s.hidden and not (o.noBackground and o.noBorder))
		I.LitWash(frame, s, look, kind)
		if S.chrome[frame] then I.ChromeParts(frame, look == "game" and not s.hidden) end
		if s.onLook then Safe(s.onLook, look) end
	end

	-- Our kinds of frame as Polestar's painters name them (its Theme.Skin kinds).
	I.POLESTAR_KIND = { window = "window", panel = "panel", menu = "panel", button = "button", editbox = "editbox" }

	-- The layer a look is drawn on: a child frame under its frame (a level lower, so the frame's
	-- own text and textures stay on top of it), the size of it.
	function I.Layer(frame, s, look)
		s.layers = s.layers or {}
		local layer = s.layers[look]
		if not layer then
			local template = (look == "game" and _G.BackdropTemplateMixin) and "BackdropTemplate" or nil
			layer = CreateFrame("Frame", nil, frame, template)
			layer:SetAllPoints()
			layer:EnableMouse(false)
			-- Blizzard Style draws at its frame's own level, sorted by draw layer under the frame's
			-- text, as Blizzard's NineSlice does (useParentLevel, Mainline/SharedUIPanelTemplates.xml:
			-- 333, :400; SimpleFrameAPIDocumentation.lua:1518). A level of its own one under the frame
			-- doesn't hold: raising the frame lifts its children over its text.
			if look == "game" and layer.SetUsingParentLevel then
				layer.parentLevel = pcall(layer.SetUsingParentLevel, layer, true)
			end
			s.layers[look] = layer
			if not s.levelHooked then
				s.levelHooked = true
				frame:HookScript("OnShow", function(f) lib.impl.LayerLevel(f) end)
			end
		end
		I.LayerLevel(frame)
		return layer
	end

	function I.LayerLevel(frame)
		local s = frame.__gloweySkin
		local level = math.max(0, (frame:GetFrameLevel() or 1) - 1)
		for _, layer in pairs(s and s.layers or EMPTY) do
			-- (Blizzard Style's art frames sit on their layer's level, under the frame's own; on the
			-- frame's own level where the client lets them: I.Layer.)
			if not layer.parentLevel then
				layer:SetFrameLevel(level)
				for _, art in pairs(layer.arts or EMPTY) do art:SetFrameLevel(level) end
			end
		end
	end

	-- ---------------------------------------------------------------------------------------------
	-- Blizzard Style (the look saved as "game"): the client's own frame art, laid out as its own
	-- FrameXML lays it out (Gethe/wow-ui-source, branch "forever"; paths under Interface/AddOns/
	-- Blizzard_SharedXML unless named):
	--   a titled window  ButtonFrameTemplate without its portrait: the metal NineSlice layout
	--                    "ButtonFrameTemplateNoPortrait" (Mainline/NineSliceLayouts.lua:43-54, with
	--                    the client's own Camelot/NineSliceLayoutOverrides.lua applied to it), the
	--                    rock background and the top streaks (Mainline/SharedUIPanelTemplates.xml:
	--                    687-702), the title (:599-614), placed as ButtonFrameTemplate_HidePortrait
	--                    places them (Mainline/SharedUIPanelTemplates.lua:90-117), and the red close
	--                    button (xml:136-142, placed as Camelot/SharedUIPanelTemplates.lua:1-5).
	--                    Host.Chrome asks for it. Our windows lay out to their own edge, so the frame
	--                    goes round the outside: by the room a ButtonFrameTemplate leaves round its
	--                    Inset (PANEL_INSET_* and the no-portrait left, Mainline/
	--                    SharedUIPanelTemplates.lua:4-8, :101-109), the title bar above.
	--   another window   the dialog border, NineSlice "Dialog" (Mainline/NineSliceLayouts.lua:157-167),
	--                    on DialogBorderDarkTemplate's background (Shared/Dialog/DialogTemplates.xml:
	--                    83-95); a small one, the tooltip's
	--   a panel          the tooltip's NineSlice "TooltipDefaultLayout" (Mainline/NineSliceLayouts.lua:
	--                    257-268), colored as SharedTooltipTemplates.lua:51-58 colors it
	--   a menu           the dropdown menu's background (Blizzard_Menu/Mainline/MenuTemplates.lua:53-61)
	--   a button         UIPanelButtonTemplate's three slices (SecureUIPanelTemplates.xml:39-80)
	--   an edit box      InputBoxTemplate's border (Shared/InputBox/InputBoxTemplates.xml:44-66);
	--                    a search box SearchBoxTemplate's glass and clear button (:209-252)
	-- All opaque, as Blizzard's are (Glowey's window opacity belongs to Glowey's own look). On a
	-- client without NineSliceUtil the old dialog and tooltip backdrops (Backdrop.lua) stand in.
	-- ---------------------------------------------------------------------------------------------

	local GAME_DIALOG = { bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
		edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", tile = true, tileEdge = true, tileSize = 32,
		edgeSize = 32, insets = { left = 11, right = 12, top = 12, bottom = 11 } }
	local GAME_BOX = { bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileEdge = true, tileSize = 16,
		edgeSize = 14, insets = { left = 3, right = 3, top = 3, bottom = 3 } }
	local GAME_BUTTON = "Interface\\Buttons\\UI-Panel-Button-"
	-- The pieces named above (each file and atlas from the template cited beside it).
	local BZ = {
		-- How far the frame goes round a titled window: a ButtonFrameTemplate's Inset sits 9 in from
		-- its left without a portrait, 6 from its right, 4 from its foot and 24 under its top.
		left = 9, right = 6, bottom = 4, top = 24,
		rock = "Interface\\FrameGeneral\\UI-Background-Rock",        -- SharedUIPanelTemplates.xml:690
		marble = "Interface\\FrameGeneral\\UI-Background-Marble",    -- InsetFrameTemplate, xml:396
		dialog = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark", -- DialogTemplates.xml:87
		-- (normal, pushed, disabled, highlight)
		close = { "RedButton-Exit", "RedButton-exit-pressed", "RedButton-Exit-Disabled", "RedButton-Highlight" },
		minimize = { "RedButton-Condense", "RedButton-Condense-Pressed", "RedButton-Condense-disabled", "RedButton-Highlight" },
		maximize = { "RedButton-Expand", "RedButton-Expand-Pressed", "RedButton-Expand-Disabled", "RedButton-Highlight" },
		-- NumericInputSpinnerTemplate's arrows (InputBoxTemplates.xml:309-345): files, not atlases
		prev = { "Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Up", "Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Down",
			"Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Disabled", "Interface\\Buttons\\UI-Common-MouseHilight", file = true },
		next = { "Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up", "Interface\\Buttons\\UI-SpellbookIcon-NextPage-Down",
			"Interface\\Buttons\\UI-SpellbookIcon-NextPage-Disabled", "Interface\\Buttons\\UI-Common-MouseHilight", file = true },
		-- SearchBoxTemplate's clear button: its one icon at half alpha (InputBoxTemplates.xml:226-233)
		clear = { "common-search-clearbutton", alpha = 0.5, size = 10 },
	}
	I.BZ = BZ

	-- The client's NineSliceUtil, when it has one.
	function I.Nine()
		local N = rawget(_G, "NineSliceUtil")
		if type(N) == "table" and type(N.ApplyLayoutByName) == "function" then return N end
		return nil
	end
	-- An atlas the client has (C_Texture.GetAtlasInfo), put on a texture: true when it went on.
	-- (Each answer kept: the client's atlases don't change while it runs.)
	function I.HasAtlas(atlas)
		local C = rawget(_G, "C_Texture")
		if type(C) ~= "table" or type(C.GetAtlasInfo) ~= "function" then return false end
		if atlas == nil then return false end
		S.atlases = S.atlases or {}
		local known = S.atlases[atlas]
		if known ~= nil then return known end
		local ok, info = pcall(C.GetAtlasInfo, atlas)
		known = (ok and info ~= nil) and true or false
		S.atlases[atlas] = known
		return known
	end
	function I.Atlas(tex, atlas, useSize)
		if not I.HasAtlas(atlas) then return false end
		return pcall(tex.SetAtlas, tex, atlas, useSize and true or false) and true or false
	end
	-- A file tiled across a texture, as horizTile / vertTile do in the templates.
	function I.Tile(tex, file)
		tex:SetTexture(file, "REPEAT", "REPEAT")
		if tex.SetHorizTile then tex:SetHorizTile(true) end
		if tex.SetVertTile then tex:SetVertTile(true) end
	end

	function I.PaintGame(layer, kind)
		if kind == "button" then
			local t = {}
			for i = 1, 3 do
				t[i] = layer:CreateTexture(nil, "BACKGROUND")
				t[i]:SetTexture(GAME_BUTTON .. "Up")
			end
			t[1]:SetPoint("TOPLEFT"); t[1]:SetPoint("BOTTOMLEFT"); t[1]:SetWidth(12)
			t[1]:SetTexCoord(0, 0.09375, 0, 0.6875)
			t[3]:SetPoint("TOPRIGHT"); t[3]:SetPoint("BOTTOMRIGHT"); t[3]:SetWidth(12)
			t[3]:SetTexCoord(0.53125, 0.625, 0, 0.6875)
			t[2]:SetPoint("TOPLEFT", t[1], "TOPRIGHT"); t[2]:SetPoint("BOTTOMRIGHT", t[3], "BOTTOMLEFT")
			t[2]:SetTexCoord(0.09375, 0.53125, 0, 0.6875)
			layer.slices = t
		elseif kind == "editbox" and I.HasAtlas("common-search-border-middle") then
			-- InputBoxVisualTemplate's left, middle and right pieces (InputBoxTemplates.xml:44-66).
			local t = {}
			for i, atlas in ipairs({ "common-search-border-left", "common-search-border-middle", "common-search-border-right" }) do
				t[i] = layer:CreateTexture(nil, "BACKGROUND")
				I.Atlas(t[i], atlas)
			end
			t[1]:SetPoint("TOPLEFT"); t[1]:SetPoint("BOTTOMLEFT"); t[1]:SetWidth(8)
			t[3]:SetPoint("TOPRIGHT"); t[3]:SetPoint("BOTTOMRIGHT"); t[3]:SetWidth(8)
			t[2]:SetPoint("TOPLEFT", t[1], "TOPRIGHT"); t[2]:SetPoint("BOTTOMRIGHT", t[3], "BOTTOMLEFT")
			layer.edge = t
		end
		-- (Fitted again whenever the frame's size changes: a border too big for its frame overlaps
		-- itself, as the dialog's 32-pixel corners did on Essentials' 26-pixel combat timer.)
		if not layer.fitHooked then
			layer.fitHooked = true
			layer:HookScript("OnSizeChanged", function(l) lib.impl.GameFit(l) end)
		end
		I.GameFit(layer)
	end

	-- The art sized to its frame. A window gets the dialog border only where it fits with room to
	-- spare; anything smaller gets the tooltip's. A red button's end caps no more than half its width.
	local DIALOG_MIN_W, DIALOG_MIN_H, BOX_EDGE = 120, 90, 14
	function I.GameFit(layer)
		local frame = layer:GetParent()
		local w, h = frame:GetWidth() or 0, frame:GetHeight() or 0
		if layer.slices or layer.edge then
			local t = layer.slices or layer.edge
			local cap = math.max(1, math.min(layer.slices and 12 or 8, math.floor(w / 2)))
			t[1]:SetWidth(cap)
			t[3]:SetWidth(cap)
			return
		end
		local how
		if layer.kind == "window" then
			if S.chrome[frame] then how = "chrome"
			elseif w >= DIALOG_MIN_W and h >= DIALOG_MIN_H then how = "dialog"
			else how = "tooltip" end
		elseif layer.kind == "menu" then
			how = "menu"
		else
			how = "tooltip"
		end
		if I.Nine() then return I.NineFit(layer, frame, how) end
		-- (No NineSliceUtil: the backdrops.)
		if not layer.SetBackdrop then return end
		local dialog = how ~= "tooltip" and how ~= "menu"
		local edge = dialog and 32 or math.max(4, math.min(BOX_EDGE, math.floor(math.min(w, h) / 2)))
		local key = (dialog and "dialog" or "box") .. edge
		if layer.fit ~= key then
			layer.fit = key
			local b
			if dialog then
				b = GAME_DIALOG
			else
				local inset = math.max(1, math.floor(edge / 4))
				b = { bgFile = GAME_BOX.bgFile, edgeFile = GAME_BOX.edgeFile, tile = true, tileEdge = true, tileSize = 16,
					edgeSize = edge, insets = { left = inset, right = inset, top = inset, bottom = inset } }
			end
			layer:SetBackdrop(b)
			if not dialog then layer:SetBackdropBorderColor(0.6, 0.6, 0.6, 1) end
			local out = dialog and 10 or math.max(1, math.floor(edge / 4))
			layer:ClearAllPoints()
			layer:SetPoint("TOPLEFT", frame, "TOPLEFT", -out, out)
			layer:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", out, -out)
		end
		-- (SetBackdrop puts its colors back.)
		layer:SetBackdropColor(1, 1, 1, 1)
	end

	-- One art frame per kind on a layer (a NineSlice layout's pieces stay on the frame they were put
	-- on, and one layout's pieces aren't another's), on the layer's level; the one asked for shown.
	function I.ArtFrame(layer, how)
		layer.arts = layer.arts or {}
		local f = layer.arts[how]
		local made = false
		if not f then
			f = CreateFrame("Frame", nil, layer)
			f:EnableMouse(false)
			layer.arts[how] = f
			made = true
		end
		if not layer.parentLevel then
			f:SetFrameLevel(layer:GetFrameLevel())
		elseif made then
			pcall(f.SetUsingParentLevel, f, true)
		end
		for k, other in pairs(layer.arts) do other:SetShown(k == how) end
		return f, made
	end

	function I.NineFit(layer, frame, how)
		local o = layer.opts or {}
		local key = how .. (o.noBackground and "-" or "+")
		if layer.fit == key then return end
		layer.fit = key
		if layer.SetBackdrop then layer:SetBackdrop(nil) end
		layer:ClearAllPoints()
		layer:SetAllPoints(frame)
		local N = I.Nine()
		local f, made = I.ArtFrame(layer, how)
		if how == "chrome" then
			if made then
				pcall(N.ApplyLayoutByName, f, "ButtonFrameTemplateNoPortrait")
				f.bg = f:CreateTexture(nil, "BACKGROUND", nil, -6)
				f.bg:SetPoint("TOPLEFT", 7, -21)
				f.bg:SetPoint("BOTTOMRIGHT", -2, 2)
				f.streaks = f:CreateTexture(nil, "BORDER")
				if I.Atlas(f.streaks, "_UI-Frame-TopTileStreaks", true) then
					if f.streaks.SetHorizTile then f.streaks:SetHorizTile(true) end
					f.streaks:SetPoint("TOPLEFT", 6, -21)
					f.streaks:SetPoint("TOPRIGHT", -2, -21)
				end
				-- The title, in the title bar's TitleContainer (xml:599-614): GameFontNormal, centered.
				f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
				f.title:SetDrawLayer("OVERLAY", 7)   -- (over the title bar's metal)
				f.title:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -6)
				f.title:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -6)
				f.title:SetHeight(12)
				f.title:SetWordWrap(false)
			end
			f:ClearAllPoints()
			f:SetPoint("TOPLEFT", frame, "TOPLEFT", -BZ.left, BZ.top)
			f:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", BZ.right, -BZ.bottom)
			I.ChromeGround(frame, f)
			I.ChromeTitle(frame, f)
		elseif how == "dialog" then
			if made then
				pcall(N.ApplyLayoutByName, f, "Dialog")
				f.bg = f:CreateTexture(nil, "BACKGROUND", nil, -5)
				I.Tile(f.bg, BZ.dialog)
				f.bg:SetPoint("TOPLEFT", 7, -7)
				f.bg:SetPoint("BOTTOMRIGHT", -7, 7)
			end
			-- (Out round the frame by the border's own inset, so it covers little of what's inside.)
			f:ClearAllPoints()
			f:SetPoint("TOPLEFT", frame, "TOPLEFT", -7, 7)
			f:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 7, -7)
			f.bg:SetShown(not o.noBackground)
		elseif how == "tooltip" then
			if made then
				pcall(N.ApplyLayoutByName, f, "TooltipDefaultLayout")
				local bg, edge = rawget(_G, "TOOLTIP_DEFAULT_BACKGROUND_COLOR"), rawget(_G, "TOOLTIP_DEFAULT_COLOR")
				local r, g, b = 0, 0, 0
				if type(bg) == "table" and bg.GetRGB then r, g, b = bg:GetRGB() end
				if type(f.Center) == "table" then f.Center:SetVertexColor(r, g, b, 1) end
				if type(edge) == "table" and edge.GetRGB then
					local er, eg, eb = edge:GetRGB()
					for _, k in ipairs({ "TopLeftCorner", "TopRightCorner", "BottomLeftCorner", "BottomRightCorner",
						"TopEdge", "BottomEdge", "LeftEdge", "RightEdge" }) do
						if type(f[k]) == "table" then f[k]:SetVertexColor(er, eg, eb, 1) end
					end
				end
			end
			f:ClearAllPoints()
			f:SetAllPoints(frame)
			if type(f.Center) == "table" then f.Center:SetShown(not o.noBackground) end
		else
			if made then
				f.bg = f:CreateTexture(nil, "BACKGROUND")
				if I.Atlas(f.bg, "common-dropdown-bg") then
					f.bg:SetPoint("TOPLEFT", -10, 3)
					f.bg:SetPoint("BOTTOMRIGHT", 10, -3)
					-- (Solid, not the game's 0.925: what's under a menu must never read through it.)
					f.bg:SetAlpha(1)
				else
					f.bg:SetAllPoints()
					f.bg:SetColorTexture(0, 0, 0, 1)
				end
			end
			f:ClearAllPoints()
			f:SetAllPoints(frame)
		end
	end

	-- A red button's art for its state: up, or the game's grey one while it can't be clicked.
	function I.ButtonArt(b)
		local s = b.__gloweySkin
		local layer = s and s.layers and s.layers.game
		if not (layer and layer.slices) then return end
		local art = GAME_BUTTON .. ((b.off or not b:IsEnabled()) and "Disabled" or "Up")
		for _, t in ipairs(layer.slices) do t:SetTexture(art) end
	end

	-- ---------------------------------------------------------------------------------------------
	-- A titled window in Blizzard Style (Host.Chrome): its title in the title bar, its close button
	-- moved up there as Blizzard's red one, the window's own heading out of sight meanwhile.
	-- ---------------------------------------------------------------------------------------------

	function I.ChromeFrame(frame)
		local s = frame.__gloweySkin
		local layer = s and s.layers and s.layers.game
		local f = layer and layer.arts and layer.arts.chrome
		if f and layer:IsShown() and f:IsShown() then return f end
		return nil
	end

	-- The ground: a window's own (opts.ground, an atlas: the profession window's), else the rock.
	function I.ChromeGround(frame, f)
		local o = S.chrome[frame] or {}
		local want = type(o.ground) == "string" and I.HasAtlas(o.ground) and o.ground or "rock"
		if f.ground == want then return end
		f.ground = want
		f.bg:SetTexCoord(0, 1, 0, 1)
		if want == "rock" then
			I.Tile(f.bg, BZ.rock)
		else
			if f.bg.SetHorizTile then f.bg:SetHorizTile(false) end
			if f.bg.SetVertTile then f.bg:SetVertTile(false) end
			I.Atlas(f.bg, want)
		end
	end

	function I.ChromeTitle(frame, f)
		f = f or I.ChromeFrame(frame)
		local o = S.chrome[frame]
		if not (f and o and f.title) then return end
		local text = o.title
		if type(text) == "function" then
			local ok, v = pcall(text)
			text = ok and v or nil
		end
		f.title:SetText(type(text) == "string" and text or "")
		-- (A language picked here that the client's own font lacks letters for: its font.)
		local font = I.LangFont(S.locale)
		if font then
			local _, size = f.title:GetFont()
			f.title:SetFont(font, size or 12, "")
		end
	end

	-- The close button (moved into the title bar and dressed as Blizzard's), the regions hidden, and
	-- the clamp (so the title bar never leaves the screen), on or back as they were.
	function I.ChromeParts(frame, on)
		local o = S.chrome[frame]
		if not o then return end
		local f = on and I.ChromeFrame(frame)
		on = f and true or false
		local b = o.close
		if type(b) == "table" and b.ClearAllPoints then
			if on and not b.__bzPoints then
				local pts = {}
				for i = 1, (b:GetNumPoints() or 0) do pts[i] = { b:GetPoint(i) } end
				b.__bzPoints, b.__bzSize = pts, { b:GetWidth(), b:GetHeight() }
			end
			if on then
				b:ClearAllPoints()
				b:SetSize(28, 28)
				b:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 3)
				b.__bzTitle = true
			elseif b.__bzPoints then
				b:ClearAllPoints()
				for _, p in ipairs(b.__bzPoints) do b:SetPoint(unpack(p)) end
				b:SetSize(b.__bzSize[1], b.__bzSize[2])
				b.__bzPoints, b.__bzSize, b.__bzTitle = nil, nil, nil
			end
			if b.Paint then Safe(b.Paint) end
		end
		for _, region in ipairs(type(o.hide) == "table" and o.hide or EMPTY) do
			if type(region) == "table" and region.SetAlpha then region:SetAlpha(on and 0 or 1) end
		end
		-- (The title bar is the window's too: it drags the window, as Blizzard's does.)
		if frame.SetHitRectInsets then
			if on and not frame.__bzHit then
				frame.__bzHit = { frame:GetHitRectInsets() }
				frame:SetHitRectInsets(0, 0, -BZ.top, 0)
			elseif not on and frame.__bzHit then
				local c = frame.__bzHit
				frame:SetHitRectInsets(c[1] or 0, c[2] or 0, c[3] or 0, c[4] or 0)
				frame.__bzHit = nil
			end
		end
		if frame.SetClampRectInsets then
			if on and not frame.__bzClamp then
				frame.__bzClamp = { frame:GetClampRectInsets() }
				frame:SetClampRectInsets(-BZ.left, BZ.right, BZ.top, -BZ.bottom)
			elseif not on and frame.__bzClamp then
				local c = frame.__bzClamp
				frame:SetClampRectInsets(c[1] or 0, c[2] or 0, c[3] or 0, c[4] or 0)
				frame.__bzClamp = nil
			end
		end
	end

	-- ---------------------------------------------------------------------------------------------
	-- Blizzard's own button art on one of ours (Host.Dress, the close buttons): normal, pushed,
	-- disabled and highlight, as a Button's four textures show them; the button's own marks out of
	-- sight meanwhile. set: one of BZ's (atlases, or files with file = true).
	-- ---------------------------------------------------------------------------------------------

	function I.ArtState(b)
		local a = b.__bzArt
		if not a then return end
		if not a.on then
			for _, k in ipairs({ "n", "p", "d", "h" }) do a[k]:Hide() end
			return
		end
		local off = b.off or not b:IsEnabled()
		local down = a.down and not off
		a.n:SetShown(not off and not down)
		a.p:SetShown(down and a.hasP)
		if down and not a.hasP then a.n:Show() end
		a.d:SetShown(off and a.hasD)
		if off and not a.hasD then a.n:Show() end
		a.h:SetShown(not off and a.hasH and b:IsMouseOver())
	end

	function I.Dressing(b, set, size)
		local a = b.__bzArt
		if set and not a then
			a = {}
			for _, k in ipairs({ "n", "p", "d", "h" }) do
				a[k] = b:CreateTexture(nil, "ARTWORK", nil, 7)
				a[k]:SetPoint("CENTER")
				a[k]:Hide()
			end
			a.h:SetBlendMode("ADD")
			b.__bzArt = a
			local function St(self) lib.impl.ArtState(self) end
			b:HookScript("OnMouseDown", function(self) local x = self.__bzArt if x then x.down = true end lib.impl.ArtState(self) end)
			b:HookScript("OnMouseUp", function(self) local x = self.__bzArt if x then x.down = nil end lib.impl.ArtState(self) end)
			b:HookScript("OnEnter", St)
			b:HookScript("OnLeave", St)
			b:HookScript("OnEnable", St)
			b:HookScript("OnDisable", St)
		end
		if not a then return false end
		if set and a.set ~= set then
			a.set = set
			local okAll = true
			for i, k in ipairs({ "n", "p", "d", "h" }) do
				local art = set[i]
				local ok = false
				if art then
					if set.file then
						a[k]:SetTexture(art)
						ok = true
					else
						ok = I.Atlas(a[k], art)
					end
				end
				if k == "n" then okAll = ok end
				a["has" .. k:upper()] = ok
				a[k]:SetAlpha(set.alpha or 1)
			end
			a.h:SetAlpha(1)
			a.usable = okAll
		end
		a.on = set ~= nil and a.usable == true
		if a.on then
			local w = size or set.size or b:GetWidth()
			local h = size or set.size or b:GetHeight()
			for _, k in ipairs({ "n", "p", "d", "h" }) do a[k]:SetSize(w, h) end
		end
		I.ArtState(b)
		return a.on
	end

	-- Each A.Close: Blizzard's red X in Blizzard Style (the clear button's glass X on a search box's
	-- little one), the drawn X otherwise.
	function I.PaintClose(b)
		local look = I.Look()
		local set, size
		if look == "game" then
			if (b.size or 16) <= 12 and not b.__bzTitle then
				set, size = BZ.clear, BZ.clear.size
			else
				set = BZ.close
				size = b.__bzTitle and 28 or math.max(20, math.min(24, (b.size or 16) + 6))
			end
		end
		local on = I.Dressing(b, set, size)
		local c = b:IsMouseOver() and INK.BAD or INK.LABEL
		b.icon:SetVertexColor(c[1], c[2], c[3])
		b.icon2:SetVertexColor(c[1], c[2], c[3])
		b.icon:SetShown(not on)
		b.icon2:SetShown(not on)
	end

	-- ---------------------------------------------------------------------------------------------
	-- The parts a plugin asks for by name, each drawn only in Blizzard Style without Daylight UI
	-- (S.looked: drawn again when the look changes).
	-- ---------------------------------------------------------------------------------------------

	function I.Blizzard() return I.Look() == "game" end

	-- A button dressed as one of Blizzard's (kind: close, minimize, maximize, prev, next; size: the
	-- art's, else the button's). hide: the button's own regions, out of sight meanwhile. One of our own buttons (API.Button) puts
	-- its red shell and its text away by itself.
	function I.Dress(b, kind, hide, size)
		local on = I.Blizzard()
		local done = I.Dressing(b, on and BZ[kind] or nil, size)
		for _, region in ipairs(type(hide) == "table" and hide or EMPTY) do
			if type(region) == "table" and region.SetAlpha then region:SetAlpha(done and 0 or 1) end
		end
		local s = b.__gloweySkin
		if s and S.buttons[b] then
			if done then s.Hide() else s.Show() end
			if b.text then b.text:SetAlpha(done and 0 or 1) end
		end
		return done
	end

	-- PanelTopTabButtonTemplate's art (Mainline/SharedUIPanelTemplates.xml:932-1006: the panel
	-- tab's atlases, turned to hang from above as PanelTopTabButtonMixin:OnLoad turns them,
	-- Mainline/SharedUIPanelTemplates.lua:283-307).
	local TAB_PARTS = {
		{ "Left", "uiframe-tab-left" }, { "Right", "uiframe-tab-right" }, { "Middle", "_uiframe-tab-center" },
		{ "LeftActive", "uiframe-activetab-left" }, { "RightActive", "uiframe-activetab-right" },
		{ "MiddleActive", "_uiframe-activetab-center" },
		{ "LeftHighlight", "uiframe-tab-left" }, { "RightHighlight", "uiframe-tab-right" },
		{ "MiddleHighlight", "_uiframe-tab-center" },
	}
	function I.MakeTab(b)
		if not I.HasAtlas("_uiframe-tab-center") then return nil end
		local t = {}
		for _, p in ipairs(TAB_PARTS) do
			local hi = p[1]:find("Highlight") ~= nil
			local tex = b:CreateTexture(nil, hi and "HIGHLIGHT" or "BACKGROUND")
			I.Atlas(tex, p[2], true)
			if p[2]:sub(1, 1) == "_" and tex.SetHorizTile then tex:SetHorizTile(true) end
			if hi then
				tex:SetBlendMode("ADD")
				tex:SetAlpha(0.4)
			end
			tex:SetTexCoord(0, 1, 1, 0.25)
			tex:SetHeight((tex:GetHeight() or 32) * 0.75)
			t[p[1]] = tex
		end
		t.Left:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", -3, 0)
		t.Right:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 7, 0)
		t.Middle:SetPoint("TOPLEFT", t.Left, "TOPRIGHT")
		t.Middle:SetPoint("TOPRIGHT", t.Right, "TOPLEFT")
		t.LeftActive:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", -1, 0)
		t.RightActive:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 8, 0)
		t.MiddleActive:SetPoint("TOPLEFT", t.LeftActive, "TOPRIGHT")
		t.MiddleActive:SetPoint("TOPRIGHT", t.RightActive, "TOPLEFT")
		t.LeftHighlight:SetPoint("TOPLEFT", t.Left, "TOPLEFT")
		t.RightHighlight:SetPoint("TOPRIGHT", t.Right, "TOPRIGHT")
		t.MiddleHighlight:SetPoint("TOPLEFT", t.Middle, "TOPLEFT")
		t.MiddleHighlight:SetPoint("TOPRIGHT", t.Middle, "TOPRIGHT")
		b.__bzTab = t
		return t
	end

	function I.Tab(b, selected, hide)
		local on = I.Blizzard()
		local t = b.__bzTab
		if on and not t then t = I.MakeTab(b) end
		on = on and t ~= nil
		if t then
			for _, p in ipairs(TAB_PARTS) do
				local k = p[1]
				local active = k:find("Active") ~= nil
				local hi = k:find("Highlight") ~= nil
				t[k]:SetShown(on and ((hi and not selected) or (not hi and active == (selected and true or false))))
			end
		end
		for _, region in ipairs(type(hide) == "table" and hide or EMPTY) do
			if type(region) == "table" and region.SetAlpha then region:SetAlpha(on and 0 or 1) end
		end
		return on
	end

	-- InsetFrameTemplate (Mainline/SharedUIPanelTemplates.xml:389-401): the marble ground (or
	-- another, an atlas) in the "InsetFrameTemplate" NineSlice (Mainline/NineSliceLayouts.lua:81-91),
	-- on its parent's level, shown in Blizzard Style only. The caller places it.
	function I.Inset(parent, ground)
		if not I.Nine() or type(parent) ~= "table" then return nil end
		local f = CreateFrame("Frame", nil, parent)
		f:EnableMouse(false)
		f:SetFrameLevel(parent:GetFrameLevel())
		if f.SetUsingParentLevel then f.parentLevel = pcall(f.SetUsingParentLevel, f, true) end
		f.bg = f:CreateTexture(nil, "BACKGROUND", nil, -5)
		f.bg:SetAllPoints()
		if not (type(ground) == "string" and I.Atlas(f.bg, ground)) then I.Tile(f.bg, BZ.marble) end
		pcall(I.Nine().ApplyLayoutByName, f, "InsetFrameTemplate")
		if not f.parentLevel then parent:HookScript("OnShow", function(p) f:SetFrameLevel(p:GetFrameLevel()) end) end
		S.insets[f] = true
		f:SetShown(I.Blizzard())
		return f
	end

	-- MinimalScrollBar's track and small thumb (Shared/Scroll/MinimalScrollBar.xml:15-100) round a
	-- thumb a window draws and moves itself (a texture), on a track down `along`'s right edge, its
	-- middle x from that edge. True while drawn (the window then hides its own thumb's color).
	local SCROLL_PARTS = { "minimal-scrollbar-track-top", "!minimal-scrollbar-track-middle",
		"minimal-scrollbar-track-bottom", "minimal-scrollbar-small-thumb-top",
		"minimal-scrollbar-small-thumb-middle", "minimal-scrollbar-small-thumb-bottom" }
	-- Blizzard Style: the game's own scroll bar, MinimalScrollBar itself (Blizzard_SharedXML/Shared/
	-- Scroll/MinimalScrollBar.xml: its arrows at both ends, the track, a thumb to drag, the track to
	-- click), made from its template beside `along` and kept in step with it the way the game's
	-- ScrollUtil.InitScrollFrameWithScrollBar does (Scroll/ScrollUtil.lua:215-270): the visible
	-- extent and the step as fractions, the scroll as a percentage, BaseScrollBoxEvents.OnScroll
	-- moving what it scrolls. ctl: { range(), at(), set(v), view(), step } for a list that isn't a
	-- ScrollFrame (rows from an offset); a ScrollFrame needs none. Nil when this client has no such
	-- template: then the picture of one below stands in.
	local function Fraction(v) return math.max(0, math.min(1, v)) end
	local function ScrollCtl(along)
		if type(along.GetVerticalScrollRange) ~= "function" then return nil end
		return {
			range = function() return along:GetVerticalScrollRange() or 0 end,
			at = function() return along:GetVerticalScroll() or 0 end,
			set = function(v) along:SetVerticalScroll(v) end,
			view = function() return along:GetHeight() or 0 end,
		}
	end
	function I.RealScrollBar(thumb, along, x, ctl)
		local bar = thumb.__bzBar
		if bar == nil then
			bar = false
			local events = rawget(_G, "BaseScrollBoxEvents")
			if type(events) == "table" and events.OnScroll then
				local ok, made = pcall(CreateFrame, "EventFrame", nil, thumb:GetParent(), "MinimalScrollBar")
				if ok and made and type(made.SetScrollPercentage) == "function" and type(made.RegisterCallback) == "function" then
					bar = made
					bar:SetFrameLevel((thumb:GetParent():GetFrameLevel() or 0) + 6)
					pcall(bar.RegisterCallback, bar, events.OnScroll, function(_, pct)
						local c = bar.__ctl
						if bar.__syncing or not c then return end
						local range = c.range()
						if range > 0 then c.set(Fraction(pct) * range) end
					end, bar)
				end
			end
			thumb.__bzBar = bar
		end
		if not bar then return false end
		bar.__ctl = ctl or bar.__ctl or ScrollCtl(along)
		local c = bar.__ctl
		local range = c and c.range() or 0
		if not (c and thumb:IsShown() and range > 0) then
			bar:Hide()
			return true
		end
		-- (Placed again only when its place changes: this runs at every scroll.)
		if bar.__along ~= along or bar.__x ~= (x or 4) then
			bar.__along, bar.__x = along, x or 4
			bar:ClearAllPoints()
			bar:SetPoint("TOP", along, "TOPRIGHT", -(x or 4), 0)
			bar:SetPoint("BOTTOM", along, "BOTTOMRIGHT", -(x or 4), 0)
		end
		local view = math.max(1, c.view())
		bar.__syncing = true
		pcall(bar.SetVisibleExtentPercentage, bar, Fraction(view / (view + range)))
		pcall(bar.SetPanExtentPercentage, bar, Fraction((c.step or 30) / range))
		local consts = rawget(_G, "ScrollBoxConstants")
		local none = type(consts) == "table" and consts.NoScrollInterpolation or nil
		pcall(bar.SetScrollPercentage, bar, Fraction(c.at() / range), none)
		bar.__syncing = nil
		bar:Show()
		return true
	end

	function I.ScrollArt(thumb, along, x, ctl)
		local on = I.Blizzard() and I.HasAtlas(SCROLL_PARTS[5])
		-- (The game's own bar when it can be made; the picture below is only its stand-in.)
		if on and I.RealScrollBar(thumb, along, x, ctl) then
			for _, t in ipairs(thumb.__bzScroll or EMPTY) do t:Hide() end
			return true
		end
		if thumb.__bzBar then thumb.__bzBar:Hide() end
		local a = thumb.__bzScroll
		if on and not a then
			a = {}
			local p = thumb:GetParent()
			for i, atlas in ipairs(SCROLL_PARTS) do
				a[i] = p:CreateTexture(nil, i <= 3 and "ARTWORK" or "OVERLAY", nil, i <= 3 and 0 or 7)
				I.Atlas(a[i], atlas, true)
			end
			a[1]:SetPoint("TOP", along, "TOPRIGHT", -(x or 4), 0)
			a[3]:SetPoint("BOTTOM", along, "BOTTOMRIGHT", -(x or 4), 0)
			a[2]:SetPoint("TOPLEFT", a[1], "BOTTOMLEFT")
			a[2]:SetPoint("BOTTOMRIGHT", a[3], "TOPRIGHT")
			a[4]:SetPoint("TOP", thumb, "TOP")
			a[6]:SetPoint("BOTTOM", thumb, "BOTTOM")
			a[5]:SetPoint("TOPLEFT", a[4], "BOTTOMLEFT")
			a[5]:SetPoint("BOTTOMRIGHT", a[6], "TOPRIGHT")
			thumb.__bzScroll = a
		end
		local shown = on and thumb:IsShown()
		for _, t in ipairs(a or EMPTY) do t:SetShown(shown) end
		return on
	end

	-- Every named part drawn again (the look changed).
	function I.RepaintBlizzard()
		for b in pairs(S.closers) do Safe(I.PaintClose, b) end
		for f in pairs(S.insets) do f:SetShown(I.Blizzard()) end
		for bar in pairs(S.bars) do Safe(I.BarArt, bar) end
		for _, fn in pairs(S.looked) do Safe(fn) end
		for frame in pairs(S.chrome) do Safe(I.ChromeTitle, frame) end
	end

	-- A titled window (S.chrome): opts.title (text, or a function asked each time), opts.close (the
	-- window's API.Close button: moved into the title bar), opts.hide (regions out of sight while the
	-- title bar shows, a heading it replaces), opts.ground (an atlas for the ground, else the rock).
	function I.Chrome(frame, opts)
		if type(frame) ~= "table" or type(opts) ~= "table" then return false end
		S.chrome[frame] = opts
		if frame.__gloweySkin then I.PaintShell(frame) end
		return true
	end

	-- UICheckButtonArtTemplate's box and check (Shared/Button/CheckButtonTemplates.xml:42-48) in
	-- place of a switch's track. True while drawn.
	local CHECK = { n = "Interface\\Buttons\\UI-CheckBox-Up", h = "Interface\\Buttons\\UI-CheckBox-Highlight",
		c = "Interface\\Buttons\\UI-CheckBox-Check", dc = "Interface\\Buttons\\UI-CheckBox-Check-Disabled" }
	function I.CheckArt(sw)
		local on = I.Blizzard()
		local a = sw.__bzCheck
		if on and not a then
			a = {}
			for k, file in pairs(CHECK) do
				local t = sw:CreateTexture(nil, k == "n" and "BACKGROUND" or "ARTWORK")
				t:SetTexture(file)
				t:SetSize(26, 26)
				t:SetPoint("LEFT", sw, "LEFT", -4, 0)
				a[k] = t
			end
			a.h:SetBlendMode("ADD")
			sw.__bzCheck = a
		end
		if not a then return false end
		local en = sw:IsEnabled()
		a.n:SetShown(on)
		a.h:SetShown(on and en and sw:IsMouseOver())
		a.c:SetShown(on and sw.on and en or false)
		a.dc:SetShown(on and sw.on and not en or false)
		return on
	end

	-- WowStyle1DropdownTemplate's text holder and arrow (Blizzard_Menu/Mainline/MenuTemplates.xml:
	-- 3-39; the arrow's states, MenuTemplates.lua:2-17) on a dropdown's button, in place of its red
	-- shell. True while drawn.
	function I.DropArt(b, over)
		local on = I.Blizzard() and I.HasAtlas("common-dropdown-textholder")
		local a = b.__bzDrop
		if on and not a then
			a = { bg = b:CreateTexture(nil, "BACKGROUND", nil, 1), arrow = b:CreateTexture(nil, "OVERLAY") }
			I.Atlas(a.bg, "common-dropdown-textholder", true)
			a.bg:SetPoint("TOPLEFT", -8, 7)
			a.bg:SetPoint("BOTTOMRIGHT", 8, -9)
			a.arrow:SetPoint("RIGHT", 1, -3)
			b.__bzDrop = a
		end
		if a then
			a.bg:SetShown(on)
			a.arrow:SetShown(on)
			if on then
				local off = b.off or not b:IsEnabled()
				I.Atlas(a.arrow, off and "common-dropdown-a-button-disabled"
					or (over and "common-dropdown-a-button-hover" or "common-dropdown-a-button"), true)
			end
		end
		local s = b.__gloweySkin
		if s then
			if on and not s.hidden then s.Hide() elseif not on and b.__bzDropHid then s.Show() end
		end
		b.__bzDropHid = on or nil
		return on
	end

	-- MinimalSliderTemplate's bar and button (Shared/Slider/MinimalSlider.xml:3-31) on a slider, in
	-- place of its track and thumb. True while drawn.
	function I.SliderArt(sl)
		local on = I.Blizzard() and I.HasAtlas("Minimal_SliderBar_Button")
		local a = sl.__bzSlider
		if on and not a then
			a = { l = sl:CreateTexture(nil, "ARTWORK"), r = sl:CreateTexture(nil, "ARTWORK"), m = sl:CreateTexture(nil, "ARTWORK") }
			I.Atlas(a.l, "Minimal_SliderBar_Left", true)
			I.Atlas(a.r, "Minimal_SliderBar_Right", true)
			I.Atlas(a.m, "_Minimal_SliderBar_Middle", true)
			a.l:SetPoint("LEFT")
			a.r:SetPoint("RIGHT")
			a.m:SetPoint("TOPLEFT", a.l, "TOPRIGHT")
			a.m:SetPoint("TOPRIGHT", a.r, "TOPLEFT")
			sl.__bzSlider = a
		end
		if a then for _, t in pairs(a) do t:SetShown(on) end end
		if sl.track then sl.track:SetShown(not on) end
		if on then
			I.Atlas(sl.thumb, "Minimal_SliderBar_Button", true)
			sl.thumb:SetVertexColor(1, 1, 1)
		elseif a then
			sl.thumb:SetTexture(WHITE)
			sl.thumb:SetTexCoord(0, 1, 0, 1)
			sl.thumb:SetSize(10, 14)
		end
		return on
	end

	-- Hover and focus in another look: the game's own highlight on a red button, else a wash in
	-- the accent over the frame (under its text).
	function I.LitWash(frame, s, look, kind)
		if not s.lit or s.hidden then
			if s.hi then s.hi:Hide() end
			return
		end
		if not s.hi then
			s.hi = frame:CreateTexture(nil, "ARTWORK", nil, -8)
			s.hi:SetAllPoints()
		end
		if look == "game" and kind == "button" then
			s.hi:SetTexture(GAME_BUTTON .. "Highlight")
			s.hi:SetTexCoord(0, 0.625, 0, 0.6875)
			s.hi:SetBlendMode("ADD")
			s.hi:SetVertexColor(1, 1, 1, 1)
		else
			local r, g, b = A.Accent()
			s.hi:SetTexCoord(0, 1, 0, 1)
			s.hi:SetBlendMode("BLEND")
			s.hi:SetColorTexture(r, g, b, 0.12)
		end
		s.hi:Show()
	end

	-- Lights a shell's edge in the accent (hover, focus, picked), or puts it back. (Runs at every
	-- hover: when the shell was last drawn in the look it is in now, only what shows the lit state
	-- is drawn again, the edges in Glowey's look, the wash in another, just as I.PaintShell draws
	-- them. Anything else that changes a shell draws it in full.)
	function I.Lit(frame, on)
		local s = frame.__gloweySkin
		if not s then return end
		s.lit = on and true or nil
		local look = s.paintedLook
		if look == nil or look ~= ShellLook(s) then return I.PaintShell(frame) end
		if look == "glowey" then
			local r, g, b = 0.24, 0.24, 0.27
			if s.lit then r, g, b = A.Accent() end
			for _, e in ipairs(s.edges) do e:SetColorTexture(r, g, b, 1) end
		else
			local o = s.opts or EMPTY
			I.LitWash(frame, s, look, o.kind or (o.window and "window") or "panel")
		end
	end

	-- ---------------------------------------------------------------------------------------------
	-- Widgets
	-- ---------------------------------------------------------------------------------------------

	local function Sound()
		if PlaySound and SOUNDKIT and SOUNDKIT.U_CHAT_SCROLL_BUTTON then PlaySound(SOUNDKIT.U_CHAT_SCROLL_BUTTON) end
	end

	local function PaintButton(b)
		local over = b:IsMouseOver() and b:IsEnabled()
		I.Lit(b, over or b.active)
		local game = I.Look() == "game"
		if b.band then
			local r, g, bb = A.Accent()
			b.band:SetColorTexture(r, g, bb, b.main and 0.22 or (b.active and 0.14 or 0))
			b.band:SetShown(not game)
		end
		I.ButtonArt(b)
		local drop = b.drop and I.DropArt(b, over)
		if b.off or not b:IsEnabled() then Ink(b.text, "OFF")
		elseif b.main then Ink(b.text, "GOOD")
		elseif drop then Ink(b.text, "VALUE")   -- a dropdown's choice: GameFontHighlight
		elseif game then Ink(b.text, (over or b.active) and "VALUE" or "TITLE")   -- the game's gold, white lit
		else Ink(b.text, "VALUE") end
	end
	I.PaintButton = PaintButton

	function A.Button(parent, text, height)
		local b = CreateFrame("Button", nil, parent)
		b:SetSize(120, height or 24)
		A.Skin(b, { bgAlpha = 0.85, kind = "button" })
		S.buttons[b] = true
		b.band = b:CreateTexture(nil, "BACKGROUND", nil, -6)
		b.band:SetPoint("TOPLEFT", 1, -1)
		b.band:SetPoint("BOTTOMRIGHT", -1, 1)
		b.text = A.Text(b, "body", "CENTER")
		b.text:SetWordWrap(false)
		b:SetFontString(b.text)
		b.text:ClearAllPoints()
		b.text:SetPoint("LEFT", 6, 0)
		b.text:SetPoint("RIGHT", -6, 0)
		b:SetText(text or "")
		b:SetScript("OnEnter", PaintButton)
		b:SetScript("OnLeave", PaintButton)
		b:HookScript("OnEnable", PaintButton)
		b:HookScript("OnDisable", PaintButton)
		b:SetScript("PostClick", Sound)
		function b.SetOff(on)
			b.off = on and true or nil
			b:SetEnabled(not on)
			PaintButton(b)
		end
		function b.SetActive(on)
			b.active = on and true or nil
			PaintButton(b)
		end
		function b.FitWidth(min)
			b:SetWidth(math.max(min or 90, math.ceil(b.text:GetStringWidth() or 0) + 32))
		end
		PaintButton(b)
		return b
	end

	function A.MainButton(button, on)
		if type(button) ~= "table" or type(button.text) ~= "table" or not button.band then return false end
		button.main = on ~= false or nil
		PaintButton(button)
		return true
	end

	function A.Close(parent, onClick, size)
		local b = CreateFrame("Button", nil, parent)
		size = size or 16
		b:SetSize(size, size)
		local function Line(angle)
			local t = b:CreateTexture(nil, "ARTWORK")
			t:SetTexture(WHITE)
			t:SetSize(size * 0.95, math.max(1.5, size / 9))
			t:SetPoint("CENTER")
			if t.SetRotation then t:SetRotation(angle) end
			return t
		end
		b.icon = Line(math.pi / 4)
		b.icon2 = Line(-math.pi / 4)
		b.size = size
		-- (Blizzard's red X in Blizzard Style: I.PaintClose.)
		local function Paint() lib.impl.PaintClose(b) end
		b.Paint = Paint
		b:SetScript("OnEnter", Paint)
		b:SetScript("OnLeave", Paint)
		b:SetScript("OnClick", function(self, ...) if onClick then onClick(self, ...) end end)
		b:SetScript("PostClick", Sound)
		S.closers[b] = true
		Paint()
		return b
	end

	function A.Switch(parent)
		local s = CreateFrame("Button", nil, parent)
		s:SetSize(32, 16)
		s.track = s:CreateTexture(nil, "BACKGROUND")
		s.track:SetAllPoints()
		s.track:SetTexture(WHITE)
		s.fill = s:CreateTexture(nil, "ARTWORK")
		s.fill:SetSize(12, 12)
		s.fill:SetTexture(WHITE)
		local function Paint()
			if s.on then
				local r, g, b = A.Accent()
				s.track:SetVertexColor(r, g, b, s:IsEnabled() and 0.85 or 0.35)
			else
				s.track:SetVertexColor(0.25, 0.25, 0.28, 1)
			end
			s.fill:ClearAllPoints()
			s.fill:SetPoint(s.on and "RIGHT" or "LEFT", s.on and -2 or 2, 0)
			s.fill:SetVertexColor(1, 1, 1, (s:IsMouseOver() or s.on) and 1 or 0.75)
			-- Blizzard Style: a check box instead (I.CheckArt).
			local box = lib.impl.CheckArt(s)
			s.track:SetShown(not box)
			s.fill:SetShown(not box)
		end
		function s.SetOn(on)
			s.on = on and true or false
			Paint()
		end
		s:SetScript("OnEnter", Paint)
		s:SetScript("OnLeave", Paint)
		s:HookScript("OnEnable", Paint)
		s:HookScript("OnDisable", Paint)
		s:SetScript("PostClick", Sound)
		s.Paint = Paint
		S.switches[s] = true
		s.SetOn(false)
		return s
	end

	function A.Input(parent, opts)
		opts = type(opts) == "table" and opts or {}
		local e = CreateFrame("EditBox", nil, parent)
		e:SetSize(160, 24)
		e:SetAutoFocus(false)
		e:SetFont(A.Font(), 12, "")
		e:SetTextColor(1, 1, 1)
		A.Skin(e, { bgAlpha = 0.6, kind = "editbox" })
		local left = opts.search and 22 or 6
		e:SetTextInsets(left, opts.search and 20 or 6, 0, 0)
		if opts.numeric then e:SetNumeric(true) end
		if type(opts.maxLetters) == "number" then
			e.maxLetters = opts.maxLetters
			e:SetMaxLetters(opts.maxLetters)
		end
		e.hint = A.Text(e, "small", opts.justify or "LEFT")
		e.hint:SetPoint("LEFT", left, 0)
		e.hint:SetPoint("RIGHT", -6, 0)
		e.hint:SetText(opts.hint or "")
		Ink(e.hint, "OFF")
		if opts.search then
			e.isSearch = true
			e.icon = e:CreateTexture(nil, "ARTWORK")
			e.icon:SetPoint("LEFT", 6, -1)
			-- SearchBoxTemplate's glass in Blizzard Style (InputBoxTemplates.xml:213-220), ours else.
			e.__gloweySkin.onLook = function(look)
				if look == "game" and lib.impl.Atlas(e.icon, "common-search-magnifyingglass") then
					e.icon:SetSize(10, 10)
					e.icon:SetVertexColor(1, 1, 1)
				else
					e.icon:SetTexture("Interface\\Common\\UI-Searchbox-Icon")
					e.icon:SetTexCoord(0, 1, 0, 1)
					e.icon:SetSize(13, 13)
					e.icon:SetVertexColor(0.6, 0.6, 0.6)
				end
			end
			e.__gloweySkin.onLook(I.Look())
			e.clear = A.Close(e, function()
				e:SetText("")
				e:ClearFocus()
			end, 10)
			e.clear:SetPoint("RIGHT", -6, 0)
			e.clear:Hide()
		end
		local function Hint()
			local empty = (e:GetText() or "") == ""
			e.hint:SetShown(empty and not e:HasFocus())
			if e.clear then e.clear:SetShown(not empty) end
		end
		e:SetScript("OnTextChanged", function(self, user)
			Hint()
			if opts.onChange then Safe(opts.onChange, self:GetText() or "", user) end
		end)
		e:SetScript("OnEditFocusGained", function(self) Hint(); I.Lit(self, true) end)
		e:SetScript("OnEditFocusLost", function(self) Hint(); I.Lit(self, false) end)
		e:SetScript("OnEscapePressed", e.ClearFocus)
		e:SetScript("OnEnterPressed", e.ClearFocus)
		Hint()
		return e
	end

	function A.Bar(parent)
		local bar = CreateFrame("StatusBar", nil, parent)
		bar:SetMinMaxValues(0, 1)
		bar:SetValue(0)
		bar.bg = bar:CreateTexture(nil, "BACKGROUND")
		bar.bg:SetAllPoints()
		S.bars[bar] = true
		I.BarArt(bar)
		return bar
	end

	-- A bar's art. Blizzard Style: the profession window's own status bar, ProfessionsStatusBarArtTemplate
	-- (Blizzard_ProfessionsTemplates/Blizzard_ProfessionsTemplates.xml:3-38): its border in three
	-- pieces of UI-Character-Skills-BarBorder hanging 2 and 3 past its ends, the skill bar's fill in
	-- its blue (.25, .25, .75). Another look: a flat fill in the accent over a dark track. Drawn
	-- again when the look changes (I.RepaintBlizzard); a color set on the bar afterwards stays.
	local SKILL = "Interface\\PaperDollInfoFrame\\UI-Character-Skills-Bar"
	local SKILL_EDGE = "Interface\\PaperDollInfoFrame\\UI-Character-Skills-BarBorder"
	function I.BarArt(bar)
		local on = I.Blizzard()
		local a = bar.__bzBar
		if on and not a then
			a = {}
			for _, k in ipairs({ "l", "r", "m" }) do
				a[k] = bar:CreateTexture(nil, "OVERLAY")
				a[k]:SetTexture(SKILL_EDGE)
			end
			a.l:SetSize(9, 18)
			a.l:SetPoint("LEFT", bar, "LEFT", -2, 0)
			a.l:SetTexCoord(0.007843, 0.043137, 0.193548, 0.774193)
			a.r:SetSize(9, 18)
			a.r:SetPoint("RIGHT", bar, "RIGHT", 3, 0)
			a.r:SetTexCoord(0.043137, 0.007843, 0.193548, 0.774193)
			a.m:SetPoint("TOPLEFT", a.l, "TOPRIGHT")
			a.m:SetPoint("BOTTOMRIGHT", a.r, "BOTTOMLEFT")
			a.m:SetTexCoord(0.113726, 0.1490196, 0.193548, 0.774193)
			bar.__bzBar = a
		end
		if a then for _, t in pairs(a) do t:SetShown(on) end end
		if (bar.__barLook or false) == on then return end
		bar.__barLook = on
		if on then
			bar:SetStatusBarTexture(SKILL)
			bar:SetStatusBarColor(0.25, 0.25, 0.75)
			bar.bg:SetColorTexture(0, 0, 0, 0.6)
		else
			bar:SetStatusBarTexture(WHITE)
			local r, g, b = A.Accent()
			bar:SetStatusBarColor(r, g, b)
			bar.bg:SetColorTexture(0.14, 0.14, 0.16, 0.85)
		end
	end

	-- A light round a frame: its edge in the accent (or r, g, b), breathing.
	function A.GlowAround(frame, on, opts)
		if type(frame) ~= "table" or type(frame.CreateTexture) ~= "function" then return false end
		opts = type(opts) == "table" and opts or {}
		local g = S.glows[frame]
		if not g then
			if on == false then return true end
			g = CreateFrame("Frame", nil, frame)
			g:SetFrameLevel(frame:GetFrameLevel() + 5)
			g.edges = {}
			for i = 1, 4 do g.edges[i] = g:CreateTexture(nil, "OVERLAY") end
			local e = g.edges
			e[1]:SetPoint("TOPLEFT"); e[1]:SetPoint("TOPRIGHT")
			e[2]:SetPoint("BOTTOMLEFT"); e[2]:SetPoint("BOTTOMRIGHT")
			e[3]:SetPoint("TOPLEFT"); e[3]:SetPoint("BOTTOMLEFT")
			e[4]:SetPoint("TOPRIGHT"); e[4]:SetPoint("BOTTOMRIGHT")
			g.anim = g:CreateAnimationGroup()
			g.anim:SetLooping("BOUNCE")
			local a = g.anim:CreateAnimation("Alpha")
			a:SetFromAlpha(1)
			a:SetToAlpha(0.3)
			a:SetDuration(0.9)
			S.glows[frame] = g
		end
		if on == false then
			g.anim:Stop()
			g:Hide()
			return true
		end
		local inset = type(opts.inset) == "number" and opts.inset or 0
		g:ClearAllPoints()
		g:SetPoint("TOPLEFT", inset, -inset)
		g:SetPoint("BOTTOMRIGHT", -inset, inset)
		local r, gg, b = A.Accent()
		if type(opts.r) == "number" and type(opts.g) == "number" and type(opts.b) == "number" then r, gg, b = opts.r, opts.g, opts.b end
		local thick = type(opts.thick) == "number" and opts.thick or 2
		for i, e in ipairs(g.edges) do
			e:SetColorTexture(r, gg, b, 1)
			if i <= 2 then e:SetHeight(thick) else e:SetWidth(thick) end
		end
		g:Show()
		g.anim:Play()
		return true
	end

	function A.GlowStyles() return { { key = "breathe", label = T("Breathe") } } end

	-- Eases a region to an alpha from where it is. A hidden region only gets the alpha.
	function A.Fade(region, toAlpha, speed)
		if type(region) ~= "table" or type(toAlpha) ~= "number" or not region.SetAlpha then return end
		local dur = type(speed) == "number" and speed or A.Speed[speed] or A.Speed.NORMAL
		if dur <= 0 or not region:IsShown() then
			S.fades[region] = nil
			region:SetAlpha(toAlpha)
			return
		end
		S.fades[region] = { from = region:GetAlpha() or 1, to = toAlpha, t = 0, dur = dur }
		if not S.fader then
			S.fader = CreateFrame("Frame")
			S.fader:SetScript("OnUpdate", function(_, elapsed) lib.impl.FadeStep(elapsed) end)
		end
		S.fader:Show()
	end

	function I.FadeStep(elapsed)
		local any = false
		for region, f in pairs(S.fades) do
			f.t = f.t + elapsed
			local p = math.min(1, f.t / f.dur)
			region:SetAlpha(f.from + (f.to - f.from) * p)
			if p >= 1 then S.fades[region] = nil else any = true end
		end
		if not any and S.fader then S.fader:Hide() end
	end

	-- A dropdown under owner (or at the cursor): keys in order, values[key] the shown word.
	-- Its rows as tall as the font needs (never under the game's 20), and its insets: Blizzard
	-- Style's are the game's menu's (MenuStyle1Mixin:GetInset, Blizzard_Menu/Mainline/
	-- MenuTemplates.lua:63-74: 8, 8, 8 and 15 at the foot, where its art's edge is deeper), else 4.
	-- Its width takes its longest word: nothing in it is ever cut.
	local MENU_ROW, MENU_MAX = 20, 14
	local function MenuRow() return math.max(MENU_ROW, math.ceil(SIZES.body + 9)) end
	local function MenuInset()
		if I.Blizzard() then return 8, 8, 8, 15 end
		return 4, 4, 4, 4
	end
	function A.Menu(owner, keys, values, current, onPick, width, opts)
		opts = type(opts) == "table" and opts or {}
		local m = S.menu
		if not m then
			m = CreateFrame("Frame", "GloweyHostMenu", UIParent)
			m:SetFrameStrata("FULLSCREEN_DIALOG")
			m:SetClampedToScreen(true)
			m:EnableMouse(true)
			m:EnableMouseWheel(true)
			A.Skin(m, { bgAlpha = 0.97, kind = "menu" })
			m.rows = {}
			m.catch = CreateFrame("Button", nil, UIParent)
			m.catch:SetAllPoints(UIParent)
			m.catch:SetFrameStrata("FULLSCREEN_DIALOG")
			m.catch:SetFrameLevel(1)
			m.catch:RegisterForClicks("AnyUp")
			m.catch:SetScript("OnClick", function() m:Hide() end)
			m.catch:Hide()
			m:SetScript("OnHide", function() m.catch:Hide() end)
			m:SetScript("OnMouseWheel", function(_, d) lib.impl.MenuScroll(-d) end)
			m:Hide()
			if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, "GloweyHostMenu") end
			S.menu = m
		end
		if m:IsShown() and m.owner == owner then
			m:Hide()
			return
		end
		if type(keys) ~= "table" then return end
		m.owner, m.keys, m.values, m.current, m.onPick, m.top = owner, keys, values or {}, current, onPick, 0
		m.fontOf = type(opts.fontOf) == "function" and opts.fontOf or nil
		local _, it, _, ib = MenuInset()
		m:SetWidth(math.max(width or 0, owner and owner.GetWidth and owner:GetWidth() or 0, 120))
		m:SetHeight(math.min(#keys, MENU_MAX) * MenuRow() + it + ib)
		m:ClearAllPoints()
		if opts.atCursor or not owner then
			local x, y = GetCursorPosition()
			local s = UIParent:GetEffectiveScale()
			m:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / s, y / s)
		else
			m:SetPoint("TOPLEFT", owner, "BOTTOMLEFT", 0, -2)
		end
		m:SetFrameLevel(10)
		m.catch:Show()
		m:Show()
		I.MenuPaint()
	end

	function I.MenuScroll(by)
		local m = S.menu
		if not m or not m.keys then return end
		m.top = math.max(0, math.min(#m.keys - MENU_MAX, m.top + by))
		I.MenuPaint()
	end

	function I.MenuPaint()
		local m = S.menu
		local il, it, ir = MenuInset()
		local rowH = MenuRow()
		local widest = 0
		for i = 1, math.min(#m.keys, MENU_MAX) do
			local row = m.rows[i]
			if not row then
				row = CreateFrame("Button", nil, m)
				row.hi = row:CreateTexture(nil, "BACKGROUND")
				row.hi:SetAllPoints()
				row.hi:SetTexture(WHITE)
				row.text = A.Text(row, "body", "LEFT")
				row.text:SetPoint("LEFT", 6, 0)
				row.text:SetPoint("RIGHT", -6, 0)
				row.text:SetWordWrap(false)
				row:SetScript("OnEnter", function(self) self.hi:SetAlpha(0.18) end)
				row:SetScript("OnLeave", function(self) self.hi:SetAlpha(self.picked and 0.1 or 0) end)
				row:SetScript("OnClick", function(self)
					local mm = S.menu
					local pick, fn = self.key, mm.onPick
					mm:Hide()
					Sound()
					if fn then Safe(fn, pick) end
				end)
				m.rows[i] = row
			end
			row:SetHeight(rowH)
			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", il, -it - (i - 1) * rowH)
			row:SetPoint("TOPRIGHT", -ir, -it - (i - 1) * rowH)
			local key = m.keys[i + m.top]
			row.key = key
			row.picked = key ~= nil and key == m.current
			local word = m.values[key]
			-- (A row may need a font of its own: a language's name in its own letters.)
			local own
			if m.fontOf and key ~= nil then
				local okF, f = pcall(m.fontOf, key)
				own = okF and f or nil
			end
			row.text:SetFont(type(own) == "string" and own or A.Font(), SIZES.body, "")
			row.text:SetText(type(word) == "string" and word or tostring(key))
			widest = math.max(widest, math.ceil(row.text:GetUnboundedStringWidth() or 0))
			Ink(row.text, row.picked and "VALUE" or "TEXT")
			local r, g, b = A.Accent()
			row.hi:SetVertexColor(r, g, b)
			row.hi:SetAlpha(row.picked and 0.1 or 0)
			row:Show()
		end
		for i = math.min(#m.keys, MENU_MAX) + 1, #m.rows do m.rows[i]:Hide() end
		-- (Wider when a word needs it: its 6 each side in the row, and the insets.)
		local need = widest + 12 + il + ir + 2
		if need > (m:GetWidth() or 0) then m:SetWidth(need) end
	end

	-- What only Daylight UI has: not here.
	function A.GetSetting(scope, path) return I.Get(scope, path) end
	function A.IsModuleEnabled() return false end
	function A.TooltipStyle() return nil end
	function A.Media() return nil end
	function A.IsUnlocked() return S.unlocked == true end
	function A.MotionOn() return true end
	function A.On(event, fn, owner) return I.On(event, fn, owner) end
	function A.Off(h) return I.Off(h) end
	function A.For(name) return lib.impl.MakeMe(name) end

	-- ---------------------------------------------------------------------------------------------
	-- me = API.For(addon)
	-- ---------------------------------------------------------------------------------------------

	local M = I.me
	function M.On(owner, event, fn) return I.On(event, fn, owner) end
	function M.Off(_, h) return I.Off(h) end
	function M.RegisterCommand(owner, word, fn, help)
		if type(word) ~= "string" or type(fn) ~= "function" then return false end
		word = word:lower()
		if S.commands[word] then return false end
		S.commands[word] = { fn = fn, help = help, owner = owner }
		if S.loggedIn then I.OwnSlash(word) end
		return true
	end
	function M.RegisterMover(owner, frame, key, label, default)
		return I.AddMover(owner, frame, key, label, default)
	end
	-- Whether a part shows its sample: here, while frames are unlocked (Daylight UI's me.IsPreviewing
	-- also counts its test mode, which this file doesn't have).
	function M.IsPreviewing() return S.unlocked == true end
	for _, name in ipairs({ "RegisterFade", "RegisterTestPart", "RegisterSkin", "AddTooltipLines", "Paint",
		"AttachCraftPane", "Override", "Hook", "AddText", "AddDefaults", "AddOptionsGroup" }) do
		M[name] = function() return false end
	end

	function I.MakeMe(name)
		return setmetatable({ name = name }, { __index = function(t, k)
			if lib.impl.me[k] == nil then return nil end
			local w = function(...) return lib.impl.me[k](name, ...) end
			rawset(t, k, w)
			return w
		end })
	end

	-- ---------------------------------------------------------------------------------------------
	-- Commands
	-- ---------------------------------------------------------------------------------------------

	local taken
	local function Taken(word)
		if not taken then
			taken = {}
			for k, v in pairs(_G) do
				if type(k) == "string" and k:sub(1, 6) == "SLASH_" and type(v) == "string" then taken[v:lower()] = true end
			end
		end
		return taken["/" .. word]
	end

	function I.OwnSlash(word)
		local c = S.commands[word]
		if not c or c.slashed or Taken(word) then return end
		c.slashed = true
		local id = "GLOWEYHOST_" .. word:upper():gsub("[^%w]", "")
		_G["SLASH_" .. id .. "1"] = "/" .. word
		SlashCmdList[id] = function(rest) lib.impl.RunCommand(word, rest) end
		taken["/" .. word] = true
	end

	function I.RunCommand(word, rest)
		local c = S.commands[word]
		if c then Safe(c.fn, rest or "") end
	end

	function I.Slash(msg)
		msg = tostring(msg or "")
		local word, rest = msg:match("^%s*(%S*)%s*(.-)%s*$")
		word = (word or ""):lower()
		if word == "" then return I.OpenOptions() end
		if word == "unlock" or word == "lock" or word == "move" then return I.Unlock(word ~= "lock" and not S.unlocked) end
		if S.commands[word] then return I.RunCommand(word, rest) end
		for _, name in ipairs(S.order) do
			local rec = S.addons[name]
			local short = rec.plugin and rec.plugin.short
			if rec.standalone and type(short) == "string" and short:lower() == word then return I.OpenOptions(name) end
		end
		I.Print("/glowey: " .. T("Open the settings"))
		I.Print("/glowey unlock: " .. T("Move frames"))
		local words = {}
		for w in pairs(S.commands) do words[#words + 1] = w end
		table.sort(words)
		for _, w in ipairs(words) do
			local help = S.commands[w].help
			I.Print("/glowey " .. w .. (type(help) == "string" and (": " .. help) or ""))
		end
	end

	-- ---------------------------------------------------------------------------------------------
	-- Movers
	-- ---------------------------------------------------------------------------------------------

	local function Rel(r)
		if type(r) == "string" then r = _G[r] end
		return type(r) == "table" and r.GetObjectType and r or UIParent
	end

	function I.AddMover(owner, frame, key, label, default)
		if type(frame) ~= "table" or type(frame.SetPoint) ~= "function" or type(key) ~= "string" then return false end
		local id = "plugin." .. tostring(owner) .. "." .. key
		if S.movers[id] then return false end
		local d = type(default) == "table" and default or nil
		if not d then
			local p, rel, rp, x, y = frame:GetPoint(1)
			d = p and { p, rel or UIParent, rp or p, x or 0, y or 0 } or { "CENTER", UIParent, "CENTER", 0, 0 }
		end
		S.movers[id] = { id = id, owner = owner, key = key, frame = frame, label = label or key, default = d }
		S.moverOrder[#S.moverOrder + 1] = id
		I.Place(S.movers[id])
		return true
	end

	local function Saved(mv)
		local rec = Rec(mv.owner)
		return rec and Store(rec).movers[mv.key]
	end

	function I.Place(mv)
		if mv.suspended then return end
		local f = mv.frame
		if InCombatLockdown() and f.IsProtected and f:IsProtected() then
			S.placeLater = true
			return
		end
		local p = Saved(mv) or mv.default
		f:ClearAllPoints()
		f:SetPoint(p[1] or "CENTER", Rel(p[2]), p[3] or p[1] or "CENTER", p[4] or 0, p[5] or 0)
	end

	function I.PlaceAll()
		S.placeLater = nil
		for _, id in ipairs(S.moverOrder) do Safe(I.Place, S.movers[id]) end
	end

	local MV = {}
	S.moverApi = S.moverApi or {}
	function MV.Get(id)
		local mv = S.movers[id]
		return mv and { frame = mv.frame, label = mv.label } or nil
	end
	function MV.Suspend(id, on)
		local mv = S.movers[id]
		if not mv then return false end
		mv.suspended = on and true or nil
		if mv.handle then mv.handle:SetShown(S.unlocked and not mv.suspended) end
		if not on then I.Place(mv) end
		return true
	end
	I.MV = MV

	local function Handle(mv)
		local h = mv.handle
		if h then return h end
		h = CreateFrame("Button", nil, UIParent)
		h:SetFrameStrata("DIALOG")
		A.Skin(h, { bgAlpha = 0.35 })
		I.Lit(h, true)
		h.text = A.Text(h, "small", "CENTER")
		h.text:SetPoint("CENTER")
		h.text:SetText(mv.label)
		Ink(h.text, "VALUE")
		h:RegisterForClicks("RightButtonUp")
		h:RegisterForDrag("LeftButton")
		h:SetScript("OnDragStart", function(self) lib.impl.DragStart(mv, self) end)
		h:SetScript("OnDragStop", function(self) lib.impl.DragStop(mv, self) end)
		h:SetScript("OnClick", function()
			local rec = Rec(mv.owner)
			if rec then Store(rec).movers[mv.key] = nil end
			lib.impl.Place(mv)
			lib.impl.FitHandle(mv)
		end)
		mv.handle = h
		return h
	end

	function I.FitHandle(mv)
		local h, f = mv.handle, mv.frame
		if not h then return end
		h:ClearAllPoints()
		local w, ht = f:GetWidth() or 0, f:GetHeight() or 0
		if w > 8 and ht > 8 then
			h:SetPoint("TOPLEFT", f, "TOPLEFT")
			h:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT")
		else
			h:SetSize(140, 24)
			h:SetPoint("CENTER", f, "CENTER")
		end
	end

	local function Center(f)
		local x, y = f:GetCenter()
		if not x then return 0, 0 end
		return x, y
	end

	function I.DragStart(mv, h)
		local f = mv.frame
		if InCombatLockdown() and f.IsProtected and f:IsProtected() then return end
		local cx, cy = GetCursorPosition()
		local x, y = Center(f)
		h.drag = { cx = cx, cy = cy, x = x, y = y, scale = f:GetEffectiveScale() }
		h:SetScript("OnUpdate", function() lib.impl.DragStep(mv, h) end)
	end

	function I.DragStep(mv, h)
		local d = h.drag
		if not d then return end
		local cx, cy = GetCursorPosition()
		local f = mv.frame
		if InCombatLockdown() and f.IsProtected and f:IsProtected() then return I.DragStop(mv, h) end
		f:ClearAllPoints()
		f:SetPoint("CENTER", UIParent, "BOTTOMLEFT", d.x + (cx - d.cx) / d.scale, d.y + (cy - d.cy) / d.scale)
	end

	function I.DragStop(mv, h)
		h:SetScript("OnUpdate", nil)
		if not h.drag then return end
		h.drag = nil
		local f = mv.frame
		local x, y = Center(f)
		local ratio = f:GetEffectiveScale() / UIParent:GetEffectiveScale()
		local rec = Rec(mv.owner)
		if rec then
			Store(rec).movers[mv.key] = { "CENTER", "UIParent", "BOTTOMLEFT", math.floor(x * ratio + 0.5) / ratio,
				math.floor(y * ratio + 0.5) / ratio }
		end
		I.Place(mv)
	end

	function I.Unlock(on)
		on = on and true or false
		if on and InCombatLockdown() then
			I.Print(T("Frames can't be moved in a fight."))
			return
		end
		S.unlocked = on
		if S.dui then S.dui.Movers.unlocked = on end
		for _, id in ipairs(S.moverOrder) do
			local mv = S.movers[id]
			if on then
				Handle(mv)
				I.FitHandle(mv)
			end
			if mv.handle then mv.handle:SetShown(on and not mv.suspended) end
		end
		if on then I.Print(T("Drag a frame to move it, right-click it to put it back. /glowey lock when done.")) end
		I.Fire("UnlockChanged", on)
		I.Repaint()
	end

	-- ---------------------------------------------------------------------------------------------
	-- The settings window
	-- ---------------------------------------------------------------------------------------------

	local WIN_W, WIN_H, RAIL_W, PAD = 780, 560, 190, 16

	-- The plugins' texts name Daylight UI's command ("/dui unlock"); here it is /glowey.
	local function Words(text)
		if type(text) ~= "string" then return text end
		return (text:gsub("/dui ", "/glowey "))
	end
	I.Words = Words

	local function Value(v, ...)
		if type(v) == "function" then
			local ok, out = pcall(v, ...)
			return ok and out or nil
		end
		return v
	end

	-- The general page: the look every Glowey window shares, and moving frames.
	local GENERAL = { id = "general", groups = {
		{ items = {
			{ type = "text", label = function()
				return T("Daylight UI isn't loaded, so Glowey's plugins run on their own. Their settings are here, and their windows use this look.")
			end },
			-- (With Daylight UI they follow its own Language pick instead: Locales.lua.)
			{ type = "dropdown", label = "Language",
			  values = function()
				local v = {}
				for _, l in ipairs(lib.impl.LANGS) do v[l[1]] = l[2] end
				local mine = v[lib.impl.LangFile(nil)]
				v.auto = mine and T("Automatic (%s)"):format(mine) or T("Automatic")
				return v
			  end,
			  order = function()
				local o = { "auto" }
				for _, l in ipairs(lib.impl.LANGS) do o[#o + 1] = l[1] end
				return o
			  end,
			  fontOf = function(key) return lib.impl.LangFont(key) end,
			  get = function() return S.general.language or "auto" end,
			  set = function(v) lib.impl.SetGeneral("language", v ~= "auto" and v or nil) end,
			  desc = "The language of the plugins' own text. The game's own text, such as spell and item names, stays in your game's language. Shows after a reload." },
			{ type = "dropdown", label = "Look",
			  values = function()
				local v = { glowey = "Glowey", game = T("Blizzard Style") }
				if lib.impl.Polestar() then v.polestar = "Polestar" end
				return v
			  end,
			  order = function()
				local o = { "glowey", "game" }
				if lib.impl.Polestar() then o[3] = "polestar" end
				return o
			  end,
			  get = function() return lib.impl.Look() end, set = function(v) lib.impl.SetGeneral("look", v) end,
			  desc = function()
				local text = T("How every Glowey window looks: Glowey's own, or Blizzard style.")
				if lib.impl.Polestar() then
					text = text .. " " .. T("Polestar: painted by Polestar in the look picked in Polestar's settings, and changes with it.")
				end
				return text
			  end },
			{ type = "color", label = "Accent Color", get = function() return Copy(S.general.accent) end,
			  set = function(v) lib.impl.SetGeneral("accent", v) end,
			  hidden = function() return lib.impl.Look() ~= "glowey" end,
			  desc = "The color of the lit edges, switches and headings." },
			{ type = "slider", label = "Window Opacity", min = 0.3, max = 1, step = 0.05, unit = "%",
			  get = function() return S.general.opacity end, set = function(v) lib.impl.SetGeneral("opacity", v) end,
			  -- (Glowey's own look's: Blizzard Style is opaque as Blizzard's windows are, Polestar's its own.)
			  hidden = function() return lib.impl.Look() ~= "glowey" end,
			  desc = "How solid the windows' backgrounds are." },
			{ type = "toggle", label = "Minimap Icon",
			  get = function() return not S.general.minimap.hide end,
			  set = function(v) S.general.minimap.hide = not v or nil; lib.impl.SetGeneral("minimap", S.general.minimap) end,
			  desc = "A button on the minimap's edge that opens these settings: drag it round the map to move it." },
			{ type = "button", label = "Move Frames", text = "Unlock",
			  textFn = function() return S.unlocked and T("Lock") or T("Unlock") end,
			  func = function() lib.impl.Unlock(not S.unlocked) end,
			  desc = "Shows a handle on each frame the plugins let you move: drag it, or right-click it to put it back. /glowey unlock does the same." },
		} },
	} }

	-- The rail: General, then each plugin running on its own with its pages.
	local function Entries()
		local out = { { kind = "general", label = T("General") } }
		for _, name in ipairs(S.order) do
			local rec = S.addons[name]
			local pages = rec.standalone and rec.module and rec.module.options and rec.module.options.pages
			if type(pages) == "table" and #pages > 0 then
				out[#out + 1] = { kind = "plugin", rec = rec }
				for _, page in ipairs(pages) do
					out[#out + 1] = { kind = "page", rec = rec, page = page, label = Value(page.label) or page.id }
				end
			end
		end
		return out
	end

	local function Title(rec)
		local p = rec.plugin or {}
		if type(p.title) == "string" then return p.title end
		local t = C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(rec.name, "Title") or rec.name
		t = tostring(t):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("%s*%(DaylightUI Plugin%)", "")
		return t
	end
	I.Title = Title

	local function Color(rec)
		local c = rec.plugin and rec.plugin.color
		if type(c) == "table" and type(c[1]) == "number" then return c[1], c[2], c[3] end
		return A.Accent()
	end

	function I.Window()
		local w = S.win
		if w then return w end
		w = CreateFrame("Frame", "GloweyOptions", UIParent)
		S.win = w
		w:SetSize(WIN_W, WIN_H)
		w:SetPoint("CENTER")
		w:SetFrameStrata("HIGH")
		w:SetToplevel(true)
		w:SetClampedToScreen(true)
		w:EnableMouse(true)
		w:SetMovable(true)
		w:RegisterForDrag("LeftButton")
		w:SetScript("OnDragStart", w.StartMoving)
		w:SetScript("OnDragStop", w.StopMovingOrSizing)
		A.Skin(w, { window = true })
		w.title = A.Text(w, "title", "LEFT")
		w.title:SetPoint("TOPLEFT", PAD, -14)
		w.title:SetText(T("Glowey's Plugins"))
		Ink(w.title, "TITLE")
		w.close = A.Close(w, function() w:Hide() end)
		w.close:SetPoint("TOPRIGHT", -12, -14)
		-- Blizzard Style: the name in the title bar, the X up there with it, the heading put away.
		I.Chrome(w, { title = function() return lib.impl.T("Glowey's Plugins") end, close = w.close, hide = { w.title } })
		w.rail = CreateFrame("Frame", nil, w)
		w.rail:SetPoint("TOPLEFT", PAD, -48)
		w.rail:SetPoint("BOTTOMLEFT", PAD, PAD)
		w.rail:SetWidth(RAIL_W)
		w.railButtons = {}
		w.line = w:CreateTexture(nil, "ARTWORK")
		w.line:SetColorTexture(1, 1, 1, 0.08)
		w.line:SetPoint("TOPLEFT", w.rail, "TOPRIGHT", 8, 0)
		w.line:SetPoint("BOTTOMLEFT", w.rail, "BOTTOMRIGHT", 8, 0)
		w.line:SetWidth(1)
		w.scroll = CreateFrame("ScrollFrame", nil, w)
		w.scroll:SetPoint("TOPLEFT", w.rail, "TOPRIGHT", 22, 0)
		w.scroll:SetPoint("BOTTOMRIGHT", -PAD - 8, PAD + 30)
		w.scroll:EnableMouseWheel(true)
		w.body = CreateFrame("Frame", nil, w.scroll)
		w.body:SetSize(WIN_W - RAIL_W - PAD * 2 - 38, 10)
		w.scroll:SetScrollChild(w.body)
		w.scroll:SetScript("OnMouseWheel", function(self, d)
			local max = math.max(0, (w.body:GetHeight() or 0) - (self:GetHeight() or 0))
			self:SetVerticalScroll(math.max(0, math.min(max, self:GetVerticalScroll() - d * 40)))
		end)
		w.thumb = w:CreateTexture(nil, "OVERLAY")
		w.thumb:SetColorTexture(1, 1, 1, 0.18)
		w.thumb:SetWidth(3)
		-- Blizzard Style: insets round the rail and the page (ButtonFrameTemplate's Inset).
		w.railInset = I.Inset(w)
		if w.railInset then
			w.railInset:SetPoint("TOPLEFT", w.rail, "TOPLEFT", -6, 6)
			w.railInset:SetPoint("BOTTOMRIGHT", w.rail, "BOTTOMRIGHT", 6, -6)
		end
		w.pageInset = I.Inset(w)
		if w.pageInset then
			w.pageInset:SetPoint("TOPLEFT", w.scroll, "TOPLEFT", -10, 6)
			w.pageInset:SetPoint("BOTTOMRIGHT", w.scroll, "BOTTOMRIGHT", 16, -6)
		end
		w.scroll:SetScript("OnVerticalScroll", function() lib.impl.Thumb() end)
		w.note = A.Text(w, "small", "LEFT")
		w.note:SetPoint("BOTTOMLEFT", w.scroll, "BOTTOMLEFT", 0, -22)
		Ink(w.note, "WARN")
		w.reload = A.Button(w, T("Reload"), 22)
		w.reload:SetWidth(90)
		w.reload:SetPoint("BOTTOMRIGHT", -PAD, PAD)
		w.reload:SetScript("OnClick", function() ReloadUI() end)
		w.reload:Hide()
		w.pools = {}
		w:SetScript("OnShow", function() lib.impl.Repaint() end)
		w:SetScript("OnHide", function() if S.menu then S.menu:Hide() end end)
		w:Hide()
		if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, "GloweyOptions") end
		return w
	end

	function I.Thumb()
		local w = S.win
		local view, full = w.scroll:GetHeight() or 1, w.body:GetHeight() or 1
		if full <= view + 1 then
			w.thumb:Hide()
			I.ScrollArt(w.thumb, w.scroll, -8.5)
			return
		end
		local h = math.max(24, view * view / full)
		local y = (w.scroll:GetVerticalScroll() or 0) / (full - view) * (view - h)
		w.thumb:ClearAllPoints()
		w.thumb:SetPoint("TOPRIGHT", w.scroll, "TOPRIGHT", 10, -y)
		w.thumb:SetHeight(h)
		w.thumb:Show()
		-- (Blizzard Style: MinimalScrollBar's track and thumb round it, its own color hidden.)
		w.thumb:SetAlpha(I.ScrollArt(w.thumb, w.scroll, -8.5) and 0 or 1)
	end

	-- entries: the rail's (Entries()), when the caller has them already.
	function I.Rail(entries)
		local w = S.win
		local y = 0
		entries = entries or Entries()
		for i, e in ipairs(entries) do
			local b = w.railButtons[i]
			if not b then
				b = CreateFrame("Button", nil, w.rail)
				b:SetHeight(22)
				b.hi = b:CreateTexture(nil, "BACKGROUND")
				b.hi:SetAllPoints()
				b.icon = b:CreateTexture(nil, "ARTWORK")
				b.icon:SetSize(16, 16)
				b.icon:SetPoint("LEFT", 2, 0)
				b.text = A.Text(b, "body", "LEFT")
				b.text:SetWordWrap(false)
				b:SetScript("OnEnter", function(self) if not self.picked and self.pick then self.hi:SetColorTexture(1, 1, 1, 0.06) end end)
				b:SetScript("OnLeave", function(self) if not self.picked then self.hi:SetColorTexture(0, 0, 0, 0) end end)
				b:SetScript("OnClick", function(self)
					if not self.pick then return end
					S.page = self.pick
					w.scroll:SetVerticalScroll(0)
					Sound()
					lib.impl.Repaint()
				end)
				w.railButtons[i] = b
			end
			b:ClearAllPoints()
			b.text:ClearAllPoints()
			b.icon:Hide()
			if e.kind == "plugin" then
				y = y + 10
				local r, g, bb = Color(e.rec)
				local icon = e.rec.plugin and e.rec.plugin.icon
				b.text:SetText(Title(e.rec))
				b.text:SetTextColor(r, g, bb)
				if icon then
					b.icon:SetTexture(icon)
					b.icon:SetVertexColor(r, g, bb)
					b.icon:Show()
					b.text:SetPoint("LEFT", 22, 0)
				else
					b.text:SetPoint("LEFT", 2, 0)
				end
				b.pick = nil
			else
				b.text:SetPoint("LEFT", e.kind == "page" and 22 or 2, 0)
				b.text:SetText(e.label)
				b.pick = e.kind == "general" and "general" or (e.rec.name .. "." .. tostring(e.page.id))
				b.entry = e
			end
			b.text:SetPoint("RIGHT", -4, 0)
			b:SetPoint("TOPLEFT", 0, -y)
			b:SetPoint("TOPRIGHT", 0, -y)
			b.picked = b.pick ~= nil and b.pick == S.page
			local r, g, bb = A.Accent()
			b.hi:SetColorTexture(r, g, bb, b.picked and 0.2 or 0)
			if b.pick then Ink(b.text, b.picked and "VALUE" or "TEXT") end
			b:Show()
			y = y + 22
		end
		for i = #entries + 1, #w.railButtons do w.railButtons[i]:Hide() end
	end

	-- The page picked now: its record (nil for General) and its definition.
	local function Picked(entries)
		if S.page and S.page ~= "general" then
			for _, e in ipairs(entries or Entries()) do
				if e.kind == "page" and (e.rec.name .. "." .. tostring(e.page.id)) == S.page then return e.rec, e.page end
			end
		end
		S.page = "general"
		return nil, GENERAL
	end

	-- Row frames are kept per kind and used again on every paint.
	local function Take(kind, make)
		local w = S.win
		local pool = w.pools[kind]
		if not pool then
			pool = { n = 0 }
			w.pools[kind] = pool
		end
		pool.n = pool.n + 1
		local f = pool[pool.n]
		if not f then
			f = make(w.body)
			pool[pool.n] = f
		end
		f:ClearAllPoints()
		f:Show()
		return f
	end

	local function Wrapped(parent, size)
		local fs = A.Text(parent, size or "small", "LEFT")
		fs:SetWordWrap(true)
		fs:SetNonSpaceWrap(false)
		return fs
	end

	local function Height(fs, width, text)
		fs:SetWidth(width)
		fs:SetText(text or "")
		if not text or text == "" then return 0 end
		return math.ceil(fs:GetStringHeight() or 0)
	end

	local MAKE = {}
	function MAKE.group(p)
		local f = CreateFrame("Frame", nil, p)
		f.head = A.Text(f, "head", "LEFT")
		f.head:SetPoint("TOPLEFT")
		f.desc = Wrapped(f)
		return f
	end
	function MAKE.toggle(p)
		local f = CreateFrame("Frame", nil, p)
		f.switch = A.Switch(f)
		f.switch:SetPoint("TOPLEFT", 0, -1)
		f.label = A.Text(f, "body", "LEFT")
		f.label:SetPoint("TOPLEFT", 44, 0)
		f.desc = Wrapped(f)
		f:EnableMouse(true)
		f:SetScript("OnMouseUp", function(self, button) if button == "LeftButton" and self.switch:IsEnabled() then self.switch:Click() end end)
		return f
	end
	function MAKE.slider(p)
		local f = CreateFrame("Frame", nil, p)
		f.label = A.Text(f, "body", "LEFT")
		f.label:SetPoint("TOPLEFT")
		f.value = A.Text(f, "body", "RIGHT")
		f.value:SetPoint("TOPRIGHT")
		local s = CreateFrame("Slider", nil, f)
		s:SetOrientation("HORIZONTAL")
		s:SetHeight(14)
		s:SetPoint("TOPLEFT", 0, -20)
		s:SetPoint("TOPRIGHT", 0, -20)
		-- (A slider made in code takes no mouse until told to: the game's own templates say so in
		-- their XML, enableMouse="true", Blizzard_SharedXML/Shared/Slider/MinimalSlider.xml:3.
		-- Without it the thumb can't be dragged nor the track clicked.)
		s:EnableMouse(true)
		s:EnableMouseWheel(false)
		-- (Held: the page and a look change wait to be drawn again, I.Repaint and I.StyleSoon. Let
		-- go, each is drawn once.)
		s:SetScript("OnMouseDown", function() S.sliding = true end)
		s:SetScript("OnMouseUp", function()
			S.sliding = nil
			local page = S.repaintWanted
			S.repaintWanted = nil
			if S.styleWanted then lib.impl.StyleNow() end
			if page then lib.impl.RepaintSoon() end
		end)
		s:HookScript("OnHide", function()
			if S.sliding then
				S.sliding = nil
				S.repaintWanted = nil
				-- (A look change made while it was held is still drawn, the next frame.)
				if S.styleWanted then lib.impl.StyleSoon() end
			end
		end)
		s.track = s:CreateTexture(nil, "BACKGROUND")
		s.track:SetColorTexture(0.22, 0.22, 0.25, 1)
		s.track:SetPoint("LEFT")
		s.track:SetPoint("RIGHT")
		s.track:SetHeight(4)
		s:SetThumbTexture(WHITE)
		s.thumb = s:GetThumbTexture()
		s.thumb:SetSize(10, 14)
		if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
		f.slider = s
		f.desc = Wrapped(f)
		return f
	end
	function MAKE.dropdown(p)
		local f = CreateFrame("Frame", nil, p)
		f.label = A.Text(f, "body", "LEFT")
		f.label:SetPoint("TOPLEFT")
		f.button = A.Button(f, "", 22)
		f.button:SetWidth(200)
		f.button:SetPoint("TOPRIGHT")
		f.button.text:SetJustifyH("LEFT")
		f.button.drop = true   -- (Blizzard Style: WowStyle1DropdownTemplate's art, I.DropArt)
		f.desc = Wrapped(f)
		return f
	end
	function MAKE.color(p)
		local f = CreateFrame("Frame", nil, p)
		f.label = A.Text(f, "body", "LEFT")
		f.label:SetPoint("TOPLEFT")
		f.swatch = CreateFrame("Button", nil, f)
		f.swatch:SetSize(44, 18)
		f.swatch:SetPoint("TOPRIGHT")
		A.Skin(f.swatch, { bgAlpha = 1, own = true })
		f.swatch:SetScript("OnEnter", function(self) I.Lit(self, true) end)
		f.swatch:SetScript("OnLeave", function(self) I.Lit(self, false) end)
		f.desc = Wrapped(f)
		return f
	end
	function MAKE.button(p)
		local f = CreateFrame("Frame", nil, p)
		f.label = A.Text(f, "body", "LEFT")
		f.label:SetPoint("TOPLEFT")
		f.button = A.Button(f, "", 22)
		f.desc = Wrapped(f)
		return f
	end
	function MAKE.text(p)
		local f = CreateFrame("Frame", nil, p)
		f.desc = Wrapped(f, "body")
		f.desc:SetPoint("TOPLEFT")
		return f
	end

	local function Unit(v, unit, step)
		if type(v) ~= "number" then return "" end
		if unit == "%" then return ("%d%%"):format(math.floor(v * 100 + 0.5)) end
		local s = (step and step < 1) and ("%.2f"):format(v):gsub("0+$", ""):gsub("%.$", "") or tostring(math.floor(v + 0.5))
		if unit == "px" then return s .. " px" end
		if unit == "x" then return s .. "x" end
		if unit == "s" then return s .. " s" end
		return s
	end

	local function Confirm(text, fn)
		if not StaticPopupDialogs then return fn() end
		StaticPopupDialogs.GLOWEY_HOST_CONFIRM = StaticPopupDialogs.GLOWEY_HOST_CONFIRM or {
			text = "%s", button1 = YES or "Yes", button2 = NO or "No", timeout = 0, whileDead = true,
			hideOnEscape = true, OnAccept = function(_, data) if type(data) == "function" then data() end end,
		}
		StaticPopup_Show("GLOWEY_HOST_CONFIRM", text, nil, fn)
	end

	local function PickColor(cur, set)
		local CP = _G.ColorPickerFrame
		if not CP then return end
		local r, g, b = cur[1] or 1, cur[2] or 1, cur[3] or 1
		local function Now()
			local nr, ng, nb = CP:GetColorRGB()
			set({ nr, ng, nb })
		end
		if CP.SetupColorPickerAndShow then
			CP:SetupColorPickerAndShow({ r = r, g = g, b = b, hasOpacity = false, swatchFunc = Now,
				cancelFunc = function() set({ r, g, b }) end })
		else
			CP.func, CP.hasOpacity = Now, false
			CP.cancelFunc = function() set({ r, g, b }) end
			CP:SetColorRGB(r, g, b)
			CP:Hide()
			CP:Show()
		end
	end

	-- A row that draws itself (MINOR 9), in Daylight UI's call shape for an item of type "custom"
	-- (DaylightUI/Options/Registry.lua:18, :75-76; drawn by Options/Widgets.lua:3590-3601):
	-- build(row) once, into a frame of its own; update(row) at every paint; height(row) for its
	-- height (28 without one, Daylight UI's W.ROW_HEIGHT). The frame belongs to the item, not to a
	-- pool, and stays shown from one paint to the next while its page is up, so a box in it keeps
	-- the keyboard through a repaint (a hidden edit box loses it). The row has row.item, row.page and
	-- an empty row.label, as Daylight UI's has; a build that errors leaves the row out.
	function I.CustomRow(item, ctx, y)
		if type(item.build) ~= "function" then return y end
		local w = S.win
		w.customs = w.customs or setmetatable({}, { __mode = "k" })
		local f = w.customs[item]
		if not f then
			f = CreateFrame("Frame", nil, w.body)
			f.item, f.page = item, ctx.page
			f.label = A.Text(f, "body", "LEFT")
			f.label:SetText("")
			f:SetPoint("TOPLEFT", 0, -y)
			f:SetWidth(ctx.width)
			f:SetHeight(28)
			w.customs[item] = f
			f.built = Safe(item.build, f) and true or false
		end
		if not f.built then
			f:Hide()
			return y
		end
		f.page = ctx.page
		f.paintN = S.paintN
		f:ClearAllPoints()
		f:SetPoint("TOPLEFT", 0, -y)
		f:SetWidth(ctx.width)
		f:SetAlpha(Value(item.disabled, ctx.get) and 0.45 or 1)
		f:Show()
		if type(item.update) == "function" then Safe(item.update, f) end
		local h = 28
		if type(item.height) == "function" then
			local ok, v = pcall(item.height, f)
			if ok and type(v) == "number" and v == v then h = v
			elseif not ok and geterrorhandler then geterrorhandler()(v) end
		end
		h = math.max(1, math.ceil(h))
		f:SetHeight(h)
		return y + h + 14
	end

	-- Paints one row at y (from the top of the body); returns the y under it.
	local function Row(item, ctx, y)
		local width = ctx.width
		local kind = item.type
		if kind == "custom" then return lib.impl.CustomRow(item, ctx, y) end
		local make = MAKE[kind]
		if not make then return y end
		local get, set = ctx.get, ctx.set
		local cur
		if kind ~= "button" and kind ~= "text" then
			if type(item.get) == "function" then
				local ok, v = pcall(item.get)
				cur = ok and v or nil
			elseif item.key then
				cur = get(item.key)
			end
		end
		local function Put(v)
			if type(item.set) == "function" then
				Safe(item.set, v)
				lib.impl.RepaintSoon()
			elseif item.key then
				set(item.key, v)
			end
			if item.reload then S.needReload = true; lib.impl.RepaintSoon() end
		end
		local off = Value(item.disabled, get) and true or false
		local label = Words(T(Value(item.label) or ""))
		local desc = Value(item.desc)
		desc = type(desc) == "string" and Words(T(desc)) or nil
		local f = Take(kind, make)
		f:SetPoint("TOPLEFT", 0, -y)
		f:SetWidth(width)
		f:SetAlpha(off and 0.45 or 1)
		local h
		if kind == "text" then
			h = Height(f.desc, width, label ~= "" and label or desc)
			Ink(f.desc, "TEXT")
		elseif kind == "toggle" then
			f.label:SetText(label)
			Ink(f.label, "VALUE")
			f.switch.SetOn(cur and true or false)
			f.switch:SetEnabled(not off)
			f.switch:SetScript("OnClick", function(self) Put(not self.on) end)
			f.desc:SetPoint("TOPLEFT", 44, -18)
			h = 18 + Height(f.desc, width - 44, desc)
		elseif kind == "slider" then
			f.label:SetText(label)
			Ink(f.label, "VALUE")
			local s = f.slider
			local mn, mx, step = tonumber(Value(item.min)) or 0, tonumber(Value(item.max)) or 1, tonumber(Value(item.step)) or 0.01
			ctx.painting = true
			s:SetScript("OnValueChanged", nil)
			s:SetMinMaxValues(mn, mx)
			s:SetValueStep(step)
			s:SetValue(type(cur) == "number" and cur or mn)
			f.value:SetText(Unit(cur, item.unit, step))
			Ink(f.value, "LABEL")
			local r, g, b = A.Accent()
			s.thumb:SetVertexColor(r, g, b)
			I.SliderArt(s)
			s:SetEnabled(not off)
			s:SetScript("OnValueChanged", function(_, v)
				-- (Painting sets it with no script on: anything that reaches here is the player's.)
				if ctx.painting then return end
				v = math.floor(v / step + 0.5) * step
				f.value:SetText(Unit(v, item.unit, step))
				Put(v)
			end)
			ctx.painting = false
			f.desc:SetPoint("TOPLEFT", 0, -40)
			h = 40 + Height(f.desc, width, desc)
		elseif kind == "dropdown" then
			f.label:SetText(label)
			Ink(f.label, "VALUE")
			local values = Value(item.values) or {}
			local order = Value(item.order)
			if type(order) ~= "table" then
				order = {}
				for k in pairs(values) do order[#order + 1] = k end
				table.sort(order, function(a, b) return tostring(values[a]) < tostring(values[b]) end)
			end
			local font = type(item.fontOf) == "function" and cur ~= nil and Value(item.fontOf, cur) or nil
			font = type(font) == "string" and font or A.Font()
			f.button.text:SetFont(font, SIZES.body, "")
			-- (As wide as its longest choice needs, the arrow's room included, never under 200 nor over
			-- most of the row: no choice is cut, on the button or in its menu. Measured again only when
			-- the choices or the font change: kept per values table, with the choices' words and the
			-- font it was measured in.)
			local words = { font }
			for i, k in ipairs(order) do words[i + 1] = type(values[k]) == "string" and values[k] or tostring(k) end
			local sig = table.concat(words, "\n")
			S.dropWidths = S.dropWidths or setmetatable({}, { __mode = "k" })
			local known = S.dropWidths[values]
			local widest = 0
			if known and known.sig == sig then
				widest = known.widest
			else
				for i = 2, #words do
					f.button.text:SetText(words[i])
					widest = math.max(widest, math.ceil(f.button.text:GetUnboundedStringWidth() or 0))
				end
				S.dropWidths[values] = { sig = sig, widest = widest }
			end
			local bw = math.max(200, math.min(math.floor(width * 0.6), widest + 44))
			f.button:SetWidth(bw)
			f.button:SetText(type(values[cur]) == "string" and values[cur] or (cur ~= nil and tostring(cur) or ""))
			f.button.SetOff(off)
			f.button:SetScript("OnClick", function(self)
				A.Menu(self, order, values, cur, function(key) Put(key) end, bw, { fontOf = item.fontOf })
			end)
			f.desc:SetPoint("TOPLEFT", 0, -20)
			h = math.max(22, 20 + Height(f.desc, width - bw - 10, desc))
		elseif kind == "color" then
			f.label:SetText(label)
			Ink(f.label, "VALUE")
			local c = type(cur) == "table" and cur or { 1, 1, 1 }
			local sk = f.swatch.__gloweySkin
			sk.opts.color = { c[1] or c.r or 1, c[2] or c.g or 1, c[3] or c.b or 1 }
			I.PaintShell(f.swatch)
			f.swatch:SetEnabled(not off)
			f.swatch:SetScript("OnClick", function() PickColor({ c[1] or c.r, c[2] or c.g, c[3] or c.b }, Put) end)
			f.desc:SetPoint("TOPLEFT", 0, -20)
			h = math.max(20, 20 + Height(f.desc, width - 60, desc))
		elseif kind == "button" then
			local text = Value(item.textFn) or Value(item.text)
			text = type(text) == "string" and T(text) or nil
			f.button:ClearAllPoints()
			f.desc:ClearAllPoints()
			if text then
				f.label:SetText(label)
				Ink(f.label, "VALUE")
				f.label:Show()
				f.button:SetText(text)
				f.button.FitWidth(110)
				f.button:SetPoint("TOPRIGHT")
				f.desc:SetPoint("TOPLEFT", 0, -20)
				h = math.max(22, 20 + Height(f.desc, width - f.button:GetWidth() - 12, desc))
			else
				f.label:Hide()
				f.button:SetText(label)
				f.button.FitWidth(150)
				f.button:SetPoint("TOPLEFT")
				f.desc:SetPoint("TOPLEFT", 0, -28)
				h = 28 + Height(f.desc, width, desc)
			end
			f.button.SetOff(off)
			f.button:SetScript("OnClick", function()
				local fn = item.func
				if type(fn) ~= "function" then return end
				local function Go()
					Safe(fn)
					lib.impl.RepaintSoon()
				end
				if item.confirm then Confirm(label .. "?", Go) else Go() end
			end)
		end
		f:SetHeight(math.max(h or 0, 1))
		return y + (h or 0) + 14
	end

	function I.Repaint()
		local w = S.win
		if not w or not w:IsShown() or S.painting then return end
		-- (A slider held: the page is drawn again once it's let go. Drawing it now hides and takes
		-- again the slider under the mouse, which ends the drag after one step.)
		if S.sliding then S.repaintWanted = true return end
		S.painting = true
		local ok, err = pcall(lib.impl.PaintPage)
		S.painting = false
		if not ok and geterrorhandler then geterrorhandler()(err) end
	end

	-- The page drawn again after a change, once a frame however many changes come in it (a color
	-- picker's drag sets a color at every move of the mouse). Opening the window or another page
	-- draws it at once (I.Repaint).
	function I.RepaintSoon()
		local w = S.win
		if not w or not w:IsShown() or S.painting then return end
		if S.sliding then S.repaintWanted = true return end
		if S.repaintPending then return end
		if not (C_Timer and C_Timer.After) then return I.Repaint() end
		S.repaintPending = true
		C_Timer.After(0, function()
			S.repaintPending = nil
			lib.impl.Repaint()
		end)
	end

	function I.PaintPage()
		local w = S.win
		for _, pool in pairs(w.pools) do
			for i = 1, #pool do pool[i]:Hide() end
			pool.n = 0
		end
		-- (The rail's entries, made once for the whole paint.)
		local entries = Entries()
		I.Rail(entries)
		S.paintN = (S.paintN or 0) + 1
		local rec, page = Picked(entries)
		local ctx = { width = w.body:GetWidth(), page = page }
		if rec then
			local scope = rec.name
			ctx.get = function(key) return I.Get(scope, key) end
			ctx.set = function(key, v) I.Set(scope, key, v) end
		else
			ctx.get = function() return nil end
			ctx.set = function() end
		end
		local head = Take("group", MAKE.group)
		head:SetPoint("TOPLEFT", 0, 0)
		head:SetWidth(ctx.width)
		head.head:SetText(rec and (Title(rec) .. " - " .. tostring(Value(page.label) or page.id)) or T("General"))
		head.head:SetFont(A.Font(), SIZES.title, "")
		Ink(head.head, "TITLE")
		local pdesc = Value(page.desc)
		head.desc:SetPoint("TOPLEFT", 0, -26)
		local dh = Height(head.desc, ctx.width, type(pdesc) == "string" and Words(pdesc) or nil)
		Ink(head.desc, "TEXT")
		head:SetHeight(26 + dh)
		local y = 26 + dh + 18
		for _, group in ipairs(page.groups or EMPTY) do
			if not Value(group.hidden, ctx.get) then
				local glabel = Value(group.label)
				if type(glabel) == "string" and glabel ~= "" then
					local g = Take("group", MAKE.group)
					g:SetPoint("TOPLEFT", 0, -y)
					g:SetWidth(ctx.width)
					g.head:SetFont(A.Font(), SIZES.head, "")
					g.head:SetText(T(glabel))
					g.head:SetTextColor(A.Accent())
					local gd = Value(group.desc)
					g.desc:SetPoint("TOPLEFT", 0, -20)
					local gh = Height(g.desc, ctx.width, type(gd) == "string" and Words(T(gd)) or nil)
					Ink(g.desc, "TEXT")
					g:SetHeight(20 + gh)
					y = y + 20 + gh + 10
				end
				for _, item in ipairs(group.items or EMPTY) do
					if type(item) == "table" and not Value(item.hidden, ctx.get) then
						local ok, ny = pcall(Row, item, ctx, y)
						if ok then y = ny elseif geterrorhandler then geterrorhandler()(ny) end
					end
				end
				y = y + 10
			end
		end
		-- (Custom rows not drawn this time: another page's, or hidden now.)
		for _, f in pairs(w.customs or EMPTY) do
			if f.paintN ~= S.paintN then f:Hide() end
		end
		w.body:SetHeight(math.max(y, 10))
		w.note:SetText(S.needReload and T("Some changes take a reload.") or "")
		w.reload:SetShown(S.needReload and true or false)
		I.Thumb()
	end

	-- Opens the window on an addon's page (its first, when pageId is left out), or on General.
	function I.OpenOptions(addon, pageId)
		local w = I.Window()
		local rec = addon and Rec(addon)
		local pages = rec and rec.module and rec.module.options and rec.module.options.pages
		if type(pages) == "table" and pages[1] then
			local id = pages[1].id
			for _, p in ipairs(pages) do if p.id == pageId then id = p.id end end
			S.page = addon .. "." .. tostring(id)
		elseif addon == nil and S.page == nil then
			S.page = "general"
		end
		w.scroll:SetVerticalScroll(0)
		if w:IsShown() then I.Repaint() else w:Show() end
		w:Raise()
	end

	-- A small panel in the game's Options > AddOns that opens the window.
	function I.GameOptions(rec)
		if rec.gamePanel or not rec.module then return end
		local p = CreateFrame("Frame")
		rec.gamePanel = p
		local title = Title(rec)
		p.name = title
		local head = A.Text(p, "title", "LEFT")
		head:SetPoint("TOPLEFT", 16, -16)
		head:SetText(title)
		Ink(head, "TITLE")
		local text = A.Text(p, "body", "LEFT")
		text:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, -10)
		text:SetWidth(560)
		text:SetWordWrap(true)
		text:SetText(T("Its settings are in the Glowey's Plugins window (/glowey)."))
		local open = A.Button(p, T("Open Settings"), 26)
		open:SetWidth(180)
		open:SetPoint("TOPLEFT", text, "BOTTOMLEFT", 0, -14)
		open:SetScript("OnClick", function()
			if _G.SettingsPanel and _G.SettingsPanel:IsShown() and HideUIPanel then HideUIPanel(_G.SettingsPanel) end
			lib.impl.OpenOptions(rec.name)
		end)
		local Settings = _G.Settings
		if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
			local ok, cat = pcall(Settings.RegisterCanvasLayoutCategory, p, title)
			if ok and cat then pcall(Settings.RegisterAddOnCategory, cat) end
		elseif _G.InterfaceOptions_AddCategory then
			pcall(_G.InterfaceOptions_AddCategory, p)
		end
	end

	-- ---------------------------------------------------------------------------------------------
	-- ns.Host: what a plugin asks of whichever host it runs on
	-- ---------------------------------------------------------------------------------------------

	local H = I.host
	-- Daylight UI's options window is open (one fading out counts as closed).
	function H.OptionsShown(host)
		local f = host.standalone and S.win or _G.DaylightUIOptions
		return type(f) == "table" and f.IsShown and f:IsShown() and (f:GetAlpha() or 0) > 0.5 or false
	end
	function H.ToggleOptions(host)
		if host.standalone then
			if H.OptionsShown(host) then S.win:Hide() else I.OpenOptions(host.addon) end
			return
		end
		local cmd = _G.SlashCmdList and _G.SlashCmdList.DAYLIGHTUI
		if type(cmd) == "function" then pcall(cmd, "") end
	end
	-- Opens the options on one of the plugin's pages (its id in the plugin's pages).
	function H.OpenOptions(host, pageId)
		if host.standalone then return I.OpenOptions(host.addon, pageId) end
		local P = _G.DaylightUI and _G.DaylightUI.OptionsPanel
		if pageId and type(P) == "table" and type(P.Show) == "function" then
			if pcall(P.Show, host.addon .. "." .. pageId) then return end
		end
		if not H.OptionsShown(host) then H.ToggleOptions(host) end
	end
	-- Whether an options page may hold an item of type "custom" (MINOR 9): always here; with
	-- Daylight UI from 2.2.5, whose registry takes one (Options/Registry.lua:47, :75-76) and whose
	-- Widgets draw it (Options/Widgets.lua:3590). It is not in its API.md, so a page asks first and
	-- keeps rows of the documented kinds for the rest.
	function H.CustomRows(host)
		if host.standalone then return true end
		local W = I.Kit("Widgets")
		return I.KitFn(W, "custom") ~= nil and I.KitFn(I.Kit("Options"), "Validate") ~= nil
	end
	-- Draws the open options page again, after a change a row's own code saved (a custom row's):
	-- the settings window here, else Daylight UI's (its OptionsPanel.Refresh, Options/Panel.lua:656,
	-- which runs every row's update and lays the page out again). Nothing when it is closed.
	function H.RefreshOptions(host)
		if host.standalone then return I.RepaintSoon() end
		local P = I.Kit("OptionsPanel")
		if I.KitFn(P, "IsShown") and I.KitFn(P, "Refresh") then
			pcall(function() if P.IsShown() then P.Refresh() end end)
		end
	end
	-- How a player types one of the plugin's commands ("/dui kos" or "/glowey kos").
	function H.Command(host, word)
		return (host.standalone and "/glowey " or "/dui ") .. tostring(word or "")
	end
	-- A text naming Daylight UI's command ("/dui unlock"), as the player types it here.
	function H.Words(host, text)
		if host.standalone then return I.Words(text) end
		return text
	end
	function H.Unlocked(host)
		if host.standalone then return S.unlocked == true end
		local api = _G.DaylightUI and _G.DaylightUI.API
		return type(api) == "table" and type(api.IsUnlocked) == "function" and api.IsUnlocked() == true or false
	end
	-- Frames unlocked to move, or locked again (a page's "Move Window"): Daylight UI's own unlock
	-- with it (its Movers.Unlock / Lock, the ones /dui unlock and /dui lock run: Movers.lua:1810-1841,
	-- asked carefully), this file's without it. True when it was done.
	function H.SetUnlocked(host, on)
		if host.standalone then
			I.Unlock(on and true or false)
			return true
		end
		local movers = I.Kit("Movers")
		local fn = I.KitFn(movers, on and "Unlock" or "Lock")
		if not fn then return false end
		local ok = pcall(fn)
		return ok
	end

	-- ---------------------------------------------------------------------------------------------
	-- Daylight UI's own table while it runs, its API (else this file's), and its version
	-- ---------------------------------------------------------------------------------------------

	local function Dui()
		local D = rawget(_G, "DaylightUI")
		local api = type(D) == "table" and D.API
		if type(api) == "table" and api.major == 1 then return D end
		return nil
	end
	I.Dui = Dui
	function I.Api()
		local D = Dui()
		return D and D.API or lib.API
	end

	-- Its version from its .toc, as numbers ({ 2, 2, 5 }); false for a copy from source (no numbers),
	-- which counts as the newest.
	function I.DuiAtLeast(want)
		if not Dui() then return false end
		if S.duiVersion == nil then
			local get = C_AddOns and C_AddOns.GetAddOnMetadata
			local ok, v = false, nil
			if type(get) == "function" then ok, v = pcall(get, "DaylightUI", "Version") end
			local parts = {}
			if ok and type(v) == "string" then for n in v:gmatch("%d+") do parts[#parts + 1] = tonumber(n) end end
			S.duiVersion = #parts > 0 and parts or false
		end
		local have = S.duiVersion
		if not have then return true end
		for i = 1, #want do
			local h = have[i] or 0
			if h ~= want[i] then return h > want[i] end
		end
		return true
	end

	-- One of Daylight UI's inside parts (not in its API.md): only from the version these calls were
	-- read in (2.2.5), only a table, and every call through it is checked and pcall'd.
	local KNOWN = { 2, 2, 5 }
	function I.Kit(name)
		local D = Dui()
		if not D or not I.DuiAtLeast(KNOWN) then return nil end
		local t = rawget(D, name)
		return type(t) == "table" and t or nil
	end
	local function KitFn(t, name)
		local fn = type(t) == "table" and t[name]
		return type(fn) == "function" and fn or nil
	end
	I.KitFn = KitFn

	-- ---------------------------------------------------------------------------------------------
	-- Colors that follow the look: inks, tints and shells drawn again on StyleChanged
	-- ---------------------------------------------------------------------------------------------

	-- A role's color: an ink of API.Colors() (TITLE, VALUE, TEXT, LABEL, OFF, GOOD, WARN, BAD,
	-- DAMAGE, MONEY: DaylightUI/API.lua:1066-1074), or "pop" for the accent (API.Accent()).
	function I.RoleColor(role, colors)
		local api = I.Api()
		if role == "pop" then return api.Accent() end
		-- (Without Daylight UI and with no colors given: the one ink straight, as API.Colors() would
		-- have it, with no table of them all made for it.)
		if colors == nil and api == lib.API then
			local c = I.InkOf(INK[role] and role or "TEXT")
			return c[1] or 1, c[2] or 1, c[3] or 1
		end
		colors = colors or api.Colors()
		local c = type(colors) == "table" and (colors[role] or colors.TEXT)
		if type(c) == "table" then return c[1] or 1, c[2] or 1, c[3] or 1 end
		return 1, 1, 1
	end

	function I.PaintInk(region, e, colors)
		local r, g, b = I.RoleColor(e.role, colors)
		local a = e.alpha or 1
		if e.how == "text" then region:SetTextColor(r, g, b, a)
		elseif e.how == "vertex" then region:SetVertexColor(r, g, b, a)
		else region:SetColorTexture(r, g, b, a) end
	end

	-- Listens for a look change once (Daylight UI's StyleChanged, or this file's own).
	function I.HookStyle()
		if S.styleHooked then return end
		S.styleHooked = true
		local D = Dui()
		if D then
			pcall(D.API.On, "StyleChanged", function() lib.impl.Restyle() end, "GloweyHost")
			-- (The profile's look is on from its Login: what was painted as the files loaded, again.)
			pcall(D.API.On, "Login", function() lib.impl.Restyle() end, "GloweyHost")
		else
			I.On("StyleChanged", function() lib.impl.Restyle() end, "GloweyHost")
		end
	end

	-- API.Colors() for this file's own reading (Restyle, tooltips). Without Daylight UI, one table
	-- kept until the look changes (SetGeneral, PolestarChanged, Restyle): never handed to a plugin
	-- (API.Colors() still makes each caller a table of its own), never changed.
	function I.ColorsNow()
		local api = I.Api()
		if api ~= lib.API then return api.Colors() end
		if not S.colors then S.colors = A.Colors() end
		return S.colors
	end

	function I.Restyle()
		local api = I.Api()
		S.colors = nil
		local okC, colors = pcall(I.ColorsNow)
		colors = okC and colors or nil
		for region, e in pairs(S.inks) do pcall(I.PaintInk, region, e, colors) end
		for frame, opts in pairs(S.skinned) do pcall(api.Skin, frame, opts) end
		for _, fn in ipairs(S.restylers) do Safe(fn) end
		I.RescaleAll()
	end

	-- (A region tracked again keeps its entry: a plugin may ink the same text at every update.)
	local function Track(region, role, alpha, how)
		if type(region) ~= "table" then return end
		local e = S.inks[region]
		if e then
			e.role, e.alpha, e.how = role, alpha, how
		else
			e = { role = role, alpha = alpha, how = how }
			S.inks[region] = e
		end
		I.HookStyle()
		pcall(I.PaintInk, region, e)
	end

	-- A font string in a role's color, now and after every look change.
	function H.Ink(_, fs, role, alpha)
		if type(fs) ~= "table" or type(fs.SetTextColor) ~= "function" then return end
		Track(fs, role or "TEXT", alpha, "text")
	end
	-- A texture in a role's color (SetColorTexture; vertex = true: SetVertexColor, for a texture
	-- with art of its own), now and after every look change.
	function H.Tint(_, tex, role, alpha, vertex)
		if type(tex) ~= "table" or type(tex.SetVertexColor) ~= "function" then return end
		Track(tex, role or "TEXT", alpha, vertex and "vertex" or "color")
	end
	-- Stops following the look (the region's color is the caller's again).
	function H.Untrack(_, region) if region then S.inks[region] = nil end end
	-- A shell (API.Skin), drawn again after every look change.
	function H.Skin(_, frame, opts)
		if type(frame) ~= "table" then return nil end
		S.skinned[frame] = opts or {}
		I.HookStyle()
		local ok, shell = pcall(I.Api().Skin, frame, opts)
		return ok and shell or nil
	end
	-- fn() after every look change (colors a plugin works out itself).
	function H.OnStyle(_, fn)
		if type(fn) ~= "function" then return end
		S.restylers[#S.restylers + 1] = fn
		I.HookStyle()
	end
	-- Blizzard Style (MINOR 6): what a plugin asks for its own windows. Without Daylight UI only (its
	-- own look applies with it): each answers false or nil then, and draws nothing.
	--   Host.Blizzard()                       true while the windows are in Blizzard Style
	--   Host.Chrome(frame, opts)              a titled window (I.Chrome: title, close, hide, ground)
	--   Host.Retitle(frame)                   its title asked for again
	--   Host.Dress(button, kind, hide, size)  one of Blizzard's buttons (close, minimize, maximize,
	--                                         prev, next), the button's own regions (hide) put away
	--   Host.Tab(button, selected, hide)      a top tab's art; true while drawn
	--   Host.Inset(parent, ground)            an inset frame (the caller places it), or nil
	--   Host.ScrollArt(thumb, along, x)       the minimal scroll bar round a window's own thumb
	--   Host.Atlas(texture, atlas, useSize)   an atlas the client has, put on a texture
	--   Host.Looked(owner, fn)                fn() again whenever the look changes
	--   Host.Outset(frame)                    left, right, top, bottom: how far a titled window's
	--                                         Blizzard Style frame reaches past its edges (0s when not drawn)
	function H.Blizzard(host) return host.standalone and I.Blizzard() or false end
	function H.Chrome(host, frame, opts)
		if not host.standalone then return false end
		return I.Chrome(frame, opts)
	end
	function H.Outset(host, frame)
		if host.standalone and type(frame) == "table" and S.chrome[frame] and I.Blizzard() then
			local s = frame.__gloweySkin
			if not (s and s.hidden) then return I.BZ.left, I.BZ.right, I.BZ.top, I.BZ.bottom end
		end
		return 0, 0, 0, 0
	end
	function H.Retitle(host, frame)
		if host.standalone and type(frame) == "table" and S.chrome[frame] then I.ChromeTitle(frame) end
	end
	function H.Dress(host, b, kind, hide, size)
		if not host.standalone or type(b) ~= "table" or type(I.BZ[kind]) ~= "table" then return false end
		S.looked[b] = function() lib.impl.Dress(b, kind, hide, size) end
		return I.Dress(b, kind, hide, size)
	end
	function H.Tab(host, b, selected, hide)
		if not host.standalone or type(b) ~= "table" then return false end
		b.__bzSel = selected and true or false
		S.looked[b] = function() lib.impl.Tab(b, b.__bzSel, hide) end
		return I.Tab(b, selected, hide)
	end
	function H.Inset(host, parent, ground)
		if not host.standalone then return nil end
		return I.Inset(parent, ground)
	end
	function H.ScrollArt(host, thumb, along, x, ctl)
		if not host.standalone or type(thumb) ~= "table" then return false end
		return I.ScrollArt(thumb, along, x, ctl)
	end
	function H.Atlas(host, tex, atlas, useSize)
		if not host.standalone or type(tex) ~= "table" then return false end
		return I.Atlas(tex, atlas, useSize)
	end
	function H.Looked(host, owner, fn)
		if host.standalone and type(owner) == "table" and type(fn) == "function" then S.looked[owner] = fn end
	end

	-- A role's color now: r, g, b; and as a "|cff......" color code.
	function H.Color(_, role) return I.RoleColor(role) end
	function H.Hex(_, role)
		local r, g, b = I.RoleColor(role)
		return string.format("|cff%02x%02x%02x", math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
	end

	-- ---------------------------------------------------------------------------------------------
	-- Hover tooltips in the look's roles: the title in TITLE, the text in TEXT, a click hint in the
	-- accent (as Daylight UI's own hover tips, DaylightUI/Tips.lua:1-15)
	-- ---------------------------------------------------------------------------------------------

	-- text: a string or a list of them (each its own wrapped line).
	function H.Tip(host, owner, title, text, hint, anchor)
		return H.TipLines(host, owner, function(t)
			if title then t.Line(title, "TITLE") end
			if type(text) == "table" then
				for _, line in ipairs(text) do t.Line(line, "TEXT", true) end
			elseif text then
				t.Line(text, "TEXT", true)
			end
			if hint then t.Line(hint, "pop", true) end
		end, anchor)
	end

	-- fn(t): t.Line(text, role, wrap), t.Double(left, right, leftRole, rightRole), t.Blank().
	function H.TipLines(_, owner, fn, anchor)
		local tip = GameTooltip
		if not tip or type(owner) ~= "table" or type(fn) ~= "function" then return end
		tip:SetOwner(owner, anchor or "ANCHOR_RIGHT")
		local okC, colors = pcall(I.ColorsNow)
		colors = okC and colors or nil
		local t = {}
		function t.Line(text, role, wrap)
			local r, g, b = I.RoleColor(role or "TEXT", colors)
			tip:AddLine(tostring(text or ""), r, g, b, wrap and true or false)
		end
		function t.Double(left, right, lrole, rrole)
			local r, g, b = I.RoleColor(lrole or "LABEL", colors)
			local r2, g2, b2 = I.RoleColor(rrole or "VALUE", colors)
			tip:AddDoubleLine(tostring(left or ""), tostring(right or ""), r, g, b, r2, g2, b2)
		end
		function t.Blank() tip:AddLine(" ") end
		Safe(fn, t)
		tip:Show()
	end

	-- ---------------------------------------------------------------------------------------------
	-- Daylight UI's global scale (general.scale, DaylightUI/DB.lua:43) on a free-floating window.
	-- A window docked to another frame takes that frame's scale already: never this factor too.
	-- ---------------------------------------------------------------------------------------------

	function I.GlobalScale()
		local D = Dui()
		if not D then return 1 end
		local ok, v = pcall(D.API.GetSetting, "general", "scale")
		return ok and type(v) == "number" and v > 0 and v or 1
	end

	function H.Scale(_, own) return (tonumber(own) or 1) * I.GlobalScale() end

	-- opts.own: the window's own scale (a number, or a function asked each time); opts.docked():
	-- true while it sits on another frame.
	function H.Scaled(_, frame, opts)
		if type(frame) ~= "table" or type(frame.SetScale) ~= "function" then return end
		S.scaled[frame] = type(opts) == "table" and opts or {}
		I.HookStyle()
		I.ApplyScale(frame)
	end
	-- The window's scale set again (its own size setting changed, or it docked or undocked).
	function H.Rescale(_, frame) I.ApplyScale(frame) end

	function I.ApplyScale(frame)
		local o = S.scaled[frame]
		if not o then return end
		local own = o.own
		if type(own) == "function" then
			local ok, v = pcall(own)
			own = ok and v or 1
		end
		own = tonumber(own) or 1
		local docked = o.docked
		if type(docked) == "function" then
			local ok, v = pcall(docked)
			docked = ok and v
		end
		local s = docked and own or own * I.GlobalScale()
		if InCombatLockdown() and frame.IsProtected and frame:IsProtected() then
			S.scaleLater = true
			return
		end
		if math.abs((frame:GetScale() or 1) - s) > 0.001 then frame:SetScale(s) end
	end

	function I.RescaleAll()
		S.scaleLater = nil
		for frame in pairs(S.scaled) do pcall(I.ApplyScale, frame) end
	end

	-- ---------------------------------------------------------------------------------------------
	-- Sounds: Daylight UI's (its per-kind soft / game / none choice, DaylightUI/Sound.lua:131-180), or
	-- the game's own kits for the same moments (its Sound.GAME_KIT, :44-46: the game's window sounds)
	-- ---------------------------------------------------------------------------------------------

	local GAME_SOUND = { open = "IG_CHARACTER_INFO_OPEN", close = "IG_CHARACTER_INFO_CLOSE",
		click = "IG_MAINMENU_OPTION", toggle = "IG_MAINMENU_OPTION_CHECKBOX_ON" }

	function I.Sound(name)
		local play = KitFn(I.Kit("Sound"), "Play")
		if play and pcall(play, name) then return end
		local kit = type(SOUNDKIT) == "table" and SOUNDKIT[GAME_SOUND[name] or ""]
		if type(kit) == "number" and PlaySound then pcall(PlaySound, kit) end
	end
	function H.Sound(_, name) I.Sound(name) end

	-- Alert sounds, for a moment in a fight. Saved as Daylight UI saves its own (DaylightUI/Sound.lua:
	-- 228-236): "none", "kit:<sound kit>", "file:<file id>", "dui:<name>", "lsm:<name>". With Daylight
	-- UI, its list (its own pickers' list, shared media included); without it, the game's own kits
	-- (Blizzard_SharedXML/Mainline/SoundKitConstants.lua).
	local GAME_ALERTS = { { "RAID_WARNING", "Raid Warning" }, { "READY_CHECK", "Ready Check" },
		{ "ALARM_CLOCK_WARNING_3", "Alarm" }, { "UI_RAID_BOSS_WHISPER_WARNING", "Boss Whisper" },
		{ "RAID_BOSS_EMOTE_WARNING", "Boss Emote" }, { "TELL_MESSAGE", "Whisper" }, { "MAP_PING", "Map Ping" } }

	-- values, order, titles (headings: keys to show as a heading, not a choice).
	function H.AlertChoices()
		local choices = KitFn(I.Kit("Sound"), "AlertChoices")
		if choices then
			local ok, values, order, titles = pcall(choices)
			if ok and type(values) == "table" and type(order) == "table" then return values, order, titles or {} end
		end
		local values, order = { none = T("None") }, { "none" }
		for _, a in ipairs(GAME_ALERTS) do
			local kit = type(SOUNDKIT) == "table" and SOUNDKIT[a[1]]
			if type(kit) == "number" then
				local key = "kit:" .. kit
				values[key] = T(a[2])
				order[#order + 1] = key
			end
		end
		return values, order, {}
	end
	-- The game's raid warning, as a key (the alert a plugin played before it had a choice).
	function H.DefaultAlert()
		local kit = type(SOUNDKIT) == "table" and SOUNDKIT.RAID_WARNING or 8959
		return "kit:" .. kit
	end

	function H.PlayAlert(host, key)
		if type(key) ~= "string" or key == "none" then return end
		local alert = KitFn(I.Kit("Sound"), "Alert")
		if alert and pcall(alert, key) then return end
		local kind, what = key:match("^(%a+):(.+)$")
		local n = tonumber(what)
		if kind == "kit" and n and PlaySound then
			pcall(PlaySound, n)
		elseif kind == "file" and n and PlaySoundFile then
			pcall(PlaySoundFile, n, "Master")
		elseif key ~= H.DefaultAlert(host) then
			-- (Daylight UI's own or a shared one, picked with it and played without it: the raid warning.)
			H.PlayAlert(host, H.DefaultAlert(host))
		end
	end

	-- ---------------------------------------------------------------------------------------------
	-- Windows: Escape, the open and close sounds, a fade, the controller, and Daylight UI's window
	-- room (other windows slide aside for one that opens, DaylightUI/Windows/Room.lua:1-6)
	--   Host.Window(frame, opts)   once per frame; opts: rise (px lifted as it appears), ownEscape
	--                              (the window takes Escape itself), close() (what Escape and B do:
	--                              Host.Close when left out), room (true, or a function: true while
	--                              the window floats free; a docked one never takes part)
	--   Host.Open(frame), Host.Close(frame), Host.Shown(frame) (shown and not closing: for toggles),
	--   Host.Moved(frame) (after a drag: the new spot is home)
	-- Three ways, picked once per frame:
	--   room    Daylight UI 2.2.5+ with Win.Feel and Win.Room, and opts.room given: Feel.Open /
	--           Feel.Close (DaylightUI/Windows/Feel.lua:229-266) with frame.room set, as its own
	--           windows (Win.Open / Win.Close, Windows/Frame.lua:839-852); the sounds, Escape and
	--           the controller from here.
	--   motion  Daylight UI 2.2.5+ with Motion.Window (DaylightUI/Motion.lua:203-238): its appear,
	--           vanish, sounds and controller; Escape from here when close() is given.
	--   own     the rest, and without Daylight UI: Escape, the game's window sounds and a fade.
	-- Escape: a hidden stand-in frame named in UISpecialFrames, shown while the window is. The
	-- game's CloseSpecialWindows hides each frame named there (Blizzard_UIParentPanelManager/Shared/
	-- UIParentPanelManager.lua:1106-1116), and the stand-in's OnHide closes the window.
	-- The controller: Daylight UI's Pad.Follow hooks its frame on every call (DaylightUI/Pad.lua:
	-- 1093-1104), so a frame is only ever followed once: frame.__gloweyFollowed, which Guide.lua's
	-- ns.Pad checks and sets too.
	-- ---------------------------------------------------------------------------------------------

	function I.RoomKit()
		local W = I.Kit("Win")
		local F, R = W and W.Feel, W and W.Room
		if KitFn(F, "Open") and KitFn(F, "Close") and KitFn(F, "IsOpen") and KitFn(F, "Slide") and KitFn(F, "OffsetX")
			and KitFn(R, "Closed") and KitFn(R, "Changed") then return F, R end
		return nil
	end

	local function RoomOn(o)
		local room = o and o.room
		if type(room) == "function" then
			local ok, v = pcall(room)
			return ok and v and true or false
		end
		return room == true
	end

	function I.Wire(frame, opts)
		if type(frame) ~= "table" or type(frame.HookScript) ~= "function" then return false end
		opts = type(opts) == "table" and opts or {}
		if S.wins[frame] then
			S.wins[frame] = opts
			return true
		end
		S.wins[frame] = opts
		local motion = I.Kit("Motion")
		local mode = "own"
		if opts.room ~= nil and I.RoomKit() then
			mode = "room"
		elseif not frame.__gloweyFollowed and KitFn(motion, "Window") and KitFn(motion, "Vanish") and KitFn(motion, "Shown") then
			mode = "motion"
		end
		frame.__gloweyWin = mode
		if mode == "motion" then
			-- (Its own Escape only without close(): ours calls close() first.)
			local own = opts.ownEscape or opts.close ~= nil
			if pcall(motion.Window, frame, opts.rise, own) then
				frame.__gloweyFollowed = true
				-- (B on a controller does what Escape does.)
				if opts.close then
					frame.SmartNavigationCloseHandler = function() lib.impl.Escape(frame) return true end
				end
			else
				mode = "own"
				frame.__gloweyWin = mode
			end
		end
		if not opts.ownEscape and (mode ~= "motion" or opts.close) then
			S.escN = (S.escN or 0) + 1
			local name = "GloweyHostEscape" .. S.escN
			local esc = CreateFrame("Frame", name, UIParent)
			esc:SetSize(1, 1)
			esc:EnableMouse(false)
			esc:Hide()
			esc:SetScript("OnHide", function(self)
				if self.quiet then self.quiet = nil return end
				-- (Hidden along with UIParent, Alt+Z, it still says it's shown: that isn't Escape.)
				if not self:IsShown() then lib.impl.Escape(frame) end
			end)
			frame.__gloweyEsc = esc
			if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, name) end
			if frame:IsShown() then esc:Show() end
		end
		if mode ~= "motion" and not frame.__gloweyFollowed then
			local follow = KitFn(I.Kit("Pad"), "Follow")
			if follow and pcall(follow, frame, function() lib.impl.Escape(frame) end) then frame.__gloweyFollowed = true end
		end
		frame:HookScript("OnShow", function(self) lib.impl.WinShown(self) end)
		frame:HookScript("OnHide", function(self) lib.impl.WinHidden(self) end)
		return true
	end

	function I.Escape(frame)
		local o = S.wins[frame]
		if o and type(o.close) == "function" then
			Safe(o.close)
			-- (A close() that left the window up: the stand-in shows again, for the next Escape.)
			local esc = frame.__gloweyEsc
			if esc and frame:IsShown() and not esc:IsShown() then esc:Show() end
		else
			I.Close(frame)
		end
	end

	function I.WinShown(frame)
		local o = S.wins[frame]
		if not o then return end
		if frame.__gloweyEsc then frame.__gloweyEsc:Show() end
		local mode = frame.__gloweyWin
		if mode == "motion" then return end   -- (its own hooks: the sound, the appear)
		if frame.__gloweyOpening then return end   -- (Host.Open drives it)
		I.Sound("open")
		if mode == "room" then
			local F = I.RoomKit()
			frame.room = RoomOn(o) or nil
			frame:SetAlpha(0)
			if not (F and pcall(F.Open, frame)) then frame:SetAlpha(1) end
			return
		end
		local api = I.Api()
		if type(api.MotionOn) == "function" and api.MotionOn() == false then return end
		frame:SetAlpha(0)
		if not pcall(api.Fade, frame, 1, "FAST") then frame:SetAlpha(1) end
	end

	function I.WinHidden(frame)
		local o = S.wins[frame]
		if not o then return end
		-- (Hidden along with its parent, it still says it's shown: the controller is told all the
		-- same, nothing else changes.)
		if frame:IsShown() then
			if frame.__gloweyFollowed then
				local leaving = KitFn(I.Kit("Pad"), "Leaving")
				if leaving then pcall(leaving, frame) end
			end
			return
		end
		local esc = frame.__gloweyEsc
		if esc and esc:IsShown() then
			esc.quiet = true
			esc:Hide()
		end
		local mode = frame.__gloweyWin
		if mode ~= "motion" and not frame.__gloweySounded then I.Sound("close") end
		frame.__gloweySounded = nil
		if mode == "room" then
			local F, R = I.RoomKit()
			if R then pcall(R.Closed, frame) end
			-- (Hidden straight away while slid aside: home again for the next time it opens.)
			local ok, dx = false, 0
			if F then ok, dx = pcall(F.OffsetX, frame) end
			if ok and type(dx) == "number" and dx ~= 0 then pcall(F.Slide, frame, 0) end
		end
	end

	function I.Open(frame)
		if type(frame) ~= "table" then return end
		if frame.__gloweyWin == "room" then
			if I.Shown(frame) then return end
			local F = I.RoomKit()
			frame.room = RoomOn(S.wins[frame]) or nil
			frame.__gloweyOpening = true
			I.Sound("open")
			local ok = F and pcall(F.Open, frame)
			frame.__gloweyOpening = nil
			if not ok then
				frame:SetAlpha(1)
				frame:Show()
			end
			if frame.__gloweyEsc and frame:IsShown() then frame.__gloweyEsc:Show() end
			return
		end
		frame:Show()
	end

	function I.Close(frame)
		if type(frame) ~= "table" or not frame:IsShown() then return end
		local mode = frame.__gloweyWin
		if mode == "room" then
			local F = I.RoomKit()
			if not I.Shown(frame) then return end   -- (closing already)
			I.Sound("close")
			frame.__gloweySounded = true
			local esc = frame.__gloweyEsc
			if esc and esc:IsShown() then
				esc.quiet = true
				esc:Hide()
			end
			if F and pcall(F.Close, frame) then return end
			return frame:Hide()
		elseif mode == "motion" then
			local vanish = KitFn(I.Kit("Motion"), "Vanish")
			if vanish and pcall(vanish, frame) then return end
		end
		frame:Hide()
	end

	function I.Shown(frame)
		if type(frame) ~= "table" or not frame:IsShown() then return false end
		local mode = frame.__gloweyWin
		if mode == "room" then
			local F = I.RoomKit()
			local ok, open = false, true
			if F then ok, open = pcall(F.IsOpen, frame) end
			return not ok or open and true or false
		elseif mode == "motion" then
			local shown = KitFn(I.Kit("Motion"), "Shown")
			local ok, v = false, true
			if shown then ok, v = pcall(shown, frame) end
			return not ok or v and true or false
		end
		return true
	end

	function H.Window(_, frame, opts) return I.Wire(frame, opts) end
	function H.Open(_, frame) return I.Open(frame) end
	function H.Close(_, frame) return I.Close(frame) end
	function H.Shown(_, frame) return I.Shown(frame) end
	-- After the window was dragged (its new spot is home, and the others make room again), or after
	-- it docked or undocked: opts.room is asked again, and a window docked now leaves the room (back
	-- home, never slid while it sits on another frame).
	function H.Moved(_, frame)
		if type(frame) ~= "table" or frame.__gloweyWin ~= "room" then return end
		local F, R = I.RoomKit()
		if not R then return end
		local on = RoomOn(S.wins[frame])
		if on then
			frame.room = true
			pcall(R.Changed, frame)
		elseif frame.room then
			frame.room = nil
			pcall(R.Closed, frame)
			local ok, dx = pcall(F.OffsetX, frame)
			if ok and type(dx) == "number" and dx ~= 0 then pcall(F.Slide, frame, 0) end
		end
	end

	-- ---------------------------------------------------------------------------------------------
	-- A window's saved spot, kept in the plugin's settings under "spots.<key>": with Daylight UI in
	-- its module settings, so in the player's profile (DaylightUI/API.md:582-583), as its own windows'
	-- spots are; without it in <Addon>Settings. The plugin's defaults need a spots = {} table (this
	-- file copies only the settings its defaults name).
	--   Host.Spot(key, legacy) -> s: s.Get() the saved table or nil, s.Save(t), s.Reset()
	--   legacy = { get = function() return <the old saved table or nil> end, clear = function() end }:
	--   a spot saved the old way is moved in once (and cleared there) the first time it's asked for.
	-- ---------------------------------------------------------------------------------------------

	function H.Spot(host, key, legacy)
		local addon, path = host.addon, "spots." .. tostring(key)
		local function Read()
			if host.standalone then return I.Get(addon, path) end
			local D = Dui()
			if not D then return nil end
			local ok, v = pcall(D.Get, D, addon, path)
			return ok and v or nil
		end
		local function Write(v)
			if host.standalone then return I.Set(addon, path, v) end
			local D = Dui()
			if not D then return false end
			local ok, done = pcall(D.Set, D, addon, path, v)
			return ok and done
		end
		local s = {}
		function s.Get()
			local v = Read()
			if type(v) == "table" and next(v) ~= nil then return v end
			if type(legacy) == "table" and type(legacy.get) == "function" then
				local ok, old = pcall(legacy.get)
				if ok and type(old) == "table" and next(old) ~= nil and Write(Copy(old)) ~= false then
					if type(legacy.clear) == "function" then pcall(legacy.clear) end
					return Copy(old)
				end
			end
			return nil
		end
		function s.Save(t) return Write(type(t) == "table" and Copy(t) or nil) end
		function s.Reset() return Write(nil) end
		return s
	end

	-- ---------------------------------------------------------------------------------------------
	-- Loading
	-- ---------------------------------------------------------------------------------------------

	function I.OnEvent(event, arg)
		if event == "ADDON_LOADED" then
			local rec = S.addons[arg]
			if not rec or rec.loaded then return end
			local sv = _G[rec.sv]
			if type(sv) ~= "table" then
				sv = {}
				_G[rec.sv] = sv
			end
			sv.values = type(sv.values) == "table" and sv.values or {}
			sv.movers = type(sv.movers) == "table" and sv.movers or {}
			local held = rec.store
			if held then
				for path, v in pairs(Leaves(held.values)) do SetPath(sv.values, path, v) end
				for k, v in pairs(held.movers) do sv.movers[k] = v end
			end
			rec.store = sv
			rec.loaded = true
			if rec.standalone and rec.module then Fill(sv.values, rec.module.defaults) end
			if type(sv.general) == "table" and (sv.generalAt or 0) >= (S.generalAt or -1) then
				S.generalAt = sv.generalAt or 0
				for k, v in pairs(sv.general) do S.general[k] = Copy(v) end
			end
		elseif event == "PLAYER_LOGIN" then
			S.loggedIn = true
			for _, name in ipairs(S.order) do
				local rec = S.addons[name]
				if rec.standalone then
					Store(rec).from = "standalone"
					Safe(I.GameOptions, rec)
				end
			end
			for word in pairs(S.commands) do Safe(I.OwnSlash, word) end
			I.PlaceAll()
			if S.anyStandalone then
				I.Fire("Login")
				-- (The shells made as the files loaded, drawn again in the look saved, and the inks.)
				I.RepaintAll()
				Safe(I.Restyle)
				local th = Polestar()
				if th and type(th.OnChanged) == "function" and not S.psHooked then
					S.psHooked = true
					pcall(th.OnChanged, function() lib.impl.PolestarChanged() end)
				end
				Safe(I.MapButton)
				Safe(I.Compartment)
			end
		elseif event == "PLAYER_LOGOUT" then
			for _, rec in pairs(S.addons) do
				local defaults = rec.loaded and rec.standalone and Defaults(rec)
				if defaults then Strip(Store(rec).values, defaults) end
			end
		elseif event == "PLAYER_REGEN_DISABLED" then
			if S.unlocked then I.Unlock(false) end
		elseif event == "PLAYER_REGEN_ENABLED" then
			if S.placeLater then I.PlaceAll() end
			if S.scaleLater then I.RescaleAll() end
		end
	end

	-- Joins a plugin: Daylight UI's own when it is there, else this file's stand-ins.
	function I.Attach(addon, pns)
		if not S.frame then
			S.frame = CreateFrame("Frame")
			for _, e in ipairs({ "ADDON_LOADED", "PLAYER_LOGIN", "PLAYER_LOGOUT", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" }) do
				S.frame:RegisterEvent(e)
			end
			S.frame:SetScript("OnEvent", function(_, event, arg) lib.impl.OnEvent(event, arg) end)
		end
		if not S.L and type(pns.L) == "table" then S.L = pns.L end
		-- (The language the plugins' text is in this session, as their Locales.lua picked it.)
		if S.locale == nil and type(pns.LOCALE) == "string" then S.locale = pns.LOCALE end
		local rec = S.addons[addon]
		if not rec then
			rec = { name = addon, sv = addon .. "Settings" }
			S.addons[addon] = rec
			S.order[#S.order + 1] = addon
		end
		local real = _G.DaylightUI
		local api = type(real) == "table" and real.API
		rec.standalone = not (type(api) == "table" and api.major == 1)
		local host = setmetatable({ addon = addon, standalone = rec.standalone }, { __index = function(t, k)
			if lib.impl.host[k] == nil then return nil end
			local f = function(...) return lib.impl.host[k](t, ...) end
			rawset(t, k, f)
			return f
		end })
		pns.Host = host
		pns.standalone = rec.standalone
		if not rec.standalone then
			pns.DUI, pns.API = real, api
			I.WatchDaylight(rec)
			return
		end
		S.anyStandalone = true
		pns.DUI, pns.API = I.StandIn(), lib.API
		if not S.slash then
			S.slash = true
			_G.SLASH_GLOWEYHOST1 = "/glowey"
			SlashCmdList.GLOWEYHOST = function(msg) lib.impl.Slash(msg) end
		end
	end

	-- The table that stands where DaylightUI would be (ns.DUI), for the calls the plugins make on it.
	function I.StandIn()
		if S.dui then return S.dui end
		S.dui = {
			standalone = true,
			RegisterPlugin = function(_, name, info) return lib.impl.RegisterPlugin(name, info) end,
			RegisterModule = function(_, name, def) return lib.impl.RegisterModule(name, def) end,
			Get = function(_, scope, path) return lib.impl.Get(scope, path) end,
			Set = function(_, scope, path, value) return lib.impl.Set(scope, path, value) end,
			GetModule = function(_, name) return lib.impl.GetModule(name) end,
			Movers = {
				unlocked = false,
				Get = function(id) return lib.impl.MV.Get(id) end,
				Suspend = function(id, on) return lib.impl.MV.Suspend(id, on) end,
			},
		}
		return S.dui
	end

	return I
end)()

-- DaylightUI.API's stand-in, shared by every plugin: each call finds the newest code.
lib.API = lib.API or setmetatable({ major = 1, standalone = true }, { __index = function(_, k)
	return lib.impl.api[k]
end })
end

lib.impl.Attach(ADDON, ns)
