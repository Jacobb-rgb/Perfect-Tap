--[[
	The Vault lobby package (src/server/World/Lobby/Vault): the Blaster Vault,
	its giant statues and jungle trees. Budget (agreed with the lobby layout:
	<= 3500 parts, <= 6 lights, <= 12 particle emitters), mobile finish (no
	shadows from small or neon parts), hooks (VaultCounter, LightingZone, the
	Spin hologram), determinism, and that everything stays inside the
	reserved footprints.
]]
return function(T, Loader)
	local roblox = require("@lune/roblox") :: any
	local Vector3 = roblox.Vector3
	local Vault = Loader.requirePath("ServerScriptService.Server.World.Lobby.Vault")
	local Rng = Loader.requirePath("ReplicatedStorage.Shared.Util.Rng")
	local LightingConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.LightingConfig")

	local function build()
		local m = roblox.Instance.new("Model")
		m.Name = "Vault"
		Vault.build(m, Rng.new("Lobby/Vault"))
		return m
	end

	local built = build()

	local function parts(root): { any }
		local out = {}
		for _, d in root:GetDescendants() do
			if d:IsA("BasePart") then
				table.insert(out, d)
			end
		end
		return out
	end

	T.test("the vault package builds its four models", function()
		for _, name in { "BlasterVault", "VaultStatueWest", "VaultStatueEast", "VaultTrees" } do
			T.truthy(built:FindFirstChild(name), name .. " exists")
		end
		T.truthy(type(Vault.build) == "function", "exports build()")
		T.truthy(type(Vault.Replaces) == "table", "exports Replaces")
	end)

	T.test("the vault package stays inside its budget", function()
		local count, lights, emitters = 0, 0, 0
		for _, d in built:GetDescendants() do
			if d:IsA("BasePart") then
				count += 1
			elseif d:IsA("PointLight") or d:IsA("SpotLight") or d:IsA("SurfaceLight") then
				lights += 1
			elseif d:IsA("ParticleEmitter") then
				emitters += 1
			end
		end
		T.lt(count, 3501, "parts (" .. count .. ")")
		T.lt(lights, 7, "lights (" .. lights .. ")")
		T.lt(emitters, 13, "particle emitters (" .. emitters .. ")")
	end)

	T.test("small and neon parts cast no shadow, everything is anchored", function()
		for _, p in parts(built) do
			T.truthy(p.Anchored, p.Name .. " anchored")
			local big = math.max(p.Size.X, p.Size.Y, p.Size.Z) >= 4
			if not big or p.Material == roblox.Enum.Material.Neon then
				T.falsy(p.CastShadow, p:GetFullName() .. " casts no shadow")
			end
		end
	end)

	T.test("hooks: the counter, the interior lighting zone, the spinning hologram", function()
		local counters, zones = 0, 0
		for _, p in parts(built) do
			if p:HasTag("VaultCounter") then
				counters += 1
			end
			if p:HasTag("LightingZone") then
				zones += 1
				local preset = p:GetAttribute("Preset")
				T.truthy(LightingConfig.Presets[preset], "zone preset " .. tostring(preset) .. " exists")
				T.falsy(p.CanCollide, "zone does not collide")
				T.falsy(p.CanQuery, "zone is not raycast")
				T.falsy(p.CanTouch, "zone is not touched")
				T.eq(p.Transparency, 1, "zone is invisible")
			end
		end
		T.eq(counters, 1, "one VaultCounter")
		T.eq(zones, 1, "one LightingZone")
		for _, name in { "VaultHologram", "VaultGems" } do
			local m = built:FindFirstChild(name, true)
			T.truthy(m and m:HasTag("Spin"), name .. " spins")
			T.truthy(m and m.PrimaryPart, name .. " has a pivot part")
		end
	end)

	T.test("the vault package is deterministic", function()
		local a, b = parts(built), parts(build())
		T.eq(#a, #b, "same part count")
		for i = 1, #a, 37 do
			T.truthy((a[i].CFrame.Position - b[i].CFrame.Position).Magnitude < 1e-4, "part " .. i .. " at the same place")
		end
	end)

	T.test("everything stays inside the reserved footprints", function()
		-- the agreed footprints (plus a small margin), in lobby coordinates
		local origin = Vault.origin()
		local boxes = {
			{ center = Vector3.new(0, 0, 112.4), half = Vector3.new(34.5, 0, 33.5) }, -- the vault
			{ center = Vector3.new(-43, 0, 92), half = Vector3.new(13.5, 0, 12.5) },
			{ center = Vector3.new(43, 0, 92), half = Vector3.new(13.5, 0, 12.5) },
		}
		for _, t in Vault.Trees do
			table.insert(
				boxes,
				{ center = (origin * roblox.CFrame.new(t[1], 0, t[2])).Position, half = Vector3.new(t[4] + 5, 0, t[4] + 5) }
			)
		end
		local outside = 0
		for _, p in parts(built) do
			local pos = p.CFrame.Position
			if pos.Y < 30 then -- the ground level (canopies, beams and the hologram are high up)
				local inside = false
				for _, b in boxes do
					if math.abs(pos.X - b.center.X) <= b.half.X and math.abs(pos.Z - b.center.Z) <= b.half.Z then
						inside = true
						break
					end
				end
				if not inside then
					outside += 1
				end
			end
		end
		T.eq(outside, 0, "parts outside the footprints")
	end)
end
