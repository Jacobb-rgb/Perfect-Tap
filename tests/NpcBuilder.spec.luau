-- NpcBuilder (quest giver prototypes): every outfit builds from plain parts
-- (no meshes, lights or effects) within the part budget, with R15-like part
-- names, Kenney Mini Characters proportions (a big head) and its own look;
-- each NPC has its own Pop paint (one source for the nameplate, the pad and
-- the marker) and a Height constant equal to its dressed top; the server
-- anchor is ONE part that carries the points and attributes; dressing adds
-- the outfit and the quest pad (and can be redone or removed); nothing
-- collides, is queried or touched (players walk through, aim and grab rays
-- pass), Root is tagged BeamIgnore; the rigid groups follow the animation
-- contract (float groups move as one, the head group holds everything worn
-- on the head); the faces smile; the outfit list names real mine floors;
-- an unknown id builds a plain NPC.
return function(T, Loader)
	local roblox = require("@lune/roblox") :: any
	local Vector3 = roblox.Vector3
	local CFrame = Loader.CFrame
	local NpcBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.NpcBuilder")
	local MineFloors = Loader.requirePath("ReplicatedStorage.Shared.Config.MineFloors")
	local PopTheme = Loader.requirePath("ReplicatedStorage.Shared.Config.PopTheme")
	local MovementConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.MovementConfig")

	local function parts(model: any): { any }
		local out = {}
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") then
				table.insert(out, d)
			end
		end
		return out
	end

	-- the world-space Y extent of a part (its box, rotated)
	local function yExtent(part: any): (number, number)
		local cf = part.CFrame
		local h = part.Size / 2
		local up = math.abs(cf.RightVector.Y) * h.X + math.abs(cf.UpVector.Y) * h.Y + math.abs(cf.LookVector.Y) * h.Z
		return cf.Position.Y - up, cf.Position.Y + up
	end

	local function point(model: any, name: string): any
		local root = model.PrimaryPart
		local a = root and root:FindFirstChild(name)
		T.truthy(a and a:IsA("Attachment"), model.Name .. " has " .. name)
		return (root.CFrame * a.CFrame).Position
	end

	local function sameColor(a: any, b: any): boolean
		return math.abs(a.R - b.R) < 0.01 and math.abs(a.G - b.G) < 0.01 and math.abs(a.B - b.B) < 0.01
	end

	T.test("NpcBuilder: the outfit list (unique ids, names, paints, real floors)", function()
		T.truthy(#NpcBuilder.Outfits >= 6 and #NpcBuilder.Outfits <= 8, "6-8 quest givers")
		local seen, paints = {}, {}
		for _, outfit in NpcBuilder.Outfits do
			T.falsy(seen[outfit.Id], outfit.Id .. " is unique")
			seen[outfit.Id] = true
			T.eq(NpcBuilder.ById[outfit.Id], outfit, outfit.Id .. " in ById")
			T.truthy(#outfit.Name > 0 and #outfit.Name <= 20, outfit.Id .. " has a short name")
			T.truthy(#outfit.Title > 0 and #outfit.Title <= 16, outfit.Id .. " has a short title")
			-- one source for the colors: a PopTheme paint, unique per NPC; the accent is its Top
			local paint = PopTheme.Paints[outfit.Paint]
			T.truthy(paint ~= nil, outfit.Id .. ": " .. tostring(outfit.Paint) .. " is a PopTheme.Paints key")
			T.truthy(outfit.Paint ~= "Slate" and outfit.Paint ~= "Night", outfit.Id .. " has a bright paint")
			T.falsy(paints[outfit.Paint], outfit.Id .. ": paint " .. outfit.Paint .. " is not shared")
			paints[outfit.Paint] = true
			T.truthy(sameColor(outfit.Accent, paint.Top), outfit.Id .. " accent = its paint's Top")
			T.eq(NpcBuilder.paintOf(outfit.Id), paint, outfit.Id .. " paintOf")
			T.truthy(type(outfit.Height) == "number", outfit.Id .. " has a Height constant")
			if outfit.Floor then
				T.truthy(MineFloors.ById[outfit.Floor] ~= nil, outfit.Id .. ": " .. outfit.Floor .. " is a MineFloors Id")
				T.eq(outfit.Area, outfit.Floor, outfit.Id .. " stands on its floor")
			else
				T.eq(outfit.Area, "Lobby", outfit.Id .. " (no floor) stands in the lobby")
			end
		end
	end)

	T.test("NpcBuilder: every NPC builds from plain parts within the budget", function()
		local plain = NpcBuilder.partCount(NpcBuilder.build("NoSuchNpc"))
		for _, outfit in NpcBuilder.Outfits do
			local model = NpcBuilder.build(outfit.Id)
			local n = NpcBuilder.partCount(model)
			T.le(n, NpcBuilder.MaxParts, outfit.Id .. " parts")
			T.truthy(n >= plain + 15, outfit.Id .. " wears its outfit (" .. n .. " parts)")
			T.eq(model.Name, "Npc_" .. outfit.Id)
			T.eq(model:GetAttribute("Npc"), outfit.Id)
			T.eq(model:GetAttribute("DisplayName"), outfit.Name)
			T.eq(model:GetAttribute("Title"), outfit.Title)
			T.eq(model:GetAttribute("Area"), outfit.Area)
			T.eq(model:GetAttribute("Paint"), outfit.Paint)
			T.eq(model:GetAttribute("RootHeight"), NpcBuilder.RootHeight)
			for _, d in model:GetDescendants() do
				local class = d.ClassName
				T.truthy(
					class == "Part" or class == "WedgePart" or class == "Attachment",
					outfit.Id .. ": only parts and attachments (" .. class .. " " .. d.Name .. ")"
				)
			end
		end
	end)

	T.test("NpcBuilder: R15-like part names, unique within each NPC", function()
		for _, outfit in NpcBuilder.Outfits do
			local model = NpcBuilder.build(outfit.Id)
			for _, name in { "Root", "Head", "UpperTorso", "LeftArm", "RightArm", "LeftHand", "RightHand" } do
				T.truthy(model:FindFirstChild(name), outfit.Id .. " has " .. name)
			end
			if not model:FindFirstChild("Robe") then
				for _, name in { "LowerTorso", "LeftLeg", "RightLeg", "LeftFoot", "RightFoot" } do
					T.truthy(model:FindFirstChild(name), outfit.Id .. " has " .. name .. " (or a Robe)")
				end
			end
			local names = {}
			for _, p in parts(model) do
				T.falsy(names[p.Name], outfit.Id .. ": one part named " .. p.Name)
				names[p.Name] = true
			end
		end
	end)

	T.test("NpcBuilder: anchored, nothing collides, is queried or touched", function()
		for _, outfit in NpcBuilder.Outfits do
			local model = NpcBuilder.build(outfit.Id)
			local root = model.PrimaryPart
			T.truthy(root and root.Name == "Root", outfit.Id .. " PrimaryPart = Root")
			T.eq(root.Transparency, 1, "Root is invisible")
			T.truthy(root.Anchored, "Root is anchored")
			-- players walk through; the mouse aim, grab and beam rays pass it
			T.falsy(root.CanCollide, outfit.Id .. " Root never collides")
			T.falsy(root.CanQuery, outfit.Id .. " Root is never queried")
			T.falsy(root.CanTouch, outfit.Id .. " Root fires no Touched")
			T.truthy(root:HasTag(MovementConfig.BeamIgnoreTag), outfit.Id .. " Root tagged BeamIgnore")
			local shadows, neon = 0, 0
			for _, p in parts(model) do
				T.truthy(p.Anchored, outfit.Id .. "." .. p.Name .. " anchored")
				if p ~= root then
					T.falsy(p.CanCollide, outfit.Id .. "." .. p.Name .. " no collision")
					T.falsy(p.CanTouch, outfit.Id .. "." .. p.Name .. " no touch")
					T.falsy(p.CanQuery, outfit.Id .. "." .. p.Name .. " no query")
					T.truthy(p.Massless, outfit.Id .. "." .. p.Name .. " massless")
					T.truthy(p.Transparency < 0.5, outfit.Id .. "." .. p.Name .. " is seen")
					if p.CastShadow then
						shadows += 1
					end
					if p.Material == roblox.Enum.Material.Neon then
						neon += 1
						-- a near-white glow blooms into a white blob
						local c = p.Color
						T.truthy(math.min(c.R, c.G, c.B) <= 0.7, outfit.Id .. "." .. p.Name .. " glows in a color")
					end
				end
			end
			T.truthy(shadows >= 3 and shadows <= 12, outfit.Id .. ": only the big parts cast shadows (" .. shadows .. ")")
			T.le(neon, 20, outfit.Id .. " glow parts")
		end
	end)

	T.test("NpcBuilder: Mini Characters proportions, standing on its feet, Height = the dressed top", function()
		for _, outfit in NpcBuilder.Outfits do
			local model = NpcBuilder.build(outfit.Id)
			local head = model:FindFirstChild("Head")
			local torso = model:FindFirstChild("UpperTorso")
			local height = model:GetAttribute("Height")
			T.eq(height, outfit.Height, outfit.Id .. " Height attribute = the outfit's constant")
			T.truthy(height >= 5.6 and height <= 7.6, outfit.Id .. " height " .. height .. " (a player is ~5.2)")
			T.truthy(head.Size.Y >= NpcBuilder.HeadTop * 0.3, outfit.Id .. ": a big head")
			T.truthy(head.Size.X >= torso.Size.X * 0.8, outfit.Id .. ": the head as wide as the shoulders")
			local _, headTop = yExtent(head)
			T.near(headTop, NpcBuilder.HeadTop, 0.01, outfit.Id .. " head top")
			local low, top = math.huge, -math.huge
			for _, p in parts(model) do
				if p.Name ~= "Root" then
					local a, b = yExtent(p)
					low = math.min(low, a)
					top = math.max(top, b)
				end
			end
			T.truthy(low >= -0.01 and low <= 0.05, outfit.Id .. " stands on the ground (lowest " .. low .. ")")
			T.near(top, outfit.Height, 0.01, outfit.Id .. " Height constant = the top of the dressed gear")
		end
	end)

	T.test("NpcBuilder: the server anchor is one part with the points and attributes", function()
		local base = CFrame.new(-14, -220, -770) * CFrame.Angles(0, 2.4, 0)
		for _, outfit in NpcBuilder.Outfits do
			local anchor = NpcBuilder.anchor(outfit.Id, base)
			T.eq(NpcBuilder.partCount(anchor), 1, outfit.Id .. " anchor = one part")
			T.eq(anchor.PrimaryPart and anchor.PrimaryPart.Name, "Root", outfit.Id .. " anchor PrimaryPart")
			for _, key in { "Npc", "DisplayName", "Title", "Area", "Paint", "Height", "RootHeight" } do
				T.truthy(anchor:GetAttribute(key) ~= nil, outfit.Id .. " anchor attribute " .. key)
			end
			T.truthy(anchor.PrimaryPart:HasTag(MovementConfig.BeamIgnoreTag), outfit.Id .. " anchor Root tagged BeamIgnore")
			-- the points need no outfit parts: the same as on the dressed NPC
			local dressed = NpcBuilder.build(outfit.Id, base)
			for _, name in { "NameplatePoint", "QuestMarkerPoint", "PromptPoint" } do
				T.near((point(anchor, name) - point(dressed, name)).Magnitude, 0, 0.001, outfit.Id .. " " .. name .. " on the anchor")
			end
		end
	end)

	T.test("NpcBuilder: dress adds the outfit and the quest pad; redress and undress", function()
		for _, outfit in NpcBuilder.Outfits do
			local model = NpcBuilder.anchor(outfit.Id, CFrame.new(5, 2, -9))
			local added = NpcBuilder.dress(model)
			T.eq(added, NpcBuilder.partCount(model) - 1, outfit.Id .. " dress returns the parts added")
			T.le(added, NpcBuilder.MaxParts - 1, outfit.Id .. " dressed parts")
			T.eq(NpcBuilder.dress(model), added, outfit.Id .. " dressing again builds the same (no doubles)")
			T.eq(NpcBuilder.partCount(model), added + 1, outfit.Id .. " no doubled parts")
			-- the pad: a flat disc in the paint's Bottom on a glowing rim in its Top, flush with the ground
			local paint = PopTheme.Paints[outfit.Paint]
			local pad, rim = model:FindFirstChild("Pad"), model:FindFirstChild("PadRim")
			T.truthy(pad and rim, outfit.Id .. " has its quest pad")
			T.truthy(sameColor(pad.Color, paint.Bottom), outfit.Id .. " pad in its paint")
			T.truthy(sameColor(rim.Color, paint.Top) and rim.Material == roblox.Enum.Material.Neon, outfit.Id .. " glowing pad rim")
			for _, p in { pad, rim } do
				local low, high = yExtent(p)
				T.near(low, 2, 0.01, outfit.Id .. "." .. p.Name .. " on the ground")
				T.le(high - low, 0.2, outfit.Id .. "." .. p.Name .. " is flat")
				T.falsy(p.CastShadow, outfit.Id .. "." .. p.Name .. " casts no shadow")
			end
			NpcBuilder.undress(model)
			T.eq(NpcBuilder.partCount(model), 1, outfit.Id .. " undressed = the anchor again")
			T.truthy(model.PrimaryPart ~= nil, outfit.Id .. " keeps its Root")
		end
	end)

	T.test("NpcBuilder: rigid groups (float groups move as one, the head group holds the head gear)", function()
		for _, outfit in NpcBuilder.Outfits do
			local model = NpcBuilder.build(outfit.Id)
			local groups: { [string]: { any } } = {}
			for _, p in parts(model) do
				local group = p:GetAttribute("Group")
				if p:GetAttribute("Float") then
					T.truthy(type(group) == "string" and group ~= NpcBuilder.HeadGroup, outfit.Id .. "." .. p.Name .. " floats in a group")
				end
				if group then
					groups[group] = groups[group] or {}
					table.insert(groups[group], p)
				end
				-- everything worn on the head turns with it: a non-floating part centered over the neck, inside the head's reach
				local c = p.CFrame.Position
				if p.Name ~= "Root" and not p:GetAttribute("Float") and math.abs(c.X) <= 1.05 and math.abs(c.Z) <= 1.1 and c.Y >= 4.0 then
					T.eq(group, NpcBuilder.HeadGroup, outfit.Id .. "." .. p.Name .. " (on the head) is in the head group")
				end
			end
			local head = groups[NpcBuilder.HeadGroup]
			T.truthy(head ~= nil, outfit.Id .. " has a head group")
			local inHead = {}
			for _, p in head do
				inHead[p.Name] = true
				T.falsy(p:GetAttribute("Float"), outfit.Id .. "." .. p.Name .. ": the head group does not float")
				T.truthy(p.CFrame.Position.Y >= 2.8, outfit.Id .. "." .. p.Name .. ": the head group holds no body part")
			end
			T.truthy(inHead.Head, outfit.Id .. " Head is in the head group")
			for _, p in parts(model) do
				if string.match(p.Name, "Eye$") or string.match(p.Name, "Brow$") or p.Name == "Mouth" then
					T.truthy(inHead[p.Name], outfit.Id .. "." .. p.Name .. " turns with the head")
				end
			end
			for name, list in groups do
				if name ~= NpcBuilder.HeadGroup then
					local sum = Vector3.new(0, 0, 0)
					for _, p in list do
						T.truthy(p:GetAttribute("Float") == true, outfit.Id .. "." .. p.Name .. ": group " .. name .. " floats as one")
						sum += p.CFrame.Position
					end
					local center = sum / #list
					for _, p in list do
						T.le((p.CFrame.Position - center).Magnitude, 1.6, outfit.Id .. "." .. p.Name .. " stays with group " .. name)
					end
				end
			end
		end
	end)

	T.test("NpcBuilder: faces (eye shines, smiles and grins)", function()
		local happy = { GemPolisher = true, Explorer = true, StormEngineer = true, LavaSmith = true }
		for _, outfit in NpcBuilder.Outfits do
			local model = NpcBuilder.build(outfit.Id)
			local dotEyes = model:FindFirstChild("LeftEye") and model.LeftEye.Shape == roblox.Enum.PartType.Cylinder
			if dotEyes then
				T.truthy(model:FindFirstChild("LeftEyeShine") and model:FindFirstChild("RightEyeShine"), outfit.Id .. " eyes shine")
			end
			if happy[outfit.Id] then
				T.truthy(model:FindFirstChild("Teeth") or model:FindFirstChild("LeftMouthCorner"), outfit.Id .. " smiles or grins")
			end
		end
	end)

	T.test("NpcBuilder: nameplate, quest marker and prompt points follow the NPC", function()
		local base = CFrame.new(40, -12, -150) * CFrame.Angles(0, 1.1, 0)
		for _, outfit in NpcBuilder.Outfits do
			local model = NpcBuilder.build(outfit.Id, base)
			local height = model:GetAttribute("Height")
			local root = model.PrimaryPart
			local rootLocal = base:ToObjectSpace(root.CFrame)
			T.near(rootLocal.Position.Y, NpcBuilder.RootHeight, 0.001, outfit.Id .. " Root over the feet")
			T.near((rootLocal.Position * Vector3.new(1, 0, 1)).Magnitude, 0, 0.001, outfit.Id .. " Root centered")
			local plate = base:PointToObjectSpace(point(model, "NameplatePoint"))
			local marker = base:PointToObjectSpace(point(model, "QuestMarkerPoint"))
			local prompt = base:PointToObjectSpace(point(model, "PromptPoint"))
			T.near(plate.Y, height + NpcBuilder.NameplateGap, 0.01, outfit.Id .. " nameplate over the gear")
			T.near(marker.Y - plate.Y, NpcBuilder.MarkerGap, 0.01, outfit.Id .. " marker over the nameplate")
			T.near(plate.X, 0, 0.001, outfit.Id .. " nameplate centered")
			T.near(marker.X, 0, 0.001, outfit.Id .. " marker centered")
			T.truthy(prompt.Z < -0.5, outfit.Id .. " prompt in front (the LookVector side)")
			T.truthy(prompt.Y > 2 and prompt.Y < 4, outfit.Id .. " prompt at chest height")
			-- every part moved with the base (no part left at the origin)
			for _, p in parts(model) do
				local localPos = base:PointToObjectSpace(p.CFrame.Position)
				local flat = Vector3.new(localPos.X, 0, localPos.Z).Magnitude
				T.truthy(flat < 4.5 and localPos.Y > -0.1 and localPos.Y < 8, outfit.Id .. "." .. p.Name .. " built at the base")
			end
		end
	end)

	T.test("NpcBuilder: an unknown id builds a plain NPC", function()
		local model = NpcBuilder.build("NoSuchNpc")
		T.eq(model:GetAttribute("Npc"), "NoSuchNpc")
		T.eq(model:GetAttribute("DisplayName"), "Townsperson")
		T.eq(model:GetAttribute("Height"), NpcBuilder.PlainHeight)
		T.le(NpcBuilder.partCount(model), NpcBuilder.MaxParts, "plain NPC parts")
		T.truthy(model:FindFirstChild("Head") and model.PrimaryPart, "plain NPC has a head and a Root")
		local top = -math.huge
		for _, p in parts(model) do
			if p.Name ~= "Root" then
				local _, b = yExtent(p)
				top = math.max(top, b)
			end
		end
		T.near(top, NpcBuilder.PlainHeight, 0.01, "plain NPC Height constant = its top")
	end)
end
