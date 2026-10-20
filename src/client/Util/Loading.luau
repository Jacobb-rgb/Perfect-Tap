--[[
	The loading screen's gate (src/first/LoadingScreen.client.luau sets the
	attribute LoadingDone = true on ReplicatedFirst as it fades out or the
	player skips). Popups that should not open under it wait here:

	  if Loading.wait() then ... end   -- true once it is done, false on the time-out

	Never longer than MaxWait seconds, so a broken loading screen can't block
	the game.
]]

local ReplicatedFirst = game:GetService("ReplicatedFirst")

local Loading = {}

Loading.Attribute = "LoadingDone" -- the same name as LoadingConfig.Attribute (tests/LoadingScreen.spec.luau)
Loading.MaxWait = 15

-- the instance carrying the attribute (tests point it at their own)
Loading.target = ReplicatedFirst :: Instance

function Loading.isDone(): boolean
	return Loading.target:GetAttribute(Loading.Attribute) == true
end

-- Yields until the loading screen is done (true) or `maxSeconds` passed (false).
function Loading.wait(maxSeconds: number?): boolean
	if Loading.isDone() then
		return true
	end
	local limit = math.min(maxSeconds or Loading.MaxWait, Loading.MaxWait)
	local thread = coroutine.running()
	local settled = false
	local conn: RBXScriptConnection? = nil
	local function settle(result: boolean)
		if settled then
			return
		end
		settled = true
		if conn then
			conn:Disconnect()
		end
		task.spawn(thread, result)
	end
	conn = Loading.target:GetAttributeChangedSignal(Loading.Attribute):Connect(function()
		if Loading.isDone() then
			settle(true)
		end
	end)
	task.delay(limit, function()
		settle(Loading.isDone())
	end)
	return coroutine.yield()
end

return Loading
