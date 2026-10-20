-- The HALL OF FAME champions (owner 2026-10-20) under Lune: the giant hall has a pedestal
-- per board; ChampionService stands each board's #1 there (only a new #1 rebuilds the
-- avatar, a board without players clears it, a failed avatar keeps the old one), dressed
-- as a harmless statue the client makes hop (tag Spin, Hop). Avatars and tags are fakes.
return function(T, Loader)
	local roblox = require("@lune/roblox") :: any
	local task = require("@lune/task") :: any
	local Instance = roblox.Instance
	local Vector3 = roblox.Vector3
	local CFrame = roblox.CFrame
	local ChampionService = Loader.requirePath("ServerScriptService.Server.Services.ChampionService")

	local function fakeHall(): (any, { any })
		local hall = Instance.new("Model")
		hall.Name = "HallOfFame"
		local list = {}
		for i = 1, 4 do
			local pedestal = Instance.new("Part")
			pedestal.Name = "Champion" .. i
			pedestal.Size = Vector3.new(0.5, 2.6, 2.6)
			pedestal.CFrame = CFrame.new(i * 5, 12, 0)
			pedestal:SetAttribute("Board", i)
			pedestal.Parent = hall
			table.insert(list, pedestal)
			local board = Instance.new("Part")
			board.Name = "Board" .. i
			board.CFrame = CFrame.lookAt(Vector3.new(i * 5, 5, 0), Vector3.new(i * 5, 5, -10))
			board.Parent = hall
		end
		return hall, list
	end

	local function avatar(userId: number): any
		local model = Instance.new("Model")
		model.Name = "Player" .. userId
		local root = Instance.new("Part")
		root.Name = "HumanoidRootPart"
		root.Size = Vector3.new(2, 2, 1)
		root.Parent = model
		local head = Instance.new("Part")
		head.Name = "Head"
		head.Parent = model
		model.PrimaryPart = root
		return model
	end

	local function tops(firsts: { number }): any
		local LeaderboardConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.LeaderboardConfig")
		local out = {}
		for i, board in LeaderboardConfig.Boards do
			local id = firsts[i] or 0
			out[board.Id] = { Rows = if id ~= 0 then { { UserId = id, Name = "P" .. id, Value = 1 } } else {}, Ready = true }
		end
		return out
	end

	T.test("Champions: the stand spot sits on the pedestal and faces out of the hall", function()
		local _, list = fakeHall()
		local cf = ChampionService.standCFrame(list[1], 5, Vector3.new(0, 0, -1))
		T.near(cf.Position.Y, 12 + 0.25 + 2.5, 1e-6, "feet on the pedestal top")
		T.near(cf.LookVector.Z, -1, 1e-6, "faces the plaza")
	end)

	T.test("Champions: a new #1 gets an avatar, the same #1 is never rebuilt, an empty board clears", function()
		local _, list = fakeHall()
		local built = {}
		ChampionService._test.reset()
		ChampionService._test.setPedestals(function()
			return list
		end)
		ChampionService._test.setMaker(function(userId)
			table.insert(built, userId)
			return if userId == 666 then nil else avatar(userId)
		end)
		local ok, err = pcall(function()
			ChampionService.update(tops({ 11, 22, 0, 666 }))
			task.wait()
			T.eq(ChampionService._test.standing(1), 11, "board 1: its #1")
			T.eq(ChampionService._test.standing(2), 22, "board 2")
			T.eq(ChampionService._test.standing(3), 0, "no players: nobody")
			T.eq(ChampionService._test.standing(4), 0, "no avatar: tried again next time")
			local model = list[1].Parent:FindFirstChild("ChampionAvatar1")
			T.truthy(model, "standing in the hall")
			T.eq(model:GetAttribute("Hop"), true, "the client makes it hop")
			T.eq(model:GetAttribute("SpinSpeed"), 0, "no spin")
			for _, d in model:GetDescendants() do
				if d:IsA("BasePart") then
					T.truthy(d.Anchored and not d.CanCollide and not d.CastShadow, d.Name .. " a harmless statue")
				end
			end
			local before = #built
			ChampionService.update(tops({ 11, 22, 0, 0 }))
			task.wait()
			T.eq(#built, before, "the same #1s: nothing rebuilt")
			ChampionService.update(tops({ 33, 0, 0, 0 }))
			task.wait()
			T.eq(ChampionService._test.standing(1), 33, "a new #1")
			T.eq(ChampionService._test.standing(2), 0, "board 2 cleared")
			T.falsy(list[2].Parent:FindFirstChild("ChampionAvatar2"), "its avatar gone")
			-- one player leading three boards: one avatar download, cloned
			local downloads = #built
			ChampionService.update(tops({ 77, 77, 77, 0 }))
			task.wait()
			T.eq(#built, downloads + 1, "one download for three boards")
			for i = 1, 3 do
				T.eq(ChampionService._test.standing(i), 77, "board " .. i)
				T.truthy(list[i].Parent:FindFirstChild("ChampionAvatar" .. i), "an avatar on board " .. i)
			end
			-- a name that arrives after the avatar went up reaches the sign
			local late = tops({ 77, 77, 77, 0 })
			for _, top in late do
				if top.Rows[1] then
					top.Rows[1].Name = "Kuba"
				end
			end
			ChampionService.update(late)
			T.eq(#built, downloads + 1, "no new download for a name")
		end)
		ChampionService._test.reset()
		if not ok then
			error(err, 0)
		end
	end)
end
