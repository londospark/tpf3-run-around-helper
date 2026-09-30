-- react-plugin resource descriptor. Confirmed pattern from two real shipped
-- TpF3 mods (Juliansgith/Transport-Fever-3-Multiplayer-Mod's tpf3mp_1, and
-- schbrongx/tf3mod-minimap) - a bare script calling react.RegisterPluginRecipe
-- is never loaded on its own; a .res.lua like this one is what actually gets
-- it required and mounted. filePath resolves from the mod root.
function data()
	return {
		type = "react-plugin ::MainModButtonAreaExtension",
		data = {
			filePath = "runaround_helper_1::/res/scripts/runaround_gui.script@RunAroundHelperButton",
			priority = 5,
		}
	}
end
