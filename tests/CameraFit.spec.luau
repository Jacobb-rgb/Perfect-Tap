-- Cleaning close-up camera: the ore stays inside the screen area the UI leaves
-- free, on a big PC screen and on a small phone.
return function(T, Loader)
	local roblox = require("@lune/roblox") :: any
	local Vector3 = roblox.Vector3
	local CF = Loader.CFrame
	local OreData = Loader.requirePath("ReplicatedStorage.Shared.Config.OreData")
	local Patterns = Loader.requirePath("ReplicatedStorage.Shared.Cleaning.CleaningPatterns")
	local OreShellBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.OreShellBuilder")
	local CameraFit = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.Cleaning.CameraFit")
	local CleaningView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.CleaningView")

	-- the Cleaning Station's OrePoint and CamPoint (MachineBuilder), station at the origin
	local top = 3.4
	local orePoint = Vector3.new(0, top + 1.95, 0.3)
	local camPoint = CF.lookAt(Vector3.new(0, top + 5.4, -4.6), orePoint + Vector3.new(0, 0.1, 0))
	local toCamera = (camPoint.Position - orePoint).Unit
	local workCF = CF.lookAt(orePoint, orePoint - toCamera)

	local screens = {
		{ name = "PC 1080p", width = 1920, height = 1080, inset = 58, scale = 1.25, compact = false },
		{ name = "laptop 720p", width = 1280, height = 720, inset = 58, scale = 0.65, compact = true },
		{ name = "iPhone SE", width = 667, height = 375, inset = 58, scale = 0.62, compact = true },
		{ name = "phone (old top bar)", width = 740, height = 360, inset = 36, scale = 0.62, compact = true },
	}

	T.test("camera fit: the whole ore is inside the free screen area", function()
		for _, screen in screens do
			for _, ore in OreData.List do
				for seed = 1, 6 do
					local pattern = Patterns.generate(ore.Id, seed * 7907)
					local freeTop = if screen.compact then 16 else CleaningView.BannerBottom
					local cam, fov = CameraFit.compute({
						ViewportHeight = screen.height,
						InsetTop = screen.inset,
						FreeTop = freeTop,
						FreeBottom = CleaningView.BottomReserved,
						UiScale = screen.scale,
						Outline = pattern.Outline,
						FaceScale = OreShellBuilder.Scale,
						CamPoint = camPoint,
						OrePoint = orePoint,
					})
					T.truthy(fov >= CameraFit.BaseFov and fov <= CameraFit.MaxFov, `{screen.name}: fov {fov}`)
					local upper = screen.inset + freeTop * screen.scale
					local lower = screen.height - CleaningView.BottomReserved * screen.scale
					-- compact: the banner sits on the left under Leave; the quality meter is on the right
					local left = if screen.compact then (16 + CleaningView.CompactWidth) * screen.scale else 0
					local right = screen.width - (18 + 92) * screen.scale
					for _, p in pattern.Outline do
						local world = workCF:PointToWorldSpace(Vector3.new(p.X * OreShellBuilder.Scale, p.Y * OreShellBuilder.Scale, 0))
						local x, y = CameraFit.screenPoint(cam, fov, screen.width, screen.height, world)
						T.truthy(
							y >= upper - 1 and y <= lower + 1,
							`{screen.name} {ore.Id} seed {seed}: ore point at y={math.floor(y)} outside {math.floor(upper)}..{math.floor(
								lower
							)}`
						)
						T.truthy(
							x >= left and x <= right,
							`{screen.name} {ore.Id} seed {seed}: ore point at x={math.floor(x)} outside {math.floor(left)}..{math.floor(
								right
							)}`
						)
					end
				end
			end
		end
	end)

	T.test("camera fit: a normal PC screen keeps the designed close-up", function()
		local pattern = Patterns.generate("Gold", 4242)
		local cam, fov = CameraFit.compute({
			ViewportHeight = 1080,
			InsetTop = 58,
			FreeTop = CleaningView.BannerBottom,
			FreeBottom = CleaningView.BottomReserved,
			UiScale = 1.25,
			Outline = pattern.Outline,
			FaceScale = OreShellBuilder.Scale,
			CamPoint = camPoint,
			OrePoint = orePoint,
		})
		T.lt(fov, 46, "PC field of view stays close to 40")
		local tilt = math.deg(math.acos(math.clamp(cam.LookVector:Dot(camPoint.LookVector), -1, 1)))
		T.lt(tilt, 4, "PC camera barely tilts")
	end)
end
