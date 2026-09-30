-- Game script descriptor. The fileName path is resolved from the MOD ROOT,
-- not from this .gs.lua file's own folder - confirmed the hard way from a
-- real "Resource not found: runaround_helper_1::/runaround.script@update"
-- error in-game (it was missing the res/scripts/ prefix that matches this
-- file's actual location per _content.json). Keep this path in sync with
-- wherever runaround.script.lua actually lives in the mod.
function data()
	return {
		updateScript = {
			fileName = "res/scripts/runaround.script@update",
		},
		postUpdateScript = {
			fileName = "res/scripts/runaround.script@postUpdate",
		},
		handleEventScript = {
			fileName = "res/scripts/runaround.script@handleEvent",
		},
	}
end
