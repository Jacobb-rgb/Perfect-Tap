--[[
	SellController: the feedback when your items are sold (Pell's bin and
	counter, Sell Chutes).

	- Fx 'Sold'(pos, total, count, rarityId), to the seller: a big '+N' in
	  the best rarity's colour rises 3 studs and fades (a pool of 3
	  billboards), a coin burst that grows with the combo, and coin sounds
	  pitched up as the combo grows. The server sends the running total of a
	  combo, so quick sales keep pumping the same '+N' instead of stacking.
	- Fx 'SellPuff'(pos), to players nearby: a small gold glint.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Rarity = require(Shared.Config.Rarity)
local Theme = require(Shared.Config.UITheme)
local Format = require(Shared.Util.Format)
local UIKit = require(script.Parent.Parent.UI.UIKit)
local Vfx = require(script.Parent.Parent.Effects.Vfx)
local Sfx = require(script.Parent.Parent.Effects.Sfx)
local FxController = require(script.Parent.FxController)

local SellController = {}

type Popup = {
	Part: Part,
	Gui: BillboardGui,
	Amount: TextLabel,
	AmountStroke: UIStroke?,
	Combo: TextLabel,
	ComboStroke: UIStroke?,
	Scale: UIScale,
	Token: number,
}

local POOL_SIZE = 3
local RISE = 3 -- studs
local RISE_TIME = 0.9
local FADE_TIME = 0.35
-- a new 'Sold' this soon after the last one pumps the same popup
local REUSE_WINDOW = GameConfig.SellComboWindow + 0.2

local pool: { Popup } = {}
local nextPopup = 1
local lastPopup: Popup? = nil
local lastAt = -math.huge

local function newPopup(folder: Folder, index: number): Popup
	local part = UIKit.new("Part", {
		Name = "SellPopup" .. index,
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
		Transparency = 1,
		Size = Vector3.new(0.2, 0.2, 0.2),
	}, folder)
	local gui = UIKit.new("BillboardGui", {
		Name = "Sold",
		Size = UDim2.fromOffset(240, 96),
		AlwaysOnTop = true,
		LightInfluence = 0,
		MaxDistance = 150,
		Enabled = false,
		Adornee = part,
	}, part)
	local scale = UIKit.new("UIScale", { Scale = 1 }, gui)
	local amount = UIKit.label(gui, "+0", 46, {
		Name = "Amount",
		Size = UDim2.new(1, 0, 0, 58),
		FontFace = Theme.TitleFont,
		TextColor3 = Theme.Coin,
	})
	local combo = UIKit.label(gui, "", 22, {
		Name = "Combo",
		Position = UDim2.fromOffset(0, 58),
		Size = UDim2.new(1, 0, 0, 28),
		TextColor3 = Theme.Text,
	})
	return {
		Part = part,
		Gui = gui,
		Amount = amount,
		AmountStroke = amount:FindFirstChildOfClass("UIStroke"),
		Combo = combo,
		ComboStroke = combo:FindFirstChildOfClass("UIStroke"),
		Scale = scale,
		Token = 0,
	}
end

local function ensurePool()
	if #pool > 0 and pool[1].Part.Parent then
		return
	end
	table.clear(pool)
	local folder = Instance.new("Folder")
	folder.Name = "SellFx"
	folder.Parent = Workspace
	for i = 1, POOL_SIZE do
		table.insert(pool, newPopup(folder, i))
	end
	nextPopup = 1
	lastPopup = nil
end

local function setTransparency(popup: Popup, value: number, tween: TweenInfo?)
	local targets: { Instance } = { popup.Amount, popup.Combo }
	local strokes: { Instance } = {}
	if popup.AmountStroke then
		table.insert(strokes, popup.AmountStroke)
	end
	if popup.ComboStroke then
		table.insert(strokes, popup.ComboStroke)
	end
	for _, label in targets do
		if tween then
			TweenService:Create(label, tween, { TextTransparency = value }):Play()
		else
			(label :: TextLabel).TextTransparency = value
		end
	end
	for _, stroke in strokes do
		if tween then
			TweenService:Create(stroke, tween, { Transparency = value }):Play()
		else
			(stroke :: UIStroke).Transparency = value
		end
	end
end

local function showPopup(position: Vector3, total: number, count: number, color: Color3)
	ensurePool()
	local now = os.clock()
	local popup: Popup
	local reuse = lastPopup
	if reuse and count > 1 and now - lastAt <= REUSE_WINDOW then
		popup = reuse
	else
		popup = pool[nextPopup]
		nextPopup = nextPopup % #pool + 1
	end
	lastPopup, lastAt = popup, now
	popup.Token += 1
	local token = popup.Token

	popup.Part.CFrame = CFrame.new(position + Vector3.new(0, 1.5, 0))
	popup.Amount.Text = "+" .. Format.commas(total)
	popup.Amount.TextColor3 = color
	popup.Combo.Text = if count > 1 then `x{count} COMBO` else ""
	popup.Gui.StudsOffsetWorldSpace = Vector3.zero
	popup.Gui.Enabled = true
	setTransparency(popup, 0, nil)
	-- pop in, rise, then fade near the top
	popup.Scale.Scale = 1.45 + 0.05 * math.min(count, 8)
	TweenService:Create(popup.Scale, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	TweenService:Create(popup.Gui, TweenInfo.new(RISE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		StudsOffsetWorldSpace = Vector3.new(0, RISE, 0),
	}):Play()
	setTransparency(popup, 1, TweenInfo.new(FADE_TIME, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, 0, false, RISE_TIME - FADE_TIME))
	task.delay(RISE_TIME + 0.05, function()
		if popup.Token == token then
			popup.Gui.Enabled = false
		end
	end)
end

-- Your items were sold: (position, combo total, combo count, best rarity id).
local function onSold(position: any, total: any, count: any, rarityId: any)
	if typeof(position) ~= "Vector3" or type(total) ~= "number" or type(count) ~= "number" then
		return
	end
	local items = math.max(1, math.floor(count))
	local info = if type(rarityId) == "string" then Rarity.ById[rarityId] else nil
	local color = if info and info.Order > 1 then info.Color else Theme.Coin
	showPopup(position, total, items, color)
	Vfx.burst("Burst", position, math.min(30, 6 + items * 3), Theme.Coin)
	if info and info.Order > 1 then
		Vfx.burst("Glint", position, 4 + info.Order * 2, info.Color)
	end
	local pitch = 1 + 0.05 * math.min(items, 8)
	Sfx.play("CoinBurst", nil, pitch)
	Sfx.play("Sell", nil, pitch)
end

-- Someone near you sold something.
local function onSellPuff(position: any)
	if typeof(position) ~= "Vector3" then
		return
	end
	Vfx.burst("Glint", position, 6, Theme.Coin)
end

function SellController.init()
	FxController.register("Sold", onSold)
	FxController.register("SellPuff", onSellPuff)
end

return SellController
