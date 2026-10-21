--[[
	Exports a ScreenGui tree (built by the real UI builders) to JSON for the
	HTML UI renderer in tools/preview/ui.js.
]]

local UiExport = {}

local function hex(c): string
	return string.format("%02x%02x%02x", math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5))
end

local function udim2(u): { number }
	return { u.X.Scale, u.X.Offset, u.Y.Scale, u.Y.Offset }
end

local function safe(instance, prop)
	local ok, value = pcall(function()
		return instance[prop]
	end)
	return if ok then value else nil
end

local function exportNode(instance): any?
	if instance:GetAttribute("IconFallback") then
		return nil -- the preview draws the rendered 3D icon instead of the stand-in emoji
	end
	local class = instance.ClassName
	local node: { [string]: any } = { c = class, n = instance.Name }
	if instance:IsA("GuiObject") then
		node.pos = udim2(instance.Position)
		node.size = udim2(instance.Size)
		node.anchor = { instance.AnchorPoint.X, instance.AnchorPoint.Y }
		node.bg = hex(instance.BackgroundColor3)
		node.bgt = instance.BackgroundTransparency
		node.vis = instance.Visible
		node.z = instance.ZIndex
		node.lo = instance.LayoutOrder
		node.rot = instance.Rotation
		node.clip = instance.ClipsDescendants
		local auto = safe(instance, "AutomaticSize")
		if auto and auto.Name ~= "None" then
			node.auto = auto.Name -- "X" | "Y" | "XY": grows to fit its text and children
		end
		if class == "ViewportFrame" then
			node.icon = instance:GetAttribute("Icon") -- a preview stand-in for the live 3D picture
		end
		if instance:IsA("TextLabel") or instance:IsA("TextButton") or instance:IsA("TextBox") then
			node.text = instance.Text
			node.ts = instance.TextSize
			node.tc = hex(instance.TextColor3)
			node.tt = instance.TextTransparency
			node.font = instance.FontFace.Family
			node.tx = instance.TextXAlignment.Name
			node.ty = instance.TextYAlignment.Name
			node.scaled = instance.TextScaled
			node.wrap = instance.TextWrapped
			local limit = instance:FindFirstChildOfClass("UITextSizeConstraint")
			if limit then
				node.maxts = limit.MaxTextSize
				node.mints = limit.MinTextSize
			end
		end
		if instance:IsA("ScrollingFrame") then
			node.cp = { instance.CanvasPosition.X, instance.CanvasPosition.Y } -- where it is scrolled to
		end
		if instance:IsA("ImageLabel") or instance:IsA("ImageButton") then
			node.img = tostring(instance.Image)
			node.it = instance.ImageTransparency
			node.ic = hex(instance.ImageColor3)
			node.icon = instance:GetAttribute("Icon") -- 3D UI icon name (tools/preview/icons), shown from build/preview/icons
		end
	elseif class == "UICorner" then
		node.r = { instance.CornerRadius.Scale, instance.CornerRadius.Offset }
	elseif class == "UIStroke" then
		node.th = instance.Thickness
		node.col = hex(instance.Color)
		node.t = if safe(instance, "Enabled") == false then 1 else instance.Transparency -- a disabled stroke draws nothing
		node.mode = instance.ApplyStrokeMode.Name
	elseif class == "UIGradient" then
		local keys = {}
		for _, k in instance.Color.Keypoints do
			table.insert(keys, { k.Time, hex(k.Value) })
		end
		node.keys = keys
		local fade = {}
		for _, k in instance.Transparency.Keypoints do
			table.insert(fade, { k.Time, k.Value })
		end
		node.tkeys = fade
		node.rot = instance.Rotation
		local offset = instance.Offset
		if offset.X ~= 0 or offset.Y ~= 0 then
			node.off = { offset.X, offset.Y } -- (UI/Motion's shine sweeps it)
		end
	elseif class == "UIListLayout" then
		node.dir = instance.FillDirection.Name
		node.pad = { instance.Padding.Scale, instance.Padding.Offset }
		node.ha = instance.HorizontalAlignment.Name
		node.va = instance.VerticalAlignment.Name
	elseif class == "UIGridLayout" then
		node.cell = udim2(instance.CellSize)
		node.cpad = udim2(instance.CellPadding)
		node.ha = instance.HorizontalAlignment.Name
		node.va = instance.VerticalAlignment.Name
		node.dir = instance.FillDirection.Name
	elseif class == "UIPadding" then
		node.p = {
			instance.PaddingTop.Offset,
			instance.PaddingRight.Offset,
			instance.PaddingBottom.Offset,
			instance.PaddingLeft.Offset,
		}
	elseif class == "UIScale" then
		node.s = instance.Scale
	elseif class == "UIAspectRatioConstraint" then
		node.ar = instance.AspectRatio
	elseif class == "UISizeConstraint" then
		local function finite(n: number): number
			return math.min(n, 1e6) -- math.huge isn't JSON
		end
		node.min = { instance.MinSize.X, instance.MinSize.Y }
		node.max = { finite(instance.MaxSize.X), finite(instance.MaxSize.Y) }
	elseif class == "ScreenGui" then
		node.inset = not instance.IgnoreGuiInset
		node.order = instance.DisplayOrder
		node.enabled = safe(instance, "Enabled") ~= false
	else
		return nil
	end
	local children = {}
	for _, child in instance:GetChildren() do
		local exported = exportNode(child)
		if exported then
			table.insert(children, exported)
		end
	end
	if #children > 0 then
		node.ch = children
	end
	return node
end

-- Called with every ScreenGui right before it is exported (export_scene sets it
-- for LIGHT_UI=1: LightSkin.refresh, since Roblox signals don't run in Lune).
UiExport.before = nil :: ((any) -> ())?

function UiExport.export(screenGuis: { any }): { any }
	local out = {}
	local before = UiExport.before
	for _, gui in screenGuis do
		if before then
			before(gui)
		end
		table.insert(out, exportNode(gui))
	end
	return out
end

return UiExport
