AddCSLuaFile()

module("wt_iointeract", package.seeall)

local inMenu = false

function IsInMenu() return inMenu end

MSG_ENTITY_FIRE_INPUT = 0
MSG_ENTITY_FIRE_OUTPUT = 1
MSG_ENTITY_FIRE_OUTPUT_SPECIFIC = 2
MSG_BITS = 2

if SERVER then

	util.AddNetworkString("io_interact")

	net.Receive("io_interact", function(len, ply)

		local graph = wt_bsp.GetCurrent().iograph

		local cmd = net.ReadUInt(MSG_BITS)
		if cmd == MSG_ENTITY_FIRE_INPUT then

			local ent = net.ReadUInt(32)
			local event = wt_ionet.ReadIndexed()
			local param = net.ReadString()
			local node = graph:GetByIndex(ent)
			if param == "" then param = nil end
			if node ~= nil then
				node:Fire(event, ply, ply, 0, param)
			end

		elseif cmd == MSG_ENTITY_FIRE_OUTPUT then

			local ent = net.ReadUInt(32)
			local event = wt_ionet.ReadIndexed()
			local node = graph:GetByIndex(ent)
			if node ~= nil then
				node:FireOutput(event, ply, node:GetEntity() or ply)
			end

		elseif cmd == MSG_ENTITY_FIRE_OUTPUT_SPECIFIC then

			local hash = net.ReadData(20)
			local edge = graph:FindEdgeByHash(hash)
			edge:Fire()

		end

	end)

elseif CLIENT then

	--[[function CL_SendTraceInteractionToServer(key, trace)

		local mode = (key == IN_ATTACK) and 0 or 1
		local id = trace:GetIndex()
		net.Start("io_trace_interact")
		net.WriteUInt( mode, 1 )
		net.WriteUInt( id-1, 32 )
		net.SendToServer()

	end]]

	local function SendInputEvent(node, event, param)

		net.Start("io_interact")
		net.WriteUInt(MSG_ENTITY_FIRE_INPUT, MSG_BITS)
		net.WriteUInt(node:GetIndex(), 32)
		wt_ionet.WriteIndexed(event)
		net.WriteString(param or "")
		net.SendToServer()

	end

	local function SendOutputEvent(node, event)

		net.Start("io_interact")
		net.WriteUInt(MSG_ENTITY_FIRE_OUTPUT, MSG_BITS)
		net.WriteUInt(node:GetIndex(), 32)
		wt_ionet.WriteIndexed(event)
		net.SendToServer()

	end

	local function SendSpecificOutput(output)

		net.Start("io_interact")
		net.WriteUInt(MSG_ENTITY_FIRE_OUTPUT_SPECIFIC, MSG_BITS)
		net.WriteData(output:GetRawHash(), 20)
		net.SendToServer()

	end

	local function OpenNodeMenu(node)

		local fgd = wt_iocommon.GetFGDClass(node:GetClass())
		if fgd == nil then return end

		local input_options = {}
		local output_options = {}
		local io_table = wt_iocommon.CategorizedIO(fgd)

		for k,v in ipairs(io_table.inputs) do

			input_options[#input_options+1] = { title = v.class }
			for _,ev in ipairs(v.list) do

				local paramType = fgd.inputs[ev]

				if paramType == "void" then
					input_options[#input_options+1] = {
						title = ev,
						func = function() SendInputEvent(node, ev) end,
					}
				elseif paramType == "float" then
					local panel = vgui.Create("DPanel")
					local numeric = vgui.Create("DNumberScratch", panel)
					panel:SetSize(60,30)
					numeric:DockMargin(4,4,4,4)
					numeric:Dock(FILL)
					numeric:SetMax(1000)
					numeric:SetMin(0)
					input_options[#input_options+1] = {
						title = ev,
						func = function() SendInputEvent(node, ev, tostring( numeric:GetFloatValue() )) end,
						options = {
							{ panel = panel, },
						}
					}
				elseif paramType == "integer" then
					local panel = vgui.Create("DPanel")
					local numeric = vgui.Create("DNumberScratch", panel)
					panel:SetSize(60,30)
					numeric:DockMargin(4,4,4,4)
					numeric:Dock(FILL)
					numeric:SetMax(1000)
					numeric:SetMin(0)
					numeric:SetDecimals(0)
					input_options[#input_options+1] = {
						title = ev,
						func = function() SendInputEvent(node, ev, tostring( numeric:GetFloatValue() )) end,
						options = {
							{ panel = panel, },
						}
					}
				end
			end

		end

		for k,v in ipairs(io_table.outputs) do

			output_options[#output_options+1] = { title = v.class }
			for _,ev in ipairs(v.list) do

				local entry = { 
					title = ev,
					func = function() SendOutputEvent(node, ev) end,
				}

				local targets = {}
				for _, v in node:Outputs() do

					if v.event == ev then

						targets[#targets+1] = {
							title = v.to:GetName() .. "(" .. v.to:GetIndex() .. ")." .. v.func .. "(" .. tostring(v.param) .. ") @" .. (v.delay or 0) .. "s",
							func = function() SendSpecificOutput(v) end,
						}

					end

				end

				if #targets > 0 then
					entry.options = targets
					entry.width = 300
				end

				output_options[#output_options+1] = entry

			end

		end

		local t = {
			x = ScrW()/2,
			y = ScrH()/2,
			width = 200,
			options = {
				{ title = node:GetName() .. "<" .. node:GetClass() .. ">", },
				{ title = "Inputs", icon = "icon16/lightning_go.png", options = input_options },
				{ title = "Outputs", icon = "icon16/lorry_go.png", options = output_options }
			},
		}

		local menu = wt_modal.Menu(t)
		menu:SetKeyboardInputEnabled(true)
		menu:SetMouseInputEnabled(true)

	end

	function CL_InteractNode(world, node, key, pressed)
		local ply = LocalPlayer()

		if key == IN_ATTACK2 then
			ply:EmitSound( "buttons/button4.wav", 75, 170 )
			OpenNodeMenu(node)
			return true
		end

		ply:EmitSound( "buttons/button3.wav" )
		return true
	end

	function CL_InteractTrace(world, trace, key, pressed)
		local ply = LocalPlayer()
		ply:EmitSound( "buttons/button3.wav" )
		return true
	end

end