AddCSLuaFile()

module( "wt_iograph", package.seeall )

G_IOGRAPH_META = G_IOGRAPH_META or {}
G_EVENTDATA_META = G_EVENTDATA_META or {}

--[[

a directed graph representing entities and their IO connections.

each node in the graph is an entity.
each edge is an IO connection between two nodes.

a node contains:
- an index which corresponds to the entity in the map.
- the position of the entity
- the name of the entity

an edge:
- points to the originator and target of the event
- contains the parameters

]]

local eventDataMeta = G_EVENTDATA_META
eventDataMeta.__index = eventDataMeta
eventDataMeta.__tostring = function(self)

	return ("%s:%s -> %s.%s(%s) @%0.2fs [%i]"):format(
		self.from:GetName(),
		self.event,
		self.to:GetName(),
		self.func,
		tostring(self.param),
		self.delay or 0,
		self.refire or -1
	)

end

function eventDataMeta:ComputeHash()

	self.hash = util.SHA1( ("%i|%i:%s.%s(%s)%f_%i"):format(
		self.from:GetIndex(),
		self.to:GetIndex(),
		self.event,
		self.func,
		tostring(self.param),
		self.delay or 0,
		self.refire or -1
	) )

	self.rawhash = self.hash:gsub("%w%w", function(x)
		return string.char(tonumber(x[1],16) * 16 + tonumber(x[2],16))
	end)

end

function eventDataMeta:GetDelay() return (self.delay or 0) end

function eventDataMeta:GetHash()

	return self.hash

end

function eventDataMeta:GetRawHash()

	return self.rawhash

end

function eventDataMeta:Fire(activator, caller, delay, param)

	local from_ent = self.from:GetEntity()

	wt_ionet.AddPendingEvent(self)

	self.to:FireInput(
		self.func, 
		activator or from_ent,
		caller or from_ent,
		delay or self:GetDelay(),
		param or self.param)

end

local meta = G_IOGRAPH_META
meta.__index = meta

