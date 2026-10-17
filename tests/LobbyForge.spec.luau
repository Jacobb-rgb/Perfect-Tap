--[[
	THE GREAT FORGE name board (lobby fix round 3): the board hung 0.8 stud
	behind the dark gable infill and never showed. In the forge's local
	frame (front = local -Z, toward the plaza) the board's front face must
	sit in front of every gable part (infill, bargeboards, timber beams),
	nothing may cover the board's face, and its ends stay clear of the
	banner rods.
]]
return function(T, Loader)
	local roblox = require("@lune/roblox") :: any
	local Vector3 = roblox.Vector3
	local LobbyLayout = Loader.requirePath("ReplicatedStorage.Shared.Config.LobbyLayout")
	local Rng = Loader.requirePath("ReplicatedStorage.Shared.Util.Rng")
	local GreatForge = Loader.requirePath("ServerScriptService.Server.World.Lobby.Plaza.GreatForge")

	local cached: any = nil
	local function forge(): any
		if not cached then
			local root = roblox.Instance.new("Model")
			GreatForge.build(root, Rng.new(7))
			cached = root:FindFirstChild("GreatForge")
		end
		return cached
	end

	local frame = LobbyLayout.frame(LobbyLayout.get("GreatForge"))

	-- bounds of a part in the forge's local frame
	local function localBounds(part: any): (any, any)
		local cf = frame:ToObjectSpace(part.CFrame)
		local size = part.Size
		local _, _, _, r00, r01, r02, r10, r11, r12, r20, r21, r22 = cf:GetComponents()
		local hx = math.abs(r00) * size.X / 2 + math.abs(r01) * size.Y / 2 + math.abs(r02) * size.Z / 2
		local hy = math.abs(r10) * size.X / 2 + math.abs(r11) * size.Y / 2 + math.abs(r12) * size.Z / 2
		local hz = math.abs(r20) * size.X / 2 + math.abs(r21) * size.Y / 2 + math.abs(r22) * size.Z / 2
		local p = cf.Position
		return p - Vector3.new(hx, hy, hz), p + Vector3.new(hx, hy, hz)
	end

	-- gable parts: bargeboards, timber beams and the infill wedges of the nave gable
	local function isGable(part: any, signLo: any): boolean
		if part.Name == "Bargeboard" or part.Name == "GableBeam" then
			return true
		end
		if part:IsA("WedgePart") and not part:FindFirstAncestor("Banner") then
			local lo, hi = localBounds(part)
			-- the nave gable's infill: on the gable front, above the eave
			return lo.Y >= GreatForge.NaveEave - 0.05 and hi.Z < signLo.Z + 2 and math.abs(lo.X + hi.X) / 2 < GreatForge.NaveRoofHalf
		end
		return false
	end

	T.test("forge: THE GREAT FORGE board hangs in front of the whole gable", function()
		local m = forge()
		local sign = m:FindFirstChild("ForgeSign")
		T.truthy(sign, "ForgeSign")
		local signLo, signHi = localBounds(sign)
		local gable = 0
		for _, part in m:GetDescendants() do
			if part:IsA("BasePart") and isGable(part, signLo) then
				gable += 1
				local lo = localBounds(part)
				T.lt(signLo.Z, lo.Z, `the board's front face ({signLo.Z}) in front of {part.Name} ({lo.Z})`)
				T.lt(signHi.Z, lo.Z + 0.001, `the board's back face ({signHi.Z}) clear of {part.Name} ({lo.Z})`)
			end
		end
		T.truthy(gable >= 6, `found the infill, bargeboards and beams ({gable})`)
	end)

	T.test("forge: nothing covers the board's face, its ends clear the banner rods", function()
		local m = forge()
		local sign = m:FindFirstChild("ForgeSign")
		local signLo, signHi = localBounds(sign)
		for _, part in m:GetDescendants() do
			if part:IsA("BasePart") and part ~= sign and part.Transparency < 0.9 then
				local lo, hi = localBounds(part)
				local overX = math.min(hi.X, signHi.X - 0.1) - math.max(lo.X, signLo.X + 0.1)
				local overY = math.min(hi.Y, signHi.Y - 0.1) - math.max(lo.Y, signLo.Y + 0.1)
				-- the board's own frame hugs its edges (inside its outline, just in front)
				local isFrame = lo.Z >= signLo.Z - 0.45
					and lo.X >= signLo.X - 0.15
					and hi.X <= signHi.X + 0.15
					and lo.Y >= signLo.Y - 0.05
					and hi.Y <= signHi.Y + 0.05
				if overX > 0 and overY > 0 and lo.Z < signLo.Z and not isFrame then
					T.truthy(false, `{part:GetFullName()} covers THE GREAT FORGE board`)
				end
				if part.Name == "BannerRod" or part.Name == "BannerFinial" then
					T.truthy(lo.X > signHi.X + 0.2 or hi.X < signLo.X - 0.2, `{part.Name} clear of the board's ends`)
				end
			end
		end
		-- the board ends stay inside the bargeboards' feet
		T.lt(signHi.X, GreatForge.NaveRoofHalf - 2, "the board stays inside the bargeboards")
		-- the board's face reads: a dark board with self-lit letters
		local gui = sign:FindFirstChild("FrontText")
		T.truthy(gui and gui.LightInfluence == 0, "the letters ignore the gable's shade")
		local c = sign.Color
		T.lt(0.299 * c.R + 0.587 * c.G + 0.114 * c.B, 0.25, "a dark board under the gold letters")
	end)
end
