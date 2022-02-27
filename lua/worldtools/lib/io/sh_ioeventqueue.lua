AddCSLuaFile()

module( "wt_ioeventqueue", package.seeall )

G_IOEVENTQUEUE_META = G_IOEVENTQUEUE_META or {}

local meta = G_IOEVENTQUEUE_META
meta.__index = meta

function meta:Init()

	self.pending = {}
	self.io_time = 0
	return self

end

function meta:SetTime( time )

	self.io_time = time

end

function meta:AddRaw(entity, func, activator, caller, delay, param)

	if not IsValid(entity) then return end

	local fire_time = self.io_time + (delay or 0)

	local event = nil
	for i=1, #self.pending do
		if self.pending[i].fire_time > fire_time then
			event = {}
			table.insert(self.pending, i, event)
			break
		end
	end

	if event == nil then
		event = {}
		self.pending[#self.pending+1] = event
	end

	event.fire_time = fire_time
	event.entity = entity
	event.func = func
	event.activator = activator
	event.caller = caller
	event.delay = delay
	event.param = param

end

function meta:Service( time )

	while #self.pending > 0 do

		local event = self.pending[1]
		if event.fire_time + 0.0001 > time then break end
		if not IsValid(event.entity) then
			print("event has missing entity")
			goto skip
		end

		event.entity:Fire(
			event.func, 
			event.param or nil, 
			0, 
			event.activator, 
			event.caller)

		::skip::
		table.remove(self.pending, 1)

	end

end

function New()

	return setmetatable({}, meta):Init()

end