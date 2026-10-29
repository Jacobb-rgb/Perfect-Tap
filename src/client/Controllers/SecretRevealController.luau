--[[
	SecretRevealController: the SECRET ores on the client (owner 2026-10-29).

	  SecretFound { OreId, New, Stars }   the server graded a secret ore this
	      player cleaned: kept until the cleaning's dirt bursts
	      (SecretCleanFx calls play), so NEW! knows a first find.
	  SecretChat { UserId, Name, OreId, Global }   a line in the chat for a
	      find on this server (Global: Rainbow Nova from any server), built
	      here from OreData (TextChatService RBXGeneral:DisplaySystemMessage):
	      "[SECRET] Mia found Hollow Eye! (1 in 4,000)"
	  Fx "SecretPillar" (position, oreId)   a column of rainbow light over a
	      station where someone near found a secret (everyone within
	      SecretService.PillarRadius sees it): six turning shafts round a
	      white core, rings climbing it, PillarSeconds, then it fades.
	  play(oreId, onDone?)   the jackpot screen (Effects/SecretReveal) from
	      the BOOM: posed every frame, a tap / click / A skips to the flight
	      after SecretReveal.SkipAfter, Reduce motion (Motion.reduced()), a
	      phone gets fewer rays and pieces, one flash at most
	      (RevealKit.takeFlash), the world camera kicks (CameraShake), the
	      sounds play in layers. onDone runs when it is over.
]]

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local OreData = require(Shared.Config.OreData)
local SecretOreConfig = require(Shared.Config.SecretOreConfig)
local SecretReveal = require(script.Parent.Parent.Effects.SecretReveal)
local RevealKit = require(script.Parent.Parent.Effects.RevealKit)
local CameraShake = require(script.Parent.Parent.Effects.CameraShake)
local Sfx = require(script.Parent.Parent.Effects.Sfx)
local Motion = require(script.Parent.Parent.UI.Motion)

local SecretRevealController = {}

SecretRevealController.KeepFound = 30 -- seconds a SecretFound waits for its cleaning to burst
SecretRevealController.Color = "#FF78E6" -- the chat line's colour (Rarity.Secret)
SecretRevealController.PillarSeconds = 3.6
SecretRevealController.PillarHeight = 120

---------------------------------------------------------------- pure (specced)

local function escape(text: string): string
	return (text:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub('"', "&quot;"):gsub("'", "&apos;"))
end

-- The chat line for a SecretChat (nil for an unknown ore or a broken name).
function SecretRevealController.chatLine(data: any): string?
	if type(data) ~= "table" or type(data.Name) ~= "string" or #data.Name == 0 or #data.Name > 40 then
		return nil
	end
	local secret = if type(data.OreId) == "string" then SecretOreConfig.ByOre[data.OreId] else nil
	local ore = if secret then OreData.ById[secret.Ore] else nil
	if not secret or not ore then
		return nil
	end
	local chance = SecretOreConfig.chanceText(secret.OneIn)
	local text = `[SECRET] {escape(data.Name)} found {ore.Name}! ({chance})`
	return `<font color="{SecretRevealController.Color}"><b>{text}</b></font>`
end

---------------------------------------------------------------- the client

local found: { [string]: { New: boolean, At: number } } = {}
local view: SecretReveal.View? = nil
local playing = false

-- The SecretFound of `oreId` if it came in the last KeepFound seconds (and forgets it).
function SecretRevealController.takeFound(oreId: string): { New: boolean }?
	local entry = found[oreId]
	found[oreId] = nil
	if entry and os.clock() - entry.At <= SecretRevealController.KeepFound then
		return { New = entry.New }
	end
	return nil
end

local function showChat(data: any)
	local line = SecretRevealController.chatLine(data)
	if not line then
		return
	end
	pcall(function()
		local channels = game:GetService("TextChatService"):FindFirstChild("TextChannels")
		local general = channels and channels:FindFirstChild("RBXGeneral")
		if general and general:IsA("TextChannel") then
			general:DisplaySystemMessage(line)
		end
	end)
end

local function sounds(stars: number)
	Sfx.play("SecretBoom")
	Sfx.play("SecretChime")
	task.delay(0.25, Sfx.play, "SecretFanfare")
	for k = 1, 2 + stars do
		task.delay(0.15 * k, Sfx.play, "SecretSparkle")
	end
end

