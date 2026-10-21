--[[
	MoveRules: the pure decisions around the player's moves (no instances:
	the caller reads the values and passes them in, so Lune tests cover
	every rule). The server (MoveService) and the client (MoveController)
	share them.

	  encode / decode       the character attribute "<Name>:<seq>"
	  clientAllowed(name)   the Net "Move" whitelist (MoveConfig.ClientMoves)
	  canPlay(last, now, gap)  a move again only after its MinGap
	  replaces(running, finished, incoming)  Priority: a shrug or a wave
	                        never cuts a throw or a celebration short
	  loopFor(carry, loop)  the loop a character plays (the server's MoveLoop
	                        first: Spray, Hammer; else Carry while carrying)
	  blocked(...)          no moves while seated, swimming, climbing,
	                        ragdolled, dead, on a hoverboard or (your own
	                        character) in a close-up camera
	  visible(distance, onScreen)  in range (MoveConfig.Range) and on screen
	  substitute(name, reducedMotion)  the calmer move for Reduce Motion
	  forClean / forCapsule / forProgress / bigSell   which celebration a
	                        server result earns (nil = none)
]]

local MoveConfig = require(script.Parent.Parent.Config.MoveConfig)
local Rarity = require(script.Parent.Parent.Config.Rarity)

local MoveRules = {}

MoveRules.MaxSeq = 999999

function MoveRules.encode(name: string, seq: number): string
	return name .. ":" .. tostring(seq)
end

-- (name, seq) of a known move, or nil for anything else.
function MoveRules.decode(value: any): (string?, number?)
	if type(value) ~= "string" or #value > MoveConfig.MaxNameLength + 8 then
		return nil, nil
	end
	local name, digits = string.match(value, "^(%a+):(%d+)$")
	if not name or not digits or not MoveConfig.Moves[name] then
		return nil, nil
	end
	return name, tonumber(digits)
end

-- The next sequence number (1..MaxSeq, then 1 again).
function MoveRules.nextSeq(seq: number): number
	return seq % MoveRules.MaxSeq + 1
end

function MoveRules.clientAllowed(name: any): boolean
	return type(name) == "string" and MoveConfig.ClientMoves[name] == true and MoveConfig.Moves[name] ~= nil
end

function MoveRules.canPlay(lastAt: number?, now: number, minGap: number): boolean
	return lastAt == nil or now - lastAt >= minGap
end

-- May `incoming` take the slot from `running` (nil or finished = free)?
function MoveRules.replaces(running: MoveConfig.Move?, finished: boolean, incoming: MoveConfig.Move): boolean
	return running == nil or finished or incoming.Priority >= running.Priority
end

function MoveRules.loopFor(carryCount: any, loopName: any): string?
	if type(loopName) == "string" then
		local move = MoveConfig.Moves[loopName]
		if move and move.Loop then
			return loopName
		end
	end
	if type(carryCount) == "number" and carryCount == carryCount and carryCount > 0 then
		return "Carry"
	end
	return nil
end

-- Humanoid states (Enum.HumanoidStateType names) that own the body: no moves.
MoveRules.BlockedStates = {
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

function MoveRules.blocked(stateName: string?, sitting: boolean, riding: boolean, closeUp: boolean, health: number?): boolean
	if sitting or riding or closeUp then
		return true
	end
	if health ~= nil and health <= 0 then
		return true
	end
	return stateName ~= nil and MoveRules.BlockedStates[stateName] == true
end

function MoveRules.visible(distance: number, onScreen: boolean): boolean
	return onScreen and distance == distance and distance <= MoveConfig.Range
end

function MoveRules.substitute(name: string, reducedMotion: boolean): string
	if reducedMotion then
		return MoveConfig.ReducedMotion[name] or name
	end
	return name
end

---------------------------------------------------------------- celebrations (server results)

local function order(rarityId: any): number
	local info = if type(rarityId) == "string" then Rarity.ById[rarityId] else nil
	return if info then info.Order else 0
end

local function big(rarityId: any): boolean
	return order(rarityId) >= order(MoveConfig.BigFrom)
end

-- A cleaned ore: Legendary+ -> BigCelebrate, else a new ore or a Flawless grade -> Celebrate.
function MoveRules.forClean(rarityId: string?, grade: string?, isNew: boolean): string?
	if big(rarityId) then
		return "BigCelebrate"
	end
	if isNew or grade == "Flawless" then
		return "Celebrate"
	end
	return nil
end

-- Golems woken from a capsule (their rarities): any Legendary+ -> BigCelebrate.
function MoveRules.forCapsule(rarities: { string }): string?
	for _, rarityId in rarities do
		if big(rarityId) then
			return "BigCelebrate"
		end
	end
	return nil
end

export type Progress = { Blaster: number, Rebirths: number }

-- The save changed: a higher blaster level (forged or bought) or one more rebirth -> BigCelebrate.
-- No `before` (the save just loaded) never celebrates.
function MoveRules.forProgress(before: Progress?, after: Progress): string?
	if not before then
		return nil
	end
	if after.Rebirths > before.Rebirths then
		return "BigCelebrate"
	end
	if after.Blaster > before.Blaster and after.Rebirths == before.Rebirths then
		return "BigCelebrate"
	end
	return nil
end

-- Items sold together at Tobin's (one batch): enough of them -> CashToss.
function MoveRules.bigSell(count: number): boolean
	return count >= MoveConfig.BigSell.Items
end

return MoveRules
