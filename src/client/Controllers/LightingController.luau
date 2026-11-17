--[[
	Tweens Lighting and post effects to the preset of the zone the player is
	in (town, quarry, caves...). Other code can push a temporary preset on top
	(the cleaning close-up uses "Workbench") and pop it again.

	The golden-hour sky (docs/ART_DIRECTION.md section 7) is set up here once:
	- a Sky object (LightingConfig.Sky) if the place has none
	- Workspace.Terrain.Clouds (LightingConfig.Clouds) if missing
	- alignSun(): the sun goes where the lobby art expects it
	  (LobbyLayout.SunDirection, low over the west sea)
]]

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local LightingConfig = require(Shared.Config.LightingConfig)
local LobbyLayout = require(Shared.Config.LobbyLayout)
local WorldLayout = require(Shared.Config.WorldLayout)

local LightingController = {}

local player = Players.LocalPlayer
local currentZonePreset = "Surface"
local overrides: { string } = {}
local activeTweens: { Tween } = {}
local tweenEndsAt = 0 -- os.clock() when the running tween ends

local EFFECT_CLASSES = {
	Atmosphere = "Atmosphere",
	ColorCorrection = "ColorCorrectionEffect",
	Bloom = "BloomEffect",
	SunRays = "SunRaysEffect",
}

local function effect(group: string): Instance?
	if group == "Lighting" then
		return Lighting
	end
	local className = EFFECT_CLASSES[group]
	return className and Lighting:FindFirstChildOfClass(className)
end

