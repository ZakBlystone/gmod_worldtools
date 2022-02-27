AddCSLuaFile()

if SERVER then

	util.AddNetworkString("io_net_event")
	util.AddNetworkString("io_player_ride")
	util.AddNetworkString("io_time_sync")

end

module( "wt_ionet", package.seeall )

local strings = {}
local stringLookup = {}
local function addLookupString(k)
	if stringLookup[k] then return end
	local id = #strings + 1
	stringLookup[k] = id
	strings[id] = k
end

for _, class in pairs(wt_iocommon.FGDClasses) do
	for input, param in pairs(class.inputs) do addLookupString(input) end
	for output, param in pairs(class.outputs) do addLookupString(output) end
end

local lookupStringBits = math.ceil(math.log(#strings) / LOG_2)

function WriteIndexed(str)

	local n = stringLookup[str]
	if n then
		net.WriteBit(1)
		net.WriteUInt(n-1, lookupStringBits)
	else
		net.WriteBit(0)
		net.WriteString(str)
	end

end

function ReadIndexed()

	if net.ReadBit() == 1 then
		return strings[net.ReadUInt(lookupStringBits)+1]
	else
		return net.ReadString()
	end

end

print("Lookup bits: " .. lookupStringBits)


if SERVER then

	local event_packs = {}
	local max_events_in_pack = 100
	local max_pack_duration = 0.5
	local next_pack_time = 0
	local next_time_sync = 0

	function AddPendingEvent( output )

		local data = wt_bsp.GetCurrent()
		if data == nil or data:IsLoading() then return end
		local graph = data.iograph
		local world = data.ioworld

		local time = world.io_time

		local pack = nil
		for _,v in ipairs(event_packs) do
			if time - v.time < max_pack_duration then
				pack = v
				break
			end
		end

		local split = pack and #pack.events > max_events_in_pack
		if pack == nil or split then
			if split then print("SPLITTING EVENT PACK") end
			pack = { time = time, last = time, events = {} }
			event_packs[#event_packs+1] = pack
		end

		if math.abs(time - pack.last) > 0.01 then
			pack.events[#pack.events+1] = { delta = time - pack.last }
			pack.last = time
		end

		pack.events[#pack.events+1] = { output = output }

	end

	function ExpediteTimeSync()

		next_time_sync = 0

	end

	function Tick( frame_time )

		if next_time_sync < CurTime() then
			next_time_sync = CurTime() + 1

			local data = wt_bsp.GetCurrent()
			if data ~= nil and data.ioworld ~= nil then
				local world = data.ioworld
				net.Start("io_time_sync")
				net.WriteFloat(CurTime())
				net.WriteFloat(world.io_time)
				net.WriteFloat(world.io_time_scale)
				net.Broadcast()
			end
		end

		--print("PENDING: " .. #event_packs)
		if next_pack_time > CurTime() then return end
		next_pack_time = CurTime() + 0.1

		if #event_packs == 0 then return end
		local pack = event_packs[1]
		table.remove(event_packs, 1)

		print("SEND EVENT PACK @" .. pack.time .. " : " .. #pack.events .. " event(s)")
		for i=1, #pack.events do
			local ev = pack.events[i]
			if ev.output then
				--print(" - " .. tostring(ev.output))
			elseif ev.delta then
				--print(" + " .. ev.delta)
			end
		end

		net.Start("io_net_event")
		net.WriteFloat( pack.time )
		net.WriteUInt( #pack.events, 8 )
		for i=1, #pack.events do
			local ev = pack.events[i]
			if ev.output then
				net.WriteBit(false)
				net.WriteData(ev.output:GetRawHash(), 20)
			elseif ev.delta then
				net.WriteBit(true)
				net.WriteFloat(ev.delta)
			end
		end
		net.Broadcast()

	end

	net.Receive("io_player_ride", function(len, ply)

		local id = net.ReadUInt(32)+1
		local along = net.ReadFloat()
		local ioworld = wt_bsp.GetCurrent().ioworld
		local trace = ioworld:GetTraceByIndex(id)
		local driver = wt_iomove.AttachPlayerToTrace( ply, trace, along )

		print(ply:Nick() .. " wants to ride trace: " .. tostring(id))

	end)

else

	function Tick() end

	function RequestRideTrace( trace, along )

		local id = trace:GetIndex()

		net.Start("io_player_ride")
		net.WriteUInt( id-1, 32 )
		net.WriteFloat( along )
		net.SendToServer()

	end

	net.Receive("io_net_event", function(len, ply)

		local data = wt_bsp.GetCurrent()
		if data == nil or data:IsLoading() then return end
		local graph = data.iograph
		local world = data.ioworld

		local time = net.ReadFloat()
		local num = net.ReadUInt(8)
		for i=1, num do
			if net.ReadBit() == 0 then
				local hash = net.ReadData(20)
				local edge = graph:FindEdgeByHash(hash)
				if edge ~= nil then
					--print("TIME: +" .. (time - world.io_time))
					world:AddBlipFromEdge(edge, time)
				end
			else
				time = time + net.ReadFloat()
			end
		end


	end)

	net.Receive("io_time_sync", function(len, ply)

		local data = wt_bsp.GetCurrent()
		if data == nil or data:IsLoading() then return end
		local graph = data.iograph
		local world = data.ioworld

		local curtime = net.ReadFloat()
		local io_time = net.ReadFloat()
		local io_time_scale = net.ReadFloat()

		local diff = CurTime() - curtime

		local prev = world.io_time

		world.io_time = io_time + diff * io_time_scale
		world.io_time_scale = io_time_scale

		print("SYNC DIFF: " .. (world.io_time - prev), diff)

	end)

end