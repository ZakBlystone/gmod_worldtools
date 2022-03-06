AddCSLuaFile()

module( "wt_ioindexing", package.seeall )

STATE = STATE or {
	entity_lookup = {},
	map_lookup = {},
}

if SERVER then

	INDEX = INDEX or {}
	ENTITIES = ENTITIES or {}

	local function FixupMatchesName( fixup, name )

		if fixup == name then return true end
		local a = fixup:match("^([^&]+)&.*")
		return a == name

	end

	print( FixupMatchesName("u7_t_phys&0288", "u7_t_phys") )

	local ent_ignore_keys = {
		["index"] = true,
		["outputs"] = true,
	}

	local empty_set = {}
	local function DiffKeys( a, b, ignore, diff )

		ignore = ignore or empty_set
		local count = 0
		local set = {}
		for k, v in pairs(a) do if not ignore[k] then set[k] = true end end
		for k, v in pairs(b) do if not ignore[k] then set[k] = true end end
		for k, _ in pairs(set) do
			if tostring(a[k]) == tostring(b[k]) then 
			elseif diff then
				count = count + 1
				diff[k] = true
			else
				count = count + 1
			end
		end
		return count

	end

	local function LocateInBSP( entry )

		if entry.bsp_index then return end

		local id = entry.real:MapCreationID()
		if id ~= -1 then
			print("IS BSP: " .. tostring(entry.real))
			entry.bsp_index = id - 1234
			entry.bsp_created = true
			return
		end

		local targetname = entry.keys.targetname
		local ents = wt_bsp.GetCurrent().entities
		if targetname then

			local best_n = math.huge
			local best = nil
			for k,v in ipairs(ents) do

				if FixupMatchesName(targetname, v.targetname) and v.origin == entry.keys.origin then

					local num_diff = DiffKeys( v, entry.keys, ent_ignore_keys )
					if num_diff < best_n then
						best_n = num_diff
						best = k
						print("TARGET [" .. targetname .. "] IN BSP: " .. tostring(entry.real) .. " -> " .. num_diff)
						entry.bsp_index = k
						entry.bsp_created = false
					end

				end

			end

		end

	end

	local function FinishAddEntity( ent, entry )

		if entry.ready then return end
		entry.ready = true

		if not IsValid(ent) then return end
		if INDEX[ ent:GetCreationID() ] == nil then return end

		LocateInBSP(entry)

	end

	function AddEntity( ent )

		local id = ent:GetCreationID() 

		INDEX[ id ] = {
			real = ent,
			keys = {},
			outputs = {},
		}

		ENTITIES[#ENTITIES+1] = ent:GetCreationID()

		print(" +" .. tostring(ent) .. " indexed at [" .. ent:GetCreationID() .. "]")

		timer.Remove( "_finish_ent_" .. id )
		timer.Create( "_finish_ent_" .. id, 0, 1, function() FinishAddEntity(ent, INDEX[ id ]) end )

	end

	function RemoveEntity( ent )

		INDEX[ ent:GetCreationID() ] = nil

		if not table.RemoveByValue(ENTITIES, ent:GetCreationID()) then
			--print(" -" .. tostring(ent) .. " removed but was not indexed [" .. ent:GetCreationID() .. "]")
		else
			print(" -" .. tostring(ent) .. " removed [" .. ent:GetCreationID() .. "]")
		end

	end

	function SetKeyValue( ent, k, v )

		local id = ent:GetCreationID() 
		local entry = INDEX[ id ]
		if entry == nil then
			ErrorNoHalt("No index entry for entity: " .. tostring(ent) .. "\n")
			return
		end

		print(tostring(ent) .. "." .. k .. " = " .. tostring(v))

		local fgd = wt_iocommon.GetFGDClass( ent:GetClass() )
		if fgd == nil then print("No FGD entry for: " .. ent:GetClass()) end
		if fgd and fgd.outputs[k] then

			local parsed = wt_iocommon.ProcessOutput(k, v)
			if parsed then 
				entry.outputs[#entry.outputs+1] = parsed 
			else
				ErrorNoHalt("Failed to process output: " .. k .. " : " .. tostring(v) .. "\n")
			end

		else

			if k == "origin" then
				local x,y,z = string.match( tostring(v), "([%+%-]?%d*%.?%d+) ([%+%-]?%d*%.?%d+) ([%+%-]?%d*%.?%d+)" )
				if x and y and z then
					v = Vector(x,y,z)
				else
					v = Vector()
				end
			end
			if k == "angles" then
				local x,y,z = string.match( tostring(v), "([%+%-]?%d*%.?%d+) ([%+%-]?%d*%.?%d+) ([%+%-]?%d*%.?%d+)" )
				v = Angle(x,y,z)
			end
			entry.keys[k] = v

		end

		timer.Remove( "_finish_ent_" .. id )
		timer.Create( "_finish_ent_" .. id, 0, 1, function() FinishAddEntity(ent, entry) end )

	end

	function PrintIndex()

		local ents = wt_bsp.GetCurrent().entities
		local sorted = {}
		for k,v in pairs(INDEX) do sorted[#sorted+1] = k end
		table.sort(sorted)

		for _,v in ipairs(sorted) do
			local entry = INDEX[v]
			MsgC(Color(80,255,255), tostring(v) .. " [" .. tostring(entry.real) .. "] : ", 
				entry.real:EntIndex() == 0 and Color(255,255,255) or Color(255,80,255), tostring(entry.real:EntIndex()) .. " = " )

			if entry.bsp_index and entry.bsp_created then

				MsgC(Color(100,255,100), tostring(entry.bsp_index) .. "\n")

			elseif entry.bsp_index then

				local diff = {}
				MsgC(Color(255,255,100), tostring(entry.bsp_index) .. "[" .. DiffKeys( ents[entry.bsp_index], entry.keys, ent_ignore_keys, diff ) ..  "]" .. "\n")

				for k,v in pairs(diff) do
					local a = ents[entry.bsp_index][k]
					local b = entry.keys[k]
					MsgC(Color(255,255,100), "  " .. k .. " = " .. tostring(a) .. " -> " .. tostring(b) .. "\n")
				end

			else

				MsgC(Color(255,100,100), "T:\n")

				PrintTable(entry.keys, 1)
				PrintTable(entry.outputs, 1)

			end

		end

	end

end


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