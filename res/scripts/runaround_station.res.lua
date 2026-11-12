-- The station window's "Run-around" cards: a react-plugin on the station
-- window's extension point (StationGroupEowExtensionPoint, drawn by the game's
-- station_group.tl with the same parameters as the train window's). Names the
-- mod ID, as runaround_vehicle.res.lua does (see there).
function data()
	return {
		type = "react-plugin ::StationGroupEowExtensionPoint",
		data = {
			filePath = "runaround_helper_1::/res/scripts/runaround_gui.script@RunAroundHelperStationPlugin",
			priority = 5,
		}
	}
end
