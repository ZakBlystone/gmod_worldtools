AddCSLuaFile()

module( "wt_ioindexing", package.seeall )

STATE = STATE or {
	entity_lookup = {},
	map_lookup = {},
}

function EncodeDeltas(t)

	local o = {}
	for k,v in ipairs(t) do
		o[#o+1] = k > 1 and v - t[k-1] or v
	end
	return o

end

function DecodeDeltas(t)

	local o,r = {}, 0
	for k,v in ipairs(t) do
		r = k == 1 and v or r + v
		o[#o+1] = k == 1 and v or r
	end
	return o

end

function EncodeRLE(t)

	local rle, num, val = {}, 0, nil
	local function emit(v)
		if num == 0 then return end
		rle[#rle+1] = bit.bor(bit.lshift(num, 16), bit.band(val+0x7FFF, 0xFFFF))
	end

	for k,v in ipairs(t) do
		if v ~= val then emit() end
		num = v ~= val and 1 or num+1
		val = v == val and val or v
	end
	emit()

	return rle

end

function DecodeRLE(t)

	local o = {}
	for k,v in ipairs(t) do
		local val = bit.band(v, 0xFFFF)-0x7FFF
		for i=1, bit.rshift(v, 16) do o[#o+1] = val end
	end
	return o

end

function EncodeIDList(t)

	return EncodeRLE(EncodeDeltas(t))

end

function DecodeIDList(t)

	return DecodeDeltas(DecodeRLE(t))

end

if CLIENT then

	function RequestIDs()

		net.Start("wt_io_mapids")
		net.SendToServer()

	end

	net.Receive("wt_io_mapids", function()

		local numEnts = net.ReadUInt(24)
		local numMapIDs = net.ReadUInt(24)
		local numEntIDs = net.ReadUInt(24)

		local mapIDs = {}
		local entIDs = {}

		for i=1, numMapIDs do mapIDs[#mapIDs+1] = net.ReadUInt(32) end
		for i=1, numEntIDs do entIDs[#entIDs+1] = net.ReadUInt(32) end

		mapIDs = DecodeIDList(mapIDs)
		entIDs = DecodeIDList(entIDs)

		assert(#mapIDs == #entIDs and #mapIDs == numEnts)

		STATE.entity_lookup = {}
		STATE.map_lookup = {}

		for i=1, numEnts do
			STATE.entity_lookup[mapIDs[i]] = entIDs[i]
			STATE.map_lookup[entIDs[i]] = mapIDs[i]
		end

		print("GOT INDEX LIST")

	end)

	--RequestIDs()

end

if SERVER then

	util.AddNetworkString("wt_io_mapids")

	function SendIDsToPlayer(ply)

		local entities = ents.GetAll()
		local mapIDs = {}
		local entIDs = {}
		local count = 0
		for _,v in ipairs(entities) do
			if v:MapCreationID() ~= -1 then
				mapIDs[#mapIDs+1] = v:MapCreationID()
				entIDs[#entIDs+1] = v:EntIndex()
				count = count + 1
			end
		end

		mapIDs = EncodeIDList(mapIDs)
		entIDs = EncodeIDList(entIDs)

		net.Start("wt_io_mapids")
		net.WriteUInt(count, 24)
		net.WriteUInt(#mapIDs, 24)
		net.WriteUInt(#entIDs, 24)

		for i=1, #mapIDs do net.WriteUInt(mapIDs[i], 32) end
		for i=1, #entIDs do net.WriteUInt(entIDs[i], 32) end

		print("SEND: " .. count .. " entity indices [" .. #mapIDs .. "]")

		net.Send(ply)

	end

	function BroadcastIDs()

		local entities = ents.GetAll()
		local mapIDs = {}
		local entIDs = {}
		local count = 0
		for _,v in ipairs(entities) do
			if v:MapCreationID() ~= -1 then
				mapIDs[#mapIDs+1] = v:MapCreationID()
				entIDs[#entIDs+1] = v:EntIndex()
				count = count + 1
			end
		end

		mapIDs = EncodeIDList(mapIDs)
		entIDs = EncodeIDList(entIDs)

		net.Start("wt_io_mapids")
		net.WriteUInt(count, 24)
		net.WriteUInt(#mapIDs, 24)
		net.WriteUInt(#entIDs, 24)

		for i=1, #mapIDs do net.WriteUInt(mapIDs[i], 32) end
		for i=1, #entIDs do net.WriteUInt(entIDs[i], 32) end

		print("SEND: " .. count .. " entity indices [" .. #mapIDs .. "]")

		net.Broadcast()

	end

	net.Receive("wt_io_mapids", function(len, ply)

		SendIDsToPlayer(ply)

	end)

	hook.Add("PostCleanupMap", "wt_io_indexercleanup", BroadcastIDs)

	local needBroadcastIDs = false
	local tickTimer = 0
	hook.Add("Tick", "wt_io_indexertick", function()

		if tickTimer <= 0 then
			tickTimer = 1
		else
			tickTimer = tickTimer - FrameTime()
			return
		end

		if needBroadcastIDs then
			BroadcastIDs()
			needBroadcastIDs = false
		end

	end)

	hook.Add("EntityRemoved", "wt_io_indexerremove", function(ent)

		if ent:MapCreationID() ~= -1 then
			needBroadcastIDs = true
		end

	end)

end

if CLIENT then

	local m = FindMetaTable("Entity")
	function m:MapCreationID()

		return STATE.map_lookup[ self:EntIndex() ]

	end

	function m:GetName()

		local bspent = ents.GetBSPEntity( self:MapCreationID() )
		if bspent then return bspent["targetname"] or "" end
		return ""

	end

	function m:GetBSPEntity()

		return ents.GetBSPEntity( self:MapCreationID() )

	end

	function ents.ExistsOnServer(id)

		return STATE.entity_lookup[id]

	end

	function ents.GetMapCreatedEntity(id)

		--[[for _,v in ipairs(ents.GetAll()) do
			if v:MapCreationID() == id then return v end
		end]]
		local entindex = STATE.entity_lookup[id]
		if entindex == nil then return end
		return ents.GetByIndex( entindex )

	end

	function ents.GetBSPEntity(id)

		local current = wt_bsp.GetCurrent()
		if current then
			return current.entities[ id-1234 ]
		end

		return nil

	end

	function ents.FindRealEntity(ent)

		if type(ent) ~= "table" then return end
		if not ent.index then return end

		return ents.GetMapCreatedEntity(ent.index+1234)

	end

end