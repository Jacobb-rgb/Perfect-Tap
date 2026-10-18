--[[
	The screen over the crate-opening cinematic (VaultController plays the
	3D stage, Builders/CrateOpeningStage): a fade in from black, the white
	flash at the burst, then "NEW BLASTER!" with the rarity, the blaster's
	name, its level and damage, and the AWESOME! button. Before the burst a
	small hint says how to skip ahead.

	Pure and time-driven: update(refs, t, burst, reveal) poses everything for
	time t (seconds since the cinematic started), so the Lune preview
	exports any moment with the same code. In the light "Bubble" look
	(VaultView.Style).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BlasterData = require(Shared.Config.BlasterData)
local OreData = require(Shared.Config.OreData)
local Rarity = require(Shared.Config.Rarity)
local Format = require(Shared.Util.Format)
local UIKit = require(script.Parent.UIKit)
local VaultView = require(script.Parent.VaultView)

local CrateOpeningView = {}

local S = VaultView.Style

CrateOpeningView.ButtonAfter = 0.8 -- seconds after the reveal: AWESOME! shows

export type Refs = {
	Gui: ScreenGui,
	Fade: Frame,
	Flash: Frame,
	Catcher: TextButton, -- the whole screen: a click / tap skips ahead or ends
	Reveal: Frame,
	RevealScale: UIScale,
	Title: TextLabel,
	RarityPill: Frame,
	RarityText: TextLabel,
	Name: TextLabel,
	Stats: TextLabel,
	Continue: TextButton,
	ContinueHolder: Frame,
	Skip: TextLabel,
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

local function outlined(label: TextLabel, thickness: number)
	UIKit.new("UIStroke", {
		Thickness = thickness,
		Color = S.Outline,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
	}, label)
end

function CrateOpeningView.build(): Refs
	local gui = UIKit.screen("TerraForgeCrateOpening", 40)
	gui:SetAttribute("TerraForge", true)
	gui.IgnoreGuiInset = true
	local fade = UIKit.new("Frame", {
		Name = "Fade",
		BackgroundColor3 = Color3.new(0, 0, 0),
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 50,
	}, gui)
	local flash = UIKit.new("Frame", {
		Name = "Flash",
		BackgroundColor3 = Color3.new(1, 1, 1),
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
	-- the reveal: the title at the top, the name and stats at the bottom (the blaster floats between)
	local reveal = UIKit.new("Frame", {
		Name = "Reveal",
		AnchorPoint = Vector2.new(0.5, 0.5), -- the pop scales around the middle
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		ZIndex = 10,
	}, gui)
	local revealScale = UIKit.new("UIScale", { Name = "Pop", Scale = 1 }, reveal)
	local title = UIKit.new("TextLabel", {
		Name = "Title",
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundTransparency = 1,
		Position = UDim2.new(0.5, 0, 0, 54),
		Size = UDim2.fromOffset(760, 84),
		Text = "NEW BLASTER!",
		TextColor3 = S.White,
		TextSize = 72,
		FontFace = S.TitleFont,
		ZIndex = 12,
	}, reveal)
	outlined(title, 5)
	UIKit.new("UIGradient", {
		Color = ColorSequence.new(Color3.fromRGB(255, 250, 214), S.Gold),
		Rotation = 90,
	}, title)
	local pill = UIKit.new("Frame", {
		Name = "RarityPill",
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundColor3 = S.Gold,
		BorderSizePixel = 0,
		Position = UDim2.new(0.5, 0, 0, 142),
		Size = UDim2.fromOffset(170, 38),
		ZIndex = 12,
	}, reveal)
	UIKit.new("UICorner", { CornerRadius = UDim.new(0, 19) }, pill)
	UIKit.new("UIStroke", { Thickness = 3, Color = S.Outline }, pill)
	local rarityText = UIKit.new("TextLabel", {
		Name = "Text",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Text = "EPIC",
		TextColor3 = S.White,
		TextSize = 24,
		FontFace = S.TitleFont,
		ZIndex = 13,
	}, pill)
	outlined(rarityText, 2.5)
	local name = UIKit.new("TextLabel", {
		Name = "BlasterName",
		AnchorPoint = Vector2.new(0.5, 1),
		BackgroundTransparency = 1,
		Position = UDim2.new(0.5, 0, 1, -150),
		Size = UDim2.fromOffset(900, 56),
		Text = "",
		TextColor3 = S.White,
		TextSize = 46,
		FontFace = S.TitleFont,
		ZIndex = 12,
	}, reveal)
	outlined(name, 4)
	local stats = UIKit.new("TextLabel", {
		Name = "Stats",
		AnchorPoint = Vector2.new(0.5, 1),
		BackgroundTransparency = 1,
		Position = UDim2.new(0.5, 0, 1, -112),
		Size = UDim2.fromOffset(700, 34),
		Text = "",
		TextColor3 = S.White,
		TextSize = 28,
		FontFace = S.Font,
		ZIndex = 12,
	}, reveal)
	outlined(stats, 3)
	-- AWESOME!: a big green bubble button
	local holder = UIKit.new("Frame", {
		Name = "Continue",
		AnchorPoint = Vector2.new(0.5, 1),
		BackgroundTransparency = 1,
		Position = UDim2.new(0.5, 0, 1, -22),
		Size = UDim2.fromOffset(280, 72 + S.Lip),
		Visible = false,
		ZIndex = 20,
	}, gui)
	local go = S.Roles.Go
	local lip = UIKit.new("Frame", {
		Name = "Lip",
		BackgroundColor3 = go.Lip,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, S.Lip),
		Size = UDim2.new(1, 0, 1, -S.Lip),
		ZIndex = 20,
	}, holder)
	UIKit.new("UICorner", { CornerRadius = UDim.new(0, 18) }, lip)
	UIKit.new("UIStroke", { Thickness = S.Stroke, Color = S.Outline }, lip)
	local button = UIKit.new("TextButton", {
		Name = "Face",
		AutoButtonColor = false,
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 1, -S.Lip),
		Text = "",
		ZIndex = 21,
	}, holder)
	UIKit.new("UICorner", { CornerRadius = UDim.new(0, 18) }, button)
	UIKit.new("UIStroke", { Thickness = S.Stroke, Color = S.Outline }, button)
	UIKit.new("UIGradient", { Color = ColorSequence.new(go.Top, go.Base), Rotation = 90 }, button)
	local label = UIKit.new("TextLabel", {
		Name = "Label",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Text = "AWESOME!",
		TextColor3 = S.White,
		TextSize = 36,
		FontFace = S.TitleFont,
		ZIndex = 22,
	}, button)
	outlined(label, 3)
	local skip = UIKit.new("TextLabel", {
		Name = "Skip",
		AnchorPoint = Vector2.new(0.5, 1),
		BackgroundTransparency = 1,
		Position = UDim2.new(0.5, 0, 1, -28),
		Size = UDim2.fromOffset(500, 28),
		Text = "Click to skip",
		TextColor3 = S.White,
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
		Reveal = reveal,
		RevealScale = revealScale,
		Title = title,
		RarityPill = pill,
		RarityText = rarityText,
		Name = name,
		Stats = stats,
		Continue = button,
		ContinueHolder = holder,
		Skip = skip,
	}
end

-- The new blaster's texts: rarity (of its ore), name, "LV 7 · 187 DMG/s".
function CrateOpeningView.setBlaster(refs: Refs, level: number, oreId: string)
	local ore = if oreId ~= "" then OreData.ById[oreId] else nil
	local rarity = if ore then Rarity.ById[ore.Rarity] else Rarity.ById.Common
	refs.RarityText.Text = string.upper(rarity.Name)
	refs.RarityPill.BackgroundColor3 = rarity.Color
	refs.Name.Text = string.upper(BlasterData.displayName(level, oreId))
	refs.Stats.Text = string.format("LV %d%s%s DMG/s", level, VaultView.Separator, Format.big(BlasterData.damage(level, oreId)))
end

function CrateOpeningView.setSkipText(refs: Refs, text: string)
	refs.Skip.Text = text
end

--[[
	Poses the overlay for time t: the fade in (0..0.35 s), the flash at
	`burst`, the reveal popping in at `reveal`, AWESOME! a moment later, the
	skip hint until just before the burst. `leaving` (0..1) fades out to
	black at the end.
]]
function CrateOpeningView.update(refs: Refs, t: number, burst: number, reveal: number, leaving: number?)
	local fadeIn = prog(t, 0, 0.35)
	local out = leaving or 0
	refs.Fade.BackgroundTransparency = math.min(fadeIn, 1 - out)
	refs.Fade.Visible = refs.Fade.BackgroundTransparency < 0.999
	local flash = if t >= burst then 1 - prog(t, burst, burst + 0.45) else 0
	refs.Flash.BackgroundTransparency = 1 - flash * 0.85
	refs.Flash.Visible = flash > 0.001
	local shown = t >= reveal
	refs.Reveal.Visible = shown
	if shown then
		local pop = prog(t, reveal, reveal + 0.4)
		refs.RevealScale.Scale = math.max(0.01, easeOutBack(pop))
	end
	refs.ContinueHolder.Visible = t >= reveal + CrateOpeningView.ButtonAfter
	refs.Skip.Visible = t > 0.6 and t < burst - 0.25
end

-- The buttons (touch-size tests).
function CrateOpeningView.touchTargets(refs: Refs): { GuiObject }
	return { refs.ContinueHolder }
end

return CrateOpeningView
