-- The guide: a first-launch welcome, a "what's new" note after an update, and short tours that
-- light one part of the screen, dim the rest and explain it on a small card (Back, Next, Skip
-- tour; Escape skips; a fight ends it at once). The look and the rules follow DaylightUI's own tour
-- (light, dim, card, a toast saying where to find it again), but this is our own code, built only
-- from DaylightUI.API, so nothing of DaylightUI's inside can change under it.
-- The same file in each Daylight plugin that has tours; each plugin describes itself once with
-- ns.Guide.Setup(spec) and adds its tours with ns.Guide.AddTour(id, def).
--
-- spec: name (shown in titles), db() (the plugin's saved variables), existing() (true for a
--   player who had the plugin before the guide came: they get "what's new", not the welcome),
--   intro (the welcome's first sentence), takes() (a list of sentences: what the plugin takes
--   over or can take over), tour (the tour Start Tour runs), accept() (Start Tour also means yes
--   to what the welcome lists), decline = { label, fn } (an optional second answer), main = { label,
--   fn } (a plugin without a tour: the welcome's main button instead of Start Tour), heading (the
--   line above the welcome's list, instead of "What it takes over"), news (newest
--   first: { { version, lines = { ... } }, ... }), reset (a token: when it differs from the one
--   saved, the welcome and every tour show again once, for everyone, players from before included;
--   change it in a release to show them all again), revert = { label (the row), text (the button:
--   a string, or a function asked each time it's drawn), fn, desc, available() } or nil (the
--   options' Revert button, hidden while available() says there's nothing to go back to).
-- Every tour closes DaylightUI's options while it runs (Retake Tour is clicked there, and the window
-- would sit over what the tour shows) and opens them again on the same page when it ends, through
-- DaylightUI's own "/dui" command (which opens and closes them).
-- Every Daylight plugin with this file shares one flag (_G.DaylightGuides: its name -> busy), so
-- two plugins' welcomes or tours never show at once.
-- A tour: { steps = { { title, text (string or function), part() (regions to light; none shown:
--   the card sits in the middle), enter(), leave(), through (the mouse reaches what's under it;
--   true, or a function asked as the step shows),
--   done() (it moves on once true) } ... }, start() (opens what the tour shows) }.
-- Seen tours, the welcome and the last notes read are kept in db().guide (per account).
-- On a controller (the game's controller interface on), the card, the welcome and "what's new" take
-- the D-pad (ns.Pad, below): it starts on Next (or the main button), A presses, B skips the tour
-- (Done on its last card) or closes the note.
-- luacheck: read globals CreateFrame UIParent C_Timer InCombatLockdown GetScreenWidth GetScreenHeight
local ADDON, ns = ...

-- ---------------------------------------------------------------------------------------------
-- ns.Pad: our windows on a controller, through DaylightUI's own controller kit (DaylightUI.Pad).
-- That kit isn't part of DaylightUI's API, so every call here is checked and wrapped: with a
-- DaylightUI without it, or one where it changed, these do nothing and our windows work as before,
-- with the mouse. The game gives its controller cursor (D-pad, A, B, the right stick) only to the
-- windows it's told about, and only out of a fight: DaylightUI tells it, and a window opened in a
-- fight is told once the fight is over.
--   Pad.On()                   the game's controller interface is on
--   Pad.Follow(frame, close)   the controller cursor works in frame while it's shown (also when
--                              it's hidden along with its parent); close() is what B does. The
--                              kit's fields work on frame: padFirst(), padTabs(), padKeys...
--   Pad.Popup(frame, close)    a small list over a window: takes the cursor, then gives it back
--   Pad.Settle(aim)            a window changed: the game finds its buttons again, the cursor goes
--                              to aim (a button) or off one that's gone
--   Pad.Front(frame)           the cursor back on frame when another window took it
--   Pad.KeepOff(frame)         a game window held out of sight under ours stays off the game's
--                              list (the game puts it back on with each page it opens);
--                              Pad.Remember(frame) puts it back once it's handed back
--   Pad.Skip(frame)            the cursor never stops on it (a look-alike under a secure button)
--   Pad.Edge(button, dir, fn)  the D-pad's "UP" or "DOWN" on button asks fn() first: true when it
--                              scrolled the list under the cursor (which then stays where it is)
--   Pad.Scroller(spec)         a stand-in scroll frame for a list drawn from an offset, for the
--                              right stick: spec = { range(), at(), set(pixels) }; s.Sync() after
--                              the list moves or changes
--   Pad.Stick(frame, scroll)   the right stick scrolls `scroll` while frame has the cursor
--   Pad.Into(region, scroll)   the same, for the followed window holding region (a row's OnEnter:
--                              the stick scrolls the list the cursor is in)
-- Nothing runs while no window of ours is open.
-- ---------------------------------------------------------------------------------------------

local Pad = {}
ns.Pad = Pad
local padFollowed = setmetatable({}, { __mode = "k" })
local padPopups = setmetatable({}, { __mode = "k" })
local padSkipped = setmetatable({}, { __mode = "k" })

local function Kit()
	local D = _G.DaylightUI
	local P = type(D) == "table" and D.Pad or nil
	return type(P) == "table" and P or nil
end

local function KitCall(name, ...)
	local P = Kit()
	local fn = P and P[name]
	if type(fn) ~= "function" then return nil end
	local ok, got = pcall(fn, ...)
	if ok then return got end
	return nil
end

function Pad.On() return KitCall("On") == true end

-- Marks the game's controller code keeps on a frame: set through its own calls, out of a fight
-- only (in one, they wait for its end).
local padLater, padWaiter = {}, nil
local function Calm(fn)
	if not InCombatLockdown() then
		pcall(fn)
		return
	end
	padLater[#padLater + 1] = fn
	if not padWaiter then
		padWaiter = CreateFrame("Frame")
		padWaiter:SetScript("OnEvent", function(self)
			self:UnregisterEvent("PLAYER_REGEN_ENABLED")
			local list = padLater
			padLater = {}
			for _, f in ipairs(list) do pcall(f) end
		end)
	end
	padWaiter:RegisterEvent("PLAYER_REGEN_ENABLED")
end

function Pad.Follow(frame, close)
	if type(frame) ~= "table" or padFollowed[frame] then return end
	local P = Kit()
	if not (P and type(P.Follow) == "function") then return end
	padFollowed[frame] = true
	KitCall("Follow", frame, close)
	-- (Hidden along with its parent, a frame still says it's shown: the game is told all the same.)
	frame:HookScript("OnHide", function(self)
		if self:IsShown() then KitCall("Leaving", self) end
	end)
end

function Pad.Popup(frame, close)
	if type(frame) ~= "table" or padPopups[frame] then return end
	local P = Kit()
	if not (P and type(P.Popup) == "function") then return end
	padPopups[frame] = true
	KitCall("Popup", frame, close)
end

function Pad.Settle(aim) KitCall("Settle", aim) end

function Pad.Front(frame)
	if not (padFollowed[frame] and frame:IsVisible() and Pad.On()) or InCombatLockdown() then return end
	local G = _G.GamepadMode
	local m = type(G) == "table" and G.FrameControlsManager or nil
	if type(m) ~= "table" or type(m.GetActiveFrame) ~= "function" then return end
	local ok, active = pcall(m.GetActiveFrame, m)
	-- (Only with another window listed: one taken off a list it leaves empty is refused.)
	if not ok or active == nil or active == frame then return end
	KitCall("Leaving", frame)
	KitCall("Returning", frame)
end

function Pad.KeepOff(frame)
	if type(frame) == "table" and Pad.On() then KitCall("KeepOff", frame) end
end

function Pad.Remember(frame)
	if type(frame) == "table" and Pad.On() then KitCall("Remember", frame) end
end

function Pad.Skip(frame)
	if type(frame) ~= "table" or padSkipped[frame] then return end
	padSkipped[frame] = true
	Calm(function()
		local mark = _G.SmartNavigation_MarkFrameIgnored
		if type(mark) == "function" then mark(frame) end
	end)
end

function Pad.Edge(button, dir, fn)
	if type(button) ~= "table" or type(fn) ~= "function" or not Kit() then return end
	Calm(function()
		local add, dirs = _G.SmartNavigation_AddJumpNavigationOverride, _G.SMART_NAV_INPUT_DIRECTION
		if type(add) ~= "function" or type(dirs) ~= "table" or not dirs[dir] then return end
		add(button, dirs[dir], function()
			local ok, moved = pcall(fn)
			if ok and moved then return true end
			return nil
		end)
	end)
end

function Pad.Scroller(spec)
	if not Kit() then return nil end
	local s = CreateFrame("ScrollFrame", nil, UIParent)
	s:SetSize(1, 100)
	s:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", -16, -16)
	s:EnableMouse(false)
	local child = CreateFrame("Frame", nil, s)
	child:SetSize(1, 100)
	s:SetScrollChild(child)
	local quiet = false
	function s.Sync()
		local okR, range = pcall(spec.range)
		local okA, at = pcall(spec.at)
		range = okR and type(range) == "number" and math.max(0, range) or 0
		at = okA and type(at) == "number" and at or 0
		quiet = true
		child:SetHeight(100 + range)
		s:SetVerticalScroll(math.max(0, math.min(range, at)))
		quiet = false
	end
	s:SetScript("OnVerticalScroll", function(_, v)
		if not quiet then pcall(spec.set, v) end
	end)
	return s
end

function Pad.Stick(frame, scroll)
	if type(frame) ~= "table" or not padFollowed[frame] or frame.padScroll == scroll then return end
	frame.padScroll = scroll
	if Pad.On() and not InCombatLockdown() then KitCall("Scrolls", frame) end
end

function Pad.Into(region, scroll)
	if not scroll or not Pad.On() then return end
	local f = region
	while f and not padFollowed[f] do f = f.GetParent and f:GetParent() or nil end
	if f then Pad.Stick(f, scroll) end
end

local API = _G.DaylightUI and _G.DaylightUI.API
if not API then return end
local L = ns.L or setmetatable({}, { __index = function(_, k) return k end })

local Guide = {}
ns.Guide = Guide

local CARD_W, EDGE, GAP, BTN_H = 320, 14, 8, 24
local PAD, MARGIN, DIM = 6, 8, 0.55
local WATCH = 0.2

local spec
local tours = {}
local S                 -- the running tour: { id, def, i, quiet }

local function G()
	local db = spec and spec.db()
	-- (Not there yet on a first launch: made, as "<addon>DB", the plugin's saved variables, which
	-- every plugin with this file keeps as a table and adds to.)
	if type(db) ~= "table" and spec then
		db = {}
		_G[ADDON .. "DB"] = db
	end
	if type(db) ~= "table" then return {} end
	db.guide = type(db.guide) == "table" and db.guide or {}
	db.guide.tours = type(db.guide.tours) == "table" and db.guide.tours or {}
	return db.guide
end

local function Ink(fs, role, alpha)
	local c = API.Colors()[role]
	if type(c) == "table" then fs:SetTextColor(c[1], c[2], c[3], alpha or 1) end
end

local function Hex(r, g, b)
	return string.format("|cff%02x%02x%02x", math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
end

-- A name in the accent, for a step's sentence.
function Guide.Pop(text)
	local r, g, b = API.Accent()
	return Hex(r, g, b) .. tostring(text) .. "|r"
end

local function Fit(b, min)
	local fs = b.text or (b.GetFontString and b:GetFontString())
	local w = fs and (fs.GetUnboundedStringWidth and fs:GetUnboundedStringWidth() or fs:GetStringWidth()) or 0
	if type(w) ~= "number" or w <= 0 then w = 60 end
	b:SetWidth(math.max(min or 72, math.ceil(w) + 28))
end

local function Button(parent, text, main)
	local b = API.Button(parent, text, BTN_H)
	Fit(b)
	if main and API.MainButton then pcall(API.MainButton, b, true) end
	return b
end

-- Ours busy (a note or a tour up), for the other Daylight plugins' guides.
local Busy = type(_G.DaylightGuides) == "table" and _G.DaylightGuides or {}
_G.DaylightGuides = Busy
local function SetBusy(on) Busy[ADDON] = on or nil end

-- DaylightUI's own setup guide or tour, or another Daylight plugin's welcome or tour, is up: ours
-- waits.
local function DaylightBusy()
	for _, name in ipairs({ "DaylightUIInstaller", "DaylightUITour", "DaylightUITourAsk" }) do
		local f = _G[name]
		if type(f) == "table" and f.IsShown and f:IsShown() and (f:GetAlpha() or 0) > 0.05 then return true end
	end
	for name, on in pairs(Busy) do
		if on and name ~= ADDON then return true end
	end
	return false
end

-- ---------------------------------------------------------------------------------------------
-- The tour's layer: the dim around the lit part, its edge, and the card
-- ---------------------------------------------------------------------------------------------

local layer, card, toast
local note

local function Box(regions)
	local ui = UIParent:GetEffectiveScale()
	local l, b, r, t
	for _, f in ipairs(regions) do
		if type(f) == "table" and f.IsVisible and f:IsVisible() and f.GetLeft and f:GetLeft() then
			local s = f:GetEffectiveScale() / ui
			local fl, fb, fw, fh = f:GetLeft() * s, f:GetBottom() * s, f:GetWidth() * s, f:GetHeight() * s
			l = l and math.min(l, fl) or fl
			b = b and math.min(b, fb) or fb
			r = r and math.max(r, fl + fw) or fl + fw
			t = t and math.max(t, fb + fh) or fb + fh
		end
	end
	if not l then return nil end
	return { l = l - PAD, b = b - PAD, r = r + PAD, t = t + PAD }
end

local function BuildLayer()
	if layer then return end
	layer = CreateFrame("Frame", nil, UIParent)
	layer:SetAllPoints(UIParent)
	layer:SetFrameStrata("FULLSCREEN_DIALOG")
	-- (Seen whatever fades the UI: Fishing Mode's fade, another addon's.)
	layer:SetIgnoreParentAlpha(true)
	layer:Hide()
	layer.dim = {}
	for i = 1, 4 do
		local t = layer:CreateTexture(nil, "BACKGROUND")
		t:SetColorTexture(0, 0, 0, DIM)
		layer.dim[i] = t
	end
	-- (The outline in a frame of its own: its pulse fades the outline only.)
	layer.edges = CreateFrame("Frame", nil, layer)
	layer.edges:SetAllPoints(layer)
	layer.edge = {}
	for i = 1, 4 do
		local t = layer.edges:CreateTexture(nil, "ARTWORK")
		layer.edge[i] = t
	end
	local pulse = layer.edges:CreateAnimationGroup()
	pulse:SetLooping("BOUNCE")
	local a = pulse:CreateAnimation("Alpha")
	a:SetFromAlpha(1)
	a:SetToAlpha(0.45)
	a:SetDuration(0.9)
	layer.pulse = pulse

	card = CreateFrame("Frame", nil, layer)
	card:SetFrameLevel(layer:GetFrameLevel() + 20)
	card:SetWidth(CARD_W)
	card:EnableMouse(true)
	API.Skin(card, { window = true })
	card.title = API.Text(card, "head", "LEFT")
	card.title:SetPoint("TOPLEFT", EDGE, -EDGE)
	card.title:SetPoint("RIGHT", card, "RIGHT", -EDGE - 40, 0)
	card.count = API.Text(card, "small", "RIGHT")
	card.count:SetPoint("TOPRIGHT", -EDGE, -EDGE - 2)
	card.text = API.Text(card, "body", "LEFT")
	card.text:SetPoint("TOPLEFT", card.title, "BOTTOMLEFT", 0, -GAP)
	card.text:SetWidth(CARD_W - 2 * EDGE)
	card.text:SetWordWrap(true)
	card.next = Button(card, L["Next"], true)
	card.next:SetPoint("BOTTOMRIGHT", -EDGE, EDGE)
	card.next:SetScript("OnClick", function() Guide.Next() end)
	card.back = Button(card, L["Back"])
	card.back:SetPoint("RIGHT", card.next, "LEFT", -GAP, 0)
	card.back:SetScript("OnClick", function() Guide.Back() end)
	card.skip = Button(card, L["Skip Tour"])
	card.skip:SetPoint("BOTTOMLEFT", EDGE, EDGE)
	card.skip:SetScript("OnClick", function() Guide.Skip() end)

	-- Escape skips; every other key goes on to the game.
	card:EnableKeyboard(true)
	card:SetScript("OnKeyDown", function(self, key)
		if InCombatLockdown() then return end
		if key == "ESCAPE" then
			self:SetPropagateKeyboardInput(false)
			Guide.Skip()
		else
			self:SetPropagateKeyboardInput(true)
		end
	end)

	-- A controller: the cursor on the card (Next first), B skips (Done on the last card). Its button
	-- bar goes under the card, above the dim.
	layer.padFirst = function() return card.next end
	layer.padKeys = { { key = "B", follow = true,
		label = function() return (S and S.i < #S.def.steps) and L["Skip Tour"] or L["Done"] end,
		when = function() return S ~= nil end, run = function() Guide.Close() end } }
	layer.padHintsPlace = function(bar)
		bar:SetPoint("TOP", card, "BOTTOM", 0, -6)
		bar:SetFrameStrata("FULLSCREEN_DIALOG")
		bar:SetFrameLevel(card:GetFrameLevel() + 5)
	end
	layer:HookScript("OnHide", function()
		local P = Kit()
		local bar = P and P.hints
		if type(bar) == "table" and bar.SetFrameStrata then pcall(bar.SetFrameStrata, bar, "DIALOG") end
	end)
	Pad.Follow(layer, function() Guide.Close() end)

	layer:SetScript("OnUpdate", function(self, dt)
		self.since = (self.since or 0) + dt
		if self.since < WATCH then return end
		self.since = 0
		-- (Only once the step's card is drawn: its done() and light belong to that card.)
		if S and S.shown == S.i then Guide.Paint(true) end
	end)

	toast = CreateFrame("Frame", nil, UIParent)
	toast:SetFrameStrata("FULLSCREEN_DIALOG")
	toast:SetIgnoreParentAlpha(true)
	toast:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 120)
	toast:SetHeight(36)
	toast:Hide()
	API.Skin(toast, { window = true })
	toast.text = API.Text(toast, "body", "CENTER")
	toast.text:SetPoint("CENTER")
end

local function Toast(text)
	BuildLayer()
	toast.text:SetText(text)
	Ink(toast.text, "TEXT")
	toast:SetWidth(math.ceil(toast.text:GetStringWidth() or 200) + 2 * EDGE)
	API.Skin(toast, { window = true })
	toast:SetAlpha(1)
	toast:Show()
	local token = {}
	toast.token = token
	C_Timer.After(3.5, function()
		if toast.token == token then API.Fade(toast, 0, "SLOW") end
	end)
end

local function Dim(box)
	local sw, sh = UIParent:GetWidth(), UIParent:GetHeight()
	local d, e = layer.dim, layer.edge
	for i = 1, 4 do d[i]:ClearAllPoints() e[i]:ClearAllPoints() end
	if not box then
		d[1]:SetAllPoints(layer)
		for i = 2, 4 do d[i]:Hide() end
		for i = 1, 4 do e[i]:Hide() end
		return
	end
	local l, b, r, t = math.max(0, box.l), math.max(0, box.b), math.min(sw, box.r), math.min(sh, box.t)
	-- Above, below, left, right of the lit part.
	d[1]:SetPoint("TOPLEFT", layer, "TOPLEFT", 0, 0)
	d[1]:SetPoint("BOTTOMRIGHT", layer, "TOPRIGHT", 0, -(sh - t))
	d[2]:SetPoint("TOPLEFT", layer, "BOTTOMLEFT", 0, b)
	d[2]:SetPoint("BOTTOMRIGHT", layer, "BOTTOMRIGHT", 0, 0)
	d[3]:SetPoint("TOPLEFT", layer, "TOPLEFT", 0, -(sh - t))
	d[3]:SetPoint("BOTTOMRIGHT", layer, "BOTTOMLEFT", l, b)
	d[4]:SetPoint("TOPLEFT", layer, "TOPLEFT", r, -(sh - t))
	d[4]:SetPoint("BOTTOMRIGHT", layer, "BOTTOMRIGHT", 0, b)
	for i = 1, 4 do d[i]:Show() end
	local cr, cg, cb = API.Accent()
	for i = 1, 4 do e[i]:SetColorTexture(cr, cg, cb, 1) e[i]:Show() end
	e[1]:SetPoint("BOTTOMLEFT", layer, "BOTTOMLEFT", l, t - 2) e[1]:SetSize(r - l, 2)
	e[2]:SetPoint("BOTTOMLEFT", layer, "BOTTOMLEFT", l, b) e[2]:SetSize(r - l, 2)
	e[3]:SetPoint("BOTTOMLEFT", layer, "BOTTOMLEFT", l, b) e[3]:SetSize(2, t - b)
	e[4]:SetPoint("BOTTOMLEFT", layer, "BOTTOMLEFT", r - 2, b) e[4]:SetSize(2, t - b)
end

-- The card beside the lit part: below it, else above, right, left; else the middle.
local function PlaceCard(box)
	local sw, sh = UIParent:GetWidth(), UIParent:GetHeight()
	local w, h = card:GetWidth(), card:GetHeight()
	card:ClearAllPoints()
	if not box then
		card:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
		return
	end
	local cx = math.max(MARGIN, math.min(sw - w - MARGIN, (box.l + box.r) / 2 - w / 2))
	local cy = math.max(MARGIN, math.min(sh - h - MARGIN, (box.b + box.t) / 2 - h / 2))
	local x, y
	if box.b - 14 - h >= MARGIN then x, y = cx, box.b - 14 - h
	elseif box.t + 14 + h <= sh - MARGIN then x, y = cx, box.t + 14
	elseif box.r + 14 + w <= sw - MARGIN then x, y = box.r + 14, cy
	elseif box.l - 14 - w >= MARGIN then x, y = box.l - 14 - w, cy
	else
		card:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
		return
	end
	card:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", x, y)
end

local function Step() return S and S.def.steps[S.i] end

-- DaylightUI's options window is open (a closing one, fading out, counts as closed).
local function OptionsOpen()
	local f = _G.DaylightUIOptions
	return type(f) == "table" and f.IsShown and f:IsShown() and (f:GetAlpha() or 0) > 0.5
end

-- Opens or closes DaylightUI's options as "/dui" does.
local function ToggleOptions()
	local cmd = _G.SlashCmdList and _G.SlashCmdList.DAYLIGHTUI
	if type(cmd) == "function" then pcall(cmd, "") end
end

local function Regions(step)
	if not step.part then return {} end
	local ok, got = pcall(step.part)
	if not ok or got == nil then return {} end
	if type(got) == "table" and got.GetObjectType then return { got } end
	return type(got) == "table" and got or {}
end

-- Draws the step (quiet: only when the lit part moved, or its done() came true).
function Guide.Paint(quiet)
	local step = Step()
	if not step then return end
	if quiet and step.done then
		local ok, yes = pcall(step.done)
		if ok and yes then return Guide.Next() end
	end
	local box = Box(Regions(step))
	if quiet then
		local was = S.box
		if (was == nil) == (box == nil) and (not box or (math.abs(was.l - box.l) < 1 and math.abs(was.t - box.t) < 1
			and math.abs(was.r - box.r) < 1 and math.abs(was.b - box.b) < 1)) then return end
	end
	S.box = box
	Dim(box)
	PlaceCard(box)
end

local function Show()
	local step = Step()
	card:Show()
	card.title:SetText(step.title or "")
	Ink(card.title, "VALUE")
	local text = step.text
	if type(text) == "function" then
		local ok, got = pcall(text)
		text = ok and got or ""
	end
	card.text:SetText(text or "")
	Ink(card.text, "TEXT")
	card.count:SetText(("%d / %d"):format(S.i, #S.def.steps))
	Ink(card.count, "LABEL")
	card.back:SetShown(S.i > 1)
	-- (The last card has nothing left to skip: Back and Done only.)
	card.skip:SetShown(S.i < #S.def.steps)
	card.next.text:SetText(S.i == #S.def.steps and L["Done"] or L["Next"])
	Fit(card.next)
	local th = card.text:GetStringHeight() or 14
	local tt = math.max(20, card.title:GetStringHeight() or 20)
	card:SetHeight(math.ceil(EDGE + tt + GAP + th + GAP * 2 + BTN_H + EDGE))
	API.Skin(card, { window = true })
	local through = step.through
	if type(through) == "function" then
		local ok, yes = pcall(through)
		through = ok and yes
	end
	layer:EnableMouse(not through)
	S.box = false
	S.shown = S.i
	Guide.Paint()
	-- A controller: the cursor back on the card (a window the step opened may have taken it), on
	-- Next unless it's on a button of the card that's still there.
	if Pad.On() then
		Pad.Front(layer)
		local at = KitCall("Stop")
		local keep = type(at) == "table" and at.IsVisible and at:IsVisible() and at.GetParent and at:GetParent() == card
		Pad.Settle(not keep and card.next or nil)
	end
end

local function Leave(nextStep)
	local step = Step()
	if step and step.leave then pcall(step.leave, nextStep) end
end

local function Go(i)
	Leave(S.def.steps[i])
	S.i = i
	local step = Step()
	if step.enter then pcall(step.enter) end
	-- (Let what enter() opened finish opening before the light looks for it.)
	C_Timer.After(step.enter and 0.3 or 0, function() if S and Step() == step then Show() end end)
end

local function Finish(how)
	if not S then return end
	Leave(nil)
	local id, def = S.id, S.def
	S = nil
	layer.pulse:Stop()
	layer:Hide()
	SetBusy(false)
	if how then G().tours[id] = true end
	-- (The options it closed, back on the page they were on.)
	if def.reopenOptions then
		def.reopenOptions = nil
		C_Timer.After(0.2, function() if not OptionsOpen() then ToggleOptions() end end)
	end
	-- (Always, a fight too: what start() raised or opened goes back.)
	if def.finished then pcall(def.finished, how) end
end

function Guide.Next()
	if not S then return end
	if S.i < #S.def.steps then return Go(S.i + 1) end
	Finish("done")
end

function Guide.Back()
	if S and S.i > 1 then Go(S.i - 1) end
end

function Guide.Skip()
	if not S then return end
	Finish("skip")
	Toast(string.format(L["Tour skipped. %s in %s's options shows it again."], Guide.Pop(L["Retake Tour"]), spec and spec.name or ""))
end

-- B on a controller: skips the tour, or ends it on its last card.
function Guide.Close()
	if not S then return end
	if S.i < #S.def.steps then return Guide.Skip() end
	Finish("done")
end

function Guide.Running() return S ~= nil end

-- Runs a tour from its first step. quiet: a first-time tour (not run in a fight, behind
-- DaylightUI's own guide, or twice).
function Guide.Run(id, quiet)
	local def = tours[id]
	if not def or S or #def.steps == 0 then return false end
	if InCombatLockdown() then
		if not quiet then print((spec and spec.name or "") .. ": " .. L["The tour waits until the fight is over."]) end
		return false
	end
	if quiet and (G().tours[id] or DaylightBusy() or (note and note:IsShown())) then return false end
	BuildLayer()
	-- (Out of the way while the tour runs: the options. Given back at its end.)
	def.reopenOptions = nil
	if OptionsOpen() then
		def.reopenOptions = true
		ToggleOptions()
	end
	if def.start then pcall(def.start) end
	S = { id = id, def = def, i = 1 }
	SetBusy(true)
	card:Hide()
	layer:SetAlpha(1)
	layer:Show()
	layer.pulse:Play()
	local step = Step()
	if step.enter then pcall(step.enter) end
	C_Timer.After((def.start or step.enter or def.reopenOptions) and 0.4 or 0, function() if S and S.id == id then Show() end end)
	return true
end

-- A first-time tour: runs once per account, the first time its screen shows.
function Guide.Offer(id)
	if not tours[id] or G().tours[id] then return end
	local tries = 0
	local function try()
		tries = tries + 1
		if not tours[id] or G().tours[id] or S then return end
		if Guide.Run(id, true) then return end
		-- (Something else is up for now: a note, another tour, a fight. A while longer.)
		if tries < 30 then C_Timer.After(2, try) end
	end
	C_Timer.After(0.5, try)
end

function Guide.AddTour(id, def) tours[id] = def end

-- Marks tours as seen (a bigger tour that already showed what they would).
function Guide.MarkSeen(...)
	local seen = G().tours
	for i = 1, select("#", ...) do seen[select(i, ...)] = true end
end

-- ---------------------------------------------------------------------------------------------
-- The welcome (first launch) and "what's new" (after an update)
-- ---------------------------------------------------------------------------------------------

local function BuildNote()
	if note then return end
	note = CreateFrame("Frame", nil, UIParent)
	note:SetFrameStrata("DIALOG")
	note:SetIgnoreParentAlpha(true)
	note:SetToplevel(true)
	note:SetClampedToScreen(true)
	note:SetWidth(460)
	note:SetPoint("CENTER", 0, 80)
	note:EnableMouse(true)
	note:SetMovable(true)
	note:RegisterForDrag("LeftButton")
	note:SetScript("OnDragStart", note.StartMoving)
	note:SetScript("OnDragStop", note.StopMovingOrSizing)
	note:Hide()
	API.Skin(note, { window = true })
	note.title = API.Text(note, "title", "LEFT")
	note.title:SetPoint("TOPLEFT", 18, -18)
	note.title:SetPoint("RIGHT", note, "RIGHT", -44, 0)
	note.close = API.Close(note, function()
		note:Hide()
		if note.onClose then note.onClose() end
	end)
	note:SetScript("OnHide", function() SetBusy(S ~= nil) end)
	note.close:SetPoint("TOPRIGHT", -10, -10)
	note.body = API.Text(note, "body", "LEFT")
	note.body:SetPoint("TOPLEFT", note.title, "BOTTOMLEFT", 0, -10)
	note.body:SetWidth(460 - 36)
	note.body:SetWordWrap(true)
	note.main = Button(note, "", true)
	note.main:SetPoint("BOTTOMRIGHT", -18, 18)
	note.other = Button(note, "")
	note.other:SetPoint("RIGHT", note.main, "LEFT", -GAP, 0)
	-- A controller: the cursor starts on the main button; B is the X.
	note.padFirst = function() return note.main end
	Pad.Follow(note, function()
		note:Hide()
		if note.onClose then note.onClose() end
	end)
end

-- title, body text, main = { label, fn }, other = { label, fn } or nil, onClose (its X).
local function ShowNote(title, body, main, other, onClose)
	BuildNote()
	note.onClose = onClose
	note.title:SetText(title)
	Ink(note.title, "VALUE")
	note.body:SetText(body)
	Ink(note.body, "TEXT")
	note.main.text:SetText(main[1])
	Fit(note.main, 110)
	note.main:SetScript("OnClick", function() note:Hide() main[2]() end)
	note.other:SetShown(other ~= nil)
	if other then
		note.other.text:SetText(other[1])
		Fit(note.other, 110)
		note.other:SetScript("OnClick", function() note:Hide() other[2]() end)
	end
	local h = 18 + (note.title:GetStringHeight() or 22) + 10 + (note.body:GetStringHeight() or 40) + 18 + BTN_H + 18
	note:SetHeight(math.ceil(h))
	API.Skin(note, { window = true })
	SetBusy(true)
	-- (Already up with other words: a controller's cursor goes to the main button again.)
	if note:IsShown() then Pad.Settle(note.main) end
	note:Show()
end

local BULLET = "|cff%02x%02x%02x•|r  "

local function Bullets(lines)
	local r, g, b = API.Accent()
	local dot = BULLET:format(math.floor(r * 255), math.floor(g * 255), math.floor(b * 255))
	local out = {}
	for _, line in ipairs(lines) do out[#out + 1] = dot .. line end
	return table.concat(out, "\n")
end

local function StartTour()
	if spec.tour then Guide.Run(spec.tour, false) end
end

-- Opens DaylightUI's options on one of this plugin's pages ("<addon>.<page id>", as DaylightUI
-- names a plugin's pages), else as "/dui" opens them. (DaylightUI has no call for a page: its
-- options window is asked directly, and any change there falls back to "/dui".)
function Guide.OpenOptions(pageId)
	local P = _G.DaylightUI and _G.DaylightUI.OptionsPanel
	if pageId and type(P) == "table" and type(P.Show) == "function" then
		if pcall(P.Show, ADDON .. "." .. pageId) then return end
	end
	if not OptionsOpen() then ToggleOptions() end
end

local function CanRevert()
	local r = spec.revert
	if type(r) ~= "table" then return false end
	if not r.available then return true end
	local ok, yes = pcall(r.available)
	return ok and yes
end

function Guide.Welcome()
	local takes = spec.takes and spec.takes() or {}
	local head = spec.heading or (CanRevert() and L["What it takes over (you can go back any time with Revert in its options):"]
		or L["What It Takes Over:"])
	local body = (spec.intro or "") .. "\n\n" .. head .. "\n" .. Bullets(takes)
	-- (Answered only by a button or the X: until then it shows again at the next login.)
	local function Answered()
		local g = G()
		g.welcomed = true
		g.newsSeen = spec.news and spec.news[1] and spec.news[1].version
	end
	local function Decline()
		Answered()
		if spec.decline then pcall(spec.decline.fn) end
	end
	local main = spec.main and { spec.main.label, function()
			Answered()
			if spec.accept then pcall(spec.accept) end
			pcall(spec.main.fn)
		end } or { L["Start Tour"], function()
			Answered()
			if spec.accept then pcall(spec.accept) end
			StartTour()
		end }
	ShowNote(string.format(L["Welcome to %s"], spec.name), body, main,
		spec.decline and { spec.decline.label, Decline } or nil,
		Decline)
end

-- The notes newer than the last ones read (all = every release's).
function Guide.News(all)
	local seen = G().newsSeen
	local parts = {}
	for _, n in ipairs(spec.news or {}) do
		if not all and n.version == seen then break end
		parts[#parts + 1] = Guide.Pop(n.version) .. "\n" .. Bullets(n.lines)
		if all and #parts >= 3 then break end
	end
	if #parts == 0 then return end
	local latest = spec.news[1].version
	G().newsSeen = latest
	ShowNote(string.format(L["What's New in %s"], spec.name), table.concat(parts, "\n\n"),
		{ L["Okay"], function() end },
		spec.tour and { L["Retake Tour"], StartTour } or nil)
end

local function Greet()
	if InCombatLockdown() or DaylightBusy() then
		C_Timer.After(5, Greet)
		return
	end
	local g = G()
	local latest = spec.news and spec.news[1] and spec.news[1].version
	if not g.welcomed then
		-- (Someone who had the plugin before the guide came: what changed, not the welcome. Asked
		-- when the saved variables loaded, before anything of this session wrote to them.)
		if spec.wasExisting then
			g.welcomed = true
			if latest and g.newsSeen ~= latest then Guide.News(false) end
			return
		end
		Guide.Welcome()
	elseif latest and g.newsSeen ~= latest then
		Guide.News(false)
	end
end

-- Whether the welcome hasn't been answered yet (the plugin's own first-launch questions wait for it).
function Guide.Welcoming()
	local db = spec and spec.db()
	return not (type(db) == "table" and type(db.guide) == "table" and db.guide.welcomed)
end

function Guide.Setup(s)
	spec = s
	local f = CreateFrame("Frame")
	f:RegisterEvent("ADDON_LOADED")
	f:RegisterEvent("PLAYER_LOGIN")
	f:RegisterEvent("PLAYER_REGEN_DISABLED")
	f:SetScript("OnEvent", function(_, event, name)
		if event == "ADDON_LOADED" then
			if name == ADDON then
				spec.wasExisting = spec.existing and spec.existing() or false
				-- (A new reset token: the welcome and every tour once more, for everyone. Before any
				-- tour can be offered this session.)
				local g = G()
				if spec.reset and g.reset ~= spec.reset then
					g.reset = spec.reset
					g.welcomed = nil
					g.tours = {}
					spec.wasExisting = false
				end
				f:UnregisterEvent("ADDON_LOADED")
			end
		elseif event == "PLAYER_LOGIN" then
			C_Timer.After(4, Greet)
		elseif S then
			Finish(nil)   -- (a fight: put everything back at once, the tour runs again another time)
		end
	end)
end

-- The options card: Retake Tour, What's new, and Revert (when there's something to go back to).
function Guide.HelpGroup()
	local items = {
		{ type = "button", label = L["Retake Tour"], text = L["Start"],
		  desc = L["Shows the tour again from its first step."],
		  func = function() StartTour() end },
		{ type = "button", label = L["What's New"], text = L["Show"],
		  desc = L["The changes in the latest versions."],
		  func = function() Guide.News(true) end },
	}
	-- (Hidden while there's nothing to go back to: an addon that isn't loaded.)
	local r = spec and spec.revert
	if type(r) == "table" and type(r.label) == "string" and type(r.fn) == "function" then
		items[#items + 1] = { type = "button", label = r.label, text = r.text or L["Revert"], confirm = true,
			desc = r.desc or L["Gives back what this plugin took over, as it was before."], func = r.fn,
			hidden = r.available and function() return not r.available() end or nil }
	end
	return { label = L["Help"], items = items }
end
