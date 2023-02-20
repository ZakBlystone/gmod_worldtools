AddCSLuaFile()

module( "wt_bsp", package.seeall )

AddCSLuaFile("bsp3.lua")
include("bsp3.lua")

LUMPS_DEFAULT_SERVER = {
	bsp3.LUMP_ENTITIES,				--All in-map entities
}

LUMPS_DEFAULT_CLIENT =
{
	bsp3.LUMP_ENTITIES,
	bsp3.LUMP_PLANES,				--Plane equations for map geometry
	bsp3.LUMP_BRUSHES,				--Brushes
	bsp3.LUMP_BRUSHSIDES,			--Sides of brushes
	--bsp3.LUMP_GAME_LUMP,				--Static props and detail props
	bsp3.LUMP_NODES,					--Spatial partitioning nodes
	bsp3.LUMP_LEAFS,					--Spatial partitioning leafs
	bsp3.LUMP_MODELS,				--Brush models (trigger_* / func_*)
	bsp3.LUMP_LEAFBRUSHES,			--Indexing between leafs and brushes
	bsp3.LUMP_TEXDATA,				--Texture data (width / height / name)
	--bsp3.LUMP_TEXDATA_STRING_DATA,	--Names of textures
	bsp3.LUMP_TEXINFO,				--Surface texture info
	--bsp3.LUMP_VERTEXES,			--All vertices that make up map geometry
	--bsp3.LUMP_EDGES,				--Edges between vertices in map geometry
	--bsp3.LUMP_SURFEDGES,			--Indexing between vertices
	--bsp3.LUMP_FACES,				--Poligonal faces
	--bsp3.LUMP_ORIGINALFACES,		--Original poligonal faces before BSP splitting
	--bsp3.LUMP_LEAFFACES,			--Indexing between leafs and faces
	bsp3.LUMP_WORLDLIGHTS,			--Extended information for light_* entities
	bsp3.LUMP_CUBEMAPS,				--env_cubemap locations and sizes
}

local function CreateBrushes( data )

	local bmeta = wt_brush.GetBrushMetatable()
	local smeta = wt_brush.GetSideMetatable()
	local blib = wt_brush
	for k, brush in pairs( ( data[bsp3.LUMP_BRUSHSIDES] and data[bsp3.LUMP_BRUSHES] ) or {} ) do

		setmetatable(brush, bmeta)
		brush:Init()

		for i = brush.firstside+1, brush.firstside + brush.numsides do
			local side = data[bsp3.LUMP_BRUSHSIDES][i]
			setmetatable(side, smeta)
			side:Init()
			side.plane = side.plane.back
			side.bevel = side.bevel != 0
			brush:Add( side )
			task.YieldPer(5000, "progress")
		end

	end

end

