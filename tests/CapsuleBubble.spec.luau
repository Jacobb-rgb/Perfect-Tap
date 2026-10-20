-- CapsuleBubble (the light Golem Capsules window, pure builder) under Lune:
-- chance text, every golem gets a card with its odds, touch sizes on phones.
local roblox = require("@lune/roblox") :: any
local Color3 = roblox.Color3

return function(T, Loader)
	local CapsuleBubble = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.CapsuleBubble")
	local UIKit = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.UIKit")

	T.test("CapsuleBubble.percent: readable chances", function()
		T.eq(CapsuleBubble.percent(0.25), "25%", "whole")
		T.eq(CapsuleBubble.percent(0.025), "2.5%", "one decimal")
		T.eq(CapsuleBubble.percent(0.01), "1%", "trailing zero cut")
		T.eq(CapsuleBubble.percent(0.007), "0.7%", "under one")
		T.eq(CapsuleBubble.percent(0.0007), "0.07%", "tiny")
		T.eq(CapsuleBubble.percent(0.0003), "0.03%", "tiniest")
	end)

	T.test("CapsuleBubble: a card with the chance for every golem, buttons for 1/3/10", function()
		local data = {
			Capsules = {
				{ Id = "Stone", Name = "Stone Capsule", Color = Color3.new(0.6, 0.6, 0.6), Glow = Color3.new(1, 0.6, 0.3), Currency = "Coins", Prices = { "$1", "$3", "$9" } },
				{ Id = "Royal", Name = "Royal Capsule", Color = Color3.new(1, 0.8, 0.2), Glow = Color3.new(1, 0.5, 0.6), Currency = "Robux", Prices = { "49", "139", "429" } },
			},
			Selected = "Stone",
			Golems = {
				{ Id = "PebbleGolem", Name = "Pebble Golem", Color = Color3.new(0.7, 0.7, 0.7), Chance = 0.9 },
				{ Id = "RubyKnight", Name = "Ruby Knight", Color = Color3.new(0.7, 0.3, 1), Chance = 0.1, Lucky = true },
			},
			Coins = "$5",
			Owned = 1,
			Cap = 60,
			Boosts = { { Id = "TripleLucky", Label = "TRIPLE LUCKY", Price = "39", Active = true, TimeLeft = "1:00" } },
		}
		for _, scale in { 1.25, 0.62 } do
			local gui = UIKit.screen("Test")
			local refs = CapsuleBubble.build(gui, scale, data)
			T.truthy(refs.Window.Close, "close button")
			for _, count in { 1, 3, 10 } do
				T.truthy(refs.Open[count], "open " .. count)
			end
			T.truthy(refs.Tabs.Stone and refs.Tabs.Royal, "capsule tabs")
			local chance = refs.Cards.RubyKnight:FindFirstChild("Chance", true)
			T.eq(chance:FindFirstChild("Text").Text, "10%", "odds on the card")
			T.truthy(refs.Cards.RubyKnight:FindFirstChild("Badge", true), "lucky golems marked")
			T.truthy(refs.Boosts.TripleLucky:FindFirstChild("TimeLeft"), "running boost shows its time")
		end
	end)

	T.test("CapsuleBubble: phone buttons >= 44 pt", function()
		local layout = CapsuleBubble.layout(0.62)
		T.truthy(layout.Compact, "compact")
		T.truthy(layout.Tab.Y * 0.62 >= 44, "tabs")
		T.truthy(layout.Open.Y * 0.62 >= 44, "open buttons")
		T.truthy(layout.Boost.Y * 0.62 >= 44, "boost buttons")
	end)
end
