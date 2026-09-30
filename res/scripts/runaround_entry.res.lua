-- react-plugin resource descriptor - see runaround_button.res.lua for the
-- full explanation of this mechanism. This one mounts the second,
-- independent copy of the panel via ModEntryPointExtension.
function data()
	return {
		type = "react-plugin ::ModEntryPointExtension",
		data = {
			filePath = "runaround_helper_1::/res/scripts/runaround_gui.script@RunAroundHelperEntry",
			priority = 5,
		}
	}
end
