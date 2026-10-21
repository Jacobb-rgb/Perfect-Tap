--[[
	VaultController: the Blaster Vault shop (client side) and its crate-opening
	cinematic.

	The shop
	- Opens on OpenUI "Vault" { Counter } (the counter's "Blaster Vault"
	  prompt, E / gamepad Y, added by VaultService). The cards come from the
	  State snapshot (VaultView.cards: your blaster level, your coins counted
	  up between snapshots like the HUD).
	- BUY sends VaultBuy { Level } for your next level only. The button shows
	  "..." until the server's VaultResult arrives (one buy waits at a time;
	  with no answer the button is freed after a while: a repeat is safe, the
	  server refuses a level you own as "Owned"). A card that can't be
	  bought answers locally with the same texts and sends nothing.
	- Closes with the X, B (gamepad), Backspace, walking away, the counter
	  streaming out, respawning or another panel opening. Other prompts are
	  hidden while it is open; gamepads get your next card selected.

	The crate opening (on VaultResult Ok)
	- The shop closes, the screen fades in on a dark round room far above the
	  map (Builders/CrateOpeningStage, the same code as the preview video):
	  the case in its ore look drops in, charges, bursts open and the new
	  blaster rises and spins to its hero pose ("NEW BLASTER!",
	  UI/CrateOpeningView). The blaster is already saved (ToolService swaps
	  it meanwhile).
	- A click / tap / A / Space before the burst skips ahead to it; after the
	  reveal AWESOME! (or A / B / Enter / Space / Backspace) ends it. Dying or
	  respawning ends it at once.
	- While it plays: the camera is scripted, walking, prompts, grab/throw,
	  the blaster, the HUD, the backpack and the touch controls are off, the
	  lighting is the "CrateOpening" preset.
]]

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BlasterData = require(Shared.Config.BlasterData)
local OreData = require(Shared.Config.OreData)
local Stage = require(Shared.Builders.CrateOpeningStage)
local Net = require(Shared.Net)
local VaultView = require(script.Parent.Parent.UI.VaultView)
local CrateOpeningView = require(script.Parent.Parent.UI.CrateOpeningView)
local Sfx = require(script.Parent.Parent.Effects.Sfx)
local Vfx = require(script.Parent.Parent.Effects.Vfx)
local MenuPanels = require(script.Parent.Parent.Util.MenuPanels)
local PlayerControls = require(script.Parent.Parent.Util.PlayerControls)
local HudController = require(script.Parent.HudController)
local LightingController = require(script.Parent.LightingController)
local PromptController = require(script.Parent.PromptController)
local StateController = require(script.Parent.StateController)
local InteractController = require(script.Parent.InteractController)
local MiningController = require(script.Parent.MiningController)

local VaultController = {}

type Panel = { isOpen: () -> boolean, close: () -> () }

