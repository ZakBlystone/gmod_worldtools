AddCSLuaFile()

module( "wt_iograph", package.seeall )

G_IOGRAPH_META = G_IOGRAPH_META or {}
G_EVENTDATA_META = G_EVENTDATA_META or {}

--[[

graph is made of nodes, each node is an entity.

a node contains:
- an index which corresponds to the entity in the map.
- the position of the entity
- the name of the entity
- inputs and outputs

each input:
- points to the originator of the event
- contains the parameters

each output:
- points to target of the event
- contains parameters

]]

local eventDataMeta = G_EVENTDATA_META
eventDataMeta.__index = eventDataMeta

function eventDataMeta:Fire(activator, caller, delay)

	local real = self.to:GetEntity()
	if IsValid(real) then
		real:Fire(
			self.func, 
			self.param, 
			delay or self.delay, 
			activator or self.from:GetEntity(), 
			caller or self.from:GetEntity())
	else
		print("COULDN'T FIND REAL ENTITY FOR: " .. self.to:GetName())
	end

end

local meta = G_IOGRAPH_META
meta.__index = meta

function meta:Init( mapData )

	self.ents = mapData.entities
	self.entsByID = {}
	self.nodes = {}

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

function meta:Link()

	wt_task.Yield("sub", "linking graph")

	for ent in self:Ents() do

		local name = ent:GetName()
		local rawOutputs = ent:GetMapEntityOutputs()
		for _, output in ipairs(rawOutputs) do

			for target in self:EntsByName(output.target) do

				local eventData = {
					from = ent,
					to = target,
					event = output.event,
					func = output.func,
					param = output.param,
					delay = (output.delay or 0),
					refire = output.refire,
				}

				setmetatable(eventData, eventDataMeta)

				ent.outputs[#ent.outputs+1] = eventData
				target.inputs[#target.inputs+1] = eventData

				wt_task.YieldPer(10, "progress", 1)

			end

		end

		if ent.parentname then

			for target in self:EntsByName(ent.parentname) do
				ent.parent = target
				break
			end

		end

	end

end

function meta:FireOutput( ent, event, activator, caller )

	for _,v in ipairs(ent.outputs) do

		if v.event == event then

			v:Fire(activator, caller)

		end

	end

end

function meta:HandleOutput( caller, activator, event, data )

	local ent = self:GetByEntity(caller)
	if ent ~= nil then

		self:FireOutput( ent, event, activator, caller )

	end

end

function meta:GetByIndex( index )

	return self.entsByID[index]

end

function meta:GetByEntity( ent )

	if not IsValid(ent) then return end
	return self:GetByIndex(ent:MapCreationID()-1234)

end

function meta:Ents()

	local i = 1
	return function()
		local n = self.nodes[i]
		i = i + 1
		return n
	end

end

function meta:EntsByClass( classname )

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

function meta:EntsByName( name )

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