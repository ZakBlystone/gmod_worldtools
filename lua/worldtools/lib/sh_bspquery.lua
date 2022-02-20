AddCSLuaFile()

module( "wt_bsp", package.seeall )

local map = wt_bsp.GetCurrent()
local vmeta = FindMetaTable("Vector")
local vdot = vmeta.Dot
local band = bit.band
local bor = bit.bor

local function findBrushSide( leaf, pos )

	for k, brush in ipairs( leaf.brushes ) do

		if band( brush.contents, leaf.contents ) == 0 then continue end

		local inside = true
		local bside = nil
		local g = -9999
		for _, side in ipairs( brush.sides ) do

			local pln = side.plane.back
			local d = vdot( pos, pln.normal ) - pln.dist
			if d > 0.01 then inside = false end
			if d > g then bside = side g = d end

		end
		if inside then return bside, brush end

	end

	return nil

end

local function traceBrushSides( brush, tw )

	local first = 0
	local last = 999999
	local testside = nil

	for _, side in ipairs( brush.sides ) do

		local pln = side.plane.back
		local denom = vdot( tw.dir, pln.normal )
		local dist = pln.dist - vdot( pln.normal, tw.pos )

		if denom ~= 0.0 then

			local t = dist / denom

			if denom < 0 then
				if t > first then
					testside = side
					first = t
				end
			elseif t < last then
				last = t
			end

		end

		if first > last then return nil end

	end

	return testside, first

end

local function traceBrushes( leaf, tw )

	local bbrush = nil
	local bside = nil

	for _, brush in ipairs( leaf.brushes ) do

		if bor( brush.contents, tw.mask ) ~= tw.mask then continue end --CONTENTS_DETAIL
		if band( brush.contents, CONTENTS_DETAIL ) == 0 then continue end

		local side, t = traceBrushSides( brush, tw )
		if side then

			if t < tw.tmax then
				tw.tmax = t
				tw.tmin = t
				bside = side
				bbrush = brush
			end

		end
	end

	return bside, bbrush

end

local leafStack = {}
local leafStackNum = 0
for i=1, 100 do leafStack[i] = {} end
function traceNode( node, tw )

	if node == nil then return end
	local pos = tw.ipos or tw.pos
	local dir = tw.idir or tw.dir
	local steps = 0

	leafStackNum = 0
	tw.t = tw.tmax

	local out = 999
	while out > 0 do
		out = out - 1

		steps = steps + 1
		tw.Steps = steps

		if not node.is_leaf then

			local pln = node.plane
			local denom = vdot( dir, pln.normal )
			local dist = pln.dist - vdot( pln.normal, pos )
			local near = dist <= 0

			if denom ~= 0.0 then

				local t = dist / denom
				if 0 <= t and t <= tw.tmax then

					if t >= tw.tmin then

						leafStackNum = leafStackNum + 1
						local st = leafStack[leafStackNum]
						if not st then
							st = {}
							leafStack[leafStackNum] = st
						end
						st.node = node.children[ near and 2 or 1 ]
						st.tmax = tw.tmax
						tw.tmax = t

					else

						near = not near

					end

				end

			end

			node = node.children[ near and 1 or 2 ]

		else

			if node.has_detail_brushes then

				local side, brush = traceBrushes( node, tw )

				if side then
					tw.hit = true
					tw.leaf = node
					tw.t = tw.tmin
					tw.Hit = true
					tw.HitPos = Vector(dir) --pos + dir * tw.t
					tw.HitPos:Mul(tw.t)
					tw.HitPos:Add(pos)
					tw.HitWorld = true
					tw.Brush = brush
					tw.Side = side
					tw.IsDetail = true
				end

			end

			if not tw.hit and band( node.contents, tw.mask ) ~= 0 then

				tw.hit = true
				tw.leaf = node
				tw.t = tw.tmin
				tw.Hit = true
				tw.HitPos = Vector(dir) --pos + dir * tw.t
				tw.HitPos:Mul(tw.t)
				tw.HitPos:Add(pos)

				tw.HitNormal = Vector(0,0,1)
				tw.HitWorld = not tw.Entity

				tw.Side, tw.Brush = findBrushSide( node, tw.HitPos )

			end

			if tw.hit == true then

				if tw.Side then
					tw.HitNormal = Vector(tw.Side.plane.back.normal)
					tw.TexInfo = tw.Side.texinfo
					tw.Contents = tw.Brush.contents
				end

				return tw

			end


			if leafStackNum == 0 then return tw end
			local top = leafStack[leafStackNum]
			leafStackNum = leafStackNum - 1

			tw.tmin = tw.tmax
			node = top.node
			tw.tmax = top.tmax

		end

	end

	return tw

end

local function buildFilterMap(filter, dest)
	table.Empty(dest)
	if not filter then return end

	for k, v in pairs(filter) do
		dest[v] = v
	end
end

