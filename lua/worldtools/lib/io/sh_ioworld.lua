AddCSLuaFile()

G_IOWORLD_META = G_IOWORLD_META or {}

module( "wt_ioworld", package.seeall )

local meta = G_IOWORLD_META
meta.__index = meta

function meta:Init(iograph)

	self.traces = {}
	self.io_to_trace = {}
	self.trace_to_io = {}
	self.should_draw_trace_index = {}
	self.graph = iograph
	self.blips = {}
	self:BuildTraces()

	return self

end

function meta:InteractTrace( ply, mode, trace, along )

	if mode == 0 then
		print(mode)

		local output = self:GetIOForTrace( trace )
		output:Fire(ply, ply, 0)

	end

end

function meta:GetTraceByIndex( index )

	return self.traces[index]

end

function meta:GetIOForTrace( trace )

	return self.trace_to_io[trace]

end

function meta:GetTraceForRay( origin, dir, result, maxDist )

	maxDist = maxDist or math.huge

	local t = maxDist
	local pick = nil
	local point = nil
	local hit_x = nil
	local hit_y = nil

	local test = wt_iotrace.G_IOTRACE_META.TestRay
	local ox, oy, oz = origin:Unpack()
	local dx, dy, dz = dir:Unpack()

	result = result or Vector()

	dx = 1/dx
	dy = 1/dy
	dz = 1/dz

	for _, trace in ipairs(self.traces) do

		local hit, toi, hitpoint, x, y = test(
			trace, 
			ox, oy, oz, 
			dx, dy, dz, 
			origin, dir, maxDist)

		if hit then

			if hit_y then
				local d0 = math.abs(y)
				local d1 = math.abs(hit_y)
				if d0 > d1 then continue end
			end

			t = toi
			pick = trace
			result:Set(dir)
			result:Mul(toi)
			result:Add(origin)
			point = hitpoint
			hit_x = x
			hit_y = y

		end

	end

	return pick, result, point, hit_x, hit_y

end

function meta:BuildTraces()

	for ent in self.graph:Nodes() do

		local n = 0
		for k, output in ent:Outputs() do

			local id = #self.traces+1
			local startPos = ent:GetPos() + Vector(0,0,n)
			local endPos = output.to:GetPos()
			local trace = wt_iotrace.New( startPos, endPos, id )

			ent.onMoved["traceUpdate" .. id] = function()
				self.traces[id]:Update(
					ent:GetPos() + Vector(0,0,self.traces[id].vertical), 
					output.to:GetPos()
				)
			end

			output.to.onMoved["traceUpdate" .. id] = function()
				self.traces[id]:Update(
					ent:GetPos() + Vector(0,0,self.traces[id].vertical), 
					output.to:GetPos()
				)
			end

			trace:BuildPath()
			trace.id = id

			self.traces[id] = trace
			self.traces[id].vertical = n
			self.io_to_trace[output] = self.traces[id]
			self.trace_to_io[trace] = output
			n = n + 2

		end

	end

end