local function tweenTo(presetName: string, duration: number)
	local preset = LightingConfig.Presets[presetName]
	if not preset then
		return
	end
	for _, t in activeTweens do
		t:Cancel()
	end
	table.clear(activeTweens)
	local groups: { [string]: { [string]: any } } = {
		Lighting = preset.Lighting,
		Atmosphere = preset.Atmosphere,
		ColorCorrection = preset.ColorCorrection,
		Bloom = preset.Bloom,
		SunRays = preset.SunRays,
	}
	tweenEndsAt = os.clock() + math.max(duration, 0)
	-- (no time: the values at once, this frame; a portal's crossing)
	if duration <= 0 then
		for group, values in groups do
			local target: any = effect(group)
			if target then
				for key, value in values do
					target[key] = value
				end
			end
		end
		return
	end
	local info = TweenInfo.new(duration, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
	for group, values in groups do
		local target = effect(group)
		if target and next(values) then
			local goals = {}
			for key, value in values do
				goals[key] = value
			end
			local tween = TweenService:Create(target, info, goals)
			table.insert(activeTweens, tween)
			tween:Play()
		end
	end
end

local function desiredPreset(): string
	if #overrides > 0 then
		return overrides[#overrides]
	end
	return currentZonePreset
end

local lastApplied = ""
local function refresh(duration: number?)
	local want = desiredPreset()
	if want ~= lastApplied then
		lastApplied = want
		tweenTo(want, duration or LightingConfig.TweenTime)
	end
end

-- Temporarily use another preset (e.g. "Workbench"). Returns a pop function.
function LightingController.push(presetName: string, duration: number?): () -> ()
	table.insert(overrides, presetName)
	refresh(duration)
	local popped = false
	return function()
		if popped then
			return
		end
		popped = true
		local index = table.find(overrides, presetName)
		if index then
			table.remove(overrides, index)
		end
		refresh(duration)
	end
end

function LightingController.currentZone(): string
	return currentZonePreset
end

-- The picture sky (LightingConfig.Skybox) once all six faces are uploaded.
function LightingController.applySkybox(sky: Sky): boolean
	local cfg = LightingConfig.Skybox
	local ids = {
		Bk = LightingConfig.skyboxId(cfg.Bk),
		Dn = LightingConfig.skyboxId(cfg.Dn),
		Ft = LightingConfig.skyboxId(cfg.Ft),
		Lf = LightingConfig.skyboxId(cfg.Lf),
		Rt = LightingConfig.skyboxId(cfg.Rt),
		Up = LightingConfig.skyboxId(cfg.Up),
	}
	if not (ids.Bk and ids.Dn and ids.Ft and ids.Lf and ids.Rt and ids.Up) then
		return false
	end
	sky.SkyboxBk = ids.Bk
	sky.SkyboxDn = ids.Dn
	sky.SkyboxFt = ids.Ft
	sky.SkyboxLf = ids.Lf
	sky.SkyboxRt = ids.Rt
	sky.SkyboxUp = ids.Up
	sky.CelestialBodiesShown = cfg.ShowSun
	return true
end

-- The Sky object (default skybox, big low sun, no stars) if the place has
-- none, with the picture sky when it is uploaded.
function LightingController.ensureSky(): Sky
	local sky = Lighting:FindFirstChildOfClass("Sky")
	if sky then
		LightingController.applySkybox(sky)
		return sky
	end
	local created = Instance.new("Sky")
	created.Name = "Sky"
	created.SunAngularSize = LightingConfig.Sky.SunAngularSize
	created.MoonAngularSize = LightingConfig.Sky.MoonAngularSize
	created.StarCount = LightingConfig.Sky.StarCount
	created.CelestialBodiesShown = LightingConfig.Sky.CelestialBodiesShown
	LightingController.applySkybox(created)
	created.Parent = Lighting
	return created
end

-- Soft pink sunset clouds (Workspace.Terrain.Clouds) if the place has none;
-- none at all over the picture sky, which has its own.
function LightingController.ensureClouds(): Clouds?
	local terrain = Workspace:FindFirstChildOfClass("Terrain")
	if not terrain then
		return nil
	end
	local clouds = terrain:FindFirstChildOfClass("Clouds")
	if LightingConfig.skyboxReady() and not LightingConfig.Skybox.TerrainClouds then
		if clouds then
			clouds.Enabled = false
		end
		return nil
	end
	if clouds then
		return clouds
	end
	local created = Instance.new("Clouds")
	created.Cover = LightingConfig.Clouds.Cover
	created.Density = LightingConfig.Clouds.Density
	created.Color = LightingConfig.Clouds.Color
	created.Parent = terrain
	return created
end

--[[
	Put the sun where the lobby art expects it. Roblox's sun path (ClockTime +
	GeographicLatitude) cannot be computed offline, so this searches once for
	the pair whose Lighting:GetSunDirection() is closest to
	LobbyLayout.SunDirection: a coarse grid over the whole day and latitudes
	-66..66, then a shrinking pattern search. Client-only (the server never
	changes ClockTime, so nothing overwrites it). Keeps the configured values
	if the engine does not update the direction immediately or no pair is
	close enough. Returns the error of the applied sun direction.
]]
function LightingController.alignSun(): number
	local config = LightingConfig.Sun
	local target = LobbyLayout.SunDirection
	local startClock, startLatitude = Lighting.ClockTime, Lighting.GeographicLatitude
	local function errorAt(clock: number, latitude: number): number
		Lighting.ClockTime = clock % 24
		Lighting.GeographicLatitude = math.clamp(latitude, -89, 89)
		return (Lighting:GetSunDirection() - target).Magnitude
	end
	local startError = errorAt(startClock, startLatitude)
	if not config.AutoAlign then
		return startError
	end
	-- the engine must report a new direction right after a property change
	local probeA = errorAt(startClock + 3, startLatitude)
	local probeB = errorAt(startClock + 9, startLatitude)
	if math.abs(probeA - startError) < 1e-4 and math.abs(probeB - startError) < 1e-4 then
		errorAt(startClock, startLatitude)
		return startError
	end
	local bestClock, bestLatitude, bestError = startClock, startLatitude, startError
	for clock = 0, 23.75, 0.25 do
		for latitude = -66, 66, 6 do
			local e = errorAt(clock, latitude)
			if e < bestError then
				bestClock, bestLatitude, bestError = clock, latitude, e
			end
		end
	end
	local stepClock, stepLatitude = 0.25, 6
	for _ = 1, 40 do
		local improved = false
		for _, delta in { { stepClock, 0 }, { -stepClock, 0 }, { 0, stepLatitude }, { 0, -stepLatitude } } do
			local clock, latitude = bestClock + delta[1], math.clamp(bestLatitude + delta[2], -89, 89)
			local e = errorAt(clock, latitude)
			if e < bestError then
				bestClock, bestLatitude, bestError = clock % 24, latitude, e
				improved = true
			end
		end
		if not improved then
			stepClock, stepLatitude = stepClock / 2, stepLatitude / 2
			if stepClock < 0.002 then
				break
			end
		end
	end
	if bestError > config.MaxError then
		return errorAt(startClock, startLatitude)
	end
	local applied = errorAt(bestClock, bestLatitude)
	if RunService:IsStudio() then
		print(
			string.format(
				"[TerraForge] sun aligned: ClockTime %.3f, GeographicLatitude %.2f (error %.3f; was %.3f). Put them in LightingConfig.Sun and default.project.json.",
				bestClock,
				bestLatitude,
				applied,
				startError
			)
		)
	end
	return applied
end

function LightingController.init()
	LightingController.ensureSky()
	LightingController.ensureClouds()
	local ok, err = pcall(LightingController.alignSun)
	if not ok then
		warn("[TerraForge] sun alignment failed: " .. tostring(err))
	end
end

--[[
	A part tagged "LightingZone" with a string attribute Preset (a
	LightingConfig preset) overrides the world zone while the player stands
	inside its box (e.g. the inside of the Blaster Vault).
]]
local function taggedZonePreset(position: Vector3): string?
	for _, zone in CollectionService:GetTagged("LightingZone") do
		if zone:IsA("BasePart") then
			local preset = zone:GetAttribute("Preset")
			if type(preset) == "string" and LightingConfig.Presets[preset] then
				local p = zone.CFrame:PointToObjectSpace(position)
				local half = zone.Size / 2
				if math.abs(p.X) <= half.X and math.abs(p.Y) <= half.Y and math.abs(p.Z) <= half.Z then
					return preset
				end
			end
		end
	end
	return nil
end

--[[
	Lighting portals (owner 2026-11-16, walking back out of the Ember Caves: "on the way back you
	still see it"): a part tagged LightingController.PortalTag (a cave's veil, Mine/Diorama) with
	string attributes Inside (the preset on its LookVector side) and Outside (the other side's).
	Where the camera looks through one, the light is the camera's side's, not the character's zone,
	and it changes at once on the frame the camera passes through: what lies beyond a veil is never
	seen in the other side's light. (The zone, polled on the character every 0.4 s and tweened over
	LightingConfig.TweenTime, left the quarry and the town in the caves' dark light, their sky black,
	for a couple of seconds after the veil; and the camera trails the character through it.)
	The camera decides near a portal (PortalReach either side of its plane, PortalMargin round its
	edges) and wherever the line from the camera's focus to the camera passes through the portal (a
	zoomed-out camera high over the quarry while the character stands just inside). Within
	PortalBand of the plane (a camera pinned on the wall round it) the way it looks decides: looking
	into the cave it sees the cave. The sides part at the portal's attribute PlaneZ (studs along its
	own Z, 0 = its middle): the middle of the wall round a veil, so a camera stopped on either face
	of that wall lies on its own side. A portal decides only while the camera's focus is within
	PortalReach of it too (a town camera hanging out over the quarry is not one), never for a
	scripted camera (cutscenes and close-ups bring their own light), and the frame it stops deciding
	the character's zone comes back at once (a cut away, the end of a film).
]]
LightingController.PortalTag = "LightingPortal"
LightingController.PortalReach = 80 -- studs either side of a portal's plane (past the max zoom)
LightingController.PortalMargin = 6 -- studs round its edges
LightingController.PortalBand = 1 -- studs either side of its plane where the camera's view decides
LightingController.CutDistance = 20 -- studs the camera moves in one frame that make a cut (a teleport)

-- The preset of the side of `portal` the camera (its CFrame) is on, or nil where the portal does not
-- decide (or without both presets). `focus`: the camera's focus (Camera.Focus), the character's end
-- of the line through the portal.
function LightingController.portalSide(portal: BasePart, camera: CFrame, focus: Vector3?): string?
	local inside = portal:GetAttribute("Inside")
	local outside = portal:GetAttribute("Outside")
	if type(inside) ~= "string" or type(outside) ~= "string" then
		return nil
	end
	if not LightingConfig.Presets[inside] or not LightingConfig.Presets[outside] then
		return nil
	end
	local planeZ = portal:GetAttribute("PlaneZ")
	local shift = Vector3.new(0, 0, if type(planeZ) == "number" then planeZ else 0)
	-- (positions in the portal's own space, from its dividing plane; its LookVector side is -Z)
	local p = portal.CFrame:PointToObjectSpace(camera.Position) - shift
	local f = if focus then portal.CFrame:PointToObjectSpace(focus) - shift else nil
	local half = portal.Size / 2
	local margin = LightingController.PortalMargin
	local reach = LightingController.PortalReach
	-- its face: its own edges and margin, or the whole wall it stands in (attributes FaceX / FaceY)
	local faceX, faceY = portal:GetAttribute("FaceX"), portal:GetAttribute("FaceY")
	local limX = math.max(half.X + margin, if type(faceX) == "number" then faceX else 0)
	local limY = math.max(half.Y + margin, if type(faceY) == "number" then faceY else 0)
	local function onFace(q: Vector3): boolean
		return math.abs(q.X) <= limX and math.abs(q.Y) <= limY
	end
	local decides
	if f then
		-- the character before its face (within reach), or a camera seen through the face from the
		-- character's side (a zoomed-out camera high over the quarry, the character just inside)
		decides = (onFace(f) and math.abs(f.Z) <= reach) or ((f.Z < 0) ~= (p.Z < 0) and onFace(f:Lerp(p, f.Z / (f.Z - p.Z))))
	else
		decides = onFace(p) and math.abs(p.Z) <= reach
	end
	if not decides then
		return nil
	end
	local isInside = p.Z < 0
	if math.abs(p.Z) <= LightingController.PortalBand then
		local look = portal.CFrame:VectorToObjectSpace(camera.LookVector)
		if math.abs(look.Z) > 0.2 then
			isInside = look.Z < 0
		end
	end
	return if isInside then inside else outside
end

-- the tagged portals streamed in (kept by the tag's signals: no list built every frame)
local portals: { BasePart } = {}

-- Count `part` as a portal (the tag's signals call it; specs too).
function LightingController.trackPortal(part: Instance)
	if part:IsA("BasePart") and not table.find(portals, part) then
		table.insert(portals, part)
	end
end

-- Forget `part` (or every portal without one).
function LightingController.untrackPortal(part: Instance?)
	if part == nil then
		table.clear(portals)
		return
	end
	local index = table.find(portals, part :: any)
	if index then
		table.remove(portals, index)
	end
end

local function trackPortals()
	local tag = LightingController.PortalTag
	for _, instance in CollectionService:GetTagged(tag) do
		LightingController.trackPortal(instance)
	end
	CollectionService:GetInstanceAddedSignal(tag):Connect(LightingController.trackPortal)
	CollectionService:GetInstanceRemovedSignal(tag):Connect(LightingController.untrackPortal)
end

local function portalPreset(camera: Camera): string?
	-- (a scripted camera, a film or a close-up, brings its own light)
	if camera.CameraType == Enum.CameraType.Scriptable then
		return nil
	end
	local cf = camera.CFrame
	local focus = camera.Focus.Position
	for _, portal in portals do
		local preset = LightingController.portalSide(portal, cf, focus)
		if preset then
			return preset
		end
	end
	return nil
end

-- The tagged zone or the world zone the character stands in (nil without a character).
local function characterPreset(): string?
	local character = player and player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return nil
	end
	local zone = WorldLayout.zoneAt(root.Position)
	return taggedZonePreset(root.Position) or (if zone then zone.Lighting else "Surface")
end

-- The zone's preset: the camera's side where it looks through a portal, else the character's.
local function zonePreset(): string?
	local camera = Workspace.CurrentCamera
	return (if camera then portalPreset(camera) else nil) or characterPreset()
end

--[[
	One frame of the portals (start() runs it every frame after the camera moves). Sets the light at
	once, a tween still on its way there finished too, when the camera passes through a portal, when
	a portal starts deciding while another zone's light (or a tween) shows, and when a cut (a
	teleport, a film) takes the camera away from it while the character's zone is another. Returns
	the preset it set, or nil.
]]
local lastPortal: string? = nil
local lastCameraAt: Vector3? = nil
function LightingController.portalStep(camera: Camera?): string?
	local preset = if camera then portalPreset(camera) else nil
	local crossed = preset ~= nil and lastPortal ~= nil and preset ~= lastPortal
	local entered = preset ~= nil and lastPortal == nil
	local left = preset == nil and lastPortal ~= nil
	lastPortal = preset
	-- (a cut: no camera, a scripted one, or one that jumped; a portal left any other way leaves the
	-- light to the zone's poll, near its plane the zone boxes and the plane part by a hair)
	local at = if camera then camera.CFrame.Position else nil
	local cut = camera == nil
		or camera.CameraType == Enum.CameraType.Scriptable
		or (at ~= nil and lastCameraAt ~= nil and (at - lastCameraAt).Magnitude > LightingController.CutDistance)
	lastCameraAt = at
	if left and not cut then
		return nil
	end
	local want = if left then characterPreset() else preset
	if want and (crossed or want ~= currentZonePreset or (entered and os.clock() < tweenEndsAt)) then
		currentZonePreset = want
		if #overrides == 0 then
			lastApplied = ""
		end
		refresh(0)
		return want
	end
	return nil
end

function LightingController.start()
	trackPortals()
	RunService:BindToRenderStep("LightingPortals", Enum.RenderPriority.Camera.Value + 1, function()
		LightingController.portalStep(Workspace.CurrentCamera)
	end)
	while true do
		local preset = zonePreset()
		if preset and preset ~= currentZonePreset then
			currentZonePreset = preset
			refresh()
		end
		task.wait(0.4)
	end
end

return LightingController
