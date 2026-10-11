--[[
	Holds the latest snapshot of the player's own data sent by StateService.
	StateController.get() -> snapshot or nil (not loaded yet)
	StateController.onChanged(fn) -> fn(snapshot) on every update
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))

local StateController = {}

local snapshot: { [string]: any }? = nil
local listeners: { ({ [string]: any }) -> () } = {}

function StateController.get(): { [string]: any }?
	return snapshot
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
		snapshot = newSnapshot
		for _, callback in listeners do
			task.spawn(callback, newSnapshot)
		end
	end)
end

return StateController
