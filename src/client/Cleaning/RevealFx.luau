--[[
	The reveal of a cleaned ore, the parts that make it feel good (pure
	builders + numbers; CleaningController plays them, the preview scene
	`cleaning_reveal_strip` draws the same parts frozen at chosen moments).

	  plan(order)      how big the moment is for a rarity order: spins, length,
	                   rays, flash, shake, a slow-motion middle and a FOV punch
	                   for Legendary / Mythic
	  warp(p, slow)    the spin's progress at time share p (slow-motion: the
	                   middle runs at a quarter speed, start and end stay crisp)
	  sweep(...)       a thin white shine bar that slides across the ore face
	  stamp(...)       the grade stamp (ROUGH / CLEAN / PRISTINE / FLAWLESS)
	                   that pops onto the ore: a SurfaceGui on a thin clear part
	                   in front of the face, tilted like a stamp
	Phone-light: one bar, one stamp part, no extra particles.
]]

local RevealFx = {}

export type Plan = {
	Spins: number, -- full turns of the rising ore
	Duration: number, -- seconds of the rise and spin
	Rays: number, -- light rays (Legendary 8, Mythic 12)
	Flash: number, -- start transparency of the screen flash (lower = stronger)
	Shake: number, -- CameraShake trauma
	SlowMo: boolean, -- the middle of the spin in slow motion
	FovPunch: number, -- degrees the view narrows for a moment (0 = none)
	Fanfare: boolean, -- an extra discovery sound
}

RevealFx.SweepDelay = 0.55 -- seconds after the reveal starts
RevealFx.SweepTime = 0.4
RevealFx.SweepColor = Color3.fromRGB(255, 252, 240)
RevealFx.StampTilt = math.rad(-12)
RevealFx.TouchShake = 0.3 -- phones and tablets get this share of the camera shake
-- Studs the treasure rises in the reveal (in the face's frame): up, clear of the card, and a little
-- toward the camera. The light rays tilt back behind it, so they never cross the ore.
RevealFx.Rise = Vector3.new(0, 0.55, 0.45)
RevealFx.RayTilt = -0.35

function RevealFx.plan(order: number): Plan
	local big = order >= 5
	return {
		Spins = 1 + order * 0.25,
		Duration = 2.4 + order * 0.25 + (if big then 0.9 else 0),
		Rays = if order >= 6 then 12 elseif big then 8 else 0,
		Flash = if big then 0.35 else 0.65,
		Shake = 0.25 + order * 0.05,
		SlowMo = big,
		FovPunch = if order >= 6 then 8 elseif big then 6 else 0,
		Fanfare = big,
	}
end

-- Progress of the spin at time share p (0..1); slow motion keeps 0 and 1 and
-- never runs backwards (its speed dips to a quarter in the middle).
function RevealFx.warp(p: number, slow: boolean): number
	p = math.clamp(p, 0, 1)
	if not slow then
		return p
	end
	return p + 0.75 * math.sin(2 * math.pi * p) / (2 * math.pi)
end

-- The shine bar: a thin Neon slab in front of the ore face. Returns it and a
-- function that places it at progress p (0..1: from lower left to upper right).
function RevealFx.sweep(parent: Instance, face: CFrame, front: number, size: number): (Part, (number) -> ())
	local bar = Instance.new("Part")
	bar.Name = "RevealSweep"
	bar.Anchored = true
	bar.CanCollide = false
	bar.CanQuery = false
	bar.CanTouch = false
	bar.CastShadow = false
	bar.Material = Enum.Material.Neon
	bar.Color = RevealFx.SweepColor
	bar.Size = Vector3.new(0.18, size * 1.6, 0.04)
	bar.Transparency = 1
	bar.Parent = parent
	local function at(p: number)
		local u = -size + 2 * size * math.clamp(p, 0, 1)
		bar.CFrame = face * CFrame.new(u, u * 0.35, front) * CFrame.Angles(0, 0, math.rad(-28))
		-- fades in and out at the ends, brightest in the middle
		bar.Transparency = 1 - 0.75 * math.sin(math.pi * math.clamp(p, 0, 1))
	end
	at(0)
	return bar, at
end

-- The grade stamp: a clear thin part in front of the face (lower right of the
-- ore), its SurfaceGui shows the grade in the grade colour; `Pop` is the
-- UIScale the controller tweens (from StampFrom to 1).
RevealFx.StampFrom = 2.4
function RevealFx.stamp(parent: Instance, face: CFrame, front: number, text: string, color: Color3): (Part, UIScale)
	local plate = Instance.new("Part")
	plate.Name = "GradeStamp"
	plate.Anchored = true
	plate.CanCollide = false
	plate.CanQuery = false
	plate.CanTouch = false
	plate.CastShadow = false
	plate.Transparency = 1
	plate.Size = Vector3.new(1.9, 0.62, 0.02)
	plate.CFrame = face * CFrame.new(0.55, -0.62, front) * CFrame.Angles(0, math.pi, RevealFx.StampTilt)
	plate.Parent = parent
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Stamp"
	gui.Face = Enum.NormalId.Front
	gui.LightInfluence = 0
	gui.AlwaysOnTop = true
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 100
	gui.Parent = plate
	local box = Instance.new("Frame")
	box.Name = "Box"
	box.AnchorPoint = Vector2.new(0.5, 0.5)
	box.Position = UDim2.fromScale(0.5, 0.5)
	box.Size = UDim2.fromScale(0.96, 0.86)
	box.BackgroundColor3 = Color3.fromRGB(20, 14, 12)
	box.BackgroundTransparency = 0.35
	box.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.2, 0)
	corner.Parent = box
	local border = Instance.new("UIStroke")
	border.Color = color
	border.Thickness = 6
	border.Parent = box
	local label = Instance.new("TextLabel")
	label.Name = "Grade"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Text = string.upper(text)
	label.TextColor3 = color
	label.TextScaled = true
	label.FontFace = Font.fromEnum(Enum.Font.LuckiestGuy)
	label.Parent = box
	local pop = Instance.new("UIScale")
	pop.Name = "Pop"
	pop.Scale = 1
	pop.Parent = box
	return plate, pop
end

return RevealFx
