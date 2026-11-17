--[[
	ChipSlot: the left column's chip slot under the coins (or under the light
	HUD's menu tiles), where the TRAIN chip stood until the owner took the
	train out (2026-11-17: "Remove all train-related UI ... Do not remove or
	change any other UI"). Nothing else moves: the HUD still keeps the slot
	(HudBubble's ChipTop / ChipLeft attributes), and the running boost chips
	(BoostView) now sit in it; the touch side menu's MENU button keeps its
	place in the slot's row (SideMenuView).

	  ChipSlot.Left / Top        the slot in the plain HUD (design units)
	  ChipSlot.MenuSlot          on touch layouts MENU sits first in the row,
	                             the slot starts this far right of Left
	  ChipSlot.RowHeight         the row's height ({ Normal, Compact }: the old
	                             TRAIN chip's, so MENU stays centred where it was)
	  ChipSlot.useHud(gui)       takes the slot from the light HUD's gui
	                             attributes (HudBubble.placeMenu; HudController)
	  ChipSlot.left(compact), ChipSlot.top()
]]

local ChipSlot = {}

ChipSlot.Left = 16 -- lines up with the coins panel
ChipSlot.Top = 136 -- under the coins panel (16..90) and its "+$X" popups (96..130)
ChipSlot.MenuSlot = 88 -- MENU (84 wide at x 12) and a gap
ChipSlot.RowHeight = { Normal = 66, Compact = 84 } :: { [string]: number }

-- the light HUD (HudBubble): the slot under its menu tiles (HudController sets it from the HUD)
ChipSlot.HudTop = nil :: number?
ChipSlot.HudLeft = nil :: number? -- the round look: under the tiles' left edge, or beside their last row

-- Takes the slot's place from the light HUD's gui attributes (HudBubble.placeMenu: ChipTop,
-- ChipLeft); nil = the plain HUD's place.
function ChipSlot.useHud(gui: Instance?)
	local function number(name: string): number?
		local value = if gui then gui:GetAttribute(name) else nil
		return if type(value) == "number" then value else nil
	end
	ChipSlot.HudTop = number("ChipTop")
	ChipSlot.HudLeft = number("ChipLeft")
end

-- The slot's left edge (design units): the light HUD's, or Left (right of MENU on touch layouts).
function ChipSlot.left(compact: boolean): number
	if ChipSlot.HudTop then
		return ChipSlot.HudLeft or ChipSlot.Left -- the light HUD has no MENU button there
	end
	return ChipSlot.Left + (if compact then ChipSlot.MenuSlot else 0)
end

-- The slot's top (design units): under the light HUD's tiles, or Top.
function ChipSlot.top(): number
	return ChipSlot.HudTop or ChipSlot.Top
end

return ChipSlot
