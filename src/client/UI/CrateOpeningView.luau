--[[
	The screen over the void crate opening (VaultController plays the 3D stage,
	Builders/CrateOpeningStage; owner 2026-11-06, his storyboard, then "slower, more
	wow, the blaster placed like the secret ore"): a fade in, the white flash at the
	burst, "NEW BLASTER!" with its crown flying in from the side and holding a
	moment; then, the blaster on the left, the words on the right one after the
	other like the secret ore's reveal: the ribbon, the rarity big, a line, the
	blaster's name, its level with the stars of its crate, its damage counting up,
	AWESOME!; after that the words slide away and COLLECTED! with its tick shows. In
	the colours of the crate's rarity. Before the burst a small hint how to skip.

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
CrateOpeningView.TitleOut = 1.0 -- "NEW BLASTER!" starts to leave (the blaster's hero moment)
CrateOpeningView.RibbonAt = 1.3
CrateOpeningView.RarityAt = 1.42
CrateOpeningView.NameAt = 1.58
CrateOpeningView.RowAt = 1.72
CrateOpeningView.ValueAt = 1.86
CrateOpeningView.CountFor = 0.4 -- the damage counts up
CrateOpeningView.ButtonAfter = 2.2 -- AWESOME! shows
CrateOpeningView.CollectAt = 2.3 -- past this (the stage's Hold) it is being collected

local PANEL = Vector2.new(660, 480)
local PANEL_X = 0.725 -- the words' middle, the screen's width

-- The crate tiers' stars.
local STARS = { COMMON = 1, RARE = 2, EPIC = 3, MYTHIC = 4 }

export type Refs = {
	Gui: ScreenGui,
	Fade: Frame,
	Flash: Frame,
	Catcher: TextButton, -- the whole screen: a click / tap skips ahead or ends
	Title: Frame,
	TitleScale: UIScale,
	TitleNew: TextLabel,
	TitleBlaster: TextLabel,
	Crown: Frame,
	NewTag: Frame,
	NewTagScale: UIScale,
	Reveal: Frame, -- the words on the right
	RevealScale: UIScale, -- fits them to the screen (fit)
	Steps: { { Item: GuiObject, Scale: UIScale, At: number } },
	Ribbon: Frame,
	RarityText: TextLabel,
	Line: Frame,
	Name: TextLabel,
	Row: Frame,
	Stats: TextLabel,
	Stars: { Frame },
	Value: Frame,
	Damage: TextLabel,
	DamageValue: number,
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
		Position = UDim2.fromScale(0.5, 0.74),
		Rotation = -6,
		Size = UDim2.fromOffset(820, 300),
		Visible = false,
		ZIndex = 12,
	}, gui)
	local titleScale = UIKit.new("UIScale", { Name = "Pop", Scale = 1 }, title)
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

	-- the NEW! tag by the blaster
	local newTag = UIKit.new("Frame", {
		Name = "NewTag",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = Color3.fromRGB(24, 12, 38),
		BorderSizePixel = 0,
		Position = UDim2.fromScale(0.43, 0.2),
		Rotation = 12,
		Size = UDim2.fromOffset(120, 46),
		Visible = false,
		ZIndex = 11,
	}, gui)
	UIKit.new("UICorner", { CornerRadius = UDim.new(0, 14) }, newTag)
	UIKit.new("UIStroke", { Thickness = 4, Color = WHITE }, newTag)
	local newTagScale = UIKit.new("UIScale", { Name = "Pop", Scale = 1 }, newTag)
	local tagText = UIKit.new("TextLabel", {
		Name = "Text",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Text = "NEW!",
		TextColor3 = WHITE,
		TextSize = 30,
		FontFace = S.TitleFont,
		ZIndex = 12,
	}, newTag)
	outlined(tagText, 2)

	-- the words on the right, each popping in on its own moment
	local reveal = UIKit.new("Frame", {
		Name = "Reveal",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(PANEL_X, 0.5),
		Size = UDim2.fromOffset(PANEL.X, PANEL.Y),
		Visible = false,
		ZIndex = 10,
	}, gui)
	local revealScale = UIKit.new("UIScale", { Name = "Fit", Scale = 1 }, reveal)
	local steps = {}
	local function step(item: GuiObject, at: number)
		table.insert(steps, { Item = item, Scale = UIKit.new("UIScale", { Name = "Pop", Scale = 1 }, item), At = at })
	end
	local function holder(name: string, y: number, w: number, h: number): Frame
		return UIKit.new("Frame", {
			Name = name,
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundTransparency = 1,
			Position = UDim2.new(0.5, 0, 0, y),
			Size = UDim2.fromOffset(w, h),
			ZIndex = 12,
		}, reveal)
	end
	local ribbon = holder("Ribbon", 28, 320, 46)
	ribbon.BackgroundTransparency = 0
	ribbon.BackgroundColor3 = WHITE
	UIKit.new("UICorner", { CornerRadius = UDim.new(0, 12) }, ribbon)
	UIKit.new("UIStroke", { Thickness = 3, Color = S.Outline }, ribbon)
	UIKit.new("UIGradient", {
		Color = ColorSequence.new(Color3.fromRGB(255, 236, 130), S.Gold),
		Rotation = 90,
	}, ribbon)
	local ribbonText = UIKit.new("TextLabel", {
		Name = "Text",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Text = "NEW BLASTER!",
		TextColor3 = WHITE,
		TextSize = 30,
		FontFace = S.TitleFont,
		ZIndex = 13,
	}, ribbon)
	outlined(ribbonText, 2.5)
	step(ribbon, CrateOpeningView.RibbonAt)
	local rarityText = UIKit.new("TextLabel", {
		Name = "RarityText",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Position = UDim2.new(0.5, 0, 0, 108),
		Size = UDim2.fromOffset(PANEL.X, 112),
		Text = "EPIC",
		TextColor3 = WHITE,
		TextSize = 124,
		FontFace = S.TitleFont,
		ZIndex = 13,
	}, reveal)
	outlined(rarityText, 6)
	UIKit.new("UIGradient", { Name = "Colour", Rotation = 90 }, rarityText)
	step(rarityText, CrateOpeningView.RarityAt)
	local line = holder("Line", 172, 480, 5)
	line.BackgroundTransparency = 0
	line.BackgroundColor3 = WHITE
	step(line, CrateOpeningView.RarityAt + 0.08)
	local name = UIKit.new("TextLabel", {
		Name = "BlasterName",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Position = UDim2.new(0.5, 0, 0, 218),
		Size = UDim2.fromOffset(PANEL.X - 20, 66),
		Text = "",
		TextColor3 = WHITE,
		TextScaled = true,
		FontFace = S.TitleFont,
		ZIndex = 12,
	}, reveal)
	UIKit.new("UITextSizeConstraint", { MaxTextSize = 54, MinTextSize = 18 }, name)
	outlined(name, 4)
	UIKit.new("UIGradient", {
		Color = ColorSequence.new(WHITE, Color3.fromRGB(226, 216, 240)),
		Rotation = 90,
	}, name)
	step(name, CrateOpeningView.NameAt)
	local function chip(chipName: string, y: number): Frame
		local c = holder(chipName, y, 390, 54)
		c.BackgroundTransparency = 0.08
		c.BackgroundColor3 = Color3.fromRGB(24, 12, 38)
		UIKit.new("UICorner", { CornerRadius = UDim.new(0, 27) }, c)
		UIKit.new("UIStroke", { Name = "Edge", Thickness = 3, Color = WHITE }, c)
		return c
	end
	local row = chip("Row", 282)
	local stats = UIKit.new("TextLabel", {
		Name = "Stats",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(24, 0),
		Size = UDim2.new(0.5, -24, 1, 0),
		Text = "",
		TextColor3 = WHITE,
		TextSize = 38,
		TextXAlignment = Enum.TextXAlignment.Left,
		FontFace = S.TitleFont,
		ZIndex = 13,
	}, row)
	outlined(stats, 2.5)
	local stars = {}
	for i = 1, 4 do
		local st = star(row, "Star" .. i, 30 + (i - 1) * 36, 22, 13)
		table.insert(stars, st)
	end
	step(row, CrateOpeningView.RowAt)
	local value = chip("Value", 346)
	local valueLabel = UIKit.new("TextLabel", {
		Name = "Label",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(24, 0),
		Size = UDim2.new(0.45, -24, 1, 0),
		Text = "DMG/s",
		TextColor3 = WHITE,
		TextSize = 30,
		TextXAlignment = Enum.TextXAlignment.Left,
		FontFace = S.TitleFont,
		ZIndex = 13,
	}, value)
	outlined(valueLabel, 2)
	local damage = UIKit.new("TextLabel", {
		Name = "Damage",
		AnchorPoint = Vector2.new(1, 0),
		BackgroundTransparency = 1,
		Position = UDim2.new(1, -24, 0, 0),
		Size = UDim2.new(0.55, -24, 1, 0),
		Text = "",
		TextColor3 = Color3.fromRGB(255, 226, 92),
		TextSize = 44,
		TextXAlignment = Enum.TextXAlignment.Right,
		FontFace = S.TitleFont,
		ZIndex = 13,
	}, value)
	outlined(damage, 2.5)
	step(value, CrateOpeningView.ValueAt)

	-- AWESOME!: a glowing button in the rarity's colour
	local holderBtn = UIKit.new("Frame", {
		Name = "Continue",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Position = UDim2.new(0.5, 0, 0, 432),
		Size = UDim2.fromOffset(280, 72 + S.Lip),
		Visible = false,
		ZIndex = 20,
	}, reveal)
	local btnScale = UIKit.new("UIScale", { Name = "Pop", Scale = 1 }, holderBtn)
	local lip = UIKit.new("Frame", {
		Name = "Lip",
		BackgroundColor3 = BLACK,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, S.Lip),
		Size = UDim2.new(1, 0, 1, -S.Lip),
		ZIndex = 20,
	}, holderBtn)
	UIKit.new("UICorner", { CornerRadius = UDim.new(0, 18) }, lip)
	local button = UIKit.new("TextButton", {
		Name = "Face",
		AutoButtonColor = false,
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 1, -S.Lip),
		Text = "",
		ZIndex = 21,
	}, holderBtn)
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
	table.insert(steps, { Item = holderBtn, Scale = btnScale, At = CrateOpeningView.ButtonAfter })

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
		TitleScale = titleScale,
		TitleNew = new,
		TitleBlaster = blasterText,
		Crown = crown,
		NewTag = newTag,
		NewTagScale = newTagScale,
		Reveal = reveal,
		RevealScale = revealScale,
		Steps = steps,
		Ribbon = ribbon,
		RarityText = rarityText,
		Line = line,
		Name = name,
		Row = row,
		Stats = stats,
		Stars = stars,
		Value = value,
		Damage = damage,
		DamageValue = 0,
		Continue = button,
		ContinueHolder = holderBtn,
		Collected = collected,
		CollectedScale = collectedScale,
		Skip = skip,
		Calm = false,
	}
end

-- The words fit the half of the screen beside the blaster (x, y in the gui's design units).
function CrateOpeningView.fit(refs: Refs, x: number, y: number)
	refs.RevealScale.Scale = math.min(1.15, x * 0.5 / PANEL.X, y * 0.94 / PANEL.Y)
end

-- The new blaster's texts: rarity (of its ore), name, level, damage, all in the crate's colours.
function CrateOpeningView.setBlaster(refs: Refs, level: number, oreId: string)
	local ore = if oreId ~= "" then OreData.ById[oreId] else nil
	local rarity = if ore then Rarity.ById[ore.Rarity] else Rarity.ById.Common
	local tier = CaseBuilder.tier(oreId)
	local glow, color = tier.Glow, tier.Color
	refs.RarityText.Text = string.upper(rarity.Name)
	refs.Name.Text = string.upper(BlasterData.displayName(level, oreId))
	refs.Stats.Text = string.format("LV %d", level)
	refs.DamageValue = BlasterData.damage(level, oreId)
	refs.Damage.Text = Format.big(refs.DamageValue)
	local dark = color:Lerp(BLACK, 0.72)
	local bright = ColorSequence.new({
		ColorSequenceKeypoint.new(0, WHITE:Lerp(glow, 0.55)),
		ColorSequenceKeypoint.new(0.55, glow),
		ColorSequenceKeypoint.new(1, color),
	})
	for _, label in { refs.TitleBlaster, refs.RarityText } do
		local gradient = label:FindFirstChild("Colour") :: UIGradient
		gradient.Color = bright
	end
	for _, label in { refs.TitleBlaster, refs.TitleNew, refs.Name, refs.RarityText } do
		local stroke = label:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Color = dark
		end
	end
	refs.Line.BackgroundColor3 = glow
	for _, c in { refs.Row, refs.Value } do
		local edge = c:FindFirstChild("Edge") :: UIStroke
		edge.Color = glow
	end
	-- the crate's stars after the level
	local count = STARS[tier.Name] or 1
	for i, st in refs.Stars do
		st.Visible = i <= count
		st.BackgroundColor3 = WHITE:Lerp(glow, 0.3)
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
	local tagStroke = refs.NewTag:FindFirstChildOfClass("UIStroke")
	if tagStroke then
		tagStroke.Color = WHITE:Lerp(glow, 0.3)
	end
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
	flying in at `reveal`, holding and flying on; the words one after the other;
	past reveal + CollectAt (time waits there for AWESOME!) they slide away and
	COLLECTED! shows. `leaving` (0..1) fades out to black at the end.
]]
function CrateOpeningView.update(refs: Refs, t: number, burst: number, reveal: number, leaving: number?)
	local fadeIn = prog(t, 0, 0.3)
	local out = leaving or 0
	refs.Fade.BackgroundTransparency = math.min(fadeIn, 1 - out)
	refs.Fade.Visible = refs.Fade.BackgroundTransparency < 0.999
	local flash = if t >= burst then 1 - prog(t, burst, burst + 0.32) else 0
	refs.Flash.BackgroundTransparency = 1 - flash * (if refs.Calm then 0.3 else 0.95)
	refs.Flash.Visible = flash > 0.001

	-- the title flies in from the left, lands with a kick, grows slowly, flies on to the right
	local since = t - reveal
	local titleIn = prog(since, 0, 0.22)
	local titleOut = prog(since, CrateOpeningView.TitleOut, CrateOpeningView.TitleOut + 0.2)
	refs.Title.Visible = since >= 0 and titleOut < 1
	if refs.Title.Visible then
		local x = -0.7 + 1.2 * easeOutBack(titleIn) + 1.3 * titleOut * titleOut
		refs.Title.Position = UDim2.fromScale(x, 0.74)
		local land = prog(since, 0.2, 0.42)
		refs.TitleScale.Scale = 0.98 - 0.14 * easeOutBack(land) + 0.05 * prog(since, 0.42, CrateOpeningView.TitleOut)
	end

	-- the words, each popping in on its moment; they slide away when it is being collected
	local collecting = prog(since, CrateOpeningView.CollectAt, CrateOpeningView.CollectAt + 0.25)
	refs.Reveal.Visible = since >= CrateOpeningView.RibbonAt and collecting < 1
	refs.NewTag.Visible = since >= CrateOpeningView.RarityAt and collecting < 1
	if refs.NewTag.Visible then
		refs.NewTagScale.Scale = math.max(0.01, easeOutBack(prog(since, CrateOpeningView.RarityAt, CrateOpeningView.RarityAt + 0.2)))
	end
	if refs.Reveal.Visible then
		refs.Reveal.Position = UDim2.fromScale(PANEL_X + collecting * collecting * 0.8, 0.5)
		for _, s in refs.Steps do
			s.Item.Visible = since >= s.At
			if s.Item.Visible then
				s.Scale.Scale = math.max(0.01, easeOutBack(prog(since, s.At, s.At + 0.2)))
			end
		end
		local count = prog(since, CrateOpeningView.ValueAt, CrateOpeningView.ValueAt + CrateOpeningView.CountFor)
		refs.Damage.Text = Format.big(refs.DamageValue * (1 - (1 - count) ^ 3))
	end

	-- COLLECTED!
	local done = since - CrateOpeningView.CollectAt
	refs.Collected.Visible = done > 0
	if done > 0 then
		refs.CollectedScale.Scale = math.max(0.01, easeOutBack(prog(done, 0.08, 0.3)))
	end
	refs.Skip.Visible = t > 0.5 and t < burst - 0.25
end

-- The buttons (touch-size tests).
function CrateOpeningView.touchTargets(refs: Refs): { GuiObject }
	return { refs.ContinueHolder }
end

return CrateOpeningView