if CLIENT then

	local blip_color = Color(255,180,50)
	local highlighted_color = Color(255,255,255)
	local trace_color_dead = Color(180,20,20,255)
	local was_mouse_down = false
	local lasermat = Material("effects/laser1.vmt")
	local flaremat = Material("effects/blueflare1")
	local spheremat = Material("metal2")
	local spherecolor = Color(0,255,255,255)

	local trace_draw = wt_iotrace.G_IOTRACE_META.Draw
	local trace_draw_flash = wt_iotrace.G_IOTRACE_META.DrawFlash
	local trace_draw_blip = wt_iotrace.G_IOTRACE_META.DrawBlip
	local trace_should_draw = wt_iotrace.G_IOTRACE_META.ShouldDraw
	local vray_result = Vector()
	local cull_distance = 600
	local MIN_DELAY = 0.5

	function meta:UpdateBlips()

		--self.blips = {}
		local time = CurTime()

		for i=#self.blips, 1, -1 do

			local blip = self.blips[i]
			local t = time - blip.time
			if t > blip.duration + MIN_DELAY then

				table.remove(self.blips, i) 
				continue

			end

		end

	end

	function meta:UpdateEntities()


		self:UpdateBlips()

		local traces = self.traces
		_G.G_EYE_POS = EyePos()
		_G.G_EYE_X = _G.G_EYE_POS.x
		_G.G_EYE_Y = _G.G_EYE_POS.y
		_G.G_EYE_Z = _G.G_EYE_POS.z

		local t = SysTime()

		local num = 0
		for ent in self.graph:Nodes() do
			ent:Update()
			num = num + 1
		end

		--print("Update Entities[" .. num .. "] took " .. (SysTime() - t) * 1000 .. "ms")

		self.should_draw_trace_index = {}
		for i=1, #traces do
			self.should_draw_trace_index[i] = trace_should_draw(traces[i], cull_distance)
		end

	end

	function meta:AddBlipFromEdge( edge, time )

		time = time or CurTime()

		local trace = self.io_to_trace[edge]
		assert(trace)

		self.blips[#self.blips+1] = {
			time = time,
			duration = tonumber(edge:GetDelay()),
			trace_id = trace.id,
		}

	end

	function meta:Draw()

		local eye, forward = EyePos(), EyeAngles():Forward() 
		local tracesDrawn = 0
		local time = CurTime()
		local ply = LocalPlayer()
		local look_at_trace = ply.look_at_trace
		local look_at_ent = ply.look_at_ent
		local should_draw_trace_index = self.should_draw_trace_index
		local traces = self.traces
		local num_traces = #traces
		local num_drawn = 0


		render.OverrideColorWriteEnable(true, false)
		render.SetMaterial( spheremat )
		render.CullMode(MATERIAL_CULLMODE_CW)
		render.DrawSphere( eye, cull_distance, 50, 50, spherecolor )
		render.CullMode(MATERIAL_CULLMODE_CCW)
		render.OverrideColorWriteEnable(false, false)

		render.SetMaterial(lasermat)

		local t = SysTime()

		for i=1, num_traces do
			if not should_draw_trace_index[i] then continue end

			local col = nil
			local trace = traces[i]

			if trace == look_at_trace then col = highlighted_color end

			local event = self.trace_to_io[trace]
			if not event then col = trace_color_dead end
			if not event.from.existsOnServerCached then col = trace_color_dead end
			if not event.to.existsOnServerCached then col = trace_color_dead end

			if trace_draw(trace, cull_distance, col) then
				num_drawn = num_drawn + 1
			end
		end

		-- Draw Entities

		render.ClearDepth()

		if look_at_ent ~= nil then
			look_at_ent:Draw()
		end

		if look_at_trace ~= nil then
			local event = self.trace_to_io[look_at_trace]
			if event ~= nil then
				event.from:Draw()
				event.to:Draw()
			end
		end

		render.SetMaterial(lasermat)
		for _, blip in ipairs(self.blips) do
			trace_draw_flash(traces[blip.trace_id], cull_distance, blip, time)
		end

		render.SetMaterial(flaremat)
		for _, blip in ipairs(self.blips) do
			trace_draw_blip(traces[blip.trace_id], blip, time)
		end

		--print("Draw[" .. num_drawn .. "] took " .. (SysTime() - t) * 1000 .. "ms")

		ply.look_at_trace = nil
		ply.look_at_ent = nil



		if ply:GetActiveTrace() == nil then

			local hitEnt, hitPos = self.graph:VisualTrace(eye, forward, 0, 5000)
			if hitEnt then

				ply.look_at_ent = hitEnt
				ply.look_at_pos = hitPos

			else

				local hitTrace, pos, point = self:GetTraceForRay( eye, forward, vray_result, cull_distance )
				if hitTrace then
					
					local along = (pos - point.pos):Dot( point.normal )
					local v = point.pos + point.normal * along
					--print(t)
					ply.look_at_trace = hitTrace
					ply.look_at_along = along
					render.SetMaterial(lasermat)
					hitTrace:Draw(cull_distance, Color(200,210,255), 15, point.along + along - 30, point.along + along + 30)
					--hitTrace:Draw( blip_color, 10, t - 30, t + 30 )

					--render.DrawLine(Vector(0,0,0), v)
				end

			end
		end

	end

end

function New(...)

	return setmetatable({}, meta):Init(...)

end

