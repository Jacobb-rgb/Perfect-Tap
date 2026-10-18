-- The Common, Uncommon and Rare ore looks from the owner's ore picture (OreShapesLow):
-- one recipe per ore, within budget, a size that fills the plinth, the rarity glow rules,
-- and the look-alike pairs of the picture kept apart.
return function(T, Loader)
	local roblox = require("@lune/roblox") :: any
	local CF = Loader.CFrame
	local OreData = Loader.requirePath("ReplicatedStorage.Shared.Config.OreData")
	local Rarity = Loader.requirePath("ReplicatedStorage.Shared.Config.Rarity")
	local ItemBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.ItemBuilder")
	local OreShapesLow = Loader.requirePath("ReplicatedStorage.Shared.Builders.OreShapesLow")
	local NEON = roblox.Enum.Material.Neon

	local function partsOf(model)
		local list = {}
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") then
				table.insert(list, d)
			end
		end
		return list
	end

	-- size of the visible parts' world bounding box
	local function sizeOf(model)
		local mn = { math.huge, math.huge, math.huge }
		local mx = { -math.huge, -math.huge, -math.huge }
		for _, part in partsOf(model) do
			if part.Transparency < 1 then
				local _, _, _, r00, r01, r02, r10, r11, r12, r20, r21, r22 = part.CFrame:GetComponents()
				local h = part.Size / 2
				local p = part.CFrame.Position
				local half = {
					math.abs(r00) * h.X + math.abs(r01) * h.Y + math.abs(r02) * h.Z,
					math.abs(r10) * h.X + math.abs(r11) * h.Y + math.abs(r12) * h.Z,
					math.abs(r20) * h.X + math.abs(r21) * h.Y + math.abs(r22) * h.Z,
				}
				local pos = { p.X, p.Y, p.Z }
				for axis = 1, 3 do
					mn[axis] = math.min(mn[axis], pos[axis] - half[axis])
					mx[axis] = math.max(mx[axis], pos[axis] + half[axis])
				end
			end
		end
		return mx[1] - mn[1], mx[2] - mn[2], mx[3] - mn[3]
	end

	-- volume-weighted brightness of the solid, non-glowing parts
	local function brightness(model)
		local sum, weight = 0, 0
		for _, part in partsOf(model) do
			if part.Material ~= NEON and part.Transparency < 0.5 then
				local s = part.Size
				local v = s.X * s.Y * s.Z
				local c = part.Color
				sum += (0.2126 * c.R + 0.7152 * c.G + 0.0722 * c.B) * v
				weight += v
			end
		end
		return sum / weight
	end

	local function glow(model)
		local faint, bright = 0, 0
		for _, part in partsOf(model) do
			if part.Material == NEON then
				if part.Transparency > 0.05 then
					faint += 1
				else
					bright += 1
				end
			end
		end
		return faint, bright
	end

	local function shown(id)
		return ItemBuilder.display({ K = "Clean", O = id }, CF.new(), 1)
	end

	T.test("ore looks (low): every Common, Uncommon and Rare ore has its own recipe", function()
		local listed = {}
		for _, id in OreShapesLow.Ores do
			listed[id] = true
			local ore = OreData.get(id)
			T.eq(ore.Shape, id, id .. " Shape is its Id")
			T.truthy(ItemBuilder.Shapes[id], id .. " has a recipe")
			T.truthy(Rarity.get(ore.Rarity).Order <= 3, id .. " is Common, Uncommon or Rare")
		end
		for _, ore in OreData.List do
			if Rarity.get(ore.Rarity).Order <= 3 then
				T.truthy(listed[ore.Id], ore.Id .. " is listed in OreShapesLow.Ores")
			end
		end
		for id in OreShapesLow.Scale do
			T.truthy(listed[id], id .. " in OreShapesLow.Scale is one of the low ores")
		end
	end)

	T.test("ore looks (low): within the part budgets and the size of a plinth", function()
		for _, id in OreShapesLow.Ores do
			for _, grade in { "Rough", "Flawless" } do
				local clean = ItemBuilder.build({ Kind = "Clean", OreId = id, Grade = grade }, CF.new(0, 4, 0), 2)
				T.le(#partsOf(clean), ItemBuilder.Budget.Clean, id .. " clean parts")
				local display = ItemBuilder.display({ K = "Clean", O = id, G = grade }, CF.new(), 2)
				T.le(#partsOf(display), ItemBuilder.Budget.Display, id .. " display parts")
			end
			local x, y, z = sizeOf(shown(id))
			-- the showcase plinth is 3 studs: every ore fills it about the same, none hangs over
			T.truthy(x <= 2.7 and z <= 2.7, `{id} fits its plinth ({x}, {z})`)
			T.truthy(y <= 2.5, `{id} is not too tall ({y})`)
			T.truthy(math.max(x, y, z) >= 1.9, `{id} fills its plinth ({x}, {y}, {z})`)
		end
	end)

	T.test("ore looks (low): Common never glows, Uncommon glows faintly, Rare glows bright", function()
		for _, id in OreShapesLow.Ores do
			local order = Rarity.get(OreData.get(id).Rarity).Order
			for _, model in { ItemBuilder.build({ Kind = "Clean", OreId = id }, CF.new(), 5), shown(id) } do
				local faint, bright = glow(model)
				if order == 1 then
					T.eq(faint + bright, 0, id .. " (Common) has no glowing parts")
				elseif order == 2 then
					T.truthy(faint > 0, id .. " (Uncommon) glows faintly")
					T.eq(bright, 0, id .. " (Uncommon) has no full glow")
				else
					T.truthy(bright > 0, id .. " (Rare) glows")
				end
			end
		end
	end)

	T.test("ore looks (low): every look is its own, the look-alike pairs stay apart", function()
		local seen = {}
		for _, id in OreShapesLow.Ores do
			local sizes = {}
			for _, part in partsOf(shown(id)) do
				local s = part.Size
				table.insert(sizes, string.format("%.2f/%.2f/%.2f", s.X, s.Y, s.Z))
			end
			table.sort(sizes)
			local signature = table.concat(sizes, ";")
			T.falsy(seen[signature], id .. " looks like " .. tostring(seen[signature]))
			seen[signature] = id
		end
		-- Honeycomb and Amber: both golden with a bee, only Amber glows (its light leaks out)
		local _, honeyBright = glow(shown("Honeycomb"))
		local amberFaint = glow(shown("Amber"))
		T.eq(honeyBright, 0, "Honeycomb does not glow")
		T.truthy(amberFaint > 0, "Amber glows")
		-- Oakwood and Bogwood: the swamp log is the darker one
		T.lt(brightness(shown("Bogwood")), brightness(shown("Oakwood")) - 0.03, "Bogwood is darker than Oakwood")
		-- Copper and Bronze: bronze is the darker, bigger lumps
		T.lt(brightness(shown("Bronze")), brightness(shown("Copper")) - 0.05, "Bronze is darker than Copper")
		local function biggest(id)
			local most = 0
			for _, part in partsOf(shown(id)) do
				most = math.max(most, part.Size.X * part.Size.Y * part.Size.Z)
			end
			return most
		end
		T.lt(biggest("Copper") * 2, biggest("Bronze"), "Bronze lumps are much bigger than Copper nuggets")
	end)
end
