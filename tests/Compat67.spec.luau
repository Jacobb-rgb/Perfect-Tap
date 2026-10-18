--[[
	Steps 6-7 bonuses against the older systems (the compatibility check,
	2026-10-18): what the client shows and aims at matches what the server
	applies (sell bonus at Tobin's stall, Reach on the blaster, the Gloves
	wall check, the default walk speed).
]]

return function(T, Loader)
	local fs = require("@lune/fs")
	local serde = require("@lune/serde")
	local GearConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.GearConfig")
	local ItemData = Loader.requirePath("ReplicatedStorage.Shared.Config.ItemData")
	local Bonuses = Loader.requirePath("ServerScriptService.Server.Bonuses")
	local SellView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.SellView")

	T.test("Compat67: Tobin's stall shows what Tobin pays with the sell bonus", function()
		local mult = 1.35
		local stats = { SellPct = 0.35 }
		local summary = { ["Clean|Gold|Pristine|"] = 3, ["Clean|Coal|Rough|"] = 7, ["Raw|Coal||"] = 2 }
		local rows = SellView.entries(summary, "Pen", mult)
		local gold: any = nil
		for _, row in rows do
			if row.Keys["Clean|Gold|Pristine|"] then
				gold = row
			end
		end
		T.truthy(gold, "a Gold row")
		local base = ItemData.value("Clean", "Gold", "Pristine")
		T.eq(gold.Base, base)
		T.eq(gold.Price, Bonuses.sellAmount(stats, base), "row price = what one sells for")
		-- the confirm text rounds the whole batch once, like SellService
		local text = SellView.confirmRowText(gold, 3)
		local Format = Loader.requirePath("ReplicatedStorage.Shared.Util.Format")
		T.truthy(text:find(Format.money(Bonuses.sellAmount(stats, base * 3)), 1, true), "the batch price: " .. text)
		-- sell-all: the plan's total is the server's payout for the same items
		local plan = SellView.plan(summary, {}, "AllButBest", nil, mult)
		local plain = SellView.plan(summary, {}, "AllButBest", nil)
		T.eq(plan.Count, plain.Count)
		T.eq(plan.Total, Bonuses.sellAmount(stats, plain.Total), "total with the bonus, rounded once")
		-- no bonus or a broken one: the plain prices
		T.eq(SellView.entries(summary, "Pen", 0 / 0)[2].Price, SellView.entries(summary, "Pen")[2].Price)
		T.eq(SellView.withBonus(100, 0.5), 100, "a bonus below 1 counts as none")
	end)

	T.test("Compat67: the client's blaster range includes the Reach enchant", function()
		local source = fs.readFile("src/client/Controllers/MiningController.luau")
		T.truthy(source:find("return base + bonusReach()", 1, true), "rangeOf adds the Reach bonus")
		T.truthy(source:find("bonuses.Reach", 1, true), "from State.Bonuses.Reach")
		local server = fs.readFile("src/server/Services/MiningService.luau")
		T.truthy(server:find("Bonuses.reach(stats)", 1, true), "the server accepts the same bonus")
	end)

	T.test("Compat67: the client skips items behind walls beyond the bare-handed reach (Gloves)", function()
		local client = fs.readFile("src/client/Controllers/InteractController.luau")
		local server = fs.readFile("src/server/Services/CarryService.luau")
		T.truthy(server:find("local PICKUP_SLACK = 2", 1, true), "the server's slack is 2 studs")
		T.truthy(server:find('local BASE_REACH = GearConfig.value("Gloves", 0)', 1, true), "the server's bare reach")
		T.truthy(client:find('local LINE_FREE_REACH = GearConfig.value("Gloves", 0) + 2', 1, true), "the same line-free reach")
		T.truthy(client:find("isPickable(model, root, true)", 1, true), "the target loop runs the wall check")
	end)

	T.test("Compat67: the place's default walk speed is Boots level 0", function()
		local project = serde.decode("json", fs.readFile("default.project.json"))
		local players = project.tree.StarterPlayer
		T.eq(players["$properties"].CharacterWalkSpeed, GearConfig.value("Boots", 0))
	end)

	T.test("Compat67: aim assist only locks onto rocks the head can see (BeamSight deals no damage through walls)", function()
		local client = fs.readFile("src/client/Controllers/MiningController.luau")
		T.truthy(client:find("if score < bestScore and canSee(eye, rock) then", 1, true), "findAssist checks the line of sight")
		T.truthy(client:find("MovementConfig.BeamStopShort", 1, true), "stops short of the rock like the server")
		T.truthy(client:find("MovementConfig.BeamIgnoreTag", 1, true), "BeamIgnore parts never block")
	end)
end
