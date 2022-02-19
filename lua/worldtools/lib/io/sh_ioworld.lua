AddCSLuaFile()

G_IOWORLD_META = G_IOWORLD_META or {}

module( "wt_ioworld", package.seeall )

local meta = G_IOWORLD_META
meta.__index = meta

function meta:Init(iograph)

	self.traces = {}
	self.io_to_trace = {}
	self.trace_to_io = {}
	self.graph = iograph
	self:BuildTraces()

	return self

end

function meta:ShouldDrawEnt( ent )

	local inputs = ent:GetInputs()
	local outputs = ent:GetOutputs()
	--if #outputs == 0 and #inputs == 0 then return false end
	return true

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

	local test = wt_iotrace.G_IOTRACE_META.TestRay
	local ox, oy, oz = origin:Unpack()
	local dx, dy, dz = dir:Unpack()

	result = result or Vector()

	dx = 1/dx
	dy = 1/dy
	dz = 1/dz

	for _, trace in ipairs(self.traces) do

		local hit, toi, hitpoint = test(
			trace, 
			ox, oy, oz, 
			dx, dy, dz, 
			origin, dir, maxDist)

		if hit then

			if toi < t then
				t = toi
				pick = trace
				result:Set(dir)
				result:Mul(toi)
				result:Add(origin)
				point = hitpoint
			end

		end

	end

	return pick, result, point

end

function meta:BuildTraces()

	for ent in self.graph:Ents() do

		local inputs = ent:GetInputs()
		local outputs = ent:GetOutputs()
		if #outputs == 0 and #inputs == 0 then continue end

		local n = 0
		for _, output in ipairs(outputs) do

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

			self.traces[id] = trace
			self.traces[id].vertical = n
			self.io_to_trace[output] = self.traces[id]
			self.trace_to_io[trace] = output
			n = n + 2

		end

	end

end

function meta:AddBlipsFromIOEvent( ent, event )

	local outputs = ent:GetOutputs()
	if #outputs == 0 then return end

	for _, output in ipairs(outputs) do

		if output.event == event then

			local trace = self.io_to_trace[output]
			assert(trace)

			trace:AddBlip( tonumber(output.delay) )

		end

	end

end

if CLIENT then

	local blip_color = Color(255,180,50)
	local was_mouse_down = false
	local lasermat = Material("effects/laser1.vmt")
	local flaremat = Material("effects/blueflare1")

	local trace_draw = wt_iotrace.G_IOTRACE_META.Draw
	local trace_draw_flashes = wt_iotrace.G_IOTRACE_META.DrawFlashes
	local trace_draw_blips = wt_iotrace.G_IOTRACE_META.DrawBlips
	local vray_result = Vector()
	local cull_distance = 600

	function meta:DrawEntities()
		for ent in self.graph:Ents() do
			if self:ShouldDrawEnt( ent ) then
				ent:Draw()
			end
		end
	end

	function meta:Draw()

		local eye, forward = EyePos(), EyeAngles():Forward() 
		local tracesDrawn = 0

		local gc0 = collectgarbage( "count" )
		local t = SysTime()

		render.OverrideColorWriteEnable(true, false)
		render.SetMaterial( Material("metal2") )
		render.CullMode(MATERIAL_CULLMODE_CW)
		render.DrawSphere( eye, cull_distance, 50, 50, Color(0,255,255,255) )
		render.CullMode(MATERIAL_CULLMODE_CCW)
		render.OverrideColorWriteEnable(false, false)

		render.SetMaterial(lasermat)
		for k, trace in ipairs(self.traces) do
			trace_draw(trace, cull_distance)
		end

		-- Draw Entities

		render.ClearDepth()
		render.SetMaterial(lasermat)
		for k, trace in ipairs(self.traces) do
			trace_draw_flashes(trace, cull_distance)
		end

		render.SetMaterial(flaremat)
		for k, trace in ipairs(self.traces) do
			trace_draw_blips(trace)
		end

		--_G.G_GARBAGE = collectgarbage( "count" ) - gc0

		if LocalPlayer():GetActiveTrace() == nil then
			local hitTrace, pos, point = self:GetTraceForRay( eye, forward, vray_result, 300 )
			if hitTrace then
				local along = (pos - point.pos):Dot( point.normal )
				local v = point.pos + point.normal * along
				--print(t)
				render.SetMaterial(lasermat)
				hitTrace:Draw(cull_distance, Color(200,210,255), 15, point.along + along - 30, point.along + along + 30)
				--hitTrace:Draw( blip_color, 10, t - 30, t + 30 )

				--render.DrawLine(Vector(0,0,0), v)

				-- FIXME: Do this better
				if input.IsMouseDown(MOUSE_LEFT) then
					if not was_mouse_down then
						print("DO IT")
						--wt_ionet.RequestRideTrace( hitTrace, point.along + along )
						was_mouse_down = true
					end
				else
					was_mouse_down = false
				end

			end
		end

		--print("Draw[" .. _G.G_GARBAGE .. "] took " .. (SysTime() - t) * 1000 .. "ms")

	end

end

function New(...)

	return setmetatable({}, meta):Init(...)

end

if CLIENT then

	local viewEnable = CreateConVar(
		"wt_debug_ioview", "0", 
		{ FCVAR_CHEAT }, 
		"Toggle drawing the io view")

	local function ShouldDrawIOView()
		if viewEnable:GetBool() then return true end

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

	hook.Add("IOEventTriggered", "wt_ioworld", function(ent, event)

		local world = wt_bsp.GetCurrent().ioworld
		if world then world:AddBlipsFromIOEvent( ent, event ) end

	end)

	hook.Add("PostDrawTranslucentRenderables", "wt_ioworld", function()

		--[[if not ShouldDrawIOView() then return end

		if wt_bsp.GetCurrent() == nil then return end
		if wt_bsp.GetCurrent():IsLoading() then return end
		if space == nil then space = wt_bsp.GetCurrent().ioworld end

		space:Draw()]]

	end)

	hook.Add("PostDrawOpaqueRenderables", "wt_ioworld", function()

		--space:Draw()
		if not ShouldDrawIOView() then return end
		local world = wt_bsp.GetCurrent().ioworld
		if world then world:DrawEntities() end

	end)

	if wt_bsp and wt_bsp.GetCurrent() ~= nil then

		print("Create IO World")
		wt_bsp.GetCurrent().iograph = wt_iograph.New( wt_bsp.GetCurrent() )
		wt_bsp.GetCurrent().ioworld = New( wt_bsp.GetCurrent().iograph )

	end

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

	end)

end