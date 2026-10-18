-- The steps 6-7 windows in the light "Bubble" look (pure builders) under Lune:
-- each builds on PC and phone scales with its main buttons.
local roblox = require("@lune/roblox") :: any
local Color3 = roblox.Color3

return function(T, Loader)
	local function ui(name: string)
		return Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI." .. name)
	end
	local UIKit = ui("UIKit")
	local grey = Color3.new(0.7, 0.7, 0.7)
	local scales = { 1.25, 0.62 }

	T.test("WheelBubble: a spoke fan per segment, SPIN and an odds row each", function()
		local segments = {}
		for i = 1, 8 do
			table.insert(segments, { Id = "S" .. i, Label = "Prize " .. i, Detail = "", Chance = "12%", Color = grey })
		end
		for _, scale in scales do
			local refs = ui("WheelBubble").build(UIKit.screen("T"), scale, { Segments = segments, Ready = true, Countdown = "ready" })
			T.truthy(refs.Spin, "spin")
			T.truthy(refs.Disc:FindFirstChild("Label8"), "8 labels")
			T.truthy(refs.Rows.S8, "8 odds rows")
		end
	end)

	T.test("CodexBubble: found ores get cards, the rest '?'", function()
		local ores = {
			{ Id = "Coal", Name = "Coal", Rarity = "Common", Color = grey, Found = true },
			{ Id = "Gold", Name = "Gold", Rarity = "Rare", Color = grey, Found = false },
		}
		local detail = { Podium = "", Sells = "", Blaster = "", FoundIn = "", Lore = "" }
		for _, scale in scales do
			local refs = ui("CodexBubble").build(UIKit.screen("T"), scale, { Ores = ores, Selected = "Coal", Detail = detail, Found = 1, Total = 2 })
			T.truthy(refs.Cards.Coal:FindFirstChild("Icon"), "found ore picture")
			T.truthy(refs.Cards.Gold:FindFirstChild("Mystery"), "unknown ore")
		end
	end)

	T.test("ArtifactsBubble: collections, artifacts, journal pages", function()
		local data = {
			Collections = { { Id = "A", Name = "A", Found = 1, Total = 6 } },
			Selected = "A",
			Artifacts = { { Id = "X", Name = "X", Rarity = "Common", Color = grey, Found = 1 }, { Id = "Y", Name = "Y", Rarity = "Epic", Color = grey, Found = 0 } },
			Artifact = "X",
			Lore = "",
			Where = "",
			Reward = "",
			Button = "FIND ALL",
			Found = 1,
			Total = 24,
		}
		for _, scale in scales do
			local refs = ui("ArtifactsBubble").build(UIKit.screen("T"), scale, data)
			T.truthy(refs.Collections.A and refs.Cards.X and refs.Cards.Y and refs.Journal, "parts")
			local j = ui("ArtifactsBubble").journal(UIKit.screen("J"), scale, {
				Chapters = { { Id = "C1", Name = "One" }, { Id = "C2", Name = "Two", Locked = true } },
				Selected = "C1",
				Kicker = "",
				Title = "",
				Text = "",
				Page = 1,
				Pages = 2,
			})
			T.truthy(j.Prev and j.Next and j.Chapters.C2, "journal")
		end
	end)

	T.test("BoardsBubble: ten rows + you, settings controls", function()
		local entries = {}
		for i = 1, 10 do
			table.insert(entries, { Rank = i, Name = "P" .. i, Value = "$1" })
		end
		for _, scale in scales do
			local refs = ui("BoardsBubble").boards(UIKit.screen("T"), scale, { Tab = "TotalEarned", Entries = entries, You = { Rank = 7, Name = "YOU", Value = "$1", You = true }, Note = "" })
			T.eq(#refs.Tabs.MoneyPerSec.Parent.Parent:GetChildren() > 0, true, "tabs")
			local s = ui("BoardsBubble").settings(UIKit.screen("S"), scale, {
				{ Id = "Sounds", Name = "Sounds", Hint = "", Icon = "speaker", Kind = "Slider", Value = 0.5 },
				{ Id = "Shake", Name = "Shake", Hint = "", Icon = "camera", Kind = "Toggle", On = true },
			}, "")
			T.truthy(s.Rows.Sounds:FindFirstChild("Slider", true), "slider")
			T.truthy(s.Rows.Shake:FindFirstChild("Toggle", true), "toggle")
		end
	end)

	T.test("Gear / Enchants / Boosts build with their buttons", function()
		local gear = { { Id = "Boots", Name = "Boots", Icon = "boots", Level = 1, MaxLevel = 5, Text = "", From = "1", To = "2", Unit = "", Price = "$1", State = "Buy", Color = grey } }
		local slots = { { Id = "Power", Name = "POWER", Effect = "" }, { Id = "S2", Locked = "Level 7" } }
		local enchants = { { Id = "Power", Name = "Power", Rarity = "Common", Color = grey, Effect = "", Price = "$1", New = true } }
		for _, scale in scales do
			local g = ui("GearBubble").build(UIKit.screen("G"), scale, { Gear = gear, Coins = "$1" })
			T.truthy(g.Buy.Boots, "gear buy")
			local e = ui("EnchantBubble").enchants(UIKit.screen("E"), scale, {
				Header = "",
				Slots = slots,
				Enchants = enchants,
				Selected = "Power",
				Description = "",
				Now = "",
				Next = "",
				Tiers = { "I" },
				Buy = "$1",
				Shards = "1",
				Coins = "$1",
				ShardCount = "1",
			})
			T.truthy(e.Buy and e.ShardsBuy and e.Equip and e.Rows.Power, "enchant parts")
			local b = ui("EnchantBubble").boosts(UIKit.screen("B"), scale, {
				Tab = "TripleLucky",
				Name = "Triple Lucky",
				Icon = "clover",
				Text = "",
				Offers = { { Text = "+5 MIN", Price = "$1" }, { Text = "+15 MIN", Soon = true } },
				Note = "",
				Capsule = "Crystal",
				Odds = { { Name = "A", Color = grey, Without = "1%", With = "3%" } },
				Coins = "$1",
			})
			T.eq(#b.Offers, 2, "offers")
		end
	end)
end
