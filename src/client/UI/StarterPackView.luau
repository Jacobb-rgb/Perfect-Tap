--[[
	The Starter Pack popup (StarterPackController): a small Pop kit window
	shown once per session in the first hour of play. The golem's live
	picture on the left, "Includes:" lines on the right, the time the offer
	is offered (plainly, no ticking clock: docs/COMPLIANCE.md 2.6a "No
	pressure"), the green Robux price and a quiet "Later".

	  build()                the popup (hidden)
	  setStatus(refs, text?) a line under the price (Coming soon, ...)

	Pure builder, no services: the Lune previews build it too.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local MonetizationConfig = require(Shared.Config.MonetizationConfig)
local StoreConfig = require(Shared.Config.StoreConfig)
local PictureModels = require(Shared.Builders.PictureModels)
local PopTheme = require(Shared.Config.PopTheme)
local UIKit = require(script.Parent.UIKit)
local Pop = require(script.Parent.Pop)

local StarterPackView = {}

StarterPackView.Key = "StarterPack"
StarterPackView.Size = Vector2.new(560, 340)
StarterPackView.OfferText = "Starter offer: available during your first hour"

export type Refs = {
	Gui: ScreenGui,
	Window: Pop.Window,
	Price: TextButton,
	Later: TextButton,
	Left: TextLabel,
	Status: TextLabel,
}

function StarterPackView.build(): Refs
	local product = MonetizationConfig.Products[StarterPackView.Key]
	local spec = StoreConfig.ById[StarterPackView.Key]
	local gui = UIKit.screen("TerraForgeStarterPack", 15)
	gui.Enabled = false
	gui:SetAttribute("TerraForge", true)
	local size = StarterPackView.Size
	local window = Pop.window(gui, "Starter Pack", size, 64, "Teal")
	window.Root.SelectionGroup = true
	local body = window.Body
	Pop.rays(body, UDim2.fromScale(0.24, 0.42), 12, 260, 0.82, 1)
	body.ClipsDescendants = true
	local model = if spec and spec.Model then PictureModels.build(spec.Model) else nil
	Pop.model(body, if spec then spec.Icon else "golem_GildedPorter", 190, model, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.24, 0, 0.44, 0),
		ZIndex = 4,
	})
	Pop.title(body, "FOR NEW FORGERS", 30, "Gold", {
		AnchorPoint = Vector2.new(0, 0),
		FontFace = PopTheme.Heavy,
		Position = UDim2.fromOffset(250, 12),
		Size = UDim2.fromOffset(290, 36),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 5,
	})
	local lines: { string } = if spec and spec.Lines then spec.Lines else {}
	for i, line in lines do
		Pop.text(body, "+ " .. line, 19, {
			Name = "Line" .. i,
			Position = UDim2.fromOffset(250, 24 + i * 30),
			Size = UDim2.fromOffset(296, 26),
			TextColor3 = Color3.fromRGB(255, 248, 200),
			TextScaled = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 5,
		})
	end
	local left = Pop.text(body, StarterPackView.OfferText, 15, {
		Name = "Left",
		Position = UDim2.fromOffset(250, 34 + (#lines + 1) * 30),
		Size = UDim2.fromOffset(296, 22),
		TextColor3 = Color3.fromRGB(150, 255, 220),
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 5,
	})
	local price = Pop.price(body, if product then product.Robux else nil, Vector2.new(200, 56), {
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -14, 1, -14),
		ZIndex = 6,
	})
	local later = Pop.button(body, "Later", "Slate", Vector2.new(130, 48), {
		Name = "Later",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -228, 1, -18),
		ZIndex = 6,
	})
	local status = Pop.text(body, "", 16, {
		Name = "Status",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 14, 1, -20),
		Size = UDim2.fromOffset(170, 44),
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		Visible = false,
		ZIndex = 6,
	})
	return { Gui = gui, Window = window, Price = price, Later = later, Left = left, Status = status }
end

-- A line in the popup's corner (nil hides it).
function StarterPackView.setStatus(refs: Refs, text: string?)
	refs.Status.Text = text or ""
	refs.Status.Visible = text ~= nil and text ~= ""
end

return StarterPackView
