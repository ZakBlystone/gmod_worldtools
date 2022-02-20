ENT.Type = "point"

function ENT:Initialize()

end

function ENT:AcceptInput( name, activator, caller, data )

	if name == "wt_io_forward" then

		local event, num = tostring(data):match("([%w_]+)_(%d+)")

		if event and num then

			local graph = wt_bsp.GetCurrent().iograph
			hook.Call("IOEventTriggered", 
				GAMEMODE,
				graph:GetByIndex(tonumber(num)), 
				event )

		end

		return true

	else

		local event = name:match("wt_io_sink_(.*)")
		if event then

			--[[print(("SINK: act: %s call: %s event: %s data: %s"):format(
				tostring(activator),
				tostring(caller),
				event,
				tostring(data)
			))]]

			if wt_bsp and wt_bsp.GetCurrent() ~= nil then

				wt_bsp.GetCurrent().iograph:HandleOutput(caller, activator, event, data)

			end

			return true

		end

	end

end
