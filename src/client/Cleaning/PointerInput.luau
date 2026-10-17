--[[
	One pointer for every device during the cleaning minigame:
	  Mouse   : position = mouse, down = left button
	  Touch   : position = first finger, down while touching
	  Gamepad : a virtual cursor moved with the left stick, down = A or R2;
	            the raw stick is also exposed (polishing uses its angle)
	Positions are viewport pixels (what Camera:ViewportPointToRay expects).
]]

local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local PointerInput = {}
PointerInput.__index = PointerInput

export type Pointer = typeof(setmetatable(
	{} :: {
		Position: Vector2,
		Down: boolean,
		Kind: string,
		Stick: Vector2,
		Moved: boolean,
		connections: { RBXScriptConnection },
		touch: InputObject?,
	},
	PointerInput
))

local STICK_SPEED = 0.9 -- screen heights per second at full tilt
local DEADZONE = 0.15

-- What the player is using right now (a PC with a controller plugged in counts as Gamepad).
local function currentKind(): string
	local last = UserInputService:GetLastInputType()
	if last == Enum.UserInputType.Touch then
		return "Touch"
	elseif last.Name:sub(1, 7) == "Gamepad" then
		return "Gamepad"
	elseif last == Enum.UserInputType.MouseMovement or last.Name:sub(1, 11) == "MouseButton" or last == Enum.UserInputType.Keyboard then
		return "Mouse"
	end
	if UserInputService.GamepadEnabled and not UserInputService.MouseEnabled and not UserInputService.TouchEnabled then
		return "Gamepad"
	elseif UserInputService.TouchEnabled and not UserInputService.MouseEnabled then
		return "Touch"
	end
	return "Mouse"
end

function PointerInput.new(): Pointer
	local camera = Workspace.CurrentCamera
	local kind = currentKind()
	local self = setmetatable({
		Position = camera.ViewportSize / 2,
		Down = false,
		Kind = kind,
		Stick = Vector2.zero,
		Moved = false,
		connections = {},
		touch = nil,
	}, PointerInput)
	return self
end

local function touchToViewport(position: Vector3): Vector2
	local inset = GuiService:GetGuiInset()
	return Vector2.new(position.X, position.Y) + inset
end

function PointerInput.start(self: Pointer)
	local c = self.connections
	table.insert(
		c,
		UserInputService.InputBegan:Connect(function(input, processed)
			if processed then
				return
			end
			local t = input.UserInputType
			if t == Enum.UserInputType.MouseButton1 then
				self.Kind = "Mouse"
				self.Down = true
			elseif t == Enum.UserInputType.Touch then
				if not self.touch then
					self.Kind = "Touch"
					self.touch = input
					self.Position = touchToViewport(input.Position)
					self.Down = true
				end
			elseif input.KeyCode == Enum.KeyCode.ButtonA or input.KeyCode == Enum.KeyCode.ButtonR2 then
				self.Kind = "Gamepad"
				self.Down = true
			end
		end)
	)
	table.insert(
		c,
		UserInputService.InputChanged:Connect(function(input)
			local t = input.UserInputType
			if t == Enum.UserInputType.Touch and (input :: any) == self.touch then
				self.Position = touchToViewport(input.Position)
			elseif input.KeyCode == Enum.KeyCode.Thumbstick1 then
				local v = Vector2.new(input.Position.X, -input.Position.Y)
				self.Stick = if v.Magnitude > DEADZONE then v else Vector2.zero
				if v.Magnitude > DEADZONE then
					self.Kind = "Gamepad"
				end
			elseif t == Enum.UserInputType.MouseMovement then
				self.Kind = "Mouse"
			end
		end)
	)
	table.insert(
		c,
		UserInputService.InputEnded:Connect(function(input)
			local t = input.UserInputType
			if t == Enum.UserInputType.MouseButton1 then
				self.Down = false
			elseif t == Enum.UserInputType.Touch and (input :: any) == self.touch then
				self.touch = nil
				self.Down = false
			elseif input.KeyCode == Enum.KeyCode.ButtonA or input.KeyCode == Enum.KeyCode.ButtonR2 then
				self.Down = false
			end
		end)
	)
end

-- Call every frame.
function PointerInput.update(self: Pointer, dt: number)
	local camera = Workspace.CurrentCamera
	local size = camera.ViewportSize
	local before = self.Position
	if self.Kind == "Mouse" then
		self.Position = UserInputService:GetMouseLocation()
	elseif self.Kind == "Gamepad" and self.Stick.Magnitude > 0 then
		self.Position += self.Stick * STICK_SPEED * size.Y * dt
		self.Position = Vector2.new(math.clamp(self.Position.X, 0, size.X), math.clamp(self.Position.Y, 0, size.Y))
	end
	self.Moved = (self.Position - before).Magnitude > 0.5
end

-- Places the gamepad cursor (e.g. at the start of a guide line).
function PointerInput.warp(self: Pointer, position: Vector2)
	if self.Kind == "Gamepad" then
		self.Position = position
	end
end

function PointerInput.stop(self: Pointer)
	for _, connection in self.connections do
		connection:Disconnect()
	end
	table.clear(self.connections)
	self.Down = false
	self.touch = nil
end

return PointerInput
