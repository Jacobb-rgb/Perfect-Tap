--[[
	Live 3D pictures for the UI (the Shop's cards, the HUD's money): a model
	by picture name, shown in a ViewportFrame (Pop.model), so the pictures
	need no uploaded images. The same names are the preview pictures
	(tools/preview/icons: cash_*, capsule_*, golem_*, train, star_*).

	  cash_*            CashBuilder (bundle, pile, stack, sack, safe)
	  capsule_<Id>      GolemBuilder.capsule
	  golem_<Kind>      GolemBuilder.build
	  train             TrainBuilder.locomotive (the shop's Express Train pass)
	  board_<BoardId>   HoverboardBuilder.build

	`from` is the camera's direction for the picture (the models face -Z).
	Pure: only creates Instances (the previews run it too).
]]

local CashBuilder = require(script.Parent.CashBuilder)
local GolemBuilder = require(script.Parent.GolemBuilder)
local TrainBuilder = require(script.Parent.TrainBuilder)
local HoverboardBuilder = require(script.Parent.HoverboardBuilder)

local PictureModels = {}

local FRONT = Vector3.new(-0.55, 0.42, -1)

-- The model for picture `name` and the camera direction (nil: no such model).
function PictureModels.build(name: string): (Model?, Vector3)
	if string.sub(name, 1, 5) == "cash_" then
		return CashBuilder.picture(name), FRONT
	elseif string.sub(name, 1, 8) == "capsule_" then
		local ok, model = pcall(GolemBuilder.capsule, string.sub(name, 9))
		return if ok then model else nil, Vector3.new(-0.35, 0.3, -1)
	elseif string.sub(name, 1, 6) == "golem_" then
		local ok, model = pcall(GolemBuilder.build, string.sub(name, 7))
		return if ok then model else nil, Vector3.new(-0.3, 0.22, -1)
	elseif name == "train" then
		local ok, model = pcall(TrainBuilder.locomotive, Color3.fromRGB(226, 72, 60))
		return if ok then model else nil, Vector3.new(-1, 0.35, -0.55)
	elseif string.sub(name, 1, 6) == "board_" then
		local ok, model = pcall(HoverboardBuilder.build, string.sub(name, 7))
		return if ok then model else nil, Vector3.new(-1, 0.75, -0.7)
	end
	return nil, FRONT
end

return PictureModels
