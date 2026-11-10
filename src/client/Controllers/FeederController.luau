--[[
	FeederController: the Ore Feeder's counter (tag FeederScreen, a screen
	part on its side, KitMachines): "stored / capacity" from the feeder
	model's Stored and Capacity attributes (FeederService), redrawn when they
	change. Feeders stream in and out with their plots.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Theme = require(ReplicatedStorage:WaitForChild("Shared").Config.UITheme)

local FeederController = {}

FeederController.Tag = "FeederScreen"
FeederController.MaxDistance = 80 -- studs: past this the counter doesn't draw

-- The counter's text ("142 / 200"; "0 / 200" for an empty feeder, "" before the server says).
function FeederController.text(stored: any, capacity: any): string
	if type(capacity) ~= "number" then
		return ""
	end
	local n = if type(stored) == "number" then math.max(0, math.floor(stored)) else 0
	return `{n} / {math.floor(capacity)}`
end

local connections: { [Instance]: { RBXScriptConnection } } = {}

local function added(screen: Instance)
	if not screen:IsA("BasePart") or connections[screen] then
		return
	end
	local model = screen:FindFirstAncestorOfClass("Model")
	if not model then
		return
	end
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Counter"
	gui.Face = Enum.NormalId.Front
	gui.LightInfluence = 0
	gui.MaxDistance = FeederController.MaxDistance
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.FontFace = Theme.TitleFont
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(70, 220, 255)
	label.Parent = gui
	gui.Parent = screen
	local function update()
		label.Text = FeederController.text(model:GetAttribute("Stored"), model:GetAttribute("Capacity"))
	end
	update()
	connections[screen] = {
		model:GetAttributeChangedSignal("Stored"):Connect(update),
		model:GetAttributeChangedSignal("Capacity"):Connect(update),
	}
end

local function removed(screen: Instance)
	local list = connections[screen]
	if list then
		for _, connection in list do
			connection:Disconnect()
		end
		connections[screen] = nil
	end
end

function FeederController.init() end

function FeederController.start()
	CollectionService:GetInstanceAddedSignal(FeederController.Tag):Connect(added)
	CollectionService:GetInstanceRemovedSignal(FeederController.Tag):Connect(removed)
	for _, screen in CollectionService:GetTagged(FeederController.Tag) do
		added(screen)
	end
end

return FeederController