function SecretRevealController.play(oreId: string, onDone: (() -> ())?)
	if playing or not SecretOreConfig.isSecret(oreId) then
		if onDone then
			onDone()
		end
		return
	end
	playing = true
	local player = Players.LocalPlayer
	local v = view or SecretReveal.build()
	view = v
	v.Gui.Parent = player:WaitForChild("PlayerGui")
	local info = SecretRevealController.takeFound(oreId)
	local secret = SecretOreConfig.ByOre[oreId]
	SecretReveal.setOre(v, oreId, { Chance = SecretOreConfig.chanceText(secret.OneIn), New = info ~= nil and info.New })
	local reduced = Motion.reduced()
	local camera = Workspace.CurrentCamera
	local screen = if camera then camera.ViewportSize else Vector2.new(1280, 720)
	local phone = UserInputService.TouchEnabled and math.min(screen.X, screen.Y) < 600
	local flash = RevealKit.takeFlash(os.clock())
	local scale = 1
	pcall(function()
		scale = require(script.Parent.HudController).uiScale()
	end)
	local opts: SecretReveal.Opts = { Screen = screen, Scale = scale, Reduced = reduced, Phone = phone, Flash = flash }
	if not reduced then
		CameraShake.add(SecretReveal.tierOf(secret.Stars).Shake)
	end
	sounds(secret.Stars)
	local t = 0
	local hold = SecretReveal.tierOf(secret.Stars).Hold
	ContextActionService:BindAction("TerraForgeSecretSkip", function(_, state)
		if state == Enum.UserInputState.Begin and t >= SecretReveal.SkipAfter and t < hold then
			t = hold
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.UserInputType.MouseButton1, Enum.UserInputType.Touch, Enum.KeyCode.ButtonA, Enum.KeyCode.Space)
	local connection: RBXScriptConnection
	connection = RunService.RenderStepped:Connect(function(dt)
		t += dt
		if SecretReveal.pose(v, t, opts) then
			connection:Disconnect()
			ContextActionService:UnbindAction("TerraForgeSecretSkip")
			playing = false
			if onDone then
				onDone()
			end
		end
	end)
end

-- The column of light over a station (Fx "SecretPillar").
local function pillar(position: any, _oreId: any)
	if typeof(position) ~= "Vector3" then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = "SecretPillar"
	folder.Parent = Workspace
	local function neon(color: Color3): Part
		local p = Instance.new("Part")
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Material = Enum.Material.Neon
		p.Color = color
		p.Parent = folder
		return p
	end
	local shafts = {}
	for _, color in SecretOreConfig.Rainbow do
		table.insert(shafts, neon(color))
	end
	local core = neon(Color3.fromRGB(255, 246, 228))
	local rings = {}
	for k = 1, 3 do
		local bars = {}
		for j = 1, 12 do
			table.insert(bars, neon(SecretOreConfig.Rainbow[(j + k) % #SecretOreConfig.Rainbow + 1]))
		end
		rings[k] = bars
	end
	local reduced = Motion.reduced()
	local started = os.clock()
	local connection: RBXScriptConnection
	connection = RunService.RenderStepped:Connect(function()
		local st = os.clock() - started
		local life = SecretRevealController.PillarSeconds
		if st >= life then
			connection:Disconnect()
			folder:Destroy()
			return
		end
		local up = if reduced then 1 else math.min(st / 0.25, 1)
		local fade = math.clamp((st - (life - 0.8)) / 0.8, 0, 1)
		local height = SecretRevealController.PillarHeight * up
		local spin = if reduced then 0 else st * 1.6
		for k, shaft in shafts do
			local a = k * math.pi / 3 + spin
			shaft.Size = Vector3.new(0.7, height, 0.7)
			shaft.CFrame = CFrame.new(position + Vector3.new(math.cos(a) * 1.3, height / 2, math.sin(a) * 1.3))
			shaft.Transparency = 0.25 + 0.75 * fade
		end
		core.Size = Vector3.new(1.4, height, 1.4)
		core.CFrame = CFrame.new(position + Vector3.new(0, height / 2, 0))
		core.Transparency = 0.15 + 0.85 * fade
		for k, bars in rings do
			local u = if reduced then k / 3 else (st * 0.7 + k / 3) % 1
			local y = position.Y + 4 + u * 50
			local r = 2.6 + 1.5 * math.sin(u * math.pi)
			for j, bar in bars do
				local a = j * math.pi / 6 + spin
				local at = Vector3.new(position.X + math.cos(a) * r, y, position.Z + math.sin(a) * r)
				bar.Size = Vector3.new(0.25, 0.25, r * 0.5)
				bar.CFrame = CFrame.lookAt(at, at + Vector3.new(-math.sin(a), 0, math.cos(a)))
				bar.Transparency = math.max(fade, u * 0.8)
			end
		end
	end)
end

function SecretRevealController.init()
	local FxController = require(script.Parent.FxController)
	FxController.register("SecretPillar", pillar)
	Net.listen("SecretFound", function(data)
		if type(data) == "table" and SecretOreConfig.isSecret(data.OreId) then
			found[data.OreId] = { New = data.New == true, At = os.clock() }
		end
	end)
	Net.listen("SecretChat", showChat)
end

function SecretRevealController.start() end

return SecretRevealController
