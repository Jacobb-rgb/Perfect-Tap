--[[
	The light HUD's BLASTER slot (owner 2026-10-28: "a custom slot for the
	blaster left of the backpack, the pair in the middle"):

	  the slot       built by the light HUD only (HudBubble.carryGroup), in
	                 the backpack button's well look, square and as tall as
	                 the button, the blaster's picture (never an emoji or a
	                 broken image), the "1" key cap, the gold ring in hand
	  centred        the slot, a GroupGap and the button are one group in the
	                 screen's middle at the bottom (design units, any scale)
	  phones         >= 44 pt, clear of the money, the level bar, the boost
	                 corner and the touch buttons (jump, Grab, FIRE) on
	                 568 x 320, 667 x 375 and 844 x 390 under a 58 px top bar;
	                 PC 1280 x 720 and 1920 x 1080 too
	  the toggle     Util/Hotbar.toggle equips the Blaster from the backpack
	                 and puts it away (a fake character and backpack); refused
	                 while busy (the controller: PlayerControls / cleaning)
	  the 1 key      KeyCode.One is bound by BlasterSlotController only, no
	                 touch button, no gamepad button
	  Roblox's bar   off on the light UI (Hotbar.hideCore, retried); the
	                 close-ups (Placement, Cleaning, Vault) give back only
	                 "off" there (Hotbar.restoreCore) and keep the dark HUD's
]]
return function(T, Loader)
	local fs = require("@lune/fs")
	local roblox = require("@lune/roblox") :: any
	local Vector2 = roblox.Vector2
	local Enum = roblox.Enum
	local UIConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.UIConfig")
	local BlasterBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.BlasterBuilder")
	local function client(path: string): any
		return Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client." .. path)
	end
	local HudView = client("UI.HudView")
	local HudBubble = client("UI.HudBubble")
	local BoostView = client("UI.BoostView")
	local LevelView = client("UI.LevelView")
	local Hotbar = client("Util.Hotbar")
	local PopTheme = Loader.requirePath("ReplicatedStorage.Shared.Config.PopTheme")

	-- runs fn with the light UI on or off, always switching it back
	local function withLight(on: boolean, fn: () -> ())
		local before = UIConfig.LightUI
		UIConfig.LightUI = on
		local ok, err = pcall(fn)
		UIConfig.LightUI = before
		if not ok then
			error(err, 0)
		end
	end

	local function read(rel: string): string
		return fs.readFile(Loader.root .. "/" .. rel)
	end

	local function overlap(a: { number }, b: { number }): boolean
		-- { left, top, right, bottom }
		return a[1] < b[3] and b[1] < a[3] and a[2] < b[4] and b[2] < a[4]
	end

	---------------------------------------------------------------- the slot

	T.test("BlasterSlot: the light HUD builds the slot left of the backpack button; the dark HUD keeps Roblox's", function()
		withLight(false, function()
			local refs = HudView.build() :: any
			T.eq(refs.BlasterSlot, nil, "dark: no slot of our own")
			T.eq(refs.CarryPanel:FindFirstChild("Blaster"), nil, "dark: nothing in the Carry holder")
			T.falsy(refs.CarryPanel:GetAttribute("Group"), "dark: the button alone")
			HudView.setBlasterKey(refs, "1")
			HudView.setBlasterEquipped(refs, true) -- (no-ops there)
		end)
		withLight(true, function()
			T.truthy((HudView.build() :: any).BlasterSlot, "light: HudView forwards to the light HUD with the slot")
			for _, scale in { 0.62, 1, 1.25 } do
				local refs = HudBubble.buildGame(scale, 1280) :: any
				local slot = refs.BlasterSlot
				local at = `at {scale}`
				T.truthy(slot and slot:IsA("TextButton"), "the slot " .. at)
				T.eq(slot.Name, "Blaster")
				T.eq(slot.Parent, refs.CarryPanel, "in the Carry holder: it hides with the backpack button " .. at)
				T.truthy(refs.CarryPanel:GetAttribute("Group"), "the holder is the whole group")
				T.truthy(slot.Selectable, "the gamepad's UI selection reaches it")
				T.eq(slot.Size.X.Offset, slot.Size.Y.Offset, "square " .. at)
				T.eq(slot.Size.Y.Offset, refs.Backpack.Size.Y.Offset, "as tall as the backpack button " .. at)
				-- the backpack button's well look: the same pieces
				for _, piece in { "Paint", "Rim", "Border" } do
					T.truthy(slot:FindFirstChild(piece), `the well's {piece}`)
					T.truthy(refs.Backpack:FindFirstChild(piece), `the button's {piece}`)
				end
				T.eq(slot:GetAttribute("PixelFx"), "Press", "pressed like the button")
				-- the blaster's picture: an uploaded icon, else the live model (the previews draw "blaster")
				local icon, picture = slot:FindFirstChild("Icon"), slot:FindFirstChild("Picture")
				T.truthy(icon or picture, "a picture " .. at)
				if picture then
					T.eq(picture:GetAttribute("Icon"), "blaster", "the preview's blaster picture")
					local view = picture:FindFirstChild("View")
					T.truthy(view and view:FindFirstChildOfClass("Model"), "a live blaster model in the view")
					T.eq(picture.Image, "", "no broken image")
				else
					T.truthy(icon.Image ~= "", "the uploaded icon")
				end
				-- never an emoji: every word in it is plain ASCII
				for _, d in slot:GetDescendants() do
					if d:IsA("TextLabel") or d:IsA("TextButton") then
						T.falsy(string.find(d.Text, "[\128-\255]"), "no emoji / no non-ASCII text: " .. d.Name)
					end
				end
				T.eq(slot.Text, "", "no text on the button itself")
			end
		end)
	end)

	T.test("BlasterSlot: the 1 key cap on the top-left corner and the gold ring while the Blaster is in hand", function()
		withLight(true, function()
			local refs = HudBubble.buildGame(1, 1280) :: any
			local slot = refs.BlasterSlot
			local key, glyph = slot:FindFirstChild("Key"), slot:FindFirstChild("Glyph")
			T.truthy(key and glyph, "the key cap and the glyph")
			T.falsy(key.Visible or glyph.Visible, "hidden until the controller names the key")
			HudView.setBlasterKey(refs, "1")
			T.truthy(key.Visible and key.Text == "1" and not glyph.Visible, "1 on a keyboard")
			T.eq(key.Position.X.Scale, 0, "the top-left corner (the backpack's Q is top-right)")
			T.eq(refs.Backpack:FindFirstChild("Key").Position.X.Scale, 1, "the backpack's key stays top-right")
			HudView.setBlasterKey(refs, nil)
			T.falsy(key.Visible or glyph.Visible, "nothing on touch or a gamepad")
			-- equipped: the gold ring and rim; then the plain well again, updated in place
			local count = #slot:GetDescendants()
			local ring = slot:FindFirstChild("Equipped")
			local light = slot:FindFirstChild("Rim"):FindFirstChild("Light")
			T.falsy(ring.Visible, "plain at first")
			T.falsy(slot:GetAttribute("Equipped"))
			HudView.setBlasterEquipped(refs, true)
			T.truthy(ring.Visible, "the gold ring in hand")
			T.eq(ring:FindFirstChild("Gold").Color, HudBubble.EquippedColor, "gold")
			T.eq(light.Color, HudBubble.EquippedColor, "the rim lit gold")
			T.eq(slot:FindFirstChild("Disc").BackgroundColor3, HudBubble.EquippedColor, "the light behind the blaster turns gold")
			T.truthy(slot:GetAttribute("Equipped"))
			T.truthy(ring.Size.X.Offset >= 2 * PopTheme.Edge, "round the black outline, not over the picture")
			HudView.setBlasterEquipped(refs, false)
			T.falsy(ring.Visible, "put away: the plain well")
			local own = slot:GetAttribute("RimColor") -- (the round look: the well's own colour)
			T.eq(light.Color, if own then own else HudBubble.SlotRim, "the plain rim")
			T.eq(slot:FindFirstChild("Disc").BackgroundColor3, HudBubble.DiscColor, "the cyan light again")
			T.eq(#slot:GetDescendants(), count, "no new instances")
		end)
	end)

	---------------------------------------------------------------- centred

	T.test(
		"BlasterSlot: the slot, a gap and the backpack button are one group in the screen's middle (phones: out of the thumbstick)",
		function()
			withLight(true, function()
				for _, screen in { { 568, 320 }, { 667, 375 }, { 844, 390 }, { 1024, 768 }, { 1280, 720 }, { 1920, 1080 } } do
					local scale = HudBubble.scaleFor(Vector2.new(screen[1], screen[2]))
					local refs = HudBubble.buildGame(scale, screen[1]) :: any
					local where = `{screen[1]} x {screen[2]}`
					local holder, slot, pack = refs.CarryPanel, refs.BlasterSlot, refs.Backpack
					local width = screen[1] / scale
					local left = width / 2 + holder.Position.X.Offset - holder.AnchorPoint.X * holder.Size.X.Offset
					local right = left + holder.Size.X.Offset
					local compact = scale <= HudBubble.CompactScale
					if compact and holder.Size.X.Offset > (1 - 2 * HudBubble.ThumbZone) * width then
						-- (phones: moved right, out of the DynamicThumbstick's zone)
						T.near(left, HudBubble.ThumbZone * width, 1, `{where}: at the thumbstick zone's edge ({left} on {width})`)
					else
						T.truthy(math.abs((left + right) / 2 - width / 2) <= 0.5, `{where}: centred ({left}..{right} on {width})`)
					end
					T.eq(holder.Position.X.Scale, 0.5, where .. ": from the middle, in design units")
					T.eq(holder.Position.Y.Offset, -HudBubble.BackpackBottom, where .. ": at the bottom")
					-- inside: the slot at the left end, the gap, the button at the right end
					T.eq(slot.Position.X.Offset + slot.Position.X.Scale * holder.Size.X.Offset, 0, where .. ": the slot first")
					local packLeft = holder.Size.X.Offset * pack.Position.X.Scale - pack.AnchorPoint.X * pack.Size.X.Offset
					T.eq(packLeft - slot.Size.X.Offset, HudBubble.GroupGap, where .. ": the gap between them")
					T.eq(packLeft + pack.Size.X.Offset, holder.Size.X.Offset, where .. ": the button last")
					-- the pure span (TutorialView, the train panel) says the same
					local spanLeft, spanRight = HudBubble.carrySpan(scale, false, true, width)
					T.eq(width / 2 + spanLeft, left, where .. ": carrySpan's left")
					T.eq(width / 2 + spanRight, right, where .. ": carrySpan's right")
					-- the same UI scale again (HudController) keeps it where it was
					local before = holder.Position
					HudView.placeBackpack(refs, scale, false)
					T.eq(holder.Position, before, where .. ": the same after a re-placement")
				end
			end)
			-- the dark HUD's span is unchanged: right of Roblox's slot
			local darkLeft, darkRight = HudBubble.carrySpan(1, false, false)
			T.eq(darkLeft, HudBubble.backpackX(1))
			T.eq(darkRight, HudBubble.backpackX(1) + HudBubble.BackpackSize.X)
		end
	)

	T.test("BlasterSlot: on phones the slot keeps out of the thumbstick's zone, in both looks", function()
		-- Roblox's DynamicThumbstick starts on touches in the left 40 % of the screen, its lower
		-- two-thirds (the group stands at the bottom: always in those two-thirds)
		local look = PopTheme.Look
		withLight(true, function()
			for _, name in { "Round", "Pixel" } do
				PopTheme.setLook(name)
				for _, size in { { 568, 320 }, { 667, 375 }, { 844, 390 } } do
					local scale = HudBubble.scaleFor(Vector2.new(size[1], size[2]))
					local refs = HudBubble.buildGame(scale, size[1]) :: any
					local width = size[1] / scale
					local holder, slot = refs.CarryPanel, refs.BlasterSlot
					local where = `{name} {size[1]} x {size[2]}`
					local left = width / 2 + holder.Position.X.Offset
					local ring = (slot:FindFirstChild("Equipped") :: any).Size.X.Offset / 2 - slot.Size.X.Offset / 2
					T.truthy(
						left - ring >= HudBubble.ThumbZone * width - 1e-6,
						`{where}: the slot from {(left - ring) * scale} pt, the zone to {HudBubble.ThumbZone * size[1]} pt`
					)
					-- and its right end left of the touch jump button (BoostView.TouchButtons)
					local small = math.min(size[1], size[2]) <= 500
					for _, b in BoostView.TouchButtons[if small then "Small" else "Large"] do
						if b.Name == "Jump" then
							T.truthy(left + holder.Size.X.Offset <= width - b.Left / scale, `{where}: clear of the jump button`)
						end
					end
					-- a new placement (HudController, the gui's size known) keeps it there
					HudView.placeBackpack(refs, scale, false)
					T.eq(width / 2 + holder.Position.X.Offset, left, where .. ": the same after a re-placement")
					refs.Gui:Destroy()
				end
			end
		end)
		PopTheme.setLook(look)
	end)

	---------------------------------------------------------------- phones and PC

	T.test("BlasterSlot: 44 pt on phones, clear of the money, the level bar, the boost corner and the touch buttons", function()
		withLight(true, function()
			-- { width, height, touch, the top bar's inset (px) }
			local screens = {
				{ 568, 320, true, 58 },
				{ 667, 375, true, 58 },
				{ 844, 390, true, 58 },
				{ 1280, 720, false, 36 },
				{ 1920, 1080, false, 58 },
			}
			for _, size in screens do
				local screen = Vector2.new(size[1], size[2])
				local touch = size[3] :: boolean
				local gui = Vector2.new(size[1], size[2] - size[4])
				local scale = HudBubble.scaleFor(screen)
				local width, height = gui.X / scale, gui.Y / scale
				local refs = HudBubble.buildGame(scale, size[1]) :: any
				local where = `{size[1]} x {size[2]}`
				local holder, slot = refs.CarryPanel, refs.BlasterSlot
				local left = width / 2 + holder.Position.X.Offset
				local top = height - HudBubble.BackpackBottom - holder.Size.Y.Offset
				local group = { left, top, left + holder.Size.X.Offset, height - HudBubble.BackpackBottom }
				-- what pokes out of it: the gold ring round the slot, the key caps over the top corners (keyboards)
				local ring = (slot:FindFirstChild("Equipped") :: any).Size.X.Offset / 2 + 4
				local keyOut = if touch then 0 else (slot:FindFirstChild("Key") :: any).Size.Y.Offset / 2 - 2
				local outer = { group[1] - ring, group[2] - math.max(ring, keyOut), group[3] + 6, group[4] + ring }
				T.truthy(outer[1] >= 0 and outer[3] <= width and outer[4] <= height, where .. ": on screen")
				if scale <= HudBubble.CompactScale then
					T.truthy(slot.Size.X.Offset * scale >= 44 and slot.Size.Y.Offset * scale >= 44, where .. ": the slot >= 44 pt")
					T.truthy(refs.Backpack.Size.Y.Offset * scale >= 44, where .. ": the button >= 44 pt tall")
				end
				-- the money (bottom left)
				local coins = refs.CoinsPanel
				local coinsTop = height + coins.Position.Y.Offset - coins.Size.Y.Offset
				local money =
					{ coins.Position.X.Offset, coinsTop, coins.Position.X.Offset + coins.Size.X.Offset, coinsTop + coins.Size.Y.Offset }
				T.falsy(overlap(outer, money), `{where}: clear of the money ({money[3]} vs {outer[1]})`)
				-- the level / XP bar over it (LevelView: the badge reaches lowest)
				local badgeBottom = LevelView.BarBottom + LevelView.BarHeight / 2 - LevelView.Badge / 2
				T.truthy(height - outer[2] < badgeBottom, `{where}: under the level bar ({height - outer[2]} < {badgeBottom})`)
				-- the boost corner (BoostView.cornerSpot, one and two boosts)
				local pill = refs.Gui:FindFirstChild("ShopPill") :: any -- (the round look: in the top row)
				local pillRect = if pill
						and pill.AnchorPoint.Y == 0
						and pill.Position.Y.Scale == 0
					then {
						Left = width * pill.Position.X.Scale + pill.Position.X.Offset - pill.AnchorPoint.X * pill.Size.X.Offset,
						Top = pill.Position.Y.Offset,
						Bottom = pill.Position.Y.Offset + pill.Size.Y.Offset,
					}
					else nil
				for _, count in { 1, 2 } do
					local right, bottom, stacked = BoostView.cornerSpot({
						Screen = screen,
						Gui = gui,
						Scale = scale,
						Touch = touch,
						Count = count,
						Pill = pillRect,
					})
					local tile = BoostView.cornerHeight()
					local rowW = if stacked
						then BoostView.CornerWidth
						else count * BoostView.CornerWidth + (count - 1) * BoostView.CornerGap
					local rowH = if stacked then count * tile + (count - 1) * BoostView.CornerGap else tile
					local row = { width - right - rowW, height - bottom - rowH, width - right, height - bottom }
					T.falsy(overlap(outer, row), `{where}: clear of the boost corner ({count})`)
				end
				-- the touch buttons (BoostView.TouchButtons, px from the gui's bottom-right)
				if touch then
					local small = math.min(size[1], size[2]) <= 500
					local slotRect = { group[1] - ring, group[2] - ring, group[1] + slot.Size.X.Offset + ring, group[4] + ring }
					for _, b in BoostView.TouchButtons[if small then "Small" else "Large"] do
						local button =
							{ width - b.Left / scale, height - b.Top / scale, width - b.Right / scale, height - b.Bottom / scale }
						T.falsy(overlap(group, button), `{where}: the group clear of {b.Name}`)
						T.falsy(overlap(slotRect, button), `{where}: the slot's ring clear of {b.Name}`)
					end
				end
				refs.Gui:Destroy()
			end
		end)
	end)

	---------------------------------------------------------------- the toggle

	-- a character (with a humanoid) and a backpack that hold tools the way Roblox moves them
	local function fakeWorld(withTool: boolean): any
		local function holder(name: string): any
			local h: any = { Name = name, items = {} }
			function h.FindFirstChild(_, n: string)
				for _, item in h.items do
					if item.Name == n then
						return item
					end
				end
				return nil
			end
			function h.FindFirstChildOfClass(_, class: string)
				return if class == "Humanoid" then h.humanoid else nil
			end
			return h
		end
		local backpack, character = holder("Backpack"), holder("Character")
		local tool: any = { Name = BlasterBuilder.ToolName }
		function tool.IsA(_, class: string)
			return class == "Tool"
		end
		if withTool then
			table.insert(backpack.items, tool)
		end
		local humanoid: any = { Health = 100, equips = 0, unequips = 0 }
		function humanoid.EquipTool(self: any, t: any)
			self.equips += 1
			local at = table.find(backpack.items, t)
			if at then
				table.remove(backpack.items, at)
			end
			table.insert(character.items, t)
		end
		function humanoid.UnequipTools(self: any)
			self.unequips += 1
			for _, item in character.items do
				table.insert(backpack.items, item)
			end
			table.clear(character.items)
		end
		character.humanoid = humanoid
		return { Backpack = backpack, Character = character, Humanoid = humanoid, Tool = tool }
	end

	T.test("BlasterSlot: the toggle equips the Blaster from the backpack and puts it away", function()
		local w = fakeWorld(true)
		T.falsy(Hotbar.equipped(w.Character), "in the backpack at first")
		T.eq(Hotbar.toggle(w.Character, w.Backpack, false), "Equipped")
		T.eq(w.Humanoid.equips, 1, "Humanoid:EquipTool")
		T.truthy(Hotbar.equipped(w.Character), "in the hand")
		T.eq(Hotbar.tool(w.Character), w.Tool, "the Blaster")
		T.eq(Hotbar.tool(w.Backpack), nil, "out of the backpack")
		T.eq(Hotbar.toggle(w.Character, w.Backpack, false), "Unequipped")
		T.eq(w.Humanoid.unequips, 1, "Humanoid:UnequipTools")
		T.falsy(Hotbar.equipped(w.Character), "put away")
		T.eq(Hotbar.tool(w.Backpack), w.Tool, "back in the backpack")
		T.eq(Hotbar.toggle(w.Character, w.Backpack, false), "Equipped", "and out again")
		T.eq(Hotbar.ToolName, BlasterBuilder.ToolName, "the server's tool name")
		-- nothing to equip, nobody to hold it
		local empty = fakeWorld(false)
		T.eq(Hotbar.toggle(empty.Character, empty.Backpack, false), "NoTool")
		T.eq(empty.Humanoid.equips, 0)
		T.eq(Hotbar.toggle(nil, empty.Backpack, false), "NoCharacter")
		local dead = fakeWorld(true)
		dead.Humanoid.Health = 0
		T.eq(Hotbar.toggle(dead.Character, dead.Backpack, false), "NoCharacter", "not while dead")
		T.eq(dead.Humanoid.equips, 0)
		-- a part named Blaster is no tool
		local odd = fakeWorld(false)
		local part: any = { Name = BlasterBuilder.ToolName }
		function part.IsA(_, class: string)
			return class == "BasePart"
		end
		table.insert(odd.Backpack.items, part)
		T.eq(Hotbar.toggle(odd.Character, odd.Backpack, false), "NoTool", "only a Tool")
	end)

	T.test("BlasterSlot: refused while busy (a close-up holds the controls, or the cleaning minigame)", function()
		local w = fakeWorld(true)
		T.eq(Hotbar.toggle(w.Character, w.Backpack, true), "Busy", "no equipping in a close-up")
		T.eq(w.Humanoid.equips, 0, "nothing equipped")
		T.eq(Hotbar.toggle(w.Character, w.Backpack, false), "Equipped")
		T.eq(Hotbar.toggle(w.Character, w.Backpack, true), "Busy", "nor putting it away")
		T.eq(w.Humanoid.unequips, 0, "still in hand")
		-- the controller's busy: MiningController.canUse's rules (PlayerControls) plus the cleaning minigame
		local source = read("src/client/Controllers/BlasterSlotController.luau")
		T.truthy(source:find("PlayerControls.owner() ~= nil or CleaningController.isActive()", 1, true), "busy = a close-up or cleaning")
		T.truthy(
			source:find('Hotbar.toggle(player.Character, player:FindFirstChildOfClass("Backpack"), busy())', 1, true),
			"the slot and the key go through the toggle with it"
		)
		T.truthy(source:find("slot.Activated:Connect", 1, true), "click, tap and a gamepad's A on the slot")
		-- the equipped look follows the character's tools, every new character too
		for _, hook in { "character.ChildAdded:Connect", "character.ChildRemoved:Connect", "player.CharacterAdded:Connect" } do
			T.truthy(source:find(hook, 1, true), hook)
		end
		-- only while the slot shows (the HUD on, the group shown: build mode hides it)
		for _, watch in
			{
				'hud.Gui:GetPropertyChangedSignal("Enabled")',
				'hud.CarryPanel:GetPropertyChangedSignal("Visible")',
			}
		do
			T.truthy(source:find(watch, 1, true), watch)
		end
		local init = read("src/client/init.client.luau")
		local at = init:find('"BlasterSlotController"', 1, true)
		local hud = init:find('"HudController"', 1, true)
		T.truthy(at and hud and hud < at, "in the client's ORDER, after HudController")
	end)

	---------------------------------------------------------------- keys

	T.test("BlasterSlot: KeyCode.One is bound only here, no touch button, no gamepad button", function()
		local source = read("src/client/Controllers/BlasterSlotController.luau")
		T.truthy(source:find("BlasterSlotController.Key = Enum.KeyCode.One\n", 1, true), "the key is 1 (Roblox's slot 1)")
		T.truthy(
			source:find("ContextActionService:BindAction(KEY_ACTION, onKey, false, BlasterSlotController.Key)", 1, true),
			"1 alone, no touch button"
		)
		T.truthy(source:find("ContextActionService:UnbindAction(KEY_ACTION)", 1, true), "unbound while the slot hides")
		T.falsy(source:find("KeyCode%.Button"), "no gamepad button (R2 equips near rocks; L1 / R1 are taken)")
		T.falsy(source:find("KeyCode%.DPad"), "no D-pad either")
		-- nothing else in the game uses 1
		local function walk(dir: string, out: { string })
			for _, entry in fs.readDir(dir) do
				local path = dir .. "/" .. entry
				if fs.isDir(path) then
					walk(path, out)
				elseif entry:match("%.luau$") then
					table.insert(out, path)
				end
			end
		end
		local files = {}
		walk(Loader.root .. "/src", files)
		local seen = 0
		for _, path in files do
			local text = fs.readFile(path)
			local uses = text:find("KeyCode%.One[^%w]") or text:find('KeyCode%["One"%]')
			if path:find("BlasterSlotController", 1, true) then
				seen += if uses then 1 else 0
			else
				T.falsy(uses, path .. " uses KeyCode.One")
			end
		end
		T.eq(seen, 1, "the slot's controller binds it")
	end)

	---------------------------------------------------------------- Roblox's hotbar

	-- a stand-in for StarterGui: Set / GetCoreGuiEnabled, refusing the first `refuse` calls
	local function fakeCore(refuse: number, startOn: boolean): any
		local core: any = { on = startOn, sets = {}, calls = 0 }
		function core.SetCoreGuiEnabled(self: any, kind: any, value: boolean)
			self.calls += 1
			if self.calls <= refuse then
				error("SetCoreGuiEnabled is not ready")
			end
			T.eq(kind, Enum.CoreGuiType.Backpack, "only the Backpack")
			table.insert(self.sets, value)
			self.on = value
		end
		function core.GetCoreGuiEnabled(self: any, _: any): boolean
			return self.on
		end
		return core
	end

	-- runs fn with Hotbar talking to `core` (no waits between tries)
	local function withCore(core: any, fn: () -> ())
		local before, wait = Hotbar.Core, Hotbar.HideWait
		Hotbar.Core, Hotbar.HideWait = core, 0
		local ok, err = pcall(fn)
		Hotbar.Core, Hotbar.HideWait = before, wait
		if not ok then
			error(err, 0)
		end
	end

	T.test("BlasterSlot: Roblox's hotbar is off on the light UI and the close-ups never turn it back on there", function()
		-- hideCore: off, retried (pcall'd) until the CoreGui takes it
		local ready = fakeCore(0, true)
		withCore(ready, function()
			T.truthy(Hotbar.hideCore(3), "off at once")
		end)
		T.falsy(ready.on, "Roblox's hotbar off")
		local late = fakeCore(2, true)
		withCore(late, function()
			T.truthy(Hotbar.hideCore(5), "off on the third try")
		end)
		T.eq(late.calls, 3, "retried until it worked")
		local never = fakeCore(99, true)
		withCore(never, function()
			T.falsy(Hotbar.hideCore(4), "gives up after its tries, never throws")
		end)
		T.eq(never.calls, 4)
		-- the close-ups' restore: what they saved, but never on with the light UI
		withLight(true, function()
			T.falsy(Hotbar.coreWanted(), "light: our own slot")
			T.falsy(Hotbar.restoreValue(true), "light: a saved 'on' gives back off")
			local core = fakeCore(0, false)
			withCore(core, function()
				Hotbar.restoreCore(true)
				Hotbar.restoreCore(false)
				Hotbar.restoreCore(nil)
			end)
			T.eq(#core.sets, 2, "nil: nothing was read, nothing is set")
			T.falsy(core.sets[1] or core.sets[2], "light: never back on")
		end)
		withLight(false, function()
			T.truthy(Hotbar.coreWanted(), "dark: Roblox's hotbar stays")
			local core = fakeCore(0, false)
			withCore(core, function()
				Hotbar.restoreCore(true)
			end)
			T.eq(core.sets[1], true, "dark: the close-up gives it back as it was")
		end)
		-- the controller turns it off on the light UI only; nothing else in src/ turns it on
		local source = read("src/client/Controllers/BlasterSlotController.luau")
		T.truthy(source:find("Hotbar.hideCore()", 1, true), "the controller hides Roblox's hotbar")
		local _, guards = string.gsub(source, "if not UIConfig%.lightUI%(%) then\n%s*return", "")
		T.eq(guards, 2, "init and start do nothing on the dark HUD")
		for _, rel in
			{
				"src/client/Controllers/PlacementController.luau",
				"src/client/Controllers/CleaningController.luau",
				"src/client/Controllers/VaultController.luau",
			}
		do
			local text = read(rel)
			-- (PlacementController requires it at the call: its top level is at Luau's 200 registers)
			local _, restores = string.gsub(text, "Hotbar%.restoreCore%(", "")
			local _, inline = string.gsub(text, "require%(script%.Parent%.Parent%.Util%.Hotbar%)%.restoreCore%(", "")
			T.truthy(
				text:find("local Hotbar = require(script.Parent.Parent.Util.Hotbar)", 1, true) or inline == 1,
				rel .. ": uses Util/Hotbar"
			)
			T.eq(restores + inline, 1, rel .. ": gives the hotbar back through Hotbar.restoreCore")
		end
		local function walk(dir: string, out: { string })
			for _, entry in fs.readDir(dir) do
				local path = dir .. "/" .. entry
				if fs.isDir(path) then
					walk(path, out)
				elseif entry:match("%.luau$") then
					table.insert(out, path)
				end
			end
		end
		local files = {}
		walk(Loader.root .. "/src", files)
		local scanned = 0
		for _, path in files do
			if not path:find("Util/Hotbar.luau", 1, true) then
				for value in string.gmatch(fs.readFile(path), "SetCoreGuiEnabled[^\n]-CoreGuiType%.Backpack,%s*([^%)\n]+)%)") do
					T.eq(value, "false", path .. ": only ever turns Roblox's hotbar off (restore: Hotbar.restoreCore)")
					scanned += 1
				end
			end
		end
		T.truthy(scanned >= 3, "the close-ups' own hide calls were found (" .. scanned .. ")")
	end)
end
