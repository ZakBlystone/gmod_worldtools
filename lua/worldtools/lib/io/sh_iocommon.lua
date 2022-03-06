AddCSLuaFile()

module( "wt_iocommon", package.seeall )

local proxy_name = "__wt_io_proxy"

local function TickWorld()

	local frame_time = FrameTime()

	local world = nil
	if wt_bsp.GetCurrent() then world = wt_bsp.GetCurrent().ioworld end

	if world then world:Tick(frame_time) end

	wt_ionet.Tick(frame_time)

	--print("tick: ", frame_time)

end

function ProcessOutput( event, str )

	if str == nil then return end

	local args = { event }
	for w in string.gmatch(str .. ",","(.-),") do
		args[#args+1] = w
	end

	if args[2] == "" then return end

	local output = {}
	output.event = args[1]  -- the event that causes this output (On*)
	output.target = args[2] -- the target to affect
	output.func = args[3]  -- the input to call on the target
	output.param = args[4]  -- parameter passed to target
	output.delay = args[5]  -- how long to wait
	output.refire = args[6] -- max times to refire

	return output

end

if SERVER then
	hook.Add("Tick", "wt_iocommon_tick", TickWorld)
else
	hook.Add("PreRender", "wt_iocommon_tick", TickWorld)
end

if SERVER then

	wt_timescale = CreateConVar("wt_timescale", "1", bit.bor(FCVAR_ARCHIVE), "How fast does IO run")

	local noReroute = CreateConVar(
		"wt_dont_reroute_io", "0", 
		{ FCVAR_ARCHIVE }, 
		"Disable IO Rerouting")

	function IsRerouteEnabled()

		return not noReroute:GetBool()

	end

	local function BindEntityToSink(entity, class)

		--if noReroute:GetBool() then return end

		if not IsValid(entity) then print("FAILED TO BIND: " .. tostring(class)) return end
		if entity:MapCreationID() == -1 then return end --print("Not binding: " .. tostring(entity) .. " because it was not in the BSP data") return end
		if entity:GetClass() == "wt_io_proxy" then return end
		if entity.bound_to_proxy then return end
		entity.bound_to_proxy = true

		--print("Bind To Sink: " .. tostring(entity) .. " : " .. tostring(entity:MapCreationID()))

		local fgd = FGDClasses[entity:GetClass()]
		if fgd then

			for ev,output in pairs(fgd.outputs) do

				--print("BIND: " .. tostring(ev))
				local outputStr = string.format(
					"%s %s,wt_io_sink_%s,,0,-1", 
					ev,
					proxy_name,
					ev)

				entity:Fire("AddOutput", outputStr)

			end

		end

	end

	local function SetupIOListener()

		print("****SetupIOListener****")

		local io_proxy = ents.FindByClass("wt_io_proxy")[1]
		if not IsValid( io_proxy ) then
			io_proxy = ents.Create("wt_io_proxy")
			io_proxy:SetPos( Vector(0,0,0) )
			io_proxy:SetName(proxy_name)
			io_proxy:Spawn()
		end

		assert(wt_bsp.GetCurrent() ~= nil)

		for _, ent in ipairs(ents.GetAll()) do
			BindEntityToSink(ent, ent:GetClass())
		end

		-- Clear any pending events
		if wt_bsp.GetCurrent().ioworld then
			wt_bsp.GetCurrent().ioworld:Reset()
		end

	end
	hook.Add("InitPostEntity", "wt_io_setuplistener", SetupIOListener)
	hook.Add("PostCleanupMap", "wt_io_listenercleanup", SetupIOListener)

	local function SetupEntity(entity)

		if not IsValid(entity) then return end
		--if noReroute:GetBool() then return end

		wt_ioindexing.AddEntity( entity )

		local class = entity:GetClass()

		--print("Created: " .. tostring(entity:GetName()) .. " : " .. entity:GetClass() .. " [" .. entity:GetCreationID() .. "]")


		--timer.Simple(0, function() BindEntityToSink(entity, class) end)
		BindEntityToSink(entity, class)

	end
	hook.Add("OnEntityCreated", "wt_io_entitycreate", SetupEntity)

	local function RemovedEntity(entity)

		if noReroute:GetBool() then return end

		wt_ioindexing.RemoveEntity( entity )

		--print("Removed: " .. tostring(entity:GetName()) .. " : " .. entity:GetClass() .. " [" .. entity:GetCreationID() .. "]")

	end
	hook.Add("EntityRemoved", "wt_io_entityremoved", RemovedEntity)

	local function StripIO(entity, key, value)

		--print(tostring(entity) .. "." .. tostring(key) .. " = " .. tostring(value) .. " [" .. entity:GetCreationID() .. "]")

		if noReroute:GetBool() then return end

		wt_ioindexing.SetKeyValue(entity, key, value)

		local fgd = FGDClasses[entity:GetClass()]
		if fgd then
			if fgd.outputs[key] then return "" end
		end

	end
	hook.Add("EntityKeyValue", "wt_io_strip", StripIO)

end