local function ConvertEntities( data )

	local function ProcessKeyValue(t, k, v)

		if k == "origin" then
			local x,y,z = string.match( tostring(v), "([%+%-]?%d*%.?%d+) ([%+%-]?%d*%.?%d+) ([%+%-]?%d*%.?%d+)" )
			if x and y and z then
				return Vector(x,y,z)
			else
				print("FAILED TO PARSE: " .. tostring(v))
				return Vector()
			end
		end
		if k == "angles" then
			local x,y,z = string.match( tostring(v), "([%+%-]?%d*%.?%d+) ([%+%-]?%d*%.?%d+) ([%+%-]?%d*%.?%d+)" )
			return Angle(x,y,z)
		end
		if k == "model" then
			if v[1] == "*" and data.models ~= nil then
				local index = string.match( v, "(%d+)")
				local model = data.models[ index+1 ]
				if model then
					t.bmodel = model
				end
			end
		end
		if k == "classname" then
			wt_task.Yield("sub", tostring(v))
		end
		if t.classname then
			local fgd = wt_iocommon.GetFGDClass(t.classname)
			if fgd and fgd.outputs[k] then
				t.outputs = t.outputs or {}
				local parsed = wt_iocommon.ProcessOutput(k, v)
				if parsed then t.outputs[#t.outputs+1] = parsed end
				return nil
			end
		end
		return v

	end

	for k, ent in pairs( ( data[bsp3.LUMP_ENTITIES] and data[bsp3.LUMP_ENTITIES] ) or {} ) do

		for _, kv in ipairs(ent) do

			ent[kv.key] = ProcessKeyValue( ent, kv.key, kv.value )

		end

		ent.index = ent.id

	end

end

local function CreateIOGraph( data )

	if CLIENT then wt_ioindexing.RequestIDs() end
	data.iograph = wt_iograph.New(data)
	data.ioworld = wt_ioworld.New(data.iograph)

end

local meta = {}

function meta:IsLoading() return false end
function meta:GetLoadTask() return nil end

function meta:GetLeaf( pos, node )

	node = node or self.models[1].headnode
	if node.is_leaf then return node end

	local d = node.plane.normal:Dot( pos ) - node.plane.dist
	return self:GetLeaf( pos, node.children[d > 0 and 1 or 2] )

end

local check_nop = function() return true end
function meta:GetBoxLeafs( list, mins, maxs, expand, check, node )

	check = check or check_nop
	node = node or self.models[1].headnode
	if node.is_leaf then
		if check( node ) then
			list[#list+1] = node
		end
		return
	end

	local test = TestBoxPlane( node.plane, mins, maxs, expand )

	if test == 0 then
		self:GetBoxLeafs( list, mins, maxs, expand, check, node.children[1] )
		self:GetBoxLeafs( list, mins, maxs, expand, check, node.children[2] )
	else
		self:GetBoxLeafs( list, mins, maxs, expand, check, node.children[test == -1 and 2 or 1] )
	end

end

function meta:GetAdjacentLeafs( leaf, list, check )

	self:GetBoxLeafs( list, leaf.mins, leaf.maxs, 10, function(l)
		if l == leaf then return false end
		if check and not check(l) then return false end
		return true
	end )

end

function meta:AreLeafsConnected(a, b, check, visited)

	if check and not check(a) then return false end
	if a == b then return true end

	visited = visited or {}
	visited[a] = true

	local connection = false
	local adjacent = {}
	self:GetAdjacentLeafs( a, adjacent, check )
	for _, l in pairs( adjacent ) do
		if l == b then return true end
	end

	for _, l in pairs( adjacent ) do
		if l == a then continue end

		if not visited[l] then
			connection = connection or self:AreLeafsConnected(l, b, check, visited)
		end
	end

	return connection

end

table.Merge( bsp3.GetMetaTable(), meta )

BLOCK_THREAD = 0x1234ABCD

function LoadBSP( filename, path, requested_lumps )

	local data = bsp3.LoadBSP( "maps/" .. filename .. ".bsp", requested_lumps, path )
	if not data then return end

	CreateBrushes(data)
	ConvertEntities(data)
	CreateIOGraph(data)

	return data

end

--if true then return end

function Init()

	local init_time = SysTime()

	if CLIENT then WT_LOADED_BSP = nil end
	if SERVER then WT_LOADED_BSP = nil end
	if WT_LOADED_BSP == nil then
		if SERVER then
			--LoadBSP(game.GetMap())
			print("SERVER LOADING BSP...")
		else
			print("CLIENT LOADING BSP...")
		end

		if CLIENT then wt_statusui.SetLoading(true) end

		WT_LOADED_BSP = LoadBSP( game.GetMap(), nil, SERVER and LUMPS_DEFAULT_SERVER or LUMPS_DEFAULT_CLIENT)

		if SERVER then

			print("SERVER FINISHED LOADING BSP")
			print( PrintTable( WT_LOADED_BSP.entities[1] ) )
			hook.Call( "wt_bsp_ready" )

		else

			hook.Call( "wt_bsp_ready" )
			print("CLIENT FINISHED LOADING BSP")
			print( PrintTable( WT_LOADED_BSP.entities[1] ) )

			wt_statusui.SetMainText( "LOADING BSP : COMPLETE")
			wt_statusui.SetSubText( "" )
			wt_statusui.SetLoading( false )

		end

	end

	print("bsp Init took: " .. (SysTime() - init_time) * 1000 .. "ms")

end

if CLIENT then

	local rendered_frames = 0

	hook.Add("PreRender", "wt_wait_prerender", function()
	
		rendered_frames = rendered_frames + 1
		if rendered_frames > 100 then

			local b,e = pcall(function() Init() end)
			if not b then
				print("FAILED TO INIT BSP DATA")
				ErrorNoHalt(e)
			end

			hook.Remove("PreRender", "wt_wait_prerender")

		end

	end)

	concommand.Add("wt_reloadbsp", function()
		WT_LOADED_BSP = nil
		Init()
	end)
else

	local b,e = pcall(function() Init() end)
	if not b then
		print("FAILED TO INIT BSP DATA")
		ErrorNoHalt(e)
	end

	concommand.Add("wt_sv_reloadbsp", function()
		WT_LOADED_BSP = nil
		Init()
	end)
end

function GetCurrent()

	return WT_LOADED_BSP

end