local CLOSE_ACTION = "TerraForgeVaultClose"
local SKIP_ACTION = "TerraForgeCrateSkip"
local RENDER_STEP = "TerraForgeCrateOpening"
-- above the default player controls, so B / Backspace close the shop first
local CLOSE_PRIORITY = Enum.ContextActionPriority.High.Value + 10
local TICK = 0.25
local PENDING_TIMEOUT = 4 -- seconds a BUY waits for its VaultResult
local MESSAGE_TIME = 3.5
-- the cinematic's room: far above and away from the map (client-only parts)
local STAGE_ORIGIN = CFrame.new(6000, 3000, 6000)
local MAX_CINEMATIC = 40 -- seconds: it ends by itself
local LEAVE_TIME = 0.3 -- the fade to black at the end
-- the other panels (one in the middle of the screen at a time): MenuPanels.Names,
-- the one list of every panel controller (a name that isn't in the game is skipped)

local player = Players.LocalPlayer
local refs: VaultView.Refs? = nil
local counter: BasePart? = nil
local tickConnection: RBXScriptConnection? = nil
local pending: { Level: number, Until: number }? = nil
local messageToken = 0
local openedAt = 0
local others: { Panel }? = nil
local session: any = nil

function VaultController.isOpen(): boolean
	return counter ~= nil
end

-- Is the crate opening playing?
function VaultController.isPlaying(): boolean
	return session ~= nil
end

local function usingGamepad(): boolean
	local last = UserInputService:GetLastInputType()
	return last.Name:sub(1, 7) == "Gamepad"
end

local function isTouch(): boolean
	return UserInputService.TouchEnabled and not UserInputService.MouseEnabled
end

local function coins(): number
	return HudController.predictedCoins(os.clock())
end

local function myLevel(): number
	local state = StateController.get()
	return BlasterData.get(if state then state.BlasterLevel else 1).Level
end

local function myOre(): string
	local state = StateController.get()
	local ore = if state then state.BlasterOre else nil
	return if type(ore) == "string" then ore else ""
end

-- The other panel controllers that exist (required on first use: they may load after this one).
local function otherPanels(): { Panel }
	local cached = others
	if cached then
		return cached
	end
	local list: { Panel } = {}
	for _, name in MenuPanels.Names do
		if name == "VaultController" then
			continue
		end
		local module = script.Parent:FindFirstChild(name)
		if module and module:IsA("ModuleScript") then
			local ok, controller = pcall(require, module :: any)
			if ok and type(controller) == "table" then
				local c = controller :: any
				if type(c.isOpen) == "function" and type(c.close) == "function" then
					table.insert(list, c :: Panel)
				end
			end
		end
	end
	others = list
	return list
end

---------------------------------------------------------------- the shop

local function message(text: string, color: Color3)
	local view = refs
	if not view or not counter then
		HudController.toast(text, "Deny")
		return
	end
	VaultView.setMessage(view, text, color)
	messageToken += 1
	local token = messageToken
	task.delay(MESSAGE_TIME, function()
		local current = refs
		if messageToken == token and current then
			VaultView.setMessage(current, nil, nil)
		end
	end)
end

local function refresh()
	local view = refs
	if not view or not counter then
		return
	end
	local cash = coins()
	VaultView.setCoins(view, cash)
	VaultView.setCurrent(view, myLevel(), myOre())
	local state = StateController.get()
	local rebirth = if state and type(state.Rebirth) == "table" then state.Rebirth else nil
	VaultView.setCards(view, VaultView.cards(myLevel(), cash, if rebirth then tonumber(rebirth.Reached) else nil))
	local wait = pending
	if wait then
		local tile = VaultView.tileFor(view, wait.Level)
		if tile then
			tile.ButtonText.Text = "..."
		end
	end
end

local function updateHint(view: VaultView.Refs)
	if usingGamepad() then
		local a = string.gsub(UserInputService:GetStringForKeyCode(Enum.KeyCode.ButtonA), "^Button", "")
		local b = string.gsub(UserInputService:GetStringForKeyCode(Enum.KeyCode.ButtonB), "^Button", "")
		VaultView.setHint(view, `{if a ~= "" then a else "A"}: buy{VaultView.Separator}{if b ~= "" then b else "B"}: close`)
	elseif isTouch() then
		VaultView.setHint(view, "Tap BUY on the next case")
	else
		VaultView.setHint(view, `Click BUY on the next case{VaultView.Separator}Backspace: close`)
	end
end

local function fit(view: VaultView.Refs)
	local camera = Workspace.CurrentCamera
	local scale = HudController.uiScale()
	local size = if camera then camera.ViewportSize else Vector2.new(1280, 720)
	local inset = GuiService:GetGuiInset()
	local compact = VaultView.compactFor(isTouch(), GuiService:IsTenFootInterface(), scale, size.Y)
	VaultView.layout(view, compact, size.X / scale, (size.Y - inset.Y) / scale)
end

local function selectDefault(view: VaultView.Refs)
	if not usingGamepad() then
		return
	end
	local button = VaultView.firstButton(view)
	GuiService.SelectedObject = button
	for _, tile in view.Tiles do
		if tile.Button == button then
			VaultView.scrollTo(view, tile)
		end
	end
end

local function buy(tile: VaultView.Tile)
	local card = tile.Card
	if not card or not counter then
		return
	end
	if pending then
		message(VaultView.reasonText("Waiting"), VaultView.Style.InkSoft)
		Sfx.play("UIDeny")
		return
	end
	-- the card was drawn with older coins: check again with the coins now
	local reason = if card.CanBuy then nil else card.Reason
	local price = card.Price
	if not reason and price and coins() < price then
		reason = "NoCoins"
	end
	if reason then
		message(
			VaultView.reasonText(reason),
			if reason == "Owned" or reason == "StarForge" then VaultView.Style.InkSoft else VaultView.Style.Bad
		)
		Sfx.play("UIDeny")
		return
	end
	pending = { Level = card.Level, Until = os.clock() + PENDING_TIMEOUT }
	tile.ButtonText.Text = "..."
	Sfx.play("UIClick")
	Net.send("VaultBuy", { Level = card.Level })
end

function VaultController.close()
	if not counter then
		return
	end
	counter = nil
	if tickConnection then
		tickConnection:Disconnect()
		tickConnection = nil
	end
	ContextActionService:UnbindAction(CLOSE_ACTION)
	local view = refs
	if view then
		local selected = GuiService.SelectedObject
		if selected and selected:IsDescendantOf(view.Gui) then
			GuiService.SelectedObject = nil
		end
		VaultView.setMessage(view, nil, nil)
		view.Gui.Enabled = false
	end
	PromptController.setSuppressed("Vault", false)
end

local function onClose(_: string, state: Enum.UserInputState): Enum.ContextActionResult
	if state ~= Enum.UserInputState.Begin or not counter then
		return Enum.ContextActionResult.Pass
	end
	VaultController.close()
	Sfx.play("UIClick")
	return Enum.ContextActionResult.Sink
end

local function ensureView(): VaultView.Refs
	local existing = refs
	if existing then
		return existing
	end
	local view = VaultView.build()
	view.Gui.Parent = player:WaitForChild("PlayerGui")
	view.Close.Activated:Connect(function()
		VaultController.close()
		Sfx.play("UIClick")
	end)
	for _, tile in view.Tiles do
		tile.Button.Activated:Connect(function()
			buy(tile)
		end)
		tile.Button.SelectionGained:Connect(function()
			VaultView.scrollTo(view, tile)
		end)
	end
	refs = view
	return view
end

-- Every TICK: close when you walk away, the counter streams out or another
-- panel opens; count the coins up; free a BUY with no answer.
local function watch(part: BasePart)
	local elapsed = 0
	local sinceRefresh = 0
	tickConnection = RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed < TICK then
			return
		end
		sinceRefresh += elapsed
		elapsed = 0
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not part:IsDescendantOf(Workspace) or not root then
			VaultController.close()
			return
		end
		local p = part.CFrame:PointToObjectSpace(root.Position)
		local half = part.Size / 2
		local outside =
			Vector3.new(math.max(math.abs(p.X) - half.X, 0), math.max(math.abs(p.Y) - half.Y, 0), math.max(math.abs(p.Z) - half.Z, 0))
		if outside.Magnitude > VaultView.CloseRange then
			VaultController.close()
			return
		end
		if os.clock() - openedAt > 0.3 then
			for _, panel in otherPanels() do
				if panel.isOpen() then
					VaultController.close()
					return
				end
			end
		end
		local wait = pending
		if wait and os.clock() > wait.Until then
			pending = nil
			message(VaultView.reasonText("NoAnswer"), VaultView.Style.Bad)
			refresh()
		end
		if sinceRefresh >= 1 then
			sinceRefresh = 0
			refresh()
		else
			local view = refs
			if view then
				VaultView.setCoins(view, coins())
			end
		end
	end)