local filterMap = {}
local meta = getmetatable( map )
local trmtx = Matrix()
local iposvec = Vector()
local idirvec = Vector()
local identVector = Vector()
local identAngle = Angle()
function meta:Trace( tdata)
	local _tmin, _tmax = tdata.tmin, tdata.tmax
	local tdatacopy = table.Copy(tdata)

	traceNode( self.models[1].headnode, tdata )

	if not tdata.ignoreents then
		for k,v in pairs( self.entities ) do
			if tdata.filter and tdata.filter[v.classname] then continue end

			if v.bmodel then
				local pos = v.origin
				local ang = v.angles
				local real = ents.GetMapCreatedEntity(v.index+1234)
				if IsValid(real) then
					pos = real:GetPos()
					ang = real:GetAngles()
				end

				local d = tdatacopy
				d.tmin = _tmin
				d.tmax = _tmax
				d.hit = false

				d.Entity = v
				d.ipos = iposvec
				d.idir = idirvec

				trmtx:SetTranslation( pos or identVector )
				trmtx:SetAngles( ang or identAngle )
				trmtx:Invert()
				trmtx:Transform3( d.pos, 1, d.ipos )
				trmtx:Transform3( d.dir, 0, d.idir )

				traceNode( v.bmodel.headnode, d )

				if d.hit then
					trmtx:Invert()
					trmtx:Transform3( d.HitPos, 1, d.HitPos )
					trmtx:Transform3( d.HitNormal, 0, d.HitNormal )
				end

				if tdata.t >= d.t then
					tdata.HitPos = d.HitPos
					tdata.HitNormal = d.HitNormal
					tdata.t = d.t
					tdata.TexInfo = d.TexInfo
					tdata.Contents = d.Contents
					tdata.Brush = d.Brush
					tdata.Side = d.Side
					tdata.IsDetail = d.IsDetail
					tdata.Entity = d.Entity
					tdata.HitWorld = d.HitWorld
					tdata.Steps = (tdata.Steps or 0) + d.Steps
				end

			end
		end
	end

	return tdata
end


if SERVER then return end


local function drawFace( face )

	local winding = wt_poly.Winding()
	for i=1, #face.edges do

		winding:Add( face.edges[i][1] )

	end
	winding:Move( face.plane.normal )
	winding:Render()

end

local function drawBrush( brush, mtx )

	if mtx then cam.PushModelMatrix(mtx) end

	brush:Render()

	if mtx then cam.PopModelMatrix() end

end

local function drawLeaf( leaf, mtx )

	if mtx then cam.PushModelMatrix(mtx) end

	for k,v in pairs( leaf.brushes ) do
		drawBrush( v )
	end

	if mtx then cam.PopModelMatrix() end

end

local function drawModel( model )

	for k,v in pairs( model.faces ) do
		drawFace( v )
	end

end

local convar_run_test = CreateClientConVar("debug_bspquery", "0", false, false, "Toggle on screen debugging of the bsp query module.")

local trace_res = nil
hook.Add( "HUDPaint", "dbgquery", function()
	if not convar_run_test:GetBool() then return end

	if map:IsLoading() then return end

	if trace_res and trace_res.Hit then

		if not map.entities[1].index then
			for k, ent in pairs( map.entities ) do
				ent.index = k
			end
		end


		local ent = trace_res.Entity
		local d = tostring( ( "%0.1f"):format( trace_res.t ) )
		d = ent and ( ( ent.targetname and ent.targetname .. "<" .. ent.classname .. ">" ) or ent.classname ) .. " [" .. d .. ", " .. ent.index .. " ]" or d
		d = trace_res.IsDetail and "detail [" .. d .. "]" or d

		local inf = trace_res.TexInfo
		local d2 = inf and (inf.texdata.material .. " [" .. inf.texdata.width .. "x" .. inf.texdata.height .. "]" ) or "<no texture data>"

		if not trace_res.Side then
			d2 = "<no side>"
		end

		surface.SetFont("DermaLarge")

		local w = math.max( surface.GetTextSize(d), surface.GetTextSize(d2) ) + 10
		draw.RoundedBox( 8, ScrW()/2 - w/2, ScrH()/2 + 20, w, 110, Color(0,0,0,220) )

		draw.SimpleText(d, "DermaLarge", ScrW()/2, ScrH()/2 + 30, Color(80,255,255), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP )
		draw.SimpleText(d2, "DermaLarge", ScrW()/2, ScrH()/2 + 60, Color(80,255,255), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP )
		draw.SimpleText(trace_res.Steps .. " iterations", "DermaLarge", ScrW()/2, ScrH()/2 + 90, Color(80,255,255), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP )

	end

end )

hook.Add( "PostDrawOpaqueRenderables", "dbgquery", function( bdepth, bsky )
	--if not cvardebug:GetBool() then return end
	--if bsky then return end

	--drawFace( face )

	--drawBrush( map.brushes[6] )

	if not convar_run_test:GetBool() then return end
	if map:IsLoading() then return end

	--if true then return end

	local mask = bor( MASK_SOLID, CONTENTS_DETAIL )
	mask = bor( mask, CONTENTS_GRATE )
	mask = bor( mask, CONTENTS_TRANSLUCENT )
	--mask = bit.bor( mask, CONTENTS_PLAYERCLIP )
	--mask = bit.bor( mask, CONTENTS_MONSTERCLIP )

	local begin = SysTime()

	local res = map:Trace({
		pos = LocalPlayer():EyePos(),
		dir = LocalPlayer():EyeAngles():Forward(),
		tmin = 0,
		tmax = 10000,
		mask = mask,
		--ignoreents = true,
	} )

	print("TRACE TOOK: " .. (SysTime() - begin) * 1000 .. "ms" )


	if res then

		--print( res.t or 0 )

		if res.Hit then

			gfx.renderAngle( res.HitPos, res.HitNormal:Angle() )

			if not res.Brush then
				drawLeaf( res.leaf, res.mtx )
			else
				drawBrush( res.Brush, res.mtx  )
			end

		end

	end
	trace_res = res

end )