function meta:Init( mapData )

	self.ents = mapData.entities
	self.entsByID = {}
	self.nodes = {}
	self.edges = {}
	self.cycles = {}
	self.cycle_nodes = {}
	self.event_queue = wt_ioeventqueue.New( self )

	wt_task.Yield("sub", "creating io nodes")

	for k, ent in ipairs(self.ents) do
		local node = wt_ionode.New( ent, self )
		self.nodes[#self.nodes+1] = node
		self.entsByID[node:GetIndex()] = node
		wt_task.YieldPer(10, "progress", k / #self.ents)
	end

	self:Link()

	return self

end

function meta:Tick( time, frame_time )

	if SERVER then
		self:GetEventQueue():SetTime( time )
		self:GetEventQueue():Service( time ) 
	end

end

function meta:GetEventQueue() return self.event_queue end
function meta:GetCycles() return self.cycles end
function meta:GetNodeCycles( node ) return self.cycle_nodes[node] end
function meta:GetCommonCycle( node_a, node_b )

	local a_cycles = self.cycle_nodes[node_a]
	local b_cycles = self.cycle_nodes[node_b]
	if a_cycles == nil or b_cycles == nil then
		return nil
	end

	for k,v in pairs(a_cycles) do
		if b_cycles[k] then return self.cycles[k] end
	end

end

function meta:NodeOutputs( node )

	local i = 1
	return function()
		local n = self.edges[i]
		while n and n.from ~= node do 
			i = i + 1
			n = self.edges[i]
		end
		i = i + 1
		if n ~= nil then return i, n end
	end

end

function meta:NodeInputs( node )

	local i = 1
	return function()
		local n = self.edges[i]
		while n and n.to ~= node do 
			i = i + 1
			n = self.edges[i]
		end
		i = i + 1
		if n ~= nil then return i, n end
	end

end

function meta:Link()

	wt_task.Yield("sub", "linking graph")

	local hashes = {}

	for node in self:Nodes() do

		local name = node:GetName()
		for _, output in ipairs(node:GetRawOutputs()) do

			for target in self:NodesByName(output.target) do

				local eventData = {
					from = node,
					to = target,
					event = output.event,
					func = output.func,
					param = output.param,
					delay = (output.delay or 0),
					refire = output.refire,
				}

				setmetatable(eventData, eventDataMeta)
				eventData:ComputeHash()

				local hash = eventData:GetHash()

				if hashes[hash] then
					print("DUPLICATE IO: " .. tostring(eventData))
					continue
				end
				
				hashes[hash] = true

				self.edges[#self.edges+1] = eventData

				wt_task.YieldPer(10, "progress", 1)

			end

		end

		if node.parentname then

			for target in self:NodesByName(node.parentname) do
				node.parent = target
				break
			end

		end

	end

	self:DetectCycles()

end

local non_cyclical_inputs = {
	["Kill"] = true,
}

function meta:TraverseEdges( node, visited, cycle )

	if visited[node] then
		if cycle[1].from == node then
			return true
		else
			return false
		end
	end

	visited[node] = true

	for k, v in self:NodeOutputs(node) do

		if non_cyclical_inputs[v.func] then return false end

		cycle[#cycle+1] = v
		if self:TraverseEdges(v.to, visited, cycle) then
			return true
		else
			table.remove(cycle, #cycle)
		end

	end

	return false

end

function meta:DetectCycles()

	print("Detecting IO cycles:")

	self.cycles = {}
	self.cycle_nodes = {}

	local ignored = {}

	local function assign_cycle(edge, id)
		self.cycle_nodes[edge.from] = self.cycle_nodes[edge.from] or {}
		self.cycle_nodes[edge.to] = self.cycle_nodes[edge.to] or {}
		self.cycle_nodes[edge.from][id] = true
		self.cycle_nodes[edge.to][id] = true
	end

	for node in self:Nodes() do

		if self.cycle_nodes[node] then continue end

		local visited = {}
		local cycle = {}
		if self:TraverseEdges( node, visited, cycle ) then

			if #cycle > 0 then
				
				MsgC(Color(100,255,80), #self.cycles+1 .. " : ")

				for k,v in ipairs(cycle) do
					MsgC(Color(255,100,100), tostring(v) .. (k ~= #cycle and " -> " or ""))
					assign_cycle(v, #self.cycles+1)
				end

				Msg("\n")
				self.cycles[#self.cycles+1] = cycle

			end

		end

	end

end

--[[if SERVER then

	local graph = wt_bsp.GetCurrent().iograph
	graph:DetectCycles()

end]]

-- Handle a sunk output from the engine
function meta:HandleOutput( caller, activator, event, data )

	local ent = self:GetByEntity(caller)
	if ent ~= nil then

		ent:FireOutput( event, activator, caller )

	end

end

function meta:FindEdgeByHash( hash )

	local i = 1
	for edge in self:Edges() do
		if edge:GetRawHash() == hash then return edge end
		if edge:GetHash() == hash then return edge end
	end

end

function meta:GetByIndex( index )

	return self.entsByID[index]

end

function meta:GetByEntity( ent )

	if not IsValid(ent) then return end
	return self:GetByIndex(ent:MapCreationID()-1234)

end

function meta:Edges()

	local i = 1
	return function()
		local n = self.edges[i]
		i = i + 1
		return n
	end

end

function meta:Nodes()

	local i = 1
	return function()
		local n = self.nodes[i]
		i = i + 1
		return n
	end

end

function meta:RecentlyRendered()

	local i = 1
	local rt = RealTime()
	return function()
		local n = self.nodes[i]
		while n and rt - n.lastRenderTime > 0.1 do 
			i = i + 1
			n = self.nodes[i]
		end
		i = i + 1
		return n
	end

end

function meta:NodesByClass( classname )

	local i = 1
	return function()
		local n = self.nodes[i]
		while n and n:GetClass() ~= classname do 
			i = i + 1
			n = self.nodes[i]
		end
		i = i + 1
		return n
	end

end

function meta:NodesByName( name )

	local i = 1
	return function()
		local n = self.nodes[i]
		while n and not n:MatchesName( name ) do 
			i = i + 1
			n = self.nodes[i]
		end
		i = i + 1
		return n
	end

end


local trmtx = Matrix()
local ipos = Vector()
local idir = Vector()
local tw = {
	tmax = 0,
	tmin = 0,
	mask = 0xFFFFFFFF,
}
function meta:VisualTrace(pos, dir, mindist, maxdist)

	local t = maxdist
	local hitEntity = nil
	local hitPos = nil
	local count = 0

	for ent in self:RecentlyRendered() do

		if ent:HasBounds() then

			count = count + 1
			ent:GetMatrix(trmtx)
			trmtx:Invert()
			trmtx:Transform3( pos, 1, ipos )
			trmtx:Transform3( dir, 0, idir )

			local min, max = ent:GetLocalBounds()
			local hit, toi = IntersectRayBox(ipos, idir, min, max)
			if hit then
				if ent.ent.bmodel then

					tw.tmin = 0
					tw.tmax = maxdist
					tw.ipos = ipos
					tw.idir = idir
					tw.hit = false
					wt_bsp.traceNode(ent.ent.bmodel.headnode, tw)
					if not tw.hit then continue end

				end

				if math.abs(t - toi) < 1 then
					if hitEntity then
						local d0 = (hitEntity:GetPos() - pos):GetNormalized():Dot(dir)
						local d1 = (ent:GetPos() - pos):GetNormalized():Dot(dir)
						if d0 > d1 then continue end
					end
				end

				if toi < t + 0.01 and toi > 0 then
					t = toi 
					hitEntity = ent
					hitPos = idir
					hitPos:Mul(toi)
					hitPos:Add(ipos)
					trmtx:Transform3( hitPos, 1, hitPos )
				end
			end

		end

	end

	--print("trace: " .. count .. " : " .. t .. " : " .. (hitEntity and hitEntity.index or -1))

	return hitEntity, hitPos

end

function New(mapData)

	if mapData == nil then
		mapData = wt_bsp.GetCurrent()
	end

	if mapData == nil then return nil end
	return setmetatable({}, meta):Init(mapData)

end

if CLIENT then

	--local graph = New()

end