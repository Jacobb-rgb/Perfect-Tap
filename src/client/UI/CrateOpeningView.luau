--[[
	The screen over the void crate opening (VaultController plays the 3D stage,
	Builders/CrateOpeningStage; owner 2026-11-06, his storyboard): a fade in, the
	white flash at the burst, "NEW BLASTER!" with its crown flying in from the
	side and out again, then the rarity with its stars, the blaster's name, its
	level and damage one after the other and the AWESOME! button; after that
	COLLECTED! with its tick. In the colours of the crate's rarity. Before the
	burst a small hint says how to skip ahead.

	Pure and time-driven: update(refs, t, burst, reveal, leaving) poses everything
	for time t, so the Lune preview exports any moment with the same code. Stars,
	crown and tick are drawn with frames (no font or image needed).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BlasterData = require(Shared.Config.BlasterData)
local OreData = require(Shared.Config.OreData)
local Rarity = require(Shared.Config.Rarity)
local CaseBuilder = require(Shared.Builders.CaseBuilder)
local Format = require(Shared.Util.Format)
local UIKit = require(script.Parent.UIKit)
local VaultView = require(script.Parent.VaultView)

local CrateOpeningView = {}

local S = VaultView.Style
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)

-- seconds after the reveal
CrateOpeningView.TitleOut = 0.42 -- "NEW BLASTER!" starts to leave
CrateOpeningView.RarityAt = 0.42
CrateOpeningView.NameAt = 0.5
CrateOpeningView.StatsAt = 0.58
CrateOpeningView.ButtonAfter = 0.68 -- AWESOME! shows
CrateOpeningView.CollectAt = 0.8 -- past this (the stage's Hold) it is being collected

export type Refs = {
	Gui: ScreenGui,
	Fade: Frame,
	Flash: Frame,
	Catcher: TextButton, -- the whole screen: a click / tap skips ahead or ends
	Title: Frame,
	TitleNew: TextLabel,
	TitleBlaster: TextLabel,
	Crown: Frame,
	Reveal: Frame,
	RevealScale: UIScale,
	RarityPill: Frame,
	RarityScale: UIScale,
	RarityRing: Frame,
	RarityRingStroke: UIStroke,
	RarityText: TextLabel,
	Name: TextLabel,
	Stats: TextLabel,
	Continue: TextButton,
	ContinueHolder: Frame,
	Collected: Frame,
	CollectedScale: UIScale,
	Skip: TextLabel,
	Calm: boolean, -- Reduce motion: a dimmer flash
}

local function clamp01(x: number): number
	return math.clamp(x, 0, 1)
end

local function prog(t: number, a: number, b: number): number
	return clamp01((t - a) / (b - a))
end

local function easeOutBack(x: number): number
	local c1 = 1.7
	local c3 = c1 + 1
	return 1 + c3 * (x - 1) ^ 3 + c1 * (x - 1) ^ 2
end

local function outlined(label: Instance, thickness: number, color: Color3?)
	return UIKit.new("UIStroke", {
		Thickness = thickness,
		Color = color or S.Outline,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
	}, label)
end

-- A small turned square: the storyboard's star.
local function star(parent: Instance, name: string, x: number, size: number, z: number): Frame
	return UIKit.new("Frame", {
		Name = name,
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
		Position = UDim2.new(0.5, x, 0.5, 0),
		Rotation = 45,
		Size = UDim2.fromOffset(size, size),
		ZIndex = z,
	}, parent)
end

function CrateOpeningView.build(): Refs
	local gui = UIKit.screen("TerraForgeCrateOpening", 40)
	gui:SetAttribute("TerraForge", true)
	gui.IgnoreGuiInset = true
	local fade = UIKit.new("Frame", {
		Name = "Fade",
		BackgroundColor3 = BLACK,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 50,
	}, gui)
	local flash = UIKit.new("Frame", {
		Name = "Flash",
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 40,
	}, gui)
	local catcher = UIKit.new("TextButton", {
		Name = "Catcher",
		BackgroundTransparency = 1,
		Text = "",
		Size = UDim2.fromScale(1, 1),
		Selectable = false,
		ZIndex = 1,
	}, gui)

	-- NEW BLASTER!: big, slanted, its crown over the N; flies through the screen
	local title = UIKit.new("Frame", {
		Name = "Title",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0.5, 0.5),
		Rotation = -6,
		Size = UDim2.fromOffset(820, 300),
		Visible = false,
		ZIndex = 12,
	}, gui)
	local new = UIKit.new("TextLabel", {
		Name = "New",
		AnchorPoint = Vector2.new(0, 0),
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(40, 34),
		Size = UDim2.fromOffset(420, 110),
		Text = "NEW",
		TextColor3 = WHITE,
		TextSize = 112,
		TextXAlignment = Enum.TextXAlignment.Left,
		FontFace = S.TitleFont,
		ZIndex = 13,
	}, title)
	outlined(new, 6)
	UIKit.new("UIGradient", {
		Color = ColorSequence.new(WHITE, Color3.fromRGB(176, 170, 196)),
		Rotation = 90,
	}, new)
	local blasterText = UIKit.new("TextLabel", {
		Name = "Blaster",
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundTransparency = 1,
		Position = UDim2.new(0.5, 0, 0, 132),
		Size = UDim2.fromOffset(820, 140),
		Text = "BLASTER!",
		TextColor3 = WHITE,
		TextSize = 140,
		FontFace = S.TitleFont,
		ZIndex = 13,
	}, title)
	outlined(blasterText, 7)
	UIKit.new("UIGradient", { Name = "Colour", Rotation = 90 }, blasterText)
	local crown = UIKit.new("Frame", {
		Name = "Crown",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(84, -6),
		Rotation = -2,
		Size = UDim2.fromOffset(76, 52),
		ZIndex = 14,
	}, title)
	UIKit.new("Frame", {
		Name = "Band",
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(6, 38),
		Size = UDim2.fromOffset(64, 12),
		ZIndex = 14,
	}, crown)
	for i, x in { 14, 38, 62 } do
		local spike = UIKit.new("Frame", {
			Name = "Spike" .. i,
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = WHITE,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(x, if i == 2 then 20 else 26),
			Rotation = 45,
			Size = UDim2.fromOffset(if i == 2 then 24 else 20, if i == 2 then 24 else 20),
			ZIndex = 14,
		}, crown)
		outlined(spike, 2)
	end

	-- the reveal: the rarity at the top, the name and stats at the bottom (the blaster floats between)
	local reveal = UIKit.new("Frame", {
		Name = "Reveal",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		ZIndex = 10,
	}, gui)
	local revealScale = UIKit.new("UIScale", { Name = "Pop", Scale = 1 }, reveal)
	local pill = UIKit.new("Frame", {
		Name = "RarityPill",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = Color3.fromRGB(24, 12, 38),
		BackgroundTransparency = 0.1,
		BorderSizePixel = 0,
		Position = UDim2.new(0.5, 0, 0, 92),
		Size = UDim2.fromOffset(250, 54),
		ZIndex = 12,
	}, reveal)
	UIKit.new("UICorner", { CornerRadius = UDim.new(0, 27) }, pill)
	UIKit.new("UIStroke", { Name = "Edge", Thickness = 4, Color = WHITE }, pill)
	local rarityScale = UIKit.new("UIScale", { Name = "Pop", Scale = 1 }, pill)
	-- the strong effect: a ring that runs out from the pill as it lands
	local ring = UIKit.new("Frame", {
		Name = "Ring",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		ZIndex = 11,
	}, pill)
	UIKit.new("UICorner", { CornerRadius = UDim.new(0, 40) }, ring)
	local ringStroke = UIKit.new("UIStroke", { Thickness = 4, Color = WHITE }, ring)
	for i, x in { -96, 96 } do
		star(pill, "StarIn" .. i, x, 13, 13)
		star(pill, "StarOut" .. i, x * 1.5, 16, 13)
	end
	local rarityText = UIKit.new("TextLabel", {
		Name = "Text",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Text = "EPIC",
		TextColor3 = WHITE,
		TextSize = 34,
		FontFace = S.TitleFont,
		ZIndex = 13,
	}, pill)
	outlined(rarityText, 2.5)
	local name = UIKit.new("TextLabel", {
		Name = "BlasterName",
		AnchorPoint = Vector2.new(0.5, 1),
		BackgroundTransparency = 1,
		Position = UDim2.new(0.5, 0, 1, -146),
		Size = UDim2.fromOffset(900, 62),
		Text = "",
		TextColor3 = WHITE,
		TextSize = 54,
		FontFace = S.TitleFont,
		ZIndex = 12,
	}, reveal)
	outlined(name, 4)
	UIKit.new("UIGradient", {
		Color = ColorSequence.new(WHITE, Color3.fromRGB(186, 180, 206)),
		Rotation = 90,
	}, name)
	local stats = UIKit.new("TextLabel", {
		Name = "Stats",
		AnchorPoint = Vector2.new(0.5, 1),
		BackgroundTransparency = 1,
		Position = UDim2.new(0.5, 0, 1, -110),
		Size = UDim2.fromOffset(700, 34),
		Text = "",
		TextColor3 = WHITE,
		TextSize = 28,
		FontFace = S.Font,
		ZIndex = 12,
	}, reveal)
	outlined(stats, 3)

	-- AWESOME!: a glowing button in the rarity's colour
	local holder = UIKit.new("Frame", {
		Name = "Continue",
		AnchorPoint = Vector2.new(0.5, 1),
		BackgroundTransparency = 1,
		Position = UDim2.new(0.5, 0, 1, -22),
		Size = UDim2.fromOffset(280, 72 + S.Lip),
		Visible = false,
		ZIndex = 20,
	}, gui)
	local lip = UIKit.new("Frame", {
		Name = "Lip",
		BackgroundColor3 = BLACK,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, S.Lip),
		Size = UDim2.new(1, 0, 1, -S.Lip),
		ZIndex = 20,
	}, holder)
	UIKit.new("UICorner", { CornerRadius = UDim.new(0, 18) }, lip)
	local button = UIKit.new("TextButton", {
		Name = "Face",
		AutoButtonColor = false,
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 1, -S.Lip),
		Text = "",
		ZIndex = 21,
	}, holder)
	UIKit.new("UICorner", { CornerRadius = UDim.new(0, 18) }, button)
	UIKit.new("UIStroke", { Name = "Edge", Thickness = 3, Color = WHITE, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, button)
	UIKit.new("UIGradient", { Name = "Colour", Rotation = 90 }, button)
	local label = UIKit.new("TextLabel", {
		Name = "Label",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Text = "AWESOME!",
		TextColor3 = WHITE,
		TextSize = 36,
		FontFace = S.TitleFont,
		ZIndex = 22,
	}, button)
	outlined(label, 3)

	-- COLLECTED! with its tick in a round badge
	local collected = UIKit.new("Frame", {
		Name = "Collected",
		AnchorPoint = Vector2.new(0.5, 1),
		BackgroundTransparency = 1,
		Position = UDim2.new(0.5, 0, 1, -40),
		Size = UDim2.fromOffset(480, 130),
		Visible = false,
		ZIndex = 20,
	}, gui)
	local collectedScale = UIKit.new("UIScale", { Name = "Pop", Scale = 1 }, collected)
	local badge = UIKit.new("Frame", {
		Name = "Badge",
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.fromOffset(52, 52),
		ZIndex = 21,
	}, collected)
	UIKit.new("UICorner", { CornerRadius = UDim.new(1, 0) }, badge)
	UIKit.new("UIStroke", { Name = "Edge", Thickness = 4, Color = WHITE }, badge)
	for _, bar in { { 18, 30, 16, 45 }, { 31, 25, 30, -45 } } do
		UIKit.new("Frame", {
			Name = "Tick",
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = WHITE,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(bar[1], bar[2]),
			Rotation = bar[4],
			Size = UDim2.fromOffset(bar[3], 6),
			ZIndex = 22,
		}, badge)
	end
	local collectedText = UIKit.new("TextLabel", {
		Name = "Text",
		AnchorPoint = Vector2.new(0.5, 1),
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.fromScale(1, 0.56),
		Text = "COLLECTED!",
		TextColor3 = WHITE,
		TextSize = 54,
		FontFace = S.TitleFont,
		ZIndex = 21,
	}, collected)
	outlined(collectedText, 4)

	local skip = UIKit.new("TextLabel", {
		Name = "Skip",
		AnchorPoint = Vector2.new(0.5, 1),
		BackgroundTransparency = 1,
		Position = UDim2.new(0.5, 0, 1, -28),
		Size = UDim2.fromOffset(500, 28),
		Text = "Click to skip",
		TextColor3 = WHITE,
		TextTransparency = 0.25,
		TextSize = 22,
		FontFace = S.Font,
		Visible = false,
		ZIndex = 12,
	}, gui)
	outlined(skip, 2)
	return {
		Gui = gui,
		Fade = fade,
		Flash = flash,
		Catcher = catcher,
		Title = title,
		TitleNew = new,
		TitleBlaster = blasterText,
		Crown = crown,
		Reveal = reveal,
		RevealScale = revealScale,
		RarityPill = pill,
		RarityScale = rarityScale,
		RarityRing = ring,
		RarityRingStroke = ringStroke,
		RarityText = rarityText,
		Name = name,
		Stats = stats,
		Continue = button,
		ContinueHolder = holder,
		Collected = collected,
		CollectedScale = collectedScale,
		Skip = skip,
		Calm = false,
	}
end

-- The new blaster's texts: rarity (of its ore), name, "LV 7 · 187 DMG/s", all in the crate's colours.
function CrateOpeningView.setBlaster(refs: Refs, level: number, oreId: string)
	local ore = if oreId ~= "" then OreData.ById[oreId] else nil
	local rarity = if ore then Rarity.ById[ore.Rarity] else Rarity.ById.Common
	local tier = CaseBuilder.tier(oreId)
	local glow, color = tier.Glow, tier.Color
	refs.RarityText.Text = string.upper(rarity.Name)
	refs.RarityText.TextColor3 = WHITE:Lerp(glow, 0.55)
	local pill = refs.RarityPill
	local edge = pill:FindFirstChild("Edge") :: UIStroke
	edge.Color = glow
	refs.RarityRingStroke.Color = glow
	for _, child in pill:GetChildren() do
		if child:IsA("Frame") and string.find(child.Name, "Star", 1, true) then
			child.BackgroundColor3 = WHITE:Lerp(glow, 0.45)
		end
	end
	refs.Name.Text = string.upper(BlasterData.displayName(level, oreId))
	refs.Stats.Text = string.format("LV %d%s%s DMG/s", level, VaultView.Separator, Format.big(BlasterData.damage(level, oreId)))
	local dark = color:Lerp(BLACK, 0.72)
	local gradient = refs.TitleBlaster:FindFirstChild("Colour") :: UIGradient
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, WHITE:Lerp(glow, 0.55)),
		ColorSequenceKeypoint.new(0.55, glow),
		ColorSequenceKeypoint.new(1, color),
	})
	for _, label in { refs.TitleBlaster, refs.TitleNew, refs.Name } do
		local stroke = label:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Color = dark
		end
	end
	-- the button and its lip
	local holder = refs.ContinueHolder
	local lip = holder:FindFirstChild("Lip") :: Frame
	lip.BackgroundColor3 = color:Lerp(BLACK, 0.55)
	local face = refs.Continue
	local faceEdge = face:FindFirstChild("Edge") :: UIStroke
	faceEdge.Color = WHITE:Lerp(glow, 0.5)
	local faceColour = face:FindFirstChild("Colour") :: UIGradient
	faceColour.Color = ColorSequence.new(glow, color:Lerp(BLACK, 0.3))
	local badge = refs.Collected:FindFirstChild("Badge") :: Frame
	badge.BackgroundColor3 = color:Lerp(BLACK, 0.6)
	local badgeEdge = badge:FindFirstChild("Edge") :: UIStroke
	badgeEdge.Color = WHITE:Lerp(glow, 0.5)
	local text = refs.Collected:FindFirstChild("Text") :: TextLabel
	local textStroke = text:FindFirstChildOfClass("UIStroke")
	if textStroke then
		textStroke.Color = dark
	end
