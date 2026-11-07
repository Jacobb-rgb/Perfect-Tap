-- TEST FILE ONLY (tools/lune/make_test_place.luau ... trace), Studio only: a small black panel top right that
-- says, live, what blocks the next egg (owner 2026-11-07: after an Open 10 the next open waits; no cause in the
-- code). Everything also goes to the Output window as "[Stopa] ...". If the whole screen goes empty and this
-- panel with it, something outside the game's scripts hid it (Roblox's own Ctrl+Shift+G hides every gui).
local RunService = game:GetService("RunService")
if not RunService:IsStudio() then
	return
end
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ProximityPromptService = game:GetService("ProximityPromptService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local client = player:WaitForChild("PlayerScripts"):WaitForChild("Client", 60)
local controllers = client:WaitForChild("Controllers", 60)
controllers:WaitForChild("EggPanelController", 60)
task.wait(3)
local CC = require(controllers.CapsuleController)
local EC = require(controllers.EggPanelController)
local Hud = require(controllers.HudController)
local Prompts = require(controllers.PromptController)
local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))
local MenuPanels = require(client:WaitForChild("Util"):WaitForChild("MenuPanels"))

local gui = Instance.new("ScreenGui")
gui.Name = "EggTrace"
gui.ResetOnSpawn = false
gui.DisplayOrder = 1000
gui.IgnoreGuiInset = true
local box = Instance.new("TextLabel")
box.AnchorPoint = Vector2.new(1, 0)
box.Position = UDim2.new(1, -6, 0, 50)
box.Size = UDim2.fromOffset(500, 340)
box.BackgroundColor3 = Color3.new(0, 0, 0)
box.BackgroundTransparency = 0.2
box.TextColor3 = Color3.new(1, 1, 1)
box.Font = Enum.Font.Code
box.TextSize = 12
box.TextXAlignment = Enum.TextXAlignment.Left
box.TextYAlignment = Enum.TextYAlignment.Top
box.TextWrapped = true
box.Parent = gui
gui.Parent = player:WaitForChild("PlayerGui")

local started = os.clock()
local events = {}
local function log(text)
	local line = string.format("%6.1f %s", os.clock() - started, text)
	print("[Stopa] " .. line)
	table.insert(events, line)
	while #events > 17 do
		table.remove(events, 1)
	end
end

-- passes everything through; `say` gets the arguments and the results
local function wrap(module, name, say)
	local original = module[name]
	if type(original) ~= "function" then
		log("no " .. name)
		return
	end
	module[name] = function(...)
		local args = table.pack(...)
		local results = table.pack(original(...))
		pcall(say, args, results)
		return table.unpack(results, 1, results.n)
	end
end

local sentAt = nil
wrap(EC, "open", function(a, r)
	log(`open x{a[2]} from={a[3]} -> {r[1]}`)
end)
wrap(CC, "buy", function(a, r)
	log(`buy x{a[2]} -> sent={r[1]} why={r[2]}`)
end)
wrap(Hud, "toast", function(a)
	log(`toast: {a[1]}`)
end)
wrap(Net, "send", function(a)
	if a[1] == "CapsuleAction" then
		sentAt = os.clock()
		log(`sent to server: x{type(a[3]) == "table" and a[3].Count or "?"}`)
	end
end)
local function waited()
	return if sentAt then string.format("%.2f s after sending", os.clock() - sentAt) else "not asked"
end
Net.listen("CapsuleResult", function(result)
	log(`server result: {type(result) == "table" and #(result.Golems or {}) or "?"} golems, {waited()}`)
end)
Net.listen("ActionResult", function(result)
	if type(result) == "table" and result.Action == "Capsule" then
		log(`server answer: ok={result.Ok} why={result.Reason}, {waited()}`)
	end
end)
Net.listen("Notify", function(message)
	if type(message) == "table" and message.Kind == "Deny" then
		log(`server says: {message.Text}`)
	end
end)

