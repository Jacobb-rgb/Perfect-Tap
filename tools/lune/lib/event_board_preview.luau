--[[
	The big iron billboard showing a page, for the owner's pictures (scene
	eventboard_<page> of tools/lune/export_scene.luau): find, nobody, weather.
	The world export draws one text per part, so here each line of the game's
	one SurfaceGui (UI/EventBoardView) gets a see-through part of its own.
]]

local Preview = {}

local NOW = 1_794_000_000

function Preview.dress(Loader: any, map: any, page: string)
	local roblox = Loader.roblox
	local EventBoardLogic = Loader.requirePath("ReplicatedStorage.Shared.Events.EventBoardLogic")
	local FindOfDay = Loader.requirePath("ReplicatedStorage.Shared.Events.FindOfDay")
	local Theme = Loader.requirePath("ReplicatedStorage.Shared.Config.UITheme")
	local screen: any = nil
	for _, d in map:GetDescendants() do
		if d:IsA("BasePart") and d:HasTag("EventBoardScreen") then
			screen = d
		end
	end
	assert(screen, "no EventBoardScreen")
	local find = { Day = FindOfDay.day(NOW), UserId = 45, Name = "EmberQueen", Ore = "RainbowNova", Grade = "Flawless" } -- (a secret: owner "Ano, ukazovat")
	-- a real storm of the schedule, a minute in
	local WeatherLogic = Loader.requirePath("ReplicatedStorage.Shared.Weather.WeatherLogic")
	local WeatherConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.WeatherConfig")
	local storm = NOW
	for slot = math.floor(NOW / WeatherConfig.Schedule.Slot), math.floor(NOW / WeatherConfig.Schedule.Slot) + 500 do
		local event = WeatherLogic.event(slot)
		if event and event.Kind == "Storm" then
			storm = event.Start + 60
			break
		end
	end
	local shown = if page == "weather"
		then EventBoardLogic.weatherPage(storm, nil)
		elseif page == "nobody" then EventBoardLogic.findPage(nil, NOW)
		else EventBoardLogic.findPage(find, NOW)
	local function line(y: number, height: number, text: string, color: any, widthShare: number)
		local size = screen.Size
		local part = roblox.Instance.new("Part")
		part.Anchored = true
		part.Transparency = 0.98 -- (the export leaves out anything clearer)
		part.Size = roblox.Vector3.new(size.X * widthShare, size.Y * height, 0.02)
		part.CFrame = screen.CFrame * roblox.CFrame.new(0, size.Y * (0.5 - y - height / 2), -0.09)
		part.Parent = map
		local gui = roblox.Instance.new("SurfaceGui")
		gui.Face = roblox.Enum.NormalId.Front
		gui.LightInfluence = 0
		gui.Parent = part
		local label = roblox.Instance.new("TextLabel")
		label.FontFace = Theme.TitleFont
		label.Text = text
		label.TextColor3 = color
		label.Size = roblox.UDim2.fromScale(1, 1)
		label.Parent = gui
	end
	line(0.08, 0.2, shown.Title, shown.Color, 0.9)
	line(0.34, 0.32, shown.Big, shown.BigColor or roblox.Color3.new(1, 1, 1), 0.9)
	line(0.72, 0.16, shown.Small, roblox.Color3.new(1, 1, 1), 0.9)
end

return Preview