end

function CrateOpeningView.setSkipText(refs: Refs, text: string)
	refs.Skip.Text = text
end

--[[
	Poses the overlay for time t: the fade in, the flash at `burst`, the title
	flying through from `reveal`, the rarity, name, stats and AWESOME! one after
	the other, COLLECTED! past reveal + CollectAt (time waits there for the
	button). `leaving` (0..1) fades out to black at the end.
]]
function CrateOpeningView.update(refs: Refs, t: number, burst: number, reveal: number, leaving: number?)
	local fadeIn = prog(t, 0, 0.3)
	local out = leaving or 0
	refs.Fade.BackgroundTransparency = math.min(fadeIn, 1 - out)
	refs.Fade.Visible = refs.Fade.BackgroundTransparency < 0.999
	local flash = if t >= burst then 1 - prog(t, burst, burst + 0.32) else 0
	refs.Flash.BackgroundTransparency = 1 - flash * (if refs.Calm then 0.3 else 0.95)
	refs.Flash.Visible = flash > 0.001

	-- the title flies in from the left and on out to the right
	local since = t - reveal
	local titleIn = prog(since, 0, 0.2)
	local titleOut = prog(since, CrateOpeningView.TitleOut, CrateOpeningView.TitleOut + 0.16)
	refs.Title.Visible = since >= 0 and titleOut < 1
	if refs.Title.Visible then
		local x = -0.7 + 1.2 * easeOutBack(titleIn) + 1.3 * titleOut * titleOut
		refs.Title.Position = UDim2.fromScale(x, 0.5)
	end

	-- then the rarity (a strong pop and a ring), the name, the stats
	local collecting = prog(since, CrateOpeningView.CollectAt, CrateOpeningView.CollectAt + 0.12)
	local shown = since >= CrateOpeningView.RarityAt and collecting < 1
	refs.Reveal.Visible = shown
	if shown then
		refs.RevealScale.Scale = 1
		local pop = prog(since, CrateOpeningView.RarityAt, CrateOpeningView.RarityAt + 0.16)
		refs.RarityScale.Scale = math.max(0.01, easeOutBack(pop) * (1 + 0.5 * (1 - pop)))
		refs.RarityPill.BackgroundTransparency = 0.1 + collecting * 0.9
		local ring = prog(since, CrateOpeningView.RarityAt + 0.05, CrateOpeningView.RarityAt + 0.4)
		refs.RarityRing.Size = UDim2.new(1, 90 * ring, 1, 70 * ring)
		refs.RarityRingStroke.Transparency = if ring > 0 and ring < 1 then ring else 1
		local nameIn = prog(since, CrateOpeningView.NameAt, CrateOpeningView.NameAt + 0.08)
		refs.Name.TextTransparency = 1 - nameIn + collecting
		local nameStroke = refs.Name:FindFirstChildOfClass("UIStroke")
		if nameStroke then
			nameStroke.Transparency = 1 - nameIn + collecting
		end
		local statsIn = prog(since, CrateOpeningView.StatsAt, CrateOpeningView.StatsAt + 0.08)
		refs.Stats.TextTransparency = 1 - statsIn + collecting
		local statsStroke = refs.Stats:FindFirstChildOfClass("UIStroke")
		if statsStroke then
			statsStroke.Transparency = 1 - statsIn + collecting
		end
	end
	refs.ContinueHolder.Visible = since >= CrateOpeningView.ButtonAfter and since < CrateOpeningView.CollectAt

	-- COLLECTED!
	local done = since - CrateOpeningView.CollectAt
	refs.Collected.Visible = done > 0
	if done > 0 then
		refs.CollectedScale.Scale = math.max(0.01, easeOutBack(prog(done, 0, 0.18)))
	end
	refs.Skip.Visible = t > 0.5 and t < burst - 0.25
end

-- The buttons (touch-size tests).
function CrateOpeningView.touchTargets(refs: Refs): { GuiObject }
	return { refs.ContinueHolder }
end

return CrateOpeningView
