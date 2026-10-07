-- A vehicle whose transformator belongs to another mod (or is its own):
-- ghost_build.script.lua points it here and keeps the original's name in
-- transformatorConfig.params.runaround_trf. The chain functions in
-- res/scripts/ghost_real.script.lua hide it, drive its ghost, or call the original.
function data()
	return {
		updateScript = {
			fileName = "runaround_helper_1::/res/scripts/ghost_real.script@chain.updateFn",
			params = {},
		},
		updateParticleSystemScript = {
			fileName = "runaround_helper_1::/res/scripts/ghost_real.script@chain.updateParticleSystemFn",
			params = {},
		},
	}
end
