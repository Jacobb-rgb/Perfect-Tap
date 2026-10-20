--[[
	Concept fixes (Plaza/Life, Flora/Stream): the miners are few, small,
	part-built and pure decoration; nothing of it stands on a road, the plaza
	ring, a stall's walking line, the Great Forge's porch, the vault zone or
	within 3 studs of a stall counter or tagged stall part; no lights; the
	stream keeps off the plot yards and the railway, Land's rim notch matches
	it and its bridge stays walkable.
]]
return function(T, Loader)
	local roblox = require("@lune/roblox") :: any
	local Vector3 = roblox.Vector3
	local WorldLayout = Loader.requirePath("ReplicatedStorage.Shared.Config.WorldLayout")
	local LobbyLayout = Loader.requirePath("ReplicatedStorage.Shared.Config.LobbyLayout")
	local WorldBuilder = Loader.requirePath("ServerScriptService.Server.World.WorldBuilder")
	local Land = Loader.requirePath("ServerScriptService.Server.World.Land")
	local Common = Loader.requirePath("ServerScriptService.Server.World.Lobby.Plaza.Common")
	local Life = Loader.requirePath("ServerScriptService.Server.World.Lobby.Plaza.Life")
	local Stream = Loader.requirePath("ServerScriptService.Server.World.Lobby.Flora.Stream")
	local FloraKit = Loader.requirePath("ServerScriptService.Server.World.Lobby.Flora.Kit")
	local Railway = Loader.requirePath("ServerScriptService.Server.World.Railway")

	local map = WorldBuilder.build(roblox.Instance.new("DataModel"):GetService("Workspace"))
	local lobby = map.Emberfall.Lobby
	local life = lobby.Plaza:FindFirstChild("Life")
	local stream = lobby.Flora:FindFirstChild("Stream")

	local function parts(model): { any }
		local out = {}
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") then
				table.insert(out, d)
			end
		end
		return out
	end

	local function bounds(part): (any, any)
		local cf, size = part.CFrame, part.Size
		local _, _, _, r00, r01, r02, r10, r11, r12, r20, r21, r22 = cf:GetComponents()
		local hx = math.abs(r00) * size.X / 2 + math.abs(r01) * size.Y / 2 + math.abs(r02) * size.Z / 2
		local hy = math.abs(r10) * size.X / 2 + math.abs(r11) * size.Y / 2 + math.abs(r12) * size.Z / 2
		local hz = math.abs(r20) * size.X / 2 + math.abs(r21) * size.Y / 2 + math.abs(r22) * size.Z / 2
		local p = cf.Position
		return Vector3.new(p.X - hx, p.Y - hy, p.Z - hz), Vector3.new(p.X + hx, p.Y + hy, p.Z + hz)
	end

	local function lights(model): number
		local n = 0
		for _, d in model:GetDescendants() do
			if d:IsA("PointLight") or d:IsA("SpotLight") or d:IsA("SurfaceLight") then
				n += 1
			end
		end
		return n
	end

	T.test("plaza life: miners are few, small and pure decoration", function()
		T.truthy(life, "Plaza.Life is built")
		local miners = life.Miners:GetChildren()
		T.truthy(#miners >= 5 and #miners <= 10, `5-10 miners ({#miners})`)
		for _, m in miners do
			T.le(#parts(m), 25, m:GetFullName() .. " has at most 25 parts")
			T.falsy(m:FindFirstChildWhichIsA("Humanoid", true), "no Humanoid")
		end
		for _, part in parts(life) do
			T.falsy(part.CanCollide or part.CanTouch or part.CanQuery or part.CastShadow, part:GetFullName() .. " is pure decoration")
			T.truthy(part.Anchored, part:GetFullName() .. " is anchored")
		end
		T.eq(lights(life), 0, "no lights")
		T.truthy(#life.Lanterns:GetChildren() >= 4, "lanterns at the stall fronts")
	end)

	T.test("plaza life: off the roads, the ring, the walking lines, the counters and the clear zones", function()
		local tagged = {}
		for _, d in lobby.Districts:GetDescendants() do
			if d:IsA("BasePart") and (#d:GetTags() > 0 or string.find(d.Name, "Counter", 1, true)) then
				table.insert(tagged, d)
			end
		end
		T.truthy(#tagged > 0, "the stalls have tagged parts")
		for _, group in { life.Miners, life.Lanterns, life.Props } do
			for _, item in group:GetChildren() do
				local lo, hi = Vector3.new(math.huge, 0, math.huge), Vector3.new(-math.huge, 0, -math.huge)
				for _, part in parts(item) do
					local a, b = bounds(part)
					lo = Vector3.new(math.min(lo.X, a.X), 0, math.min(lo.Z, a.Z))
					hi = Vector3.new(math.max(hi.X, b.X), 0, math.max(hi.Z, b.Z))
				end
				local c = (lo + hi) / 2
				local name = item:GetFullName()
				T.truthy(c.Magnitude > Common.PlazaRadius, name .. " stays off the plaza ring")
				T.truthy(Common.offStrips(c, 0.3), name .. " stays off the roads and paths")
				for _, apron in FloraKit.Aprons do
					T.truthy(FloraKit.apronDistance(apron, c) > 0, name .. " stays off " .. apron.Id .. "'s walking line")
				end
				for _, zone in Life.Clear do
					local inside = c.X > zone.Min.X and c.X < zone.Max.X and c.Z > zone.Min.Z and c.Z < zone.Max.Z
					T.falsy(inside, name .. " stays off the forge porch and the vault zone")
				end
				for _, t in tagged do
					local p = t.CFrame.Position
					local reach = math.max(t.Size.X, t.Size.Z) / 2
					local dx = math.max(lo.X - (p.X + reach), (p.X - reach) - hi.X, 0)
					local dz = math.max(lo.Z - (p.Z + reach), (p.Z - reach) - hi.Z, 0)
					T.truthy(math.max(dx, dz) >= Life.PromptClear - 0.01, `{name} keeps {Life.PromptClear} studs off {t:GetFullName()}`)
				end
			end
		end
	end)

	T.test("stream: in place, off the yards and the railway, a low rim, a walkable bridge", function()
		T.truthy(stream, "Flora.Stream is built")
		T.eq(Land.RimNotch.X0, Stream.Notch.X0, "rim notch start matches the stream")
		T.eq(Land.RimNotch.X1, Stream.Notch.X1, "rim notch end matches the stream")
		local lines = Railway.visibleLines()
		for _, part in parts(stream) do
			local lo, hi = bounds(part)
			local c = (lo + hi) / 2
			for _, plot in WorldLayout.Plots do
				T.falsy(LobbyLayout.onBase(plot, Vector3.new(c.X, 0, c.Z), 0), part:GetFullName() .. " stays off the plot yards")
			end
			for _, points in lines do
				for i = 1, #points - 1 do
					local a, b = points[i], points[i + 1]
					local near = c.X > math.min(a.X, b.X) - 8
						and c.X < math.max(a.X, b.X) + 8
						and c.Z > math.min(a.Z, b.Z) - 8
						and c.Z < math.max(a.Z, b.Z) + 8
					T.falsy(near, part:GetFullName() .. " stays off the railway")
				end
			end
			T.truthy(c.X > 72, part:GetFullName() .. " stays out of the vault zone")
		end
		local deck = 0
		for _, part in parts(stream.StreamBridge) do
			if part.CanCollide then
				deck += 1
			end
		end
		T.truthy(deck > 0, "the bridge deck is walkable")
		T.eq(lights(stream), 0, "no lights")
		-- the waterfall pours from the rim's lip (about ground height) into the sea
		for _, part in parts(stream) do
			local _, hi = bounds(part)
			if not part:IsDescendantOf(stream.StreamBridge) then
				T.truthy(hi.Y < 4, part:GetFullName() .. " stays low (no fall from the sky)")
			end
		end
		-- the rim under the mouth stays below the water
		for _, part in parts(map.Land) do
			local lo, hi = bounds(part)
			if part.Transparency < 1 and hi.X > Land.RimNotch.X0 + 2 and lo.X < Land.RimNotch.X1 - 2 and lo.Z >= 152 and hi.Y > -3 then
				T.truthy(hi.Y <= 0.2, `{part:GetFullName()} stays low under the stream's mouth ({hi.Y})`)
			end
		end
	end)
end
