-- A newer version out? Each copy of this plugin tells the others in your guild and your group
-- which version it is (an addon message, never seen in chat), at login and when you join a group.
-- Hearing a newer one, it says so once a session in chat; hearing an older one, it answers with its
-- own a moment later, so the news gets round. "Tell me when a newer version is out" (on the
-- plugin's first options page) turns it off: then nothing is sent or heard.
-- The same file in each of the Daylight plugins; only PREFIX differs. A copy run from its source
-- folder (its version still "@project-version@") stays quiet.
-- luacheck: read globals C_AddOns C_ChatInfo LE_PARTY_CATEGORY_INSTANCE LE_PARTY_CATEGORY_HOME
-- luacheck: read globals IsInRaid IsInGroup IsInGuild InCombatLockdown GetTime C_Timer CreateFrame
local ADDON, ns = ...

local PREFIX = "DaylightFish"            -- the addon message prefix (16 characters at most)
local DB_NAME = ADDON .. "DB"            -- the plugin's saved variables (the switch lives there)
local L = ns.L or setmetatable({}, { __index = function(_, k) return k end })

local Meta = (C_AddOns and C_AddOns.GetAddOnMetadata) or _G.GetAddOnMetadata

-- "1.6.11" (a release's "v1.6.11" too) as { 1, 6, 11 }; nil for anything else.
local function Parts(v)
	if type(v) ~= "string" then return nil end
	local a, b, c = v:match("^v?(%d+)%.(%d+)%.(%d+)$")
	if a then return { tonumber(a), tonumber(b), tonumber(c) } end
end

local function Newer(a, b)
	local x, y = Parts(a), Parts(b)
	if not x or not y then return false end
	for i = 1, 3 do
		if x[i] ~= y[i] then return x[i] > y[i] end
	end
	return false
end


local function On()
	local db = _G[DB_NAME]
	return not (type(db) == "table" and db.updateCheck == false)
end

-- The switch, for the plugin's first options page (its own saved variables: no default needed).
function ns.UpdateGroup()
	return { label = L["Updates"], items = {
		{ type = "toggle", label = L["Tell me when a newer version is out"],
		  desc = L["Your copy tells others in your guild and group which version it is, and you hear about a newer one (once a session). Off: nothing is sent or heard."],
		  get = function() return On() end,
		  set = function(v)
			local db = _G[DB_NAME]
			if type(db) ~= "table" then
				db = {}
				_G[DB_NAME] = db
			end
			db.updateCheck = v and nil or false
		  end },
	} }
end

local mine = Meta and Meta(ADDON, "Version")
if not Parts(mine) then return end
mine = mine:gsub("^v", "")

local Chat = _G.C_ChatInfo
if not (Chat and Chat.SendAddonMessage and Chat.RegisterAddonMessagePrefix) then return end
pcall(Chat.RegisterAddonMessagePrefix, PREFIX)

local sentAt, waiting, told = {}, {}, false

local function Say(channel)
	if not channel or not On() then return end
	-- (Out of a fight only: addon messages can be held back there.)
	if InCombatLockdown() then
		waiting[channel] = true
		return
	end
	local now = GetTime()
	if sentAt[channel] and now - sentAt[channel] < 60 then return end
	sentAt[channel] = now
	pcall(Chat.SendAddonMessage, PREFIX, "V\t" .. mine, channel)
end

-- The group's channel: a raid, a party, or the dungeon finder's group (its own chat).
local function GroupChannel()
	local inst, home = LE_PARTY_CATEGORY_INSTANCE, LE_PARTY_CATEGORY_HOME
	if IsInRaid() then
		return (inst and IsInRaid(inst) and not IsInRaid(home)) and "INSTANCE_CHAT" or "RAID"
	end
	if IsInGroup() then
		return (inst and IsInGroup(inst) and not IsInGroup(home)) and "INSTANCE_CHAT" or "PARTY"
	end
end

local ANSWER = { GUILD = true, PARTY = true, RAID = true, INSTANCE_CHAT = true }
local secret = _G.issecretvalue

local function Heard(prefix, text, channel)
	if secret and (secret(prefix) or secret(text) or secret(channel)) then return end
	if prefix ~= PREFIX or type(text) ~= "string" or not On() then return end
	local v = text:match("^V\t(%d+%.%d+%.%d+)$")
	if not v then return end
	if Newer(v, mine) then
		if not told then
			told = true
			local title = (Meta and Meta(ADDON, "Title")) or ADDON
			print(title .. ": " .. string.format(L["A newer version is out (%s): update through CurseForge or WowUp."], v))
		end
	elseif Newer(mine, v) and ANSWER[channel] then
		-- (Theirs is older: ours back, a moment later, so not everyone answers at once.)
		C_Timer.After(1 + math.random() * 4, function() Say(channel) end)
	end
end

local grouped = false
local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("GROUP_ROSTER_UPDATE")
f:RegisterEvent("PLAYER_REGEN_ENABLED")
f:RegisterEvent("CHAT_MSG_ADDON")
f:SetScript("OnEvent", function(_, event, a, b, c)
	if event == "CHAT_MSG_ADDON" then
		pcall(Heard, a, b, c)
	elseif event == "PLAYER_LOGIN" then
		C_Timer.After(15, function()
			if IsInGuild() then Say("GUILD") end
			Say(GroupChannel())
		end)
	elseif event == "GROUP_ROSTER_UPDATE" then
		local now = GroupChannel() ~= nil
		if now and not grouped then C_Timer.After(3, function() Say(GroupChannel()) end) end
		grouped = now
	elseif event == "PLAYER_REGEN_ENABLED" then
		for channel in pairs(waiting) do
			waiting[channel] = nil
			Say(channel)
		end
	end
end)
