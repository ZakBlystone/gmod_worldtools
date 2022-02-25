if SERVER then AddCSLuaFile() return end

module("wt_modal", package.seeall)

--[[{
	options = {
		{ title = "Test", func = function() end, }
		{ options = {
			title = "Others",
			options = {
				{ title = "Hi", func = function() end, }
			}
		} }
	}
}]]

local function RecursiveConstructMenu(menu, t, depth)

	for k, v in ipairs(t.options) do

		local submenu, op = nil
		if v.options then
			submenu, op = menu:AddSubMenu( v.title, v.func )
			RecursiveConstructMenu( submenu, v, depth + 1 )
		elseif not v.title then
			menu:AddSpacer()
		elseif not v.func then
			local panel = vgui.Create("DPanel")
			local label = vgui.Create("DLabel", panel)
			panel.Paint = function() end
			label:SetText(tostring(v.title))
			label:SetTextColor(Color(0,0,0,255))
			label:DockMargin(5,5,5,5)
			label:Dock(FILL)
			menu:AddPanel(panel)
		else
			op = menu:AddOption( v.title, v.func )
		end

		if op then
			if v.icon then op:SetIcon( v.icon ) end
			if v.desc then op:SetTooltip( v.desc ) end
		end

	end

end

function Menu(t, parent)

	local menu = DermaMenu( false, parent )
	RecursiveConstructMenu( menu, t, 0 )

	if t.width then
		menu:SetMinimumWidth(t.width)
	end

	menu:Open( t.x or gui.MouseX(), t.y or gui.MouseY(), false, parent )

	return menu

end

function String(t)

	local pnl = Derma_StringRequest(
		t.title or "WorldTools", 
		t.message or "WorldTools", 
		t.default or "", 
		t.confirm or function() end, 
		t.cancel or function() end,
		t.confirmText or "ok", 
		t.cancelText or "cancel")

	return pnl

end

function Query(t)

	local pnl = Derma_Query(
		t.message or "",
		t.title or "WorldTools",
		t.options[1] and t.options[1][1] or "Button",
		t.options[1] and t.options[1][2] or nil,
		t.options[2] and t.options[2][1] or nil,
		t.options[2] and t.options[2][2] or nil,
		t.options[3] and t.options[3][1] or nil,
		t.options[3] and t.options[3][2] or nil,
		t.options[4] and t.options[4][1] or nil,
		t.options[4] and t.options[4][2] or nil)

	return pnl

end

function Message(t)

	local pnl = Derma_Message(
		t.message or "WorldTools",
		t.title or "WorldTools",
		t.button or "ok")

	return pnl

end