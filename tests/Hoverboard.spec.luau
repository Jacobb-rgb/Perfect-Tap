-- Hoverboards (owner, mine floors point 3): 3 coin boards that get faster, 2 Robux
-- boards that are faster still and have effects; models from parts within budget.
return function(T, Loader)
	local roblox = require("@lune/roblox") :: any
	local HoverboardData = Loader.requirePath("ReplicatedStorage.Shared.Config.HoverboardData")
	local HoverboardBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.HoverboardBuilder")
	local HoverboardFx = Loader.requirePath("ReplicatedStorage.Shared.Builders.HoverboardFx")
	local MonetizationConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.MonetizationConfig")

	local function partsOf(model)
		local list = {}
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") then
				table.insert(list, d)
			end
		end
		return list
	end

	T.test("hoverboards: 3 coin boards then 2 Robux boards, speeds rise", function()
		T.eq(#HoverboardData.List, 5, "board count")
		local coins, robux = 0, 0
		local lastSpeed = HoverboardData.BaseWalkSpeed
		local lastPrice = 0
		for i, board in HoverboardData.List do
			T.eq(board.Order, i, board.Id .. " order")
			T.eq(HoverboardData.get(board.Id), board, board.Id .. " by id")
			T.truthy(board.Speed > lastSpeed, board.Id .. " is faster than the board before (and walking)")
			lastSpeed = board.Speed
			T.truthy(#board.Name > 0 and #board.Description > 0, board.Id .. " has a name and a description")
			T.truthy(#board.Perks > 0, board.Id .. " perks")
			if board.Kind == "Coins" then
				coins += 1
				T.eq(robux, 0, board.Id .. ": coin boards come first")
				T.truthy(type(board.Price) == "number" and board.Price > lastPrice, board.Id .. " costs more than the coin board before")
				lastPrice = board.Price
				T.truthy(board.Effect ~= "None", board.Id .. ": small thruster effects")
				T.falsy(board.IgnoresCarrySlow, board.Id .. " keeps the full carry slowdown")
				T.falsy(HoverboardData.canPrompt(board), board.Id .. " is never prompted for Robux")
			else
				robux += 1
				T.eq(board.Kind, "Robux", board.Id .. " kind")
				T.eq(board.Robux, 49, board.Id .. " costs 49 R$")
				local pass = MonetizationConfig.get(board.PassKey)
				T.truthy(pass ~= nil, board.Id .. " names a game pass in MonetizationConfig")
				T.eq(pass.Kind, "GamePass", board.Id .. " is a game pass (owned forever, never bought twice)")
				T.eq(pass.Grant, "Hoverboard", board.Id .. " pass grant")
				T.eq(pass.BoardId, board.Id, board.Id .. " pass unlocks this board")
				T.eq(pass.Robux, board.Robux, board.Id .. " shown price = the pass price")
				T.truthy(board.IgnoresCarrySlow, board.Id .. " ignores the carry slowdown (owner)")
				T.truthy(board.Effect ~= "None", board.Id .. " has a special effect")
				T.eq(board.Price, nil, board.Id .. " is not sold for coins")
			end
		end
		T.eq(coins, 3, "coin boards")
		T.eq(robux, 2, "Robux boards")
	end)

	T.test("hoverboards: the Robux boards are the fastest", function()
		local fastestCoin, slowestRobux = 0, math.huge
		for _, board in HoverboardData.List do
			if board.Kind == "Coins" then
				fastestCoin = math.max(fastestCoin, board.Speed)
			else
				slowestRobux = math.min(slowestRobux, board.Speed)
			end
		end
		T.lt(fastestCoin, slowestRobux, "every Robux board beats every coin board")
		local expected = math.floor((23 / HoverboardData.BaseWalkSpeed - 1) * 100 + 0.5)
		T.eq(HoverboardData.speedBonus(HoverboardData.ById.TimberDrifter), expected, `23 vs walking {HoverboardData.BaseWalkSpeed}`)
	end)

	T.test("hoverboards: game pass ids live in MonetizationConfig, 0 is never prompted or matched", function()
		T.eq(HoverboardData.byPass(0), nil, "id 0 matches no board")
		T.eq(HoverboardData.byPass("12"), nil, "a string is no pass id")
		T.eq(HoverboardData.byPass(0 / 0), nil, "NaN is no pass id")
		T.falsy(MonetizationConfig.isLive(0), "0 is not live")
		T.falsy(MonetizationConfig.isLive(-5), "negative ids are not live")
		T.falsy(MonetizationConfig.isLive(1.5), "fractions are not live")
		T.falsy(MonetizationConfig.isLive("7"), "strings are not live")
		T.truthy(MonetizationConfig.isLive(7), "a whole id is live")
		T.eq(MonetizationConfig.byId(-5), nil, "negative ids never match")
		T.eq(MonetizationConfig.byId(1.5), nil, "fractions never match")
		T.eq(HoverboardData.get(nil), nil, "nil id")
		T.eq(HoverboardData.get("Nope"), nil, "unknown id")
		local seen = {}
		for key, entry in MonetizationConfig.Entries do
			T.eq(entry.Key, key, key .. " knows its key")
			T.truthy(entry.Kind == "GamePass" or entry.Kind == "Product", key .. " kind")
			if entry.BoardId then
				T.eq(entry.Grant, "Hoverboard", key .. " (a board) is granted by the Hoverboard handler")
				T.eq(entry.Kind, "GamePass", key .. " (a board, owned forever) is a game pass")
			end
			T.truthy(entry.Id == 0 or MonetizationConfig.isLive(entry.Id), key .. " id is 0 or a whole number")
			if entry.Id > 0 then
				T.falsy(seen[entry.Id], key .. " id is unique")
				seen[entry.Id] = true
			end
			T.eq(MonetizationConfig.canPrompt(key), entry.Id > 0, key .. " prompts only with a real id")
		end
		for _, board in HoverboardData.List do
			if board.Kind == "Robux" then
				local id = HoverboardData.passId(board)
				T.eq(HoverboardData.canPrompt(board), id > 0, board.Id .. " prompts only with a real id")
				-- a real id (simulated) matches the board as a pass, never as a product
				local pass = MonetizationConfig.get(board.PassKey)
				local old = pass.Id
				pass.Id = 9000000 + board.Order
				local ok, err = pcall(function()
					T.truthy(HoverboardData.canPrompt(board), board.Id .. " prompts once it has an id")
					T.eq(HoverboardData.byPass(pass.Id), board, board.Id .. " by pass id")
					T.eq(MonetizationConfig.byId(pass.Id, "GamePass"), pass, board.Id .. " is found as a pass")
					T.eq(MonetizationConfig.byId(pass.Id, "Product"), nil, board.Id .. " is never a developer product")
				end)
				pass.Id = old
				if not ok then
					error(err, 0)
				end
			else
				T.eq(HoverboardData.passId(board), 0, board.Id .. " has no pass")
			end
		end
	end)

	T.test("hoverboards: one walk speed formula (carry slowdown, Robux boards ignore it)", function()
		local base, slow, max = HoverboardData.BaseWalkSpeed, HoverboardData.SlowPerItem, HoverboardData.MaxSlow
		T.eq(HoverboardData.walkSpeed(nil, 0), base, "on foot, empty hands")
		T.eq(HoverboardData.walkSpeed("", 4), base - 4 * slow, "on foot, 4 items")
		T.eq(HoverboardData.walkSpeed(nil, 1000), base - max, "on foot never below base - MaxSlow")
		T.eq(HoverboardData.walkSpeed(nil, 1000), 13, "on foot never below 13 (the old CarryService floor)")
		T.eq(HoverboardData.walkSpeed("Nope", 0), base, "an unknown board is walking")
		T.eq(HoverboardData.walkSpeed(nil, -3), base, "negative counts are ignored")
		T.eq(HoverboardData.walkSpeed(nil, 0 / 0), base, "NaN counts are ignored")
		for _, board in HoverboardData.List do
			T.eq(HoverboardData.walkSpeed(board.Id, 0), board.Speed, board.Id .. " empty hands = its speed")
			local loaded = HoverboardData.walkSpeed(board.Id, 6)
			if board.IgnoresCarrySlow then
				T.eq(loaded, board.Speed, board.Id .. " ignores the carry slowdown")
			else
				T.eq(loaded, board.Speed - 6 * slow, board.Id .. " keeps the full carry slowdown")
				T.eq(HoverboardData.walkSpeed(board.Id, 999), board.Speed - max, board.Id .. " slowdown capped")
			end
			T.truthy(
				HoverboardData.walkSpeed(board.Id, 999) >= HoverboardData.walkSpeed(nil, 0),
				board.Id .. " fully loaded is never slower than walking empty-handed"
			)
		end
	end)

	T.test("hoverboard builder: every board builds within its part budget", function()
		for _, board in HoverboardData.List do
			local model = HoverboardBuilder.build(board.Id)
			local parts = partsOf(model)
			local max = HoverboardBuilder.MaxParts[board.Kind]
			T.le(#parts, max, board.Id .. " parts")
			T.truthy(#parts >= 30, board.Id .. " is a real model (" .. #parts .. " parts)")
			T.eq(model.Name, board.Id, board.Id .. " model name")
			T.eq(model.PrimaryPart and model.PrimaryPart.Name, "Root", board.Id .. " PrimaryPart")
			T.eq(model:GetAttribute("BoardId"), board.Id, board.Id .. " attribute")
			T.eq(model:GetAttribute("Effect"), board.Effect, board.Id .. " effect attribute")
			local neon, shadows = 0, 0
			for _, p in parts do
				T.truthy(
					p.Anchored and not p.CanCollide and not p.CanTouch and not p.CanQuery,
					board.Id .. " " .. p.Name .. " is a plain visual"
				)
				T.falsy(p:IsA("MeshPart"), board.Id .. " uses no meshes")
				if p.Material == roblox.Enum.Material.Neon then
					neon += 1
				end
				if p.CastShadow then
					shadows += 1
				end
			end
			T.truthy(neon >= 3, board.Id .. " glows")
			T.le(shadows, 8, board.Id .. " only big parts cast shadows")
		end
		T.truthy(not pcall(HoverboardBuilder.build, "Nope"), "an unknown board errors")
	end)

	T.test("hoverboard builder: Robux boards are the most detailed", function()
		local coinMax, robuxMin = 0, math.huge
		for _, board in HoverboardData.List do
			local n = #partsOf(HoverboardBuilder.build(board.Id))
			if board.Kind == "Coins" then
				coinMax = math.max(coinMax, n)
			else
				robuxMin = math.min(robuxMin, n)
			end
		end
		T.lt(coinMax, robuxMin, "the Robux boards have more detail than any coin board")
	end)

	T.test("hoverboard builder: attachments, deck height, hover gap", function()
		for _, board in HoverboardData.List do
			local model = HoverboardBuilder.build(board.Id)
			local root = model.PrimaryPart
			for _, name in HoverboardBuilder.Attachments do
				local a = root:FindFirstChild(name)
				T.truthy(a and a:IsA("Attachment"), board.Id .. " attachment " .. name)
			end
			local exhausts = model:GetAttribute("Exhausts")
			T.truthy(type(exhausts) == "number" and exhausts >= 1, board.Id .. " exhaust count")
			for i = 1, exhausts do
				local a = root:FindFirstChild("Exhaust" .. i)
				T.truthy(a ~= nil, board.Id .. " Exhaust" .. i)
				local back = a.CFrame.UpVector
				T.truthy(back.Z > 0.99, board.Id .. " Exhaust" .. i .. " blows backward (+Y = +Z)")
				T.truthy(a.CFrame.Position.Z > 2, board.Id .. " Exhaust" .. i .. " sits at the tail")
			end
			T.near(root.Feet.CFrame.Position.Y, HoverboardBuilder.DeckHeight, 1e-4, board.Id .. " feet on the deck")
			T.truthy(root.Pad.CFrame.UpVector.Y < -0.99, board.Id .. " Pad points down")
			T.truthy(
				root.TrailLeft.CFrame.Position.X < 0 and root.TrailRight.CFrame.Position.X > 0,
				board.Id .. " trail ends left and right"
			)
			T.truthy(root.TrailLeft.CFrame.Position.Z > 2, board.Id .. " trail at the tail")
			T.truthy(root.Nose.CFrame.Position.Z < -2, board.Id .. " nose at the front")
			T.near(model:GetAttribute("DeckHeight"), HoverboardBuilder.DeckHeight, 1e-6, board.Id .. " DeckHeight attribute")
			-- the deck top: the highest point of the parts the feet stand on is the deck height,
			-- the lowest point of the board is the hover pad at HoverGap
			local low, deckTop = math.huge, -math.huge
			for _, p in partsOf(model) do
				if p ~= root then
					local cf, s = p.CFrame, p.Size / 2
					local extent = math.abs(cf.RightVector.Y) * s.X + math.abs(cf.UpVector.Y) * s.Y + math.abs(cf.LookVector.Y) * s.Z
					low = math.min(low, cf.Position.Y - extent)
					local pos = cf.Position
					if math.abs(pos.X) < 0.6 and math.abs(pos.Z) < 0.6 and p.Name ~= "Crystal" and p.Name ~= "CrystalTip" then
						deckTop = math.max(deckTop, pos.Y + extent)
					end
				end
			end
			T.near(low, HoverboardBuilder.HoverGap, 0.03, board.Id .. " floats HoverGap above the ground")
			T.truthy(math.abs(deckTop - HoverboardBuilder.DeckHeight) <= 0.03, board.Id .. " deck top under the feet " .. deckTop)
		end
	end)

	T.test("hoverboard builder: rig welds every part to Root", function()
		local model = HoverboardBuilder.build("RoyalPhoenix")
		HoverboardBuilder.rig(model)
		local root = model.PrimaryPart
		for _, p in partsOf(model) do
			T.falsy(p.Anchored, p.Name .. " unanchored")
			T.truthy(p.Massless, p.Name .. " massless")
			if p ~= root then
				local weld = p:FindFirstChildWhichIsA("WeldConstraint")
				T.truthy(weld and weld.Part0 == root and weld.Part1 == p, p.Name .. " welded to Root")
			end
		end
	end)

	T.test("hoverboard fx: every board, trails for Robux only, mobile budget, bursts, mount and pool", function()
		for _, board in HoverboardData.List do
			local set = HoverboardFx.create(board.Id)
			if board.Effect == "None" then
				T.eq(set, nil, board.Id .. " has no effects")
			else
				T.truthy(set ~= nil, board.Id .. " effect set")
				if board.Kind == "Robux" then
					T.truthy(#set.Trails >= 1, board.Id .. " has a trail")
					T.le(HoverboardFx.rate(set), 40, board.Id .. " particles per second")
				else
					T.eq(#set.Trails, 0, board.Id .. ": the trail stays a Robux perk")
					T.le(HoverboardFx.rate(set), 14, board.Id .. " small effects (particles per second)")
				end
				for _, kind in { "Start", "Boost" } do
					local count = HoverboardFx.burstCount(set, kind :: any)
					T.truthy(count > 0 and count <= 30, board.Id .. " " .. kind .. " burst size " .. count)
				end
				T.truthy(
					HoverboardFx.burstCount(HoverboardFx.create(board.Id, true) :: any, "Start") < HoverboardFx.burstCount(set, "Start"),
					board.Id .. " lite bursts are smaller"
				)
				local lite = HoverboardFx.create(board.Id, true)
				T.le(HoverboardFx.rate(lite), HoverboardFx.rate(set) / 2 + 0.01, board.Id .. " lite halves the rate")
				local model = HoverboardBuilder.build(board.Id)
				T.truthy(HoverboardFx.mount(set, model), board.Id .. " mounts on its board")
				for _, e in set.Emitters do
					T.truthy(
						e.Parent and e.Parent:IsA("Attachment") and e.Parent.Name == e:GetAttribute("Mount"),
						e.Name .. " on its attachment"
					)
					T.falsy(e.Enabled, e.Name .. " starts disabled")
				end
				for _, e in set.Bursts do
					T.truthy(e.Parent and e.Parent.Name == e:GetAttribute("Mount"), e.Name .. " burst on its attachment")
					T.eq(e.Rate, 0, e.Name .. " bursts never stream")
				end
				for _, t in set.Trails do
					T.eq(t.Attachment0.Name, "TrailLeft", t.Name .. " attachment 0")
					T.eq(t.Attachment1.Name, "TrailRight", t.Name .. " attachment 1")
				end
				HoverboardFx.setActive(set, true, 0.5)
				T.truthy(set.Emitters[1].Enabled, "enabled while riding")
				T.near(set.Emitters[1].Rate, set.Emitters[1]:GetAttribute("BaseRate") * 0.5, 1e-6, "rate follows the speed")
				-- a board without the attachments is refused and nothing moves
				local bare = roblox.Instance.new("Model")
				local bareRoot = roblox.Instance.new("Part")
				bareRoot.Parent = bare
				bare.PrimaryPart = bareRoot
				local other = HoverboardFx.create(board.Id)
				T.falsy(HoverboardFx.mount(other, bare), board.Id .. " refuses a board without attachments")
				T.eq(other.Emitters[1].Parent, nil, "nothing mounted")
				-- release keeps it for the next rider, acquire hands the same set back
				local before = HoverboardFx.pooled(board.Id)
				HoverboardFx.release(set)
				T.falsy(set.Emitters[1].Enabled, "released sets are off")
				T.eq(set.Emitters[1].Parent, nil, "released sets are unmounted")
				T.eq(HoverboardFx.pooled(board.Id), before + 1, "pooled")
				HoverboardFx.release(set)
				T.eq(HoverboardFx.pooled(board.Id), before + 1, "a double release is ignored")
				T.eq(HoverboardFx.acquire(board.Id), set, "acquire reuses the pooled set")
			end
		end
		T.eq(HoverboardFx.acquire("NoSuchBoard"), nil, "unknown boards acquire nothing")
	end)
end