end

function VaultController.open(part: BasePart)
	if counter == part then
		refresh()
		return
	end
	if session then
		return
	end
	local owner = PlayerControls.owner()
	if owner ~= nil then
		HudController.toast(if owner == "Build" then "Finish building first." else "Finish what you are doing first.", "Info")
		return
	end
	VaultController.close()
	for _, panel in otherPanels() do
		if panel.isOpen() then
			panel.close()
		end
	end
	local view = ensureView()
	counter = part
	openedAt = os.clock()
	fit(view)
	updateHint(view)
	VaultView.setMessage(view, nil, nil)
	view.Cards.CanvasPosition = Vector2.zero
	view.Gui.Enabled = true
	PromptController.setSuppressed("Vault", true)
	ContextActionService:BindActionAtPriority(CLOSE_ACTION, onClose, false, CLOSE_PRIORITY, Enum.KeyCode.ButtonB, Enum.KeyCode.Backspace)
	watch(part)
	GuiService.SelectedObject = nil
	refresh()
	-- the next card in view (the phones' row scrolls)
	for _, tile in view.Tiles do
		if tile.Card and tile.Card.State == "Next" then
			VaultView.scrollTo(view, tile)
		end
	end
	selectDefault(view)
	Sfx.play("UIClick")
	local scale = view.Panel:FindFirstChild("OpenPop") :: UIScale?
	if not scale then
		local made = Instance.new("UIScale")
		made.Name = "OpenPop"
		made.Parent = view.Panel
		scale = made
	end
	local s = scale :: UIScale
	s.Scale = 0.85
	TweenService:Create(s, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

---------------------------------------------------------------- the crate opening

local function finish(s: any)
	if s.done then
		return
	end
	s.done = true
	RunService:UnbindFromRenderStep(RENDER_STEP)
	ContextActionService:UnbindAction(SKIP_ACTION)
	for _, connection in s.connections do
		connection:Disconnect()
	end
	Sfx.loop("CaseCharge", false)
	local camera = s.camera :: Camera
	camera.CameraType = Enum.CameraType.Custom
	camera.FieldOfView = s.savedFov
	s.folder:Destroy()
	s.view.Gui:Destroy()
	s.popLighting()
	if s.backpackWasEnabled ~= nil then
		pcall(StarterGui.SetCoreGuiEnabled, StarterGui, Enum.CoreGuiType.Backpack, s.backpackWasEnabled)
	end
	local hud = HudController.refs()
	if hud then
		hud.Gui.Enabled = true
	end
	pcall(function()
		GuiService.TouchControlsEnabled = true
	end)
	PlayerControls.set(true)
	PlayerControls.release("Vault")
	PromptController.setSuppressed("VaultOpening", false)
	InteractController.resume()
	MiningController.setBusy(false)
	if session == s then
		session = nil
	end
end

-- Fades to black, then gives the game back.
local function leave(s: any)
	if s.leaving or s.done then
		return
	end
	s.leaving = os.clock()
	Sfx.play("UIClick")
	task.delay(LEAVE_TIME, function()
		finish(s)
		HudController.toast("New blaster: " .. s.name .. "!", "Reward")
	end)
end

-- A click / tap / button: before the burst skip ahead to it, after the reveal end.
local function advance(s: any)
	local t = os.clock() - s.started
	if t < s.stage.SkipTo then
		s.started = os.clock() - s.stage.SkipTo
	elseif t >= s.stage.Reveal + CrateOpeningView.ButtonAfter then
		leave(s)
	end
end

local function skipText(): string
	if usingGamepad() then
		local a = string.gsub(UserInputService:GetStringForKeyCode(Enum.KeyCode.ButtonA), "^Button", "")
		return `{if a ~= "" then a else "A"}: skip`
	end
	return if isTouch() then "Tap to skip" else "Click to skip"
end

local function step(s: any)
	if s.done then
		return
	end
	local now = os.clock()
	local t = now - s.started
	local stage = s.stage
	stage.update(t)
	local cf, fov = stage.camera(t)
	s.camera.CFrame = cf
	s.camera.FieldOfView = fov
	local leaving = if s.leaving then math.clamp((now - s.leaving) / LEAVE_TIME, 0, 1) else 0
	CrateOpeningView.update(s.view, t, stage.Burst, stage.Reveal, leaving)
	-- the sounds and particle bursts, once each
	local fired = s.fired
	local function once(key: string, at: number): boolean
		if t >= at and not fired[key] then
			fired[key] = true
			return true
		end
		return false
	end
	if once("land", Stage.T_LAND) then
		Sfx.play("CaseLand")
	end
	if once("charge", 1.0) and t < stage.Burst then
		Sfx.loop("CaseCharge", true)
	end
	if once("burst", stage.Burst) then
		Sfx.loop("CaseCharge", false)
		Sfx.play("CaseBurst")
		Sfx.play("CaseBoom")
		Sfx.play("NodeShatter")
		local core = (STAGE_ORIGIN * CFrame.new(0, 2.2, 0)).Position
		Vfx.burst("Burst", core, 40, stage.Glow)
		Vfx.burst("Sparks", core, 60, stage.Glow:Lerp(Color3.new(1, 1, 1), 0.4))
		Vfx.burst("Glint", core, 24, Color3.new(1, 1, 1))
	end
	if once("rise", stage.Burst + 0.15) then
		Sfx.play("CaseRise")
	end
	if once("reveal", stage.Reveal) then
		Sfx.play("Reveal")
	end
	if once("button", stage.Reveal + CrateOpeningView.ButtonAfter) and usingGamepad() then
		GuiService.SelectedObject = s.view.Continue
	end
	if t > MAX_CINEMATIC then
		leave(s)
	end
end

local function onSkip(_: string, state: Enum.UserInputState): Enum.ContextActionResult
	local s = session
	if state ~= Enum.UserInputState.Begin or not s then
		return Enum.ContextActionResult.Pass
	end
	advance(s)
	return Enum.ContextActionResult.Sink
end

--[[
	Plays the crate opening for a new `level` blaster in `oreId`'s look (the
	purchase is saved already). Returns false when something else holds the
	player (then only a toast says it).
]]
function VaultController.play(level: number, oreId: string): boolean
	local name = BlasterData.displayName(level, oreId)
	if session or not PlayerControls.claim("Vault") then
		HudController.toast("New blaster: " .. name .. "!", "Reward")
		return false
	end
	-- every panel goes (the STORE a Robux blaster was bought in too), then the stage owns the screen
	MenuPanels.closeAll()
	VaultController.close()
	local camera = Workspace.CurrentCamera :: Camera
	local folder = Instance.new("Folder")
	folder.Name = "CrateOpening"
	folder.Parent = Workspace
	local stage = Stage.build(folder, STAGE_ORIGIN, level, oreId, Stage.blasterModel(level, oreId))
	local view = CrateOpeningView.build()
	CrateOpeningView.setBlaster(view, level, oreId)
	CrateOpeningView.setSkipText(view, skipText())
	view.Gui.Parent = player:WaitForChild("PlayerGui")
	CrateOpeningView.update(view, 0, stage.Burst, stage.Reveal)
	local s: any = {
		started = os.clock(),
		stage = stage,
		view = view,
		folder = folder,
		camera = camera,
		savedFov = camera.FieldOfView,
		name = name,
		fired = {},
		connections = {},
	}
	session = s
	-- take over: controls, prompts, grab/throw, blaster, HUD, backpack, touch controls
	PlayerControls.set(false)
	PromptController.setSuppressed("VaultOpening", true)
	InteractController.suspend()
	MiningController.setBusy(true)
	local hud = HudController.refs()
	if hud then
		hud.Gui.Enabled = false
	end
	local okBackpack, backpackEnabled = pcall(StarterGui.GetCoreGuiEnabled, StarterGui, Enum.CoreGuiType.Backpack)
	s.backpackWasEnabled = if okBackpack then backpackEnabled else nil
	pcall(StarterGui.SetCoreGuiEnabled, StarterGui, Enum.CoreGuiType.Backpack, false)
	pcall(function()
		GuiService.TouchControlsEnabled = false
	end)
	GuiService.SelectedObject = nil
	s.popLighting = LightingController.push("CrateOpening", 0.2)
	camera.CameraType = Enum.CameraType.Scriptable
	RunService:BindToRenderStep(RENDER_STEP, Enum.RenderPriority.Camera.Value + 1, function()
		step(s)
	end)
	ContextActionService:BindActionAtPriority(
		SKIP_ACTION,
		onSkip,
		false,
		CLOSE_PRIORITY,
		Enum.KeyCode.ButtonA,
		Enum.KeyCode.ButtonB,
		Enum.KeyCode.Return,
		Enum.KeyCode.Space,
		Enum.KeyCode.Backspace
	)
	table.insert(
		s.connections,
		view.Catcher.Activated:Connect(function()
			advance(s)
		end)
	)
	table.insert(
		s.connections,
		view.Continue.Activated:Connect(function()
			leave(s)
		end)
	)
	return true
end

---------------------------------------------------------------- results

local function onResult(payload: any)
	if type(payload) ~= "table" then
		return
	end
	local level = payload.Level
	local wait = pending
	if wait and (wait.Level == level or payload.Ok ~= true) then
		pending = nil
	end
	if payload.Ok == true and type(level) == "number" then
		local ore = payload.Ore
		local oreId = if type(ore) == "string" and (ore == "" or OreData.ById[ore]) then ore else BlasterData.vaultOre(level)
		Sfx.play("CoinBurst")
		VaultController.play(BlasterData.get(level).Level, oreId)
		return
	end
	if counter then
		message(VaultView.reasonText(payload.Reason), VaultView.Style.Bad)
		Sfx.play("UIDeny")
		refresh()
	else
		HudController.toast(VaultView.reasonText(payload.Reason), "Deny")
	end
end

---------------------------------------------------------------- lifecycle

function VaultController.init()
	Net.listen("OpenUI", function(kind, payload)
		if kind ~= "Vault" or type(payload) ~= "table" then
			return
		end
		local part = payload.Counter
		if typeof(part) == "Instance" and part:IsA("BasePart") then
			VaultController.open(part)
		end
	end)
	Net.listen("VaultResult", onResult)
	StateController.onChanged(function()
		if counter then
			refresh()
		end
	end)
	player.CharacterRemoving:Connect(function()
		VaultController.close()
		local s = session
		if s then
			finish(s)
		end
	end)
	UserInputService.LastInputTypeChanged:Connect(function()
		local view = refs
		if view and counter then
			updateHint(view)
		end
		local s = session
		if s then
			CrateOpeningView.setSkipText(s.view, skipText())
		end
	end)
	local camera = Workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			local view = refs
			if view and counter then
				fit(view)
			end
		end)
	end
end

return VaultController
