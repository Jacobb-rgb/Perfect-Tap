--[[
	GolemService: the player's golem pets (step 7, GolemConfig).

	- GolemAction (Net, rate limited), every request read gets one
	  ActionResult { Action = "Golem", Op, Ok, Reason? (GolemConfig.Reasons),
	  Id?, Count? (golems deleted) }:
	    "Equip"     { Id }              into the first free slot (3 slots)
	    "Unequip"   { Id }
	    "EquipBest" (no arg)            the 3 best owned golems
	    "Lock"      { Id, Locked }      a locked golem is never deleted
	    "Delete"    { Ids = { Id } }    1..GolemConfig.MaxDelete ids; locked
	                                    golems and golems of unknown kinds are
	                                    skipped (they stay, and stay equipped)
	  The writes go through GolemConfig's pure helpers (the same ones the
	  capsules, the wheel and step 8 receipts use), with no yield between the
	  check and the write; every change ends with DataService.changed.
	- Followers: the player attribute GolemConfig.EquippedAttribute
	  ("EquippedGolems" = "KindA,KindB,KindC", GolemConfig.equippedKinds) is
	  kept in step with the save (on load and after every save change, set
	  only when it differs). Clients build and animate the followers from it
	  (GolemController): the server replicates no golem parts.
	- Bonuses: the equipped golems' bonuses are a Bonuses provider ("Golems",
	  src/server/Bonuses.luau); DataService.changed drops the cached totals,
	  so mining, walking (CarryService), selling and the podium income
	  (EconomyService income bonus "Bonuses") follow at once.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GolemConfig = require(Shared.Config.GolemConfig)
local Net = require(Shared.Net)
local Guard = require(script.Parent.Parent.Guard)
local DataService = require(script.Parent.DataService)

local GolemService = {}

export type Answer = { Action: string, Op: string, Ok: boolean, Reason: string?, Id: number?, Count: number? }

local MAX_PAYLOAD = 4
local MAX_ID = 2 ^ 53

local function answer(player: Player, op: string, ok: boolean, reason: string?, id: number?, count: number?)
	local payload: Answer = { Action = "Golem", Op = op, Ok = ok, Reason = reason, Id = id, Count = count }
	Net.fire("ActionResult", player, payload)
end

-- The player's golem record, made whole first (writers only).
local function record(data: { [string]: any }): { [string]: any }
	local golems = data.Golems
	if type(golems) ~= "table" then
		golems = { Owned = {}, Equipped = {}, NextId = 1 }
		data.Golems = golems
	end
	return golems
end

-- Sets the followers attribute from the save (only when it differs).
function GolemService.refresh(player: Player)
	local data = DataService.get(player)
	local kinds = if data then GolemConfig.equippedKinds(data.Golems) else ""
	if player:GetAttribute(GolemConfig.EquippedAttribute) ~= kinds then
		player:SetAttribute(GolemConfig.EquippedAttribute, kinds)
	end
end

--[[
	Runs one GolemAction for the player. Returns (ok, reason?, id?, count?)
	without answering (the request handler answers). Changes the save only
	on success.
]]
function GolemService.act(player: Player, op: string, arg: any): (boolean, string?, number?, number?)
	local data = DataService.get(player)
	if not data then
		return false, "BadGolem", nil, nil
	end
	local args = Guard.table(arg, MAX_PAYLOAD)
	if op == "Equip" or op == "Unequip" or op == "Lock" then
		local id = if args then Guard.integer(args.Id, 1, MAX_ID) else nil
		if not id then
			return false, if op == "Unequip" then "NotEquipped" else "BadGolem", nil, nil
		end
		if not GolemConfig.find(data.Golems, id) then
			return false, "BadGolem", id, nil
		end
		local golems = record(data)
		local ok: boolean, reason: string?
		if op == "Equip" then
			ok, reason = GolemConfig.equip(golems, id)
		elseif op == "Unequip" then
			ok, reason = GolemConfig.unequip(golems, id)
		else
			ok, reason = GolemConfig.setLocked(golems, id, if args then args.Locked else nil)
		end
		return ok, reason, id, nil
	elseif op == "EquipBest" then
		GolemConfig.equipBest(record(data))
		return true, nil, nil, nil
	elseif op == "Delete" then
		local ids = if args then Guard.table(args.Ids, GolemConfig.MaxDelete) else nil
		if not ids then
			return false, "BadIds", nil, nil
		end
		local removed, reason = GolemConfig.delete(record(data), ids)
		if reason then
			return false, reason, nil, nil
		end
		if removed == 0 then
			return false, "BadIds", nil, 0 -- only locked or unknown golems named
		end
		return true, nil, nil, removed
	end
	return false, "BadGolem", nil, nil
end

-- GolemAction (action, arg): see the header.
local function onGolemAction(player: Player, action: any, arg: any)
	local op = Guard.string(action, 16) or ""
	local ok, reason, id, count = GolemService.act(player, op, arg)
	if ok then
		DataService.changed(player)
		GolemService.refresh(player)
	end
	answer(player, op, ok, reason, id, count)
end

-- Internals for the Lune tests only.
GolemService._test = {
	action = onGolemAction,
}

function GolemService.init()
	Net.on("GolemAction", onGolemAction)
	DataService.onLoaded(function(player: Player)
		GolemService.refresh(player)
	end)
	-- capsules, the wheel, receipts and Migrations change golems too
	DataService.onChanged(GolemService.refresh)
end

return GolemService
