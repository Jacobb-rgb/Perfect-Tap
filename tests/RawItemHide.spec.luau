-- The dirty item in the Cleaning Station's vise stays hidden for the whole close-up, also when it
-- reaches the client after CleanBegin (an ore out of the backpack, owner's playtest 2026-11-06).
return function(T, Loader)
	local roblox = require("@lune/roblox") :: any
	local fs = require("@lune/fs")
	local Vector3, CFrame, Instance = roblox.Vector3, roblox.CFrame, roblox.Instance
	local RawItemHide = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.Cleaning.RawItemHide")

	local AT = Vector3.new(10, 5, 10)
	local items = Instance.new("Folder")

	local function part(parent: any, at: any, name: string?): any
		local p = Instance.new("Part")
		p.Name = name or "Part"
		p.CFrame = CFrame.new(at)
		p.LocalTransparencyModifier = 0
		p.Parent = parent
		return p
	end

	local function item(state: string?, at: any?): any
		local m = Instance.new("Model")
		m.Parent = items
		m:SetAttribute("State", state or "Machine")
		if at then
			m.PrimaryPart = part(m, at, "Body")
		end
		return m
	end

	T.test("raw item: the item in the vise hides and shows again after the session", function()
		local raw = item("Machine", AT + Vector3.new(0, -0.55, 0))
		local detail = part(raw, AT)
		local state = RawItemHide.new(AT)
		RawItemHide.scan(state, { raw })
		T.eq(raw.Body.LocalTransparencyModifier, 1, "body hidden")
		T.eq(detail.LocalTransparencyModifier, 1, "detail hidden")
		RawItemHide.restore(state)
		T.eq(raw.Body.LocalTransparencyModifier, 0, "body back")
		T.eq(detail.LocalTransparencyModifier, 0, "detail back")
		T.eq(next(state.Hidden), nil, "nothing left to restore")
	end)

	T.test("raw item: an ore out of the backpack that arrives after CleanBegin still hides", function()
		local state = RawItemHide.new(AT)
		RawItemHide.scan(state, {})
		-- the model first, without its parts (StreamingEnabled): the scan waits
		local raw = item("Machine")
		RawItemHide.scan(state, { raw })
		T.eq(next(state.Hidden), nil, "no part here yet: nothing to measure")
		-- a decor part before the Body: enough to know where the model is
		local detail = part(raw, AT)
		RawItemHide.scan(state, { raw })
		T.eq(detail.LocalTransparencyModifier, 1, "the first part to arrive hides")
		-- the Body streams in later: the next scan covers it, also with the item list empty
		local body = part(raw, AT, "Body")
		raw.PrimaryPart = body
		T.eq(body.LocalTransparencyModifier, 0, "(just arrived)")
		RawItemHide.scan(state, {})
		T.eq(body.LocalTransparencyModifier, 1, "a part that streamed in later hides too")
		RawItemHide.restore(state)
		T.eq(body.LocalTransparencyModifier, 0, "and shows again")
	end)

	T.test("raw item: other items keep showing", function()
		local state = RawItemHide.new(AT)
		local far = item("Machine", AT + Vector3.new(RawItemHide.Reach + 1, 0, 0))
		local loose = item("Loose", AT)
		RawItemHide.scan(state, { far, loose, Instance.new("Folder") })
		T.eq(far.Body.LocalTransparencyModifier, 0, "another machine's item")
		T.eq(loose.Body.LocalTransparencyModifier, 0, "a loose item")
		RawItemHide.restore(state)
	end)

	T.test("raw item: a gone item doesn't break the restore", function()
		local state = RawItemHide.new(AT)
		local raw = item("Machine", AT)
		RawItemHide.scan(state, { raw })
		raw.Parent = nil
		RawItemHide.restore(state)
		T.eq(next(state.Hidden), nil, "cleared")
		local other = item("Machine", AT)
		RawItemHide.scan(state, { other })
		other.Parent = nil
		RawItemHide.scan(state, {})
		T.eq(next(state.Hidden), nil, "a scan forgets an item that went")
	end)

	T.test("raw item: scans are paced, and the session's frame loop keeps scanning", function()
		local state = RawItemHide.new(AT)
		T.truthy(RawItemHide.due(state, 100), "the first scan")
		T.falsy(RawItemHide.due(state, 100 + RawItemHide.Gap / 2), "not yet")
		T.truthy(RawItemHide.due(state, 100 + RawItemHide.Gap), "after the gap")
		local source = fs.readFile("src/client/Controllers/CleaningController.luau")
		T.truthy(string.find(source, "RawItemHide.due(ctx.RawHide", 1, true) ~= nil, "the frame loop scans again")
		T.truthy(string.find(source, "RawItemHide.restore(ctx.RawHide)", 1, true) ~= nil, "the session's end restores")
	end)
end
