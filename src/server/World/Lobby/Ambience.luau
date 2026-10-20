--[[
	Ambience spots (AmbienceConfig): invisible Attachments tagged
	AmbienceConfig.Tag whose "Ambience" attribute names the kind of sound.
	They add no parts: each one rides on a part that is already there, so it
	streams in and out with that part and the client's AmbienceController
	hangs its sounds on it.

	  Waterfall  the top third of every waterfall's sheet (Style.waterfall:
	             the part named Water) but the floating islands', the
	             nearest to the plaza first
	  Brook      the middle of the stream's bridge (Stream.Bridge), on the
	             nearest water part of its channel
	  Pond       the water of every pond (the stream's pond and the meadow's)
	  Forge      in front of THE GREAT FORGE's furnace (the ForgeGlow part)
	  Plaza      over the town spawn (TownSpawn)

	Runs last in WorldBuilder, after the meadow has placed its ponds.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local AmbienceConfig = require(Shared.Config.AmbienceConfig)
local WorldLayout = require(Shared.Config.WorldLayout)
local Stream = require(script.Parent.Flora.Stream)

local Ambience = {}

-- An Attachment on `host` at the world point `at`, tagged for the client.
function Ambience.spot(host: BasePart, kind: string, at: Vector3): Attachment
	local a = Instance.new("Attachment")
	a.Name = "Ambience" .. kind
	a.CFrame = host.CFrame:Inverse() * CFrame.new(at)
	a:SetAttribute(AmbienceConfig.Attribute, kind)
	a:AddTag(AmbienceConfig.Tag)
	a.Parent = host
	return a
end

local function parts(model: Instance): { BasePart }
	local list: { BasePart } = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(list, d)
		end
	end
	return list
end

local function nearest(list: { BasePart }, p: Vector3): BasePart?
	local best: BasePart?, bestD = nil, math.huge
	for _, part in list do
		local d = (part.CFrame.Position - p).Magnitude
		if d < bestD then
			best, bestD = part, d
		end
	end
	return best
end

local function largest(model: Instance): BasePart?
	local best: BasePart?, bestV = nil, -1
	for _, part in parts(model) do
		local v = part.Size.X * part.Size.Y * part.Size.Z
		if v > bestV then
			best, bestV = part, v
		end
	end
	return best
end

-- the plaza is the centre the "nearest first" caps count from
local function fromPlaza(part: BasePart): number
	local p = part.CFrame.Position
	return Vector3.new(p.X - WorldLayout.SpawnPoint.X, 0, p.Z - WorldLayout.SpawnPoint.Z).Magnitude
end

local function byDistance(list: { BasePart }): { BasePart }
	table.sort(list, function(a: BasePart, b: BasePart): boolean
		local da, db = fromPlaza(a), fromPlaza(b)
		if da ~= db then
			return da < db
		end
		return a.CFrame.Position.X < b.CFrame.Position.X
	end)
	return list
end

function Ambience.build(map: Instance): { Attachment }
	local spots: { Attachment } = {}
	local emberfall = map:FindFirstChild("Emberfall")
	local lobby = emberfall and emberfall:FindFirstChild("Lobby")
	if not lobby then
		return spots
	end
	local falls: { BasePart } = {}
	local ponds: { BasePart } = {}
	local forge: BasePart? = nil
	local stream: Instance? = nil
	local sky = lobby:FindFirstChild("Sky")
	for _, d in lobby:GetDescendants() do
		if d:IsA("Model") then
			-- (the floating islands' falls hang where nobody can stand)
			if d.Name == "Waterfall" and not (sky and d:IsDescendantOf(sky)) then
				local sheet = d:FindFirstChild("Water")
				if sheet and sheet:IsA("BasePart") then
					table.insert(falls, sheet)
				end
			elseif d.Name == "Pond" or d.Name == "StreamPond" then
				local water = largest(d)
				if water then
					table.insert(ponds, water)
				end
			elseif d.Name == "Stream" and not stream then
				stream = d
			end
		elseif d:IsA("BasePart") and d.Name == "ForgeGlow" and not forge then
			forge = d
		end
	end

	for i, sheet in byDistance(falls) do
		if i > AmbienceConfig.MaxWaterfalls then
			break
		end
		table.insert(spots, Ambience.spot(sheet, "Waterfall", (sheet.CFrame * CFrame.new(0, sheet.Size.Y / 6, 0)).Position))
	end
	for i, water in byDistance(ponds) do
		if i > AmbienceConfig.MaxPonds then
			break
		end
		table.insert(spots, Ambience.spot(water, "Pond", water.CFrame.Position + Vector3.new(0, 0.5, 0)))
	end
	if stream then
		local channel = stream:FindFirstChild("Channel")
		local mid = (Stream.Bridge.From + Stream.Bridge.To) / 2 + Vector3.new(0, 0.5, 0)
		local host = channel and nearest(parts(channel), mid)
		if host then
			table.insert(spots, Ambience.spot(host, "Brook", mid))
		end
	end
	if forge then
		-- the forge's front faces +Z (toward the plaza): the anvil stands just in front of the furnace
		table.insert(spots, Ambience.spot(forge, "Forge", forge.CFrame.Position + Vector3.new(0, 0, 3)))
	end
	local spawn = map:FindFirstChild("TownSpawn", true)
	if spawn and spawn:IsA("BasePart") then
		table.insert(spots, Ambience.spot(spawn, "Plaza", spawn.CFrame.Position + Vector3.new(0, 4, 0)))
	end
	return spots
end

return Ambience
