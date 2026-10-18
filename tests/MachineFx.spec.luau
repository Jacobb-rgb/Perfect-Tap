-- The parts MachineFxController animates on the roster machines (furnace
-- glows and smoke, the Polisher's wheel, the Wind Turbine's blades) exist
-- where it looks for them: direct children of the model (FindFirstChild,
-- not recursive) at every upgrade level, with their lights and emitters.
return function(T, Loader)
	local KitMachines = Loader.requirePath("ReplicatedStorage.Shared.Builders.KitMachines")

	local function child(model: any, name: string): any
		local part = model:FindFirstChild(name)
		return if part and part:IsA("BasePart") then part else nil
	end

	-- the "Glow" child holding the door light (an arch is built from two "Glow" parts)
	local function litGlow(model: any): any
		for _, part in model:GetChildren() do
			if part.Name == "Glow" and part:IsA("BasePart") and part:FindFirstChildOfClass("PointLight") then
				return part
			end
		end
		return nil
	end

	T.test("MachineFx: roster furnaces have a lit Glow, embers and chimney smoke", function()
		for level = 0, KitMachines.MaxLevel do
			for _, id in { "BrickFurnace", "AlloyFurnace", "PlasmaFurnace" } do
				local model = KitMachines.build(id, level)
				local tag = `{id} L{level}`
				local glow = litGlow(model)
				T.truthy(glow, tag .. " Glow with a PointLight")
				if id ~= "PlasmaFurnace" then
					T.truthy(glow:FindFirstChild("Embers"), tag .. " Embers")
					local top = child(model, "ChimneyTop")
					T.truthy(top and top:FindFirstChild("Smoke"), tag .. " chimney smoke")
				end
			end
			local alloy = KitMachines.build("AlloyFurnace", level)
			T.truthy(child(alloy, "Molten"), `AlloyFurnace L{level} Molten column`)
			local plasma = KitMachines.build("PlasmaFurnace", level)
			T.truthy(child(plasma, "PlasmaBall"), `PlasmaFurnace L{level} PlasmaBall`)
		end
	end)

	T.test("MachineFx: the Polisher's wheel and turntable", function()
		for level = 0, KitMachines.MaxLevel do
			local model = KitMachines.build("Polisher", level)
			local wheel = child(model, "Wheel")
			T.truthy(wheel, `Polisher L{level} Wheel`)
			-- a cylinder turns round its own X axis: upright for the wheel
			T.truthy(math.abs(wheel.CFrame.RightVector.Y) > 0.99, `Polisher L{level} wheel axis upright`)
			local turntable = child(model, "Turntable")
			T.truthy(turntable and turntable:FindFirstChild("Sparkle"), `Polisher L{level} sparkles`)
		end
	end)

	T.test("MachineFx: the Wind Turbine's blades turn across the Nacelle's axis", function()
		for level = 0, KitMachines.MaxLevel do
			local model = KitMachines.build("WindTurbine", level)
			local tag = `WindTurbine L{level}`
			local rotor = child(model, "Rotor")
			local nacelle = child(model, "Nacelle")
			T.truthy(rotor, tag .. " Rotor")
			T.truthy(nacelle, tag .. " Nacelle")
			local axis = nacelle.CFrame.RightVector
			local blades = 0
			for _, part in model:GetChildren() do
				if part.Name == "Blade" and part:IsA("BasePart") then
					blades += 1
					local offset = part.CFrame.Position - rotor.CFrame.Position
					T.truthy(offset.Magnitude > 0.5, tag .. " blade away from the hub")
					T.truthy(math.abs(offset.Unit:Dot(axis)) < 0.05, tag .. " blade in the turning plane")
				end
			end
			T.truthy(blades >= 3, `{tag} blades ({blades})`)
		end
	end)
	T.test("MachineFx: the Robot Arm swings its Arm parts round the Pedestal", function()
		for level = 0, KitMachines.MaxLevel do
			local model = KitMachines.build("RobotArm", level)
			local tag = `RobotArm L{level}`
			local pedestal = child(model, "Pedestal")
			T.truthy(pedestal, tag .. " Pedestal")
			local arms, frontmost = 0, math.huge
			for _, part in model:GetChildren() do
				if part.Name == "Arm" and part:IsA("BasePart") then
					arms += 1
					frontmost = math.min(frontmost, part.CFrame.Position.Z)
				end
			end
			T.truthy(arms >= 6, tag .. " arm parts (" .. arms .. ")")
			-- at rest the hand reaches over the front (-Z), so a half turn brings it over the back
			T.lt(frontmost, pedestal.CFrame.Position.Z - 1, tag .. " hand in front of the pedestal")
		end
	end)

	T.test("MachineFx: Splitter / Sorter flippers, the Sorter's scan bar and the Sell Box coin", function()
		for level = 0, KitMachines.MaxLevel do
			for _, id in { "Splitter", "Sorter" } do
				local model = KitMachines.build(id, level)
				T.truthy(child(model, "Flipper"), `{id} L{level} Flipper`)
			end
			T.truthy(child(KitMachines.build("Sorter", level), "ScanBar"), `Sorter L{level} ScanBar`)
		end
		T.truthy(child(KitMachines.build("SellBox", 0), "Coin"), "Sell Box Coin")
	end)
end
