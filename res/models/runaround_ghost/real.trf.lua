-- The stock train transformator with a free-entity branch (see
-- res/scripts/ghost_real.script.lua). ghost_build.script.lua points loco models
-- that use the stock one (vehicle/train/shared/default_train.trf) at this.
function data()
	return {
		updateScript = {
			fileName = "runaround_helper_1::/res/scripts/ghost_real.script@train.updateFn",
			params = {},
		},
		updateParticleSystemScript = {
			fileName = "runaround_helper_1::/res/scripts/ghost_real.script@train.updateParticleSystemFn",
			params = {},
		},
	}
end
