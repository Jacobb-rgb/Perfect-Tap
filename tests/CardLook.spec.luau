-- The store-card spray look (Cleaning/CardLook) under Lune: dirt chunks fly out of the
-- face toward the camera and up, then fall; the look wraps every DefaultLook callback.
return function(T, Loader)
	local roblox = require("@lune/roblox") :: any
	local Vector3 = roblox.Vector3
	local CFrame = roblox.CFrame
	local CardLook = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.Cleaning.CardLook")
	local DefaultLook = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.Cleaning.DefaultLook")

	T.test("CardLook: chunks fly out of the face and up, then gravity pulls them down", function()
		-- the face's +Z points at the camera (CleaningController's WorkCF)
		local face = CFrame.new(0, 5, 0) * CFrame.Angles(0, 0.6, 0)
		local toCamera = face:VectorToWorldSpace(Vector3.new(0, 0, 1))
		local seed = 3
		local function r(): number
			seed = (seed * 16807) % 2147483647
			return seed / 2147483647
		end
		for _ = 1, 20 do
			local v = CardLook.throw(face, r)
			T.truthy(v:Dot(toCamera) > 0, "out of the face, toward the camera")
			T.truthy(v.Y > 0, "and up")
		end
		local from = Vector3.new(0, 5, 0)
		local up = Vector3.new(0, 10, 0)
		T.near(CardLook.chunkAt(from, up, 0).Y, 5, 1e-9, "starts at the dirt")
		T.truthy(CardLook.chunkAt(from, up, 1).Y < CardLook.chunkAt(from, up, 0.25).Y, "falls later")
	end)

	T.test("CardLook: every DefaultLook callback is wrapped", function()
		for name, fn in DefaultLook do
			if type(fn) == "function" and name ~= "banner" then
				T.eq(type(CardLook[name]), "function", name)
			end
		end
	end)
end
