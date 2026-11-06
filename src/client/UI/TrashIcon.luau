--[[
	TrashIcon: a small trash can drawn from frames (our own drawing, no
	image): the egg panel's auto-delete toggle on each golem card and the
	"Deleted" mark under an auto-deleted golem in the egg opening.

	  TrashIcon.build(parent, size, color, z) -> Frame   a size x size icon
	  TrashIcon.paint(icon, color)                       its colour

	Pure: only Instance creation (the Lune specs and previews run it).
]]

local UIKit = require(script.Parent.UIKit)

local TrashIcon = {}

-- (shares of the icon's size: x, y, w, h)
local PIECES: { [string]: { number } } = {
	Handle = { 0.38, 0.06, 0.24, 0.1 },
	Lid = { 0.14, 0.16, 0.72, 0.11 },
	Body = { 0.22, 0.32, 0.56, 0.6 },
}

function TrashIcon.build(parent: Instance, size: number, color: Color3, z: number): Frame
	local icon = UIKit.new("Frame", {
		Name = "Trash",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(size, size),
		ZIndex = z,
	}, parent) :: Frame
	for name, p in PIECES do
		local piece = UIKit.new("Frame", {
			Name = name,
			BackgroundColor3 = color,
			BorderSizePixel = 0,
			Position = UDim2.fromScale(p[1], p[2]),
			Size = UDim2.fromScale(p[3], p[4]),
			ZIndex = z,
		}, icon) :: Frame
		if name == "Body" then
			UIKit.corner(piece, 2)
			-- two slits down the can
			for i, x in { 0.3, 0.62 } do
				UIKit.new("Frame", {
					Name = "Slit" .. i,
					BackgroundColor3 = Color3.new(0, 0, 0),
					BackgroundTransparency = 0.55,
					BorderSizePixel = 0,
					Position = UDim2.fromScale(x, 0.18),
					Size = UDim2.fromScale(0.1, 0.64),
					ZIndex = z + 1,
				}, piece)
			end
		end
	end
	return icon
end

-- The icon's colour (its can, lid and handle; the slits stay dark).
function TrashIcon.paint(icon: Instance, color: Color3)
	for _, name in { "Handle", "Lid", "Body" } do
		local piece = icon:FindFirstChild(name)
		if piece and piece:IsA("Frame") then
			piece.BackgroundColor3 = color
		end
	end
end

return TrashIcon
