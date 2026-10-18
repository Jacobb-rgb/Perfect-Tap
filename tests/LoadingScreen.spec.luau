--[[
	The loading screen (src/first): the copied world values still match, the
	stages add up, it never waits past MaxSeconds, SKIP comes after SkipAfter,
	the tips rotate, the layout keeps SKIP big enough to tap and inside the TV
	safe area, nothing overlaps on PC / phone / TV, the logo slot falls back
	to the text logo, and the gate (Util/Loading) reads the same attribute.
]]
return function(T, Loader)
	local roblox = require("@lune/roblox") :: any
	local fs = require("@lune/fs")
	local serde = require("@lune/serde")
	local process = require("@lune/process")
	local Vector2 = roblox.Vector2
	local LoadingConfig = Loader.requirePath("ReplicatedFirst.LoadingConfig")
	local LoadingView = Loader.requirePath("ReplicatedFirst.LoadingView")
	local Loading = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.Util.Loading")
	local WorldLayout = Loader.requirePath("ReplicatedStorage.Shared.Config.WorldLayout")

	T.test("loading: copied values, one loading script, the gate's attribute", function()
		T.eq(LoadingConfig.SpawnPoint, WorldLayout.SpawnPoint, "the town spawn (WorldLayout.SpawnPoint)")
		local project = serde.decode("json", fs.readFile(process.cwd .. "/default.project.json"))
		T.eq(LoadingConfig.StreamRadius, project.tree.Workspace["$properties"].StreamingMinRadius, "StreamingMinRadius")
		T.eq(Loading.Attribute, LoadingConfig.Attribute, "the gate reads what the loading screen sets")
		T.truthy(Loading.MaxWait <= 15 and Loading.MaxWait >= LoadingConfig.MaxSeconds, "the gate outlasts the screen, briefly")
		local scripts = 0
		for _, name in fs.readDir(process.cwd .. "/src/first") do
			if string.find(name, "%.client%.luau$") then
				scripts += 1
			end
		end
		T.eq(scripts, 1, "one loading script in ReplicatedFirst")
	end)

	T.test("loading: stages, finish and skip", function()
		local state = LoadingConfig.newState()
		T.near(LoadingConfig.progress(state), LoadingConfig.Weights.Assets, 1e-6, "an empty queue counts as loaded")
		T.falsy(LoadingConfig.ready(state), "not ready at the start")
		state.AssetsLeft, state.AssetsPeak = 40, 40
		T.eq(LoadingConfig.progress(state), 0, "nothing loaded yet")
		state.AssetsLeft = 20
		T.near(LoadingConfig.assets(state), 0.5, 1e-6, "half the queue drained")
		state.GameLoaded, state.Character, state.Persistent, state.Spawn, state.AssetsLeft = true, true, true, 1, 2
		T.near(LoadingConfig.progress(state), 1, 1e-6, "everything in")
		T.truthy(LoadingConfig.ready(state), "ready")
		T.falsy(LoadingConfig.shouldFinish(state, 0.3, false), "never just a flash")
		T.truthy(LoadingConfig.shouldFinish(state, LoadingConfig.MinSeconds, false), "fades when ready")
		local stuck = LoadingConfig.newState()
		T.falsy(LoadingConfig.shouldFinish(stuck, LoadingConfig.MaxSeconds - 0.1, false), "waits while loading")
		T.truthy(LoadingConfig.shouldFinish(stuck, LoadingConfig.MaxSeconds, false), "the hard cap")
		T.truthy(LoadingConfig.MaxSeconds >= 10 and LoadingConfig.MaxSeconds <= 12, "a 10-12 s cap")
		T.truthy(LoadingConfig.shouldFinish(stuck, 0.5, true), "skip ends it")
		T.falsy(LoadingConfig.canSkip(LoadingConfig.SkipAfter - 0.1), "no skip at first")
		T.truthy(LoadingConfig.canSkip(LoadingConfig.SkipAfter), "skip after a few seconds")
		T.truthy(LoadingConfig.SkipAfter >= 2 and LoadingConfig.SkipAfter <= 4, "about 3 s")
		T.eq(LoadingConfig.smooth(0.6, 0.4, 0.1), 0.6, "the bar never goes back")
		local s = LoadingConfig.smooth(0.2, 0.8, 0.1)
		T.truthy(s > 0.2 and s <= 0.8, "the bar eases forward")
	end)

	T.test("loading: tips and the logo slot", function()
		local n = #LoadingConfig.Tips
		T.truthy(n >= 6 and n <= 8, `{n} tips`)
		for i, tip in LoadingConfig.Tips do
			T.truthy(#tip <= 80, `tip {i} is short`)
			T.truthy(string.match(tip, "^[%w%s%.,!'%-]+$") ~= nil, `tip {i} is plain text`)
		end
		T.eq(LoadingConfig.tipIndex(1, 0), 1, "first tip")
		T.eq(LoadingConfig.tipIndex(1, LoadingConfig.TipEvery), 2, "next tip")
		T.eq(LoadingConfig.tipIndex(n, LoadingConfig.TipEvery), 1, "wraps around")
		T.eq(LoadingConfig.Logo.Id, 0, "the logo waits for the owner's upload")
		T.eq(LoadingConfig.logoId(), nil, "0 = the text logo")
		local keep = LoadingConfig.Logo.Id
		LoadingConfig.Logo.Id = 123456
		T.eq(LoadingConfig.logoId(), "rbxassetid://123456", "content id")
		local refs = LoadingView.build()
		T.truthy(refs.Logo:FindFirstChild("Image"), "an uploaded logo shows as an image")
		LoadingConfig.Logo.Id = keep
		local text = LoadingView.build()
		T.truthy(text.Logo:FindFirstChild("Forge") and text.Logo:FindFirstChild("Emblem"), "the text logo")
	end)

	-- the rectangle (in design units) of an offset-sized element on the canvas
	local function rect(o: any, canvas: any): { number }
		local w, h = o.Size.X.Offset, o.Size.Y.Offset
		local x = o.Position.X.Scale * canvas.X + o.Position.X.Offset - o.AnchorPoint.X * w
		local y = o.Position.Y.Scale * canvas.Y + o.Position.Y.Offset - o.AnchorPoint.Y * h
		return { x, y, x + w, y + h }
	end
	local function overlap(a: { number }, b: { number }): boolean
		return a[1] < b[3] and b[1] < a[3] and a[2] < b[4] and b[2] < a[4]
	end

	T.test("loading: PC, phone and TV layouts", function()
		local screens = {
			{ Name = "PC", Viewport = Vector2.new(1600, 900), Touch = false, TenFoot = false },
			{ Name = "phone", Viewport = Vector2.new(667, 375), Touch = true, TenFoot = false },
			{ Name = "small phone", Viewport = Vector2.new(568, 320), Touch = true, TenFoot = false },
			{ Name = "tablet", Viewport = Vector2.new(1024, 768), Touch = true, TenFoot = false },
			{ Name = "TV", Viewport = Vector2.new(1920, 1080), Touch = false, TenFoot = true },
		}
		for _, screen in screens do
			local layout = LoadingConfig.layout(screen.Viewport, screen.Touch, screen.TenFoot)
			local refs = LoadingView.build()
			LoadingView.apply(refs, layout)
			local canvas, m = layout.Canvas, layout.Margin
			local name = screen.Name
			if screen.Touch then
				T.truthy(refs.Skip.Size.Y.Offset * layout.Scale >= LoadingConfig.MinTouch - 0.01, name .. ": SKIP is big enough to tap")
				local tipPt = refs.Tip:FindFirstChildOfClass("UITextSizeConstraint").MaxTextSize * layout.Scale
				T.truthy(tipPt >= LoadingConfig.MinTipPt - 1, `{name}: the tip reads ({tipPt} pt)`)
			end
			if screen.TenFoot then
				T.truthy(m >= canvas.X * 0.05 - 0.01, name .. ": the TV safe area")
			end
			local skip = rect(refs.Skip, canvas)
			local bottom = rect(refs.Bottom, canvas)
			local logo = rect(refs.Logo, canvas)
			logo[4] += (logo[4] - logo[2]) * 0.06 -- the ribbon hangs under the logo's box
			for label, r in { SKIP = skip, bottom = bottom, logo = logo } do
				T.truthy(r[1] >= m - 0.01 and r[3] <= canvas.X - m + 0.01, `{name}: {label} inside the margins (x)`)
				T.truthy(r[2] >= m - 0.01 and r[4] <= canvas.Y - m + 0.01, `{name}: {label} inside the margins (y)`)
			end
			-- SKIP's gamepad glyph sits 48 units left of the button
			local glyph = { skip[1] - 48, skip[2], skip[3], skip[4] }
			T.falsy(overlap(glyph, bottom), name .. ": SKIP clear of the bar and the tip")
			T.falsy(overlap(logo, bottom), name .. ": the logo clear of the bar")
			T.falsy(overlap(logo, glyph), name .. ": the logo clear of SKIP")
		end
	end)

	T.test("loading: the gate", function()
		local keep = Loading.target
		local flag = roblox.Instance.new("Folder")
		Loading.target = flag
		T.falsy(Loading.isDone(), "not done before the attribute")
		flag:SetAttribute(Loading.Attribute, true)
		T.truthy(Loading.isDone(), "done")
		T.truthy(Loading.wait(), "returns at once when done")
		Loading.target = keep
	end)
end
