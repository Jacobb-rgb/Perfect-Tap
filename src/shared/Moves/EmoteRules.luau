--[[
	EmoteRules: the pure decisions around the emotes (Config/EmoteConfig;
	owner 2026-10-21: "add the emotes"). No instances: the server
	(EmoteService), the client (MoveController, EmoteController) and the
	Lune tests share them.

	  allowed(name)            the Net "Emote" whitelist: EmoteConfig.List only
	  encode / decode          the character attribute "Emote" = "<Name>:<seq>"
	                           ("" or nil = no emote)
	  blocked(state)           why an emote can't START now (nil = it can):
	                           carrying ore, cleaning, building / a close-up,
	                           on a hoverboard, seated, dead
	  toolOk(name, blaster)    the Blaster Spin needs the blaster in hand
	  moving(speed, state)     the character moves / jumps: a playing emote stops
	  stopReason(name, s)      why a PLAYING emote stops (nil = it plays on):
	                           moving, seated, riding, a tool picked up (or the
	                           blaster put away for the Blaster Spin), firing,
	                           a panel opening
	  canPlay(last, now, gap)  the per-emote cooldown (Cooldown on the client,
	                           the shorter ServerCooldown on the server)
	Reduce Motion keeps the emotes (the player picked them).
]]

local EmoteConfig = require(script.Parent.Parent.Config.EmoteConfig)

local EmoteRules = {}

EmoteRules.Attribute = "Emote" -- character attribute, server-set only
EmoteRules.MaxName = 24
EmoteRules.MaxSeq = 999999
EmoteRules.Cooldown = 1.0 -- seconds before the same emote may start again (the client's menu)
-- the server's own gap: a little shorter, so packets that arrive closer together than they were
-- sent (network jitter) never refuse an emote the client already shows
EmoteRules.ServerCooldown = 0.85
EmoteRules.MoveSpeed = 0.1 -- Humanoid.MoveDirection magnitude that counts as moving
EmoteRules.NeedsBlaster = "Hold your blaster" -- the menu's note on a tool emote
EmoteRules.BlasterTool = "Blaster" -- the held blaster Tool's name (ToolService)

-- Humanoid states (Enum.HumanoidStateType names) in which a playing emote stops.
EmoteRules.StopStates = {
	Jumping = true,
	Freefall = true,
	Seated = true,
	Swimming = true,
	Climbing = true,
	Ragdoll = true,
	FallingDown = true,
	GettingUp = true,
	Physics = true,
	PlatformStanding = true,
	Dead = true,
} :: { [string]: boolean }

function EmoteRules.allowed(name: any): boolean
	return type(name) == "string" and EmoteConfig.Emotes[name] ~= nil and table.find(EmoteConfig.List, name) ~= nil
end

function EmoteRules.encode(name: string, seq: number): string
	return name .. ":" .. tostring(seq)
end

function EmoteRules.decode(value: any): (string?, number?)
	if type(value) ~= "string" or value == "" or #value > EmoteRules.MaxName + 8 then
		return nil, nil
	end
	local name, digits = string.match(value, "^(%a+):(%d+)$")
	if not name or not digits or not EmoteRules.allowed(name) then
		return nil, nil
	end
	return name, tonumber(digits)
end

function EmoteRules.nextSeq(seq: number): number
	return seq % EmoteRules.MaxSeq + 1
end

function EmoteRules.canPlay(lastAt: number?, now: number, gap: number): boolean
	return lastAt == nil or now - lastAt >= gap
end

export type StartState = {
	Carrying: boolean?,
	Cleaning: boolean?,
	Building: boolean?, -- build mode or another close-up holding the character (client)
	Riding: boolean?,
	Seated: boolean?,
	Dead: boolean?,
}

-- Why an emote can't start now (nil = it can).
function EmoteRules.blocked(s: StartState): string?
	if s.Dead then
		return "Dead"
	elseif s.Carrying then
		return "Carrying"
	elseif s.Cleaning then
		return "Cleaning"
	elseif s.Building then
		return "Building"
	elseif s.Riding then
		return "Riding"
	elseif s.Seated then
		return "Seated"
	end
	return nil
end

function EmoteRules.needsTool(name: string): boolean
	local move = EmoteConfig.Emotes[name]
	return move ~= nil and move.NeedsTool == true
end

-- May `name` play with (or without) the blaster in hand?
function EmoteRules.toolOk(name: string, holdingBlaster: boolean): boolean
	return not EmoteRules.needsTool(name) or holdingBlaster
end

function EmoteRules.moving(speed: number, stateName: string?): boolean
	if speed == speed and speed > EmoteRules.MoveSpeed then
		return true
	end
	return stateName == "Jumping" or stateName == "Freefall"
end

export type PlayState = {
	Speed: number,
	State: string?,
	Seated: boolean?,
	Riding: boolean?,
	Tool: boolean?, -- any tool in hand
	Blaster: boolean?, -- the blaster in hand
	Firing: boolean?,
	Panel: boolean?, -- a menu panel opened (your own character)
	Carrying: boolean?,
}

-- Why a playing emote stops now (nil = it plays on).
function EmoteRules.stopReason(name: string, s: PlayState): string?
	if EmoteRules.moving(s.Speed, s.State) then
		return "Moving"
	end
	if s.Seated or (s.State ~= nil and EmoteRules.StopStates[s.State]) then
		return "State"
	end
	if s.Riding then
		return "Riding"
	end
	if s.Carrying then
		return "Carrying"
	end
	if EmoteRules.needsTool(name) then
		if not s.Blaster then
			return "NoBlaster"
		end
	elseif s.Tool then
		return "Tool"
	end
	if s.Firing then
		return "Firing"
	end
	if s.Panel then
		return "Panel"
	end
	return nil
end

return EmoteRules
