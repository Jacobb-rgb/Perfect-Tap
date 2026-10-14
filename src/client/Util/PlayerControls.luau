--[[
	PlayerControls: one shared movement lock for close-ups that take over
	the character (build mode, the anvil).

	  if PlayerControls.claim("Build") then
	      PlayerControls.set(false)
	      ...
	      PlayerControls.set(true)
	      PlayerControls.release("Build")
	  end

	claim() fails while someone else holds the lock. The Cleaning Station
	has its own lock, so callers also check CleaningController.isActive().
	release() only frees the claim; turn the controls back on with set(true).
]]

local Players = game:GetService("Players")

local PlayerControls = {}

local player = Players.LocalPlayer
local holder: string? = nil
local controls: any = nil

-- The default PlayerModule's controls object (inserted by Roblox at
-- runtime, so not a static path). Cached once found.
local function getControls(): any
	if controls then
		return controls
	end
	local ok, module = pcall(function()
		local playerModule = player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule", 5)
		local requireAny: any = require
		return if playerModule then requireAny(playerModule) else nil
	end)
	if ok and module then
		local okControls, result = pcall(function()
			return (module :: any):GetControls()
		end)
		if okControls then
			controls = result
		end
	end
	return controls
end

-- Turns walking/jumping input on or off (may wait up to 5 s for the PlayerModule).
function PlayerControls.set(enabled: boolean)
	local current = getControls()
	if not current then
		return
	end
	if enabled then
		current:Enable()
	else
		current:Disable()
	end
end

-- Takes the lock for `name`. True if it was free or already `name`'s.
function PlayerControls.claim(name: string): boolean
	if holder == nil or holder == name then
		holder = name
		return true
	end
	return false
end

-- Frees the lock if `name` holds it.
function PlayerControls.release(name: string)
	if holder == name then
		holder = nil
	end
end

-- Who holds the lock right now, if anyone.
function PlayerControls.owner(): string?
	return holder
end

return PlayerControls
