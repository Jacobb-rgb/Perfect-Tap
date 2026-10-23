-- The DROPPERS shop (owner 2026-10-23): the server's shell and the showroom every client builds near the camera.
return function(T, Loader)
	local roblox = require("@lune/roblox") :: any
	local WorldBuilder = Loader.requirePath("ServerScriptService.Server.World.WorldBuilder")
	local DropperShopBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.DropperShopBuilder")
	local DropperConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.DropperConfig")

	local map = WorldBuilder.build(roblox.Instance.new("DataModel"):GetService("Workspace"))
	local house = map:FindFirstChild("DroppersHouse", true)

	local function parts(instance: any): { any }
		local list = {}
		for _, d in instance:GetDescendants() do
			if d:IsA("BasePart") then
				table.insert(list, d)
			end
		end
		return list
	end

	T.test("dropper shop: the server house is tagged for the showroom, carries its frame and the counter", function()
		T.truthy(house, "the DroppersHouse is built")
		T.truthy(house:HasTag(DropperShopBuilder.Tag), "tagged for the clients' showroom loop")
		local frame = house:GetAttribute(DropperShopBuilder.FrameAttribute)
		T.eq(typeof(frame), "CFrame", "the house frame")
		local counter = house:FindFirstChild("DropperCounter", true)
		T.truthy(counter and counter:HasTag("DropperCounter"), "the counter keeps the shop prompt tag")
		T.falsy(house:FindFirstChild(DropperShopBuilder.DetailName), "the server builds no showroom")
		T.eq(#DropperShopBuilder.Slots + 1, #DropperConfig.List, "a slot for every dropper but the hero")
		local LobbyLayout = Loader.requirePath("ReplicatedStorage.Shared.Config.LobbyLayout")
		local piece = LobbyLayout.get("DroppersHouse")
		T.truthy((piece.Facing.Unit + piece.Center.Unit).Magnitude < 0.01, "the entrance faces the plaza's crystal")
		T.truthy(DropperShopBuilder.Room.W >= 30, "a wide shop (owner: it was terribly narrow)")
	end)

	T.test("dropper shop: the showroom has every dropper, the hero and the laser, quiet parts, and comes and goes", function()
		local frame = house:GetAttribute(DropperShopBuilder.FrameAttribute)
		local detail = DropperShopBuilder.show(house, frame)
		T.eq(DropperShopBuilder.show(house, frame), detail, "built once")
		for _, dropper in DropperConfig.List do
			T.truthy(detail:FindFirstChild(dropper.Id), dropper.Id .. " on display")
		end
		T.truthy(detail:FindFirstChild(DropperConfig.Laser.Id), "the Money Laser on the counter")
		local list = parts(detail)
		T.truthy(#list <= 1500, `the showroom stays light near the camera ({#list} parts)`)
		local ceiling = DropperShopBuilder.Room.Plinth + DropperShopBuilder.Room.Ground
		local lights = 0
		for _, d in detail:GetDescendants() do
			if d:IsA("Light") then
				lights += 1
				T.falsy(d.Shadows, "no shadows")
			end
		end
		T.truthy(lights <= 3, `three lights at most ({lights})`)
		for _, p in list do
			T.truthy(p.Anchored and not p.CanCollide and not p.CastShadow, p:GetFullName() .. " is quiet decoration")
		end
		-- the droppers stand inside the room, under its ceiling
		for _, dropper in DropperConfig.List do
			for _, p in parts(detail[dropper.Id]) do
				local q = frame:PointToObjectSpace(p.CFrame.Position)
				T.truthy(q.Y + p.Size.Y / 2 <= ceiling + 0.3, `{dropper.Id} {p.Name} under the ceiling ({q.Y})`)
				T.truthy(math.abs(q.X) <= DropperShopBuilder.Room.W / 2, `{dropper.Id} inside the side walls ({q.X})`)
			end
		end
		DropperShopBuilder.clear(house)
		T.falsy(house:FindFirstChild(DropperShopBuilder.DetailName), "cleared")
	end)
end
