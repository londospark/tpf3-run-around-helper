-- react-plugin resource descriptor - see runaround_button.res.lua for the
-- full explanation of this mechanism. This one is the least-confirmed of
-- the three: VehicleEowExtensionPoint itself is not proven by either real
-- example mod found so far (unlike MainModButtonAreaExtension and
-- ModEntryPointExtension, which both are). If this one doesn't render,
-- the other two mounts still work for rename/tune/delete - only "add loop"
-- and "capture edge" (which need a concrete vehicle) would be unavailable,
-- with the dev-console fallback in runaround_gui.script.lua's header
-- comment as the workaround.
function data()
	return {
		type = "react-plugin ::VehicleEowExtensionPoint",
		data = {
			filePath = "runaround_helper_1::/res/scripts/runaround_gui.script@RunAroundHelperVehiclePlugin",
			priority = 5,
		}
	}
end
