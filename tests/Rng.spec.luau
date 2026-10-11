return function(T, Loader)
	local Rng = Loader.requirePath("ReplicatedStorage.Shared.Util.Rng")

	T.test("Rng: same seed gives the same sequence", function()
		local a, b = Rng.new(12345), Rng.new(12345)
		for _ = 1, 50 do
			T.eq(a:next(), b:next())
		end
		local c, d = Rng.new("session-abc"), Rng.new("session-abc")
		for _ = 1, 20 do
			T.eq(c:int(1, 100), d:int(1, 100))
		end
	end)

	T.test("Rng: values stay in range", function()
		local r = Rng.new(7)
		for _ = 1, 2000 do
			local f = r:next()
			T.truthy(f >= 0 and f < 1, "next in [0,1)")
			local i = r:int(3, 9)
			T.truthy(i >= 3 and i <= 9 and i == math.floor(i), "int in [3,9]")
		end
	end)

	T.test("Rng: weighted pick respects weights roughly", function()
		local r = Rng.new(99)
		local counts = { A = 0, B = 0 }
		for _ = 1, 4000 do
			local k = r:weighted({ A = 3, B = 1 })
			counts[k] += 1
		end
		local ratio = counts.A / counts.B
		T.truthy(ratio > 2.5 and ratio < 3.6, "ratio " .. ratio)
	end)
end