if wt_bsp and wt_bsp.GetCurrent() ~= nil then

	print("Create IO World")
	wt_bsp.GetCurrent().iograph = wt_iograph.New( wt_bsp.GetCurrent() )
	wt_bsp.GetCurrent().ioworld = New( wt_bsp.GetCurrent().iograph )

end

if CLIENT then

	local viewEnable = CreateConVar(
		"wt_debug_ioview", "0", 
		{ FCVAR_CHEAT }, 
		"Toggle drawing the io view")

	function ShouldDrawIOView()
		if viewEnable:GetBool() then return true end

		local weapon = LocalPlayer():GetActiveWeapon()
		if IsValid(weapon) and weapon:GetClass() == "weapon_iotool" then
			return true
		end

		return false
	end

	local blip_color = Color(255,180,50)
	local io_vision = CreateMaterial("IOVision" .. FrameNumber(), "UnLitGeneric", {
		["$basetexture"] = "concrete/concretefloor001a",
		["$vertexcolor"] = 1,
		["$vertexalpha"] = 1,
		["$model"] = 0,
		["$additive"] = 1,
	})

	local io_vision_noadd = CreateMaterial("IOVisionBlur" .. FrameNumber(), "UnLitGeneric", {
		["$basetexture"] = "concrete/concretefloor001a",
		["$vertexcolor"] = 1,
		["$vertexalpha"] = 1,
		["$model"] = 0,
		["$additive"] = 0,
	})

	--[[hook.Add("IOEventTriggered", "wt_ioworld", function(ent, event)

		local world = wt_bsp.GetCurrent().ioworld
		if world then world:AddBlipsFromIOEvent( ent, event ) end

	end)]]

	hook.Add("PreRender", "wt_ioworld", function()

		if not ShouldDrawIOView() then return end
		local world = wt_bsp.GetCurrent().ioworld
		if world then world:UpdateEntities() end

	end)

	local invert_color_mod = {
		[ "$pp_colour_addr" ] = -1,
		[ "$pp_colour_addg" ] = -1,
		[ "$pp_colour_addb" ] = -1,
		[ "$pp_colour_brightness" ] = 0,
		[ "$pp_colour_contrast" ] = -1,
		[ "$pp_colour_colour" ] = 0,
		[ "$pp_colour_mulr" ] = 0,
		[ "$pp_colour_mulg" ] = 0,
		[ "$pp_colour_mulb" ] = 0
	}

	local function DrawEntInfo(ent, world)

		local zone = wt_textfx.Box(ScrW()/2, ScrH()/2, 100, 100)
			:Pad(-10)

		local title = wt_textfx.Builder(ent:GetName() .. " : " .. ent:GetClass(), "WTStatusFont")
		:Box()
		:HAlignTo(zone, "left")
		:VAlignTo(zone, "top")

		local frame = wt_textfx.BuilderBox(title)
		:Pad(8)
		frame:DrawRounded(0,0,0,120,8)

		title:Draw()

	end

	local function DrawTraceInfo(trace, world)

		local output = world.trace_to_io[trace]
		if output then

			local zone = wt_textfx.Box(ScrW()/2, ScrH()/2, 100, 100)
				:Pad(-10)

			local title = wt_textfx.Builder(output.from:GetName() .. " : " .. output.from:GetClass(), "WTStatusFont")
			:Box()
			:HAlignTo(zone, "left")
			:VAlignTo(zone, "top")

			local from = wt_textfx.Builder(output.event, "WTStatusFontSmall")
			:Box()
			:HAlignTo(title, "left")
			:VAlignTo(title, "after")

			local to = wt_textfx.Builder(output.to:GetName() .. "." .. output.func .. "(" .. tostring(output.param) .. ")", "WTStatusFontSmall")
			:Box()
			:HAlignTo(from, "left")
			:VAlignTo(from, "after")

			local delay = wt_textfx.Builder("@" .. tostring(output:GetDelay()) .. "s", "WTStatusFontSmall")
			:Box()
			:HAlignTo(to, "left")
			:VAlignTo(to, "after")

			local frame = wt_textfx.BuilderBox(title, from, to, delay)
			:Pad(8)
			frame:DrawRounded(0,0,0,120,8)

			title:Draw()
			from:Draw()
			to:Draw()
			delay:Draw()

		end

	end

	hook.Add( "KeyPress", "wt_interact_keypress", function( ply, key )

		if not ShouldDrawIOView() then return end
		if not IsFirstTimePredicted() and not game.SinglePlayer() then return end
		if wt_iointeract.IsInMenu() then return end

		local world = wt_bsp.GetCurrent().ioworld

		if key == IN_ATTACK or key == IN_ATTACK2 then

			local node = LocalPlayer().look_at_ent
			if node ~= nil then
				if wt_iointeract.CL_InteractNode(world, node, key, true) then return end
			end

			local trace = LocalPlayer().look_at_trace
			if trace ~= nil then
				if wt_iointeract.CL_InteractTrace(world, node, key, true) then return end
			end

			ply:EmitSound( "Weapon_Pistol.Empty" )

		end

	end )
	
	hook.Add("HUDPaint", "wt_ioworld", function()

		--if true then return end
		if not ShouldDrawIOView() then return end

		if wt_bsp.GetCurrent() == nil then print("NO BSP") return end
		if wt_bsp.GetCurrent():IsLoading() then return end
		local world = wt_bsp.GetCurrent().ioworld
		if world == nil then return end

		local w = ScrW()
		local h = ScrH()

		local rt = wt_irt.New("io_vision", w, h)
			:EnableDepth(true,true)
			:EnableFullscreen(false)
			:EnablePointSample(true)
			:SetAlphaBits(8)

		local rtdark = wt_irt.New("io_vision2", w, h)
			:EnableDepth(true,true)
			:EnableFullscreen(false)
			:EnablePointSample(true)
			:SetAlphaBits(8)

		io_vision:SetTexture("$basetexture", rt:GetTarget())
		io_vision_noadd:SetTexture("$basetexture", rtdark:GetTarget())

		render.PushRenderTarget(rtdark:GetTarget())
		render.Clear( 0, 0, 0, 0, true, true )
		render.PopRenderTarget()

		render.PushRenderTarget(rt:GetTarget())
		render.Clear( 0, 0, 0, 0, true, true ) --60

		cam.Start(
			{
				x = 0,
				y = 0,
				w = w,
				h = h,
			})

			--render.SetMaterial( lasermat );

			local b,e = pcall( function()

				_G.G_EYE_POS = EyePos()
				_G.G_EYE_X = _G.G_EYE_POS.x
				_G.G_EYE_Y = _G.G_EYE_POS.y
				_G.G_EYE_Z = _G.G_EYE_POS.z
				world:Draw()

			end)
			if not b then print( e ) end

		cam.End()
		render.PopRenderTarget()

		-- Generate an RT of dark soft outline around lines
		render.PushRenderTarget(rtdark:GetTarget())
			cam.Start2D()
				render.SetMaterial(io_vision)
				for i=1,5 do
					render.DrawScreenQuad()
				end

			cam.End2D()

			render.BlurRenderTarget(rtdark:GetTarget(), 4, 4, 2)	
			DrawColorModify( invert_color_mod )
		render.PopRenderTarget()


		cam.Start2D()

		--surface.SetDrawColor(0,0,0,230)
		--surface.DrawRect(0,0,ScrW(),ScrH())

		-- Render the soft outline to keep visibility with light backgrounds
		surface.SetDrawColor(255,255,255)
		render.OverrideBlend(true, BLEND_ONE_MINUS_SRC_ALPHA,BLEND_DST_COLOR,BLENDFUNC_MIN)
		render.SetMaterial(io_vision_noadd)
		render.DrawScreenQuad()
		render.OverrideBlend(false)

		surface.SetDrawColor(255,255,255,255)
		render.SetMaterial(io_vision)
		render.DrawScreenQuad()

		surface.SetDrawColor(blip_color)
		surface.DrawRect( ScrW()/2 - 5, ScrH()/2 - 1, 10,2 )
		surface.DrawRect( ScrW()/2 - 1, ScrH()/2 - 5, 2,10 )

		cam.End2D()

		local trace = LocalPlayer().look_at_trace
		if trace ~= nil then
			DrawTraceInfo(trace, world)
		end

		local ent = LocalPlayer().look_at_ent
		if ent ~= nil then
			DrawEntInfo(ent, world)
		end

	end)

end