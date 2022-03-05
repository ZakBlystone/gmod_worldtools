AddCSLuaFile()

module( "wt_ioeventqueue", package.seeall )

G_IOEVENTQUEUE_META = G_IOEVENTQUEUE_META or {}

local meta = G_IOEVENTQUEUE_META
meta.__index = meta

function meta:Init( graph )

	self.graph = graph
	self.pending = {}
	self.counters = {}
	self.io_time = 0
	return self

end

function meta:SetTime( time )

	self.io_time = time

end

-- Number of inbound pending events for a node
function meta:GetPendingCount(node)

	return self.counters[node] or 0

end

function meta:Clear()

	self.counters = {}
	self.pending = {}

end

function meta:DetectCycle(node, func)

	for i=1, #self.pending do

		local cycle = self.graph:GetCommonCycle(node, self.pending[i].node)
		if cycle then

			local triggers_cycle = nil
			for _,v in ipairs(cycle) do

				if v.func == func and v.to == node then
					triggers_cycle = v
					break
				end

			end

			if triggers_cycle ~= nil then

				MsgC(Color(255,80,80), 
					"Canceling event: " .. tostring(triggers_cycle) .. "\n", 
					Color(255,255,255),
					"Introducing new event into pending cycle might create additional feedback loop\n")
				return true

			end

		end

	end

	return false

end

function meta:Cancel(node, func)

	for i=#self.pending, 1, -1 do
		if self.pending[i].node == node and self.pending[i].func == func then
			table.remove(self.pending, i)
		end
	end

end

function meta:AddRaw(node, func, activator, caller, delay, param)

	local fire_time = self.io_time + (delay or 0)

	--print("ADD INPUT: " .. node:GetName() .. "." .. func .. "(" .. tostring(param) .. ")")

	if self:DetectCycle(node, func) then return end

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
	event.node = node
	event.func = func
	event.activator = activator
	event.caller = caller
	event.delay = delay
	event.param = param

	self.counters[node] = (self.counters[node] or 0) + 1

end

function meta:Service( time )

	while #self.pending > 0 do

		local event = self.pending[1]
		if event.fire_time + 0.0001 > time then break end

		self.counters[event.node] = (self.counters[event.node] or 1) - 1

		local entity = event.node:GetEntity()
		if not IsValid(entity) then
			print("COULDN'T FIND REAL ENTITY FOR: " .. event.node:GetName())
			goto skip
		end

		--print("FIRE: " .. event.node:GetName() .. "." .. event.func .. "(" .. tostring(event.param) .. ")")

		entity:Fire(
			event.func, 
			event.param or nil, 
			0, 
			event.activator, 
			event.caller)

		::skip::
		table.remove(self.pending, 1)

	end

end

function New( graph )

	return setmetatable({}, meta):Init( graph )

end