local shownE = false
ProximityPromptService.PromptShown:Connect(function(prompt)
	if prompt.Name == "EggBuyPrompt" then
		shownE = true
		log("big E shows")
	end
end)
ProximityPromptService.PromptHidden:Connect(function(prompt)
	if prompt.Name == "EggBuyPrompt" then
		shownE = false
		log("big E hides")
	end
end)
ProximityPromptService.PromptTriggered:Connect(function(prompt)
	if prompt.Name == "EggBuyPrompt" then
		log("E pressed: the prompt fired")
	end
end)
UserInputService.InputBegan:Connect(function(input, processed)
	local key = input.KeyCode
	if key == Enum.KeyCode.E or key == Enum.KeyCode.R or key == Enum.KeyCode.X then
		log(`key {key.Name} (taken by the game: {processed})`)
	end
end)

local frames, frameTime = 0, 0
local fps = 0
RunService.Heartbeat:Connect(function(dt)
	frames += 1
	frameTime += dt
	if frameTime >= 1 then
		fps = math.floor(frames / frameTime + 0.5)
		frames, frameTime = 0, 0
	end
	if dt >= 0.3 then
		log(`FROZEN {math.floor(dt * 1000)} ms`)
	end
end)

local function look()
	local s = EC._test.state()
	local id = s.Current
	local spot = if id then s.Spots[id] else nil
	local card = if id then CC.quote(id) else nil
	local buys = {}
	if card and card.Buys then
		for _, b in card.Buys do
			table.insert(buys, `x{b.Count}:{if b.CanBuy then "ok" else tostring(b.Reason)}`)
		end
	end
	local windows = {}
	for _, name in MenuPanels.Names do
		if MenuPanels.isOpen(name) then
			table.insert(windows, (string.gsub(name, "Controller", "")))
		end
	end
	local hud = Hud.refs()
	local scale = hud and hud.Gui:FindFirstChild("Scale")
	-- every game gui at scale 0 or off (the opening's hold, or anything else that hides them)
	local zero, off = 0, 0
	for _, g in player.PlayerGui:GetChildren() do
		if g:IsA("ScreenGui") and string.sub(g.Name, 1, 10) == "TerraForge" then
			local gs = g:FindFirstChild("Scale")
			if gs and gs:IsA("UIScale") and gs.Scale < 0.001 then -- (Roblox reads a 0 back as 1e-07)
				zero += 1
			end
			if not g.Enabled then
				off += 1
			end
		end
	end
	local camera = workspace.CurrentCamera
	return {
		playing = tostring(CC._test.playing()),
		held = tostring(CC._test.hudHidden()),
		queue = tostring(CC._test.queued()),
		blur = tostring(camera ~= nil and camera:FindFirstChild("TerraForgeOpeningBlur") ~= nil),
		guis0 = tostring(zero),
		guisOff = tostring(off),
		owner = tostring(require(client.Util.PlayerControls).owner()),
		egg = tostring(id),
		sold = tostring(s.Sellable),
		E_on = tostring(spot ~= nil and spot.Buy.Enabled),
		E_shown = tostring(shownE),
		reach = tostring(s.Reach),
		opening = (CC.openingState()),
		prompts = tostring(ProximityPromptService.Enabled),
		off_for = table.concat(Prompts.suppressedReasons(), ","),
		windows = table.concat(windows, ","),
		buys = table.concat(buys, " "),
		room = tostring(card and card.Room),
		hud = `{hud and hud.Gui.Enabled}/{scale and scale.Scale}`,
	}
end

local ORDER = {
	"egg", "sold", "E_on", "E_shown", "reach", "opening", "playing", "held", "queue", "blur",
	"prompts", "off_for", "windows", "buys", "room", "hud", "guis0", "guisOff", "owner",
}
local last = {}
while true do
	local ok, now = pcall(look)
	if ok then
		for _, key in ORDER do
			if now[key] ~= last[key] then
				log(`{key}: {last[key]} -> {now[key]}`)
			end
		end
		last = now
		local top = {}
		for _, key in ORDER do
			table.insert(top, `{key}={now[key]}`)
		end
		box.Text = `STOPA {fps} fps\n{table.concat(top, " ")}\n----\n{table.concat(events, "\n")}`
	else
		box.Text = "STOPA failed: " .. tostring(now)
	end
	task.wait(0.2)
end
