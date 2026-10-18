--[[
	Holds the latest snapshot of the player's own data sent by StateService.
	StateController.get() -> snapshot or nil (not loaded yet)
	StateController.onChanged(fn) -> fn(snapshot) on every update
	StateController.sellMult() -> the player's sell bonus (State.Bonuses.SellMult, 1 without)
	Every snapshot is whole: keys the server left out because they didn't
	change (snapshot.Kept, see StateService) are copied from the previous one.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))

local StateController = {}

local snapshot: { [string]: any }? = nil
local listeners: { ({ [string]: any }) -> () } = {}

function StateController.get(): { [string]: any }?
	return snapshot
end

-- The player's sell bonus (State.Bonuses.SellMult: Midas, SellValue golems,
-- collections), 1 when none or not loaded: coin numbers the client shows
-- for sales are base x this, rounded like Bonuses.sellAmount.
function StateController.sellMult(): number
	local bonuses = if snapshot then snapshot.Bonuses else nil
	local mult = if type(bonuses) == "table" then bonuses.SellMult else nil
	return if type(mult) == "number" and mult == mult and mult >= 1 and mult < math.huge then mult else 1
end

function StateController.onChanged(callback: ({ [string]: any }) -> ())
	table.insert(listeners, callback)
	if snapshot then
		task.spawn(callback, snapshot)
	end
end

function StateController.init()
	Net.listen("State", function(newSnapshot)
		if type(newSnapshot) ~= "table" then
			return
		end
		-- records the server left out because they didn't change (StateService.trim)
		local kept = newSnapshot.Kept
		newSnapshot.Kept = nil
		local previous = snapshot
		if type(kept) == "table" and previous then
			for _, key in kept do
				if type(key) == "string" and newSnapshot[key] == nil then
					newSnapshot[key] = previous[key]
				end
			end
		end
		snapshot = newSnapshot
		for _, callback in listeners do
			task.spawn(callback, newSnapshot)
		end
	end)
end

return StateController
