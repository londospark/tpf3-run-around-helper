-- The train window's "Run-around" card: a react-plugin on the vehicle window's
-- extension point (works live). filePath names the mod ID, as every plugin
-- descriptor in the game names its owner ("::/" for the base game); no relative
-- form is known to work here. If the game ever loads the mod under another ID,
-- this card does not load: the log then lacks "[RunAroundHelper] GUI registered"
-- and ghost_build logs "loco setup: SKIPPED" (see CODE_REVIEW.md N3).
function data()
	return {
		type = "react-plugin ::VehicleEowExtensionPoint",
		data = {
			filePath = "runaround_helper_1::/res/scripts/runaround_gui.script@RunAroundHelperVehiclePlugin",
			priority = 5,
		}
	}
end
