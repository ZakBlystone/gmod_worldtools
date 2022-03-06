AddCSLuaFile()

module("wt_iointeract", package.seeall)

local inMenu = false

function IsInMenu() return inMenu end

MSG_ENTITY_FIRE_INPUT = 0
MSG_ENTITY_FIRE_OUTPUT = 1
MSG_ENTITY_FIRE_OUTPUT_SPECIFIC = 2
MSG_ENTITY_CANCEL_OUTPUT = 3
MSG_BITS = 2

if SERVER then

	util.AddNetworkString("io_interact")

	net.Receive("io_interact", function(len, ply)

		local world = wt_bsp.GetCurrent().ioworld
		local graph = wt_bsp.GetCurrent().iograph

		world:ManualOverride( true )

		local cmd = net.ReadUInt(MSG_BITS)
		if cmd == MSG_ENTITY_FIRE_INPUT then

			local ent = net.ReadUInt(32)
			local event = wt_ionet.ReadIndexed()
			local param = net.ReadString()
			local node = graph:GetByIndex(ent)
			if param == "" then param = nil end
			if node ~= nil then
				world:FireInput(node, event, ply, ply, 0, param)
			end

		elseif cmd == MSG_ENTITY_FIRE_OUTPUT then

			local ent = net.ReadUInt(32)
			local event = wt_ionet.ReadIndexed()
			local node = graph:GetByIndex(ent)
			if node ~= nil then
				world:FireOutput(node, event, ply, node:GetEntity() or ply)
			end

		elseif cmd == MSG_ENTITY_FIRE_OUTPUT_SPECIFIC then

			local hash = net.ReadData(20)
			local edge = graph:FindEdgeByHash(hash)
			local immediate = net.ReadBit() == 1
			if edge ~= nil then
				world:FireOutputEdge(edge, nil, nil, immediate and 0 or nil)
			end

		elseif cmd == MSG_ENTITY_CANCEL_OUTPUT then

			local hash = net.ReadData(20)
			local edge = graph:FindEdgeByHash(hash)
			if edge ~= nil then
				world:GetEventQueue():Cancel( edge.to, edge.func )
			end

		end

		-- Temporary solution, does not propegate through IO chains
		-- TODO: custom activator to indicate manual override
		-- need to replace multi_manager as it doesn't persist activator
		timer.Simple(0.1, function() world:ManualOverride( false ) end )

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

	local function SendSpecificOutput(output, immediate)

		net.Start("io_interact")
		net.WriteUInt(MSG_ENTITY_FIRE_OUTPUT_SPECIFIC, MSG_BITS)
		net.WriteData(output:GetRawHash(), 20)
		net.WriteBit(immediate or false)
		net.SendToServer()

	end

	local function SendCancelOutput(output)

		net.Start("io_interact")
		net.WriteUInt(MSG_ENTITY_CANCEL_OUTPUT, MSG_BITS)
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
			width = 250,
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

	local function OpenTraceMenu(world, trace)

		local edge = world:GetIOForTrace(trace)
		if edge == nil then return false end

		local function OpenNode(node)
			timer.Simple(0.1, function() OpenNodeMenu( node ) end)
		end

		local t = {
			x = ScrW()/2,
			y = ScrH()/2,
			width = 250,
			options = {
				{ title = "Cancel pending events", icon = "icon16/delete.png",  func = function() SendCancelOutput(edge) end, },
				{ title = "Execute", icon = "icon16/add.png", func = function() SendSpecificOutput(edge) end, },
				{ title = "Execute Immediately", icon = "icon16/resultset_next.png", func = function() SendSpecificOutput(edge, true) end, },
				{ title = "From: " .. edge.from:GetName(), icon = "icon16/arrow_right.png", func = function() OpenNode(edge.from) end, },
				{ title = "To: " .. edge.to:GetName(), icon = "icon16/arrow_down.png", func = function() OpenNode(edge.to) end, },
				{ title = ": " .. tostring(edge.func) .. "(" .. tostring(edge.param) .. ") @" .. (edge.delay or 0) .. " seconds" }
			},
		}

		local menu = wt_modal.Menu(t)
		menu:SetKeyboardInputEnabled(true)
		menu:SetMouseInputEnabled(true)

		return true

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

		if key == IN_ATTACK2 then
			if OpenTraceMenu(world, trace) then
				ply:EmitSound( "buttons/button4.wav", 75, 170 )
			else
				ply:EmitSound( "buttons/button3.wav" )
			end
			return true
		elseif key == IN_ATTACK then
			local edge = world:GetIOForTrace(trace)
			if edge == nil then return false end
			SendSpecificOutput(edge)
			ply:EmitSound( "buttons/button3.wav" )
			return true
		end

		return false
	end

end