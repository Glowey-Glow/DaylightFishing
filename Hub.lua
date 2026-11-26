-- Hub.lua: shared by Glowey's plugins (DaylightAddonSkins, DaylightEssentials, DaylightFishing,
-- DaylightRecipes, GloweyGear). The same file is in each: keep the copies the same, and raise
-- MINOR with any change. The copy with the highest MINOR provides the code (_G.GloweyHub.impl).
--
-- With Daylight UI loaded and two or more of these plugins on for this character, their sections
-- on the options window's rail fold into one: "Glowey's". Its page list has a row for each
-- plugin (an overview with a button for each of its pages). Picking a plugin opens its pages
-- under it and closes the one open before. While the player searches, every page is listed, so
-- search finds them all.
--
-- Each plugin still registers itself (DaylightUI:RegisterPlugin), so General > Plugins, its setup
-- guide and its saved settings stay its own; only its pages move. That uses what Daylight UI's
-- RegisterModule passes on to its options registry, beyond its API.md: a module's `section` and
-- `pageOrder` (Plugins.lua Adopt), and a page's `hidden` and `onShow` (Options/Registry.lua
-- RegisterModule, pageShown; Options/Panel.lua Show). Were a later Daylight UI to stop passing them
-- on, each plugin's pages show in its own section again, or all of them unfolded in the hub: never
-- an error. The search watch is a hook on Daylight UI's OptionsPanel.Search, after type checks.
--
-- Without Daylight UI (or with only one of them on) nothing here changes anything: Join registers
-- the plugin and its module the way it always did.

-- luacheck: read globals C_AddOns C_Timer hooksecurefunc geterrorhandler GetAddOnInfo IsAddOnLoaded strtrim

local MINOR = 1

local lib = _G.GloweyHub
if type(lib) ~= "table" then
	lib = { minor = 0 }
	_G.GloweyHub = lib
end
lib.state = lib.state or {}

