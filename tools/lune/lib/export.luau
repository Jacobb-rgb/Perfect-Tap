--[[
	Converts Roblox instances into a compact JSON scene for the Three.js
	preview renderer (tools/preview). Only for screenshots outside Studio.
]]

local roblox = require("@lune/roblox") :: any

local Export = {}

local SHAPES = { Block = 0, Ball = 1, Cylinder = 2, Wedge = 3 }

local function hex(c): string
	return string.format("%02x%02x%02x", math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5))
end

local function round(n: number): number
	return math.floor(n * 1000 + 0.5) / 1000
end

local function cframeList(cf): { number }
	local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = cf:GetComponents()
	return {
		round(x),
		round(y),
		round(z),
		round(r00),
		round(r01),
		round(r02),
		round(r10),
		round(r11),
		round(r12),
		round(r20),
		round(r21),
		round(r22),
	}
end

local FACE_INDEX = { Front = 0, Back = 1, Top = 2, Bottom = 3, Left = 4, Right = 5 }

function Export.collect(root: any, scene: any?)
	scene = scene or { parts = {}, lights = {}, emitters = {}, texts = {} }
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") then
			if d.Transparency < 0.99 then
				local shape = SHAPES.Block
				if d.ClassName == "WedgePart" then
					shape = SHAPES.Wedge
				elseif d.ClassName == "Part" then
					local s = d.Shape
					if s == roblox.Enum.PartType.Ball then
						shape = SHAPES.Ball
					elseif s == roblox.Enum.PartType.Cylinder then
						shape = SHAPES.Cylinder
					end
				end
				local size = d.Size
				local entry = {
					shape,
					round(size.X),
					round(size.Y),
					round(size.Z),
					cframeList(d.CFrame),
					hex(d.Color),
					d.Material.Name,
					round(d.Transparency),
					round(d.Reflectance),
				}
				table.insert(scene.parts, entry)
				local partIndex = #scene.parts - 1
				for _, child in d:GetChildren() do
					if child:IsA("SurfaceGui") then
						local label = child:FindFirstChildWhichIsA("TextLabel")
						if label then
							table.insert(scene.texts, {
								partIndex,
								FACE_INDEX[child.Face.Name] or 0,
								label.Text,
								hex(label.TextColor3),
								label.FontFace.Family,
							})
						end
					end
				end
			end
		elseif d:IsA("PointLight") and d.Parent and d.Parent:IsA("BasePart") then
			local p = d.Parent.CFrame.Position
			table.insert(scene.lights, { round(p.X), round(p.Y), round(p.Z), hex(d.Color), d.Range, d.Brightness })
		elseif d:IsA("ParticleEmitter") and d.Parent and d.Parent:IsA("BasePart") then
			local p = d.Parent.CFrame.Position
			local kind = "Sparkle"
			local tex = tostring(d.Texture)
			if d.Name:sub(1, 3) == "Gun" then
				kind = d.Name -- small blaster effects (GunFlame / GunSpark)
			elseif tex:find("smoke") then
				kind = "Smoke"
			elseif tex:find("fire") then
				kind = "Fire"
			elseif d.Name:find("Ember") then
				kind = "Embers"
			end
			local color = d.Color.Keypoints[1].Value
			local size = d.Parent.Size
			local entry = { round(p.X), round(p.Y), round(p.Z), kind, hex(color), round(math.max(size.X, size.Z)) }
			if kind:sub(1, 3) == "Gun" then
				-- the emission box: world-axis half extents of the (rotated) part
				local r = d.Parent.CFrame
				local s = size / 2
				local function ext(axis: string): number
					return round(
						math.abs(r.RightVector[axis]) * s.X + math.abs(r.UpVector[axis]) * s.Y + math.abs(r.LookVector[axis]) * s.Z
					)
				end
				entry[7] = { ext("X"), ext("Y"), ext("Z") }
			end
			table.insert(scene.emitters, entry)
		end
	end
	return scene
end

return Export
