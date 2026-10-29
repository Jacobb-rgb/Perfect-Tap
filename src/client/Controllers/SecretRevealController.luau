--[[
	SecretRevealController: the SECRET ores on the client (owner 2026-10-29).

	  SecretFound { OreId, New, Stars }   the server graded a secret ore this
	      player cleaned: kept until the cleaning's dirt bursts
	      (SecretCleanFx calls play), so NEW! knows a first find.
	  SecretChat { UserId, Name, OreId, Global }   a line in the chat for a
	      find on this server (Global: Rainbow Nova from any server), built
	      here from OreData (TextChatService RBXGeneral:DisplaySystemMessage):
	      "[SECRET] Mia found Hollow Eye! (1 in 4,000)"
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

function SecretRevealController.init()
	Net.listen("SecretFound", function(data)
		if type(data) == "table" and SecretOreConfig.isSecret(data.OreId) then
			found[data.OreId] = { New = data.New == true, At = os.clock() }
		end
	end)
	Net.listen("SecretChat", showChat)
end

function SecretRevealController.start() end

return SecretRevealController
