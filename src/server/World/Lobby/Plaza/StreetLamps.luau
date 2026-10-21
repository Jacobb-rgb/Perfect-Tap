--[[
	The street lamps along every road (owner 2026-10-20, after the owner's
	TERRAFORGE street lamp picture: "lamps along the roads, the whole map
	lit"). Spots: StreetLampPlan. Built from WorldBuilder after Plaza/Life
	(the lobby packages, the stream and the plaza life stand already), into
	Emberfall.Lobby.Plaza.StreetLamps, so it counts in the Plaza budget; a
	spot whose pole, arm or head would cut into anything already built is
	left out.

	The lamp (Kenney-style chunky sci-fi, all parts, no meshes): a stepped
	dark metal foot with an orange glowing panel, a square grey pole with a
	deep-orange neon slot up its road face and an orange collar, a dark
	joint block at the top, an arm tilted up over the road with an orange
	neon brace under it, and a wide dark head with an orange rim round a
	warm glowing panel underneath. Small 12 parts, Medium/Tall 14. Every
	other lamp of a road carries a PointLight (shadows off) in the panel.
	When its spot is taken, a lamp moves to the plan's next place.
]]

local Style = require(script.Parent.Parent.Style)
local Common = require(script.Parent.Common)
local StreetLampPlan = require(script.Parent.StreetLampPlan)
local Meadow = require(script.Parent.Parent.Flora.Meadow)

local K = Common.Colors
local NEON = Enum.Material.Neon
local rgb = Color3.fromRGB

local StreetLamps = {}

StreetLamps.Colors = {
	Pole = rgb(66, 70, 86), -- grey machine metal (a touch lighter than the plinths)
	Panel = rgb(255, 196, 96), -- warm lamp panel (stays warm under bloom, never white)
	Light = rgb(255, 190, 110),
}
StreetLamps.ArmTilt = math.rad(9)
StreetLamps.Brightness = 1.2 -- (phones: <= 1.2, integrator 2026-10-21)

--[[
	One lamp. `base`: ground point under the pole, LookVector = toward the
	road (the arm's direction). Returns the model (PrimaryPart = the
	glowing panel "LampGlow").
]]
function StreetLamps.lamp(parent: Instance, base: CFrame, size: string, lit: boolean): Model
	local spec = StreetLampPlan.Sizes[size]
	assert(spec, "unknown street lamp size " .. size)
	local h, arm = spec.Height, spec.Arm
	local small = size == "Small"
	local m = Style.model("StreetLamp", parent)
	m:SetAttribute("Size", size)
	local function at(x: number, y: number, z: number): CFrame
		return base * CFrame.new(x, y, z)
	end
	-- the stepped foot: a wide dark plate, a grey plinth with an orange panel on
	-- both faces along the road, a dark chamfer cap
	local foot = StreetLampPlan.BaseHalf * 2
	Style.block(m, at(0, 0.16, 0), Vector3.new(foot, 0.32, foot), K.MetalDark, nil, Style.decor()).Name = "Foot"
	local plinthH = if small then 1.0 else 1.3
	Style.block(m, at(0, 0.32 + plinthH / 2, 0), Vector3.new(1.42, plinthH, 1.42), K.Metal, nil, Style.decor()).Name = "Plinth"
	local accent = Style.block(m, at(0, 0.32 + plinthH / 2, 0), Vector3.new(1.48, plinthH * 0.5, 0.5), K.SlotAmber, NEON, Style.tiny())
	accent.Name = "PlinthGlow"
	local capY = 0.32 + plinthH + 0.13
	Style.block(m, at(0, capY, 0), Vector3.new(1.12, 0.26, 1.12), K.MetalDark, nil, Style.tiny()).Name = "PlinthCap"
	-- the pole with its slot on the road face (and the back)
	local poleBottom = capY + 0.13
	local poleH = h - poleBottom
	Style.block(m, at(0, poleBottom + poleH / 2, 0), Vector3.new(0.72, poleH, 0.72), StreetLamps.Colors.Pole, nil, Style.decor()).Name =
		"Pole"
	local slotLo, slotHi = poleBottom + 0.5, h - 1.4
	local slotH = slotHi - slotLo
	local slot = Style.block(m, at(0, slotLo + slotH / 2, 0), Vector3.new(0.18, slotH, 0.78), K.SlotAmber, NEON, Style.tiny())
	slot.Name = "PoleSlot"
	if not small then
		local collar = Style.block(m, at(0, slotLo + slotH * 0.36, 0), Vector3.new(0.84, 0.26, 0.84), K.NeonOrange, NEON, Style.tiny())
		collar.Name = "Collar"
	end
	-- the joint block at the top
	Style.block(m, at(0, h, 0), Vector3.new(1.0, 0.95, 1.0), K.MetalDark, nil, Style.tiny()).Name = "Joint"
	-- the arm, tilted up over the road (local -Z = toward the road)
	local armRoot = at(0, h + 0.1, 0) * CFrame.Angles(StreetLamps.ArmTilt, 0, 0)
	Style.block(m, armRoot * CFrame.new(0, 0, -arm / 2), Vector3.new(0.56, 0.46, arm), K.MetalDark, nil, Style.tiny()).Name = "Arm"
	-- the brace: from low on the pole's road face up to the arm's middle
	local braceFrom = at(0, h - (if small then 1.3 else 1.9), -0.38).Position
	local braceTo = (armRoot * CFrame.new(0, -0.2, -arm * 0.58)).Position
	local braceLen = (braceTo - braceFrom).Magnitude
	local brace =
		Style.block(m, CFrame.lookAt((braceFrom + braceTo) / 2, braceTo), Vector3.new(0.2, 0.2, braceLen), K.SlotAmber, NEON, Style.tiny())
	brace.Name = "Brace"
	-- the head: a wide dark housing at the arm's end, an orange rim and the
	-- warm panel under it
	local head = armRoot * CFrame.new(0, -0.05, -arm - (if small then 0.55 else 0.75))
	local headL = if small then 1.6 else 2.3
	local headW = if small then 1.05 else 1.35
	Style.block(m, head, Vector3.new(headW, 0.44, headL), K.MetalDark, nil, Style.tiny()).Name = "Head"
	if not small then
		Style.block(m, head * CFrame.new(0, 0.3, 0.1), Vector3.new(headW - 0.3, 0.2, headL - 0.5), K.Metal, nil, Style.tiny()).Name =
			"HeadCap"
	end
	local rim =
		Style.block(m, head * CFrame.new(0, -0.24, 0), Vector3.new(headW - 0.12, 0.08, headL - 0.14), K.NeonOrange, NEON, Style.tiny())
	rim.Name = "HeadRim"
	local glow = Style.block(
		m,
		head * CFrame.new(0, -0.28, 0),
		Vector3.new(headW - 0.42, 0.1, headL - 0.46),
		StreetLamps.Colors.Panel,
		NEON,
		Style.tiny()
	)
	glow.Name = "LampGlow"
	if lit then
		Style.light(glow, StreetLamps.Colors.Light, spec.Range, StreetLamps.Brightness)
	end
	m.PrimaryPart = glow
	return m
end

-- Is the lamp at `spot` clear of everything built so far (the pole column
-- above the ground clutter, the arm and the head)?
local function fits(index: Meadow.Index, size: string, place: StreetLampPlan.Place, built: { Vector3 }): boolean
	local spec = StreetLampPlan.Sizes[size]
	local p = place.Position
	for _, other in built do
		if (other - p).Magnitude < StreetLampPlan.MinGap then
			return false
		end
	end
	if not Meadow.freeBand(index, p, StreetLampPlan.BaseHalf, 0.45, spec.Height + 0.6) then
		return false
	end
	for _, f in { 0.45, 0.9, 1.25 } do
		local q = p + place.Facing * (spec.Arm * f)
		if not Meadow.freeBand(index, q, 0.7, spec.Height - 0.8, spec.Height + 1.4) then
			return false
		end
	end
	return true
end

function StreetLamps.build(map: Instance): Model?
	if not StreetLampPlan.Enabled then
		return nil
	end
	local emberfall = map:FindFirstChild("Emberfall")
	local lobby = emberfall and emberfall:FindFirstChild("Lobby")
	local plaza = lobby and lobby:FindFirstChild("Plaza")
	local m = Style.model("StreetLamps", plaza or map)
	local index = Meadow.index(map)
	local skipped = 0
	local built: { Vector3 } = {}
	for _, spot in StreetLampPlan.spots() do
		local chosen: StreetLampPlan.Place? = nil
		for _, place in { { Position = spot.Position, Facing = spot.Facing } :: StreetLampPlan.Place, table.unpack(spot.Alternates) } do
			if fits(index, spot.Size, place, built) then
				chosen = place
				break
			end
		end
		if chosen then
			local lamp = StreetLamps.lamp(m, CFrame.lookAt(chosen.Position, chosen.Position + chosen.Facing), spot.Size, spot.Lit)
			lamp:SetAttribute("Road", spot.Road)
			Meadow.track(index, lamp)
			table.insert(built, chosen.Position)
		else
			skipped += 1
		end
	end
	m:SetAttribute("Skipped", skipped)
	return m
end

return StreetLamps
