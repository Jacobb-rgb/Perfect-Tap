--[[
	Holds the latest snapshot of the player's own data sent by StateService.
	StateController.get() -> snapshot or nil (not loaded yet)
	StateController.onChanged(fn) -> fn(snapshot) on every update
	Every snapshot listeners see is whole. The server sends only the
	sections that changed (StateService, perf pass 1), so merge() fills in
	the rest from the previous snapshot:
	- a missing section is unchanged (kept from the previous snapshot);
	- snapshot.Removed lists sections that are gone;
	- snapshot.Patch[section] = { Set, Clear } changes a few keys of a flat
	  section (the previous one is copied, never changed);
	- snapshot.Full (the first push after a join) replaces everything;
	- snapshot.Kept (steps 6-7) lists sticky records left out: copied too.
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

-- The whole snapshot after `incoming` (a push from StateService) arrives on
-- top of `previous` (nil: none yet). `incoming` loses its Full / Kept /
-- Removed / Patch keys; `previous` is not changed.
function StateController.merge(previous: { [string]: any }?, incoming: { [string]: any }): { [string]: any }
	local full = incoming.Full == true
	local kept = incoming.Kept
	local removed = incoming.Removed
	local patch = incoming.Patch
	incoming.Full = nil
	incoming.Kept = nil
	incoming.Removed = nil
	incoming.Patch = nil
	if full or not previous then
		return incoming
	end
	local merged = table.clone(previous)
	for key, value in incoming do
		merged[key] = value
	end
	if type(patch) == "table" then
		for key, change in patch do
			if type(key) == "string" and type(change) == "table" and incoming[key] == nil then
				local base = previous[key]
				local section = if type(base) == "table" then table.clone(base) else {}
				if type(change.Set) == "table" then
					for k, v in change.Set do
						section[k] = v
					end
				end
				if type(change.Clear) == "table" then
					for _, k in change.Clear do
						section[k] = nil
					end
				end
				merged[key] = section
			end
		end
	end
	if type(removed) == "table" then
		for _, key in removed do
			if type(key) == "string" and incoming[key] == nil then
				merged[key] = nil
			end
		end
	end
	-- steps 6-7: sticky records the server left out (already copied above,
	-- unless a Removed entry named one by mistake)
	if type(kept) == "table" then
		for _, key in kept do
			if type(key) == "string" and incoming[key] == nil then
				merged[key] = previous[key]
			end
		end
	end
	return merged
end

function StateController.init()
	Net.listen("State", function(newSnapshot)
		if type(newSnapshot) ~= "table" then
			return
		end
		local merged = StateController.merge(snapshot, newSnapshot)
		snapshot = merged
		for _, callback in listeners do
			task.spawn(callback, merged)
		end
	end)
end

return StateController
