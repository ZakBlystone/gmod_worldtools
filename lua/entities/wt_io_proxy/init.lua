ENT.Type = "point"

function ENT:Initialize()

end

function ENT:AcceptInput( name, activator, caller, data )

	if name == "wt_io_forward" then

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

				if wt_bsp.GetCurrent().ioworld ~= nil then
					wt_bsp.GetCurrent().ioworld:HandleOutput(caller, activator, event, data)
				end

			end

			return true

		end

	end

end
