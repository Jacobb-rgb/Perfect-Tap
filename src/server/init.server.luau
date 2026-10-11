--[[
	Terra Forge server bootstrap.

	Every module in Services/ is a table with optional init() and start().
	init() runs first for all services in ORDER (set up state, remotes),
	then start() runs for each in its own thread (loops, connections).
]]

local Services = script:WaitForChild("Services")

local ORDER = {
	"WorldService",
}

local loaded = {}
for _, name in ORDER do
	local module = Services:FindFirstChild(name)
	if module then
		loaded[name] = require(module) :: any
	else
		warn("[TerraForge] missing service " .. name)
	end
end

for _, name in ORDER do
	local service = loaded[name]
	if service and service.init then
		local ok, err = pcall(service.init)
		if not ok then
			warn(`[TerraForge] {name}.init failed: {err}`)
		end
	end
end

for _, name in ORDER do
	local service = loaded[name]
	if service and service.start then
		task.spawn(function()
			local ok, err = pcall(service.start)
			if not ok then
				warn(`[TerraForge] {name}.start failed: {err}`)
			end
		end)
	end
end

print("[TerraForge] server ready")