if (lib.minor or 0) < MINOR then
lib.minor = MINOR
lib.impl = (function()
	local S = lib.state
	local I = {}

	-- The plugins that fold in, in their order on the hub's list.
	I.MEMBERS = { "DaylightAddonSkins", "DaylightEssentials", "DaylightFishing", "DaylightRecipes", "GloweyGear" }
	I.SECTION_PLUGIN = "GloweyHub"
	I.SECTION = "plugin:GloweyHub"
	I.INDENT = "   "

	local function Rank(addon)
		for i, name in ipairs(I.MEMBERS) do
			if name == addon then return i end
		end
		return #I.MEMBERS + 1
	end

	-- Whether an addon is on for this character and will load (or has).
	local function On(addon)
		local api = C_AddOns
		local loaded = api and api.IsAddOnLoaded or IsAddOnLoaded
		if type(loaded) == "function" then
			local ok, yes = pcall(loaded, addon)
			if ok and yes then return true end
		end
		local info = api and api.GetAddOnInfo or GetAddOnInfo
		if type(info) ~= "function" then return false end
		local ok, _, _, _, loadable = pcall(info, addon)
		return ok and loadable == true
	end

	-- The real Daylight UI (not the plugins' stand-in, Host.lua).
	local function Dui(dui)
		local D = _G.DaylightUI
		return type(D) == "table" and dui == D and type(D.RegisterPlugin) == "function" and D or nil
	end

	-- Whether the plugins fold into the hub: Daylight UI is here and two or more of them are on.
	-- Decided once, the same way by each plugin.
	function I.Active(dui)
		if not Dui(dui) then return false end
		if S.active == nil then
			local n = 0
			for _, addon in ipairs(I.MEMBERS) do
				if On(addon) then n = n + 1 end
			end
			S.active = n >= 2
		end
		return S.active
	end

	-- While the options window's search has results up, every page is listed. The box empties
	-- before a picked result's page opens (Panel.Show), so the pages stay listed one frame more,
	-- and that page is opened rather than refused; the list then folds again.
	local function Searching() return S.searching == true or S.linger == true end
	local function Refresh()
		local P = _G.DaylightUI and rawget(_G.DaylightUI, "OptionsPanel")
		if type(P) == "table" and type(P.IsShown) == "function" and type(P.Refresh) == "function" then
			pcall(function() if P.IsShown() then P.Refresh() end end)
		end
	end
	local function WatchSearch()
		if S.watching then return end
		local P = _G.DaylightUI and rawget(_G.DaylightUI, "OptionsPanel")
		if type(P) ~= "table" or type(P.Search) ~= "function" or type(hooksecurefunc) ~= "function" then return end
		S.watching = true
		hooksecurefunc(P, "Search", function(text)
			local need = type(P.MIN_QUERY) == "number" and P.MIN_QUERY or 2
			local q = type(text) == "string" and strtrim(text) or ""
			if #q >= need then
				S.searching = true
				return
			end
			if not S.searching then return end
			S.searching = false
			S.linger = true
			C_Timer.After(0, function()
				S.linger = false
				Refresh()
			end)
		end)
	end

	-- The plugin whose pages are open on the hub's list.
	function I.Open(addon)
		S.open = addon
	end
	function I.IsOpen(addon) return S.open == addon end

	-- Shows one of a plugin's pages ("<Addon>.<id>"), opening its place on the list first.
	function I.Show(addon, pageId)
		I.Open(addon)
		local P = _G.DaylightUI and rawget(_G.DaylightUI, "OptionsPanel")
		if type(P) == "table" and type(P.Show) == "function" then
			return pcall(P.Show, addon .. "." .. tostring(pageId))
		end
		return false
	end

	-- The hub's own entry on the rail, made by the first plugin to join.
	local function Section(D, spec)
		if S.section then return true end
		local ok, err = pcall(D.RegisterPlugin, D, I.SECTION_PLUGIN, {
			title = "Glowey's",
			author = "Glowey",
			needs = { 1, 1 },
			icon = spec.hubIcon,
			color = { 0.92, 0.62, 1 },
			short = "Glowey's",
			blurb = spec.hubBlurb,
			desc = spec.hubDesc,
		})
		if not ok then
			geterrorhandler()(err)
			return false
		end
		S.section = true
		return true
	end

	-- A plugin's overview: its name and blurb, and a button for each of its pages.
	local function Overview(addon, plugin, pages, words)
		local items = {}
		for _, p in ipairs(pages) do
			local id, label = p.id, p.label
			items[#items + 1] = { type = "button", label = label, text = words.open,
				hidden = p.hidden,
				func = function() I.Show(addon, id) end }
		end
		if #items == 0 then items[1] = { type = "text", label = plugin.blurb or "" } end
		return {
			id = "hub",
			label = plugin.short or plugin.title,
			desc = plugin.blurb,
			groups = { { label = plugin.title or addon, desc = words.pages, items = items } },
			onShow = function() I.Open(addon) end,
		}
	end

	-- Registers a plugin and its module with Daylight UI (or the plugins' stand-in), folding its
	-- pages into the hub when that's on. spec: { addon, dui, plugin (RegisterPlugin's table),
	-- module (RegisterModule's table), words = { open, pages }, hubIcon, hubBlurb, hubDesc }.
	function I.Join(spec)
		local D, addon = spec.dui, spec.addon
		D:RegisterPlugin(addon, spec.plugin)
		local mod = spec.module
		local opts = mod.options
		local real = Dui(D)
		if real and I.Active(D) and type(opts) == "table" and type(opts.pages) == "table" and #opts.pages > 0
			and Section(real, spec) then
			WatchSearch()
			local pages = {}
			for _, p in ipairs(opts.pages) do
				local own, show = p.hidden, p.onShow
				local q = {}
				for k, v in pairs(p) do q[k] = v end
				q.label = I.INDENT .. tostring(p.label or p.id)
				q.hidden = function(get)
					if own and own(get) == true then return true end
					return not (S.open == addon or Searching())
				end
				q.onShow = function(...)
					I.Open(addon)
					if show then return show(...) end
				end
				pages[#pages + 1] = q
			end
			table.insert(pages, 1, Overview(addon, spec.plugin, opts.pages, spec.words or {}))
			mod.options = { pages = pages }
			mod.section = I.SECTION
			mod.pageOrder = Rank(addon) * 1000
		end
		D:RegisterModule(addon, mod)
	end

	return I
end)()
end

-- Each plugin's handle: calls go to the newest copy's code at the time of the call.
local _, ns = ...
ns.Hub = setmetatable({}, { __index = function(_, k) return lib.impl[k] end })
