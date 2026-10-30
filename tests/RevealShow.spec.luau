-- RevealFx, the shared "you got it" reveal (the secret ores' jackpot calls it; its API stays as
-- it is for them): the rarity tiers and their looks, the flash cap every flash in the game shares
-- (the egg opening asks it too: RevealFx.claimFlash), and the reveal built, posed and pooled
-- without the game's services (Manual).
return function(T, Loader)
	local roblox = require("@lune/roblox") :: any
	local Instance = roblox.Instance
	local Vector2 = roblox.Vector2
	local RevealFx = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.Effects.RevealFx")
	local Rarity = Loader.requirePath("ReplicatedStorage.Shared.Config.Rarity")

	T.test("RevealFx: tiers, palettes and the shared flash cap", function()
		T.eq(RevealFx.tierOf("Common"), "Normal")
		T.eq(RevealFx.tierOf("Uncommon"), "Normal")
		T.eq(RevealFx.tierOf("Rare"), "Rare")
		T.eq(RevealFx.tierOf("Epic"), "Rare")
		T.eq(RevealFx.tierOf("Legendary"), "Jackpot")
		T.eq(RevealFx.tierOf("Mythic"), "Jackpot")
		T.eq(RevealFx.tierOf("Secret"), "Secret", "the secret ores' tier")
		T.eq(RevealFx.tierOf("NoSuch"), "Normal")
		-- bigger moments for rarer things
		local tiers = RevealFx.Tiers
		T.truthy(tiers.Rare.Rays > tiers.Normal.Rays and tiers.Jackpot.Rays > tiers.Rare.Rays)
		T.truthy(tiers.Jackpot.Back ~= 0 and tiers.Secret.Back ~= 0, "two ray layers for the jackpots")
		T.truthy(tiers.Jackpot.Confetti > 0 and tiers.Jackpot.Shake > 0 and tiers.Jackpot.Headline)
		T.falsy(tiers.Normal.Headline)
		T.truthy(RevealFx.PhoneRays <= 12 and RevealFx.PhoneConfetti <= 24, "phones: capped")
		-- headlines
		T.eq(RevealFx.headlineFor("Jackpot", "Legendary"), "LEGENDARY!")
		T.eq(RevealFx.headlineFor("Jackpot", "Mythic"), "MYTHIC!")
		T.eq(RevealFx.headlineFor("Secret", "Secret"), "SECRET!")
		T.eq(RevealFx.headlineFor("Rare", "Epic"), "EPIC!")
		T.eq(RevealFx.headlineFor("Normal", "Common"), nil)
		-- colours: Legendary gold, Mythic a drifting rainbow, Secret black and rainbow
		local gold = RevealFx.palette("Legendary")
		T.truthy(gold.Light.R > 0.9 and gold.Light.G > 0.75 and gold.Light.B < 0.4, "gold")
		local a = RevealFx.rayColor("Mythic", 1, 10, 0)
		local b = RevealFx.rayColor("Mythic", 1, 10, 1)
		T.truthy(a ~= b, "Mythic's rainbow drifts")
		T.eq(RevealFx.rayColor("Secret", 2, 10, 0), RevealFx.palette("Secret").Dark, "every other Secret ray near-black")
		T.truthy(RevealFx.palette("Secret").Black)
		for _, info in Rarity.List do
			local p = RevealFx.palette(info.Id)
			T.truthy(p.Light and p.Dark and p.Glow and p.Flash, info.Id .. ": a full palette")
		end
		-- the flash cap: 2.5 a second at most, one clock for every reveal
		T.truthy(1 / RevealFx.FlashGap <= 2.5 + 1e-9, "at most 2.5 flashes a second")
		T.falsy(RevealFx.flashOk(10, 10 + RevealFx.FlashGap - 0.01))
		T.truthy(RevealFx.flashOk(10, 10 + RevealFx.FlashGap))
		T.truthy(RevealFx.FlashPeak < 1, "never fully opaque")
		local source = require("@lune/fs").readFile(Loader.root .. "/src/client/Controllers/CapsuleController.luau")
		T.truthy(string.find(source, "Claim = RevealFx.claimFlash", 1, true), "the egg's burst flash asks the same clock")
		-- the pose curves stay in bounds
		for i = 0, 40 do
			local t = i / 40
			T.truthy(RevealFx.swellAt(t) > 0.3 and RevealFx.swellAt(t) < 1.2)
			T.truthy(RevealFx.headlineAt(t) >= 0.3 and RevealFx.headlineAt(t) <= 1.15 + 1e-9)
		end
		T.near(RevealFx.swellAt(1), 1, 1e-9)
		T.eq(RevealFx.inAt(0, 0), 0, "the banner comes in after")
		T.eq(RevealFx.inAt(1, 0.2), 1)
	end)

	T.test("RevealFx: shows into a caller's frame, posed by hand (Manual), and pools on close", function()
		local parent = Instance.new("Frame")
		local reduced = RevealFx.show("Golem", "HeartstoneColossus", "Mythic", {
			Parent = parent,
			Chance = "0.03%",
			New = true,
			Manual = true,
			Flash = false,
			Sound = false,
			Shake = false,
			Reduced = true,
			Phone = true,
		})
		T.eq(reduced.Tier, "Jackpot")
		T.eq(reduced.Root.Parent, parent, "in the caller's frame")
		T.eq(reduced.NameLabel.Text, "Heartstone Colossus", "the golem's name")
		T.eq(reduced.PillLabel.Text, "MYTHIC")
		T.eq(reduced.ChanceLabel.Text, "0.03%", "its chance")
		T.truthy(reduced.NewLabel.Visible)
		T.eq(reduced.Headline.Text, "MYTHIC!")
		T.eq(#reduced.Sparkles + #reduced.Confetti, 0, "Reduce motion: no pieces")
		local bars = 0
		for _, list in reduced.RayFrames do
			bars += #list
		end
		T.truthy(bars * 2 <= RevealFx.PhoneRays, "phones: 12 rays at most")
		reduced:pose(2)
		T.eq(reduced.Layers[1].Rotation, 0, "Reduce motion: the rays stand still")
		T.eq(reduced.NameLabel.TextTransparency, 0, "and the banner just shows")
		reduced:close()
		T.eq(reduced.Root.Parent, nil, "closed: let go")
		-- the pool hands the same frames back, filled anew (a secret ore, no banner)
		local secret = RevealFx.show("Ore", "NoSuchOre", "Secret", {
			Parent = parent,
			Chance = "1 in 25,000",
			Banner = false,
			Manual = true,
			Flash = false,
			Sound = false,
			Shake = false,
			Reduced = false,
			Phone = false,
		})
		T.eq(secret.Root, reduced.Root, "pooled")
		T.eq(secret.Tier, "Secret")
		T.eq(secret.Headline.Text, "SECRET!")
		-- rainbow LETTERS on a plain dark edge (a gradient on the stroke smudges inside the letters)
		local edge = secret.Headline:FindFirstChildOfClass("UIStroke")
		T.truthy(edge and edge:FindFirstChildOfClass("UIGradient") == nil, "the edge stays plain")
		T.truthy(#secret.HeadlineGradient.Color.Keypoints >= 6, "the letters a rainbow")
		T.falsy(secret.Banner.Visible, "no banner when asked")
		T.truthy(#secret.Confetti > 0, "a jackpot's confetti")
		secret:pose(0.5)
		T.truthy(secret.Layers[1].Rotation > 0 and #secret.Layers == 2, "two layers turning")
		secret:close()
		-- text sizes: 18 px at 1080p (the HUD's 1.25), 8 pt on a phone (0.62)
		T.truthy(secret.ChanceLabel.TextSize * 0.62 >= 8 and secret.ChanceLabel.TextSize * 1.25 >= 18)
		T.truthy(secret.PillLabel.TextSize * 1.25 >= 18)
		local _ = Vector2
	end)
end
