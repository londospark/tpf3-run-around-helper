-- The stock tilting-train transformator with a free-entity branch (see
-- res/scripts/ghost_real.script.lua). ghost_build.script.lua points loco models
-- that use vehicle/train/shared/tilting_train.trf at this.
function data()
	return {
		updateScript = {
			fileName = "runaround_helper_1::/res/scripts/ghost_real.script@tiltingTrain.updateFn",
			params = {},
		},
		updateParticleSystemScript = {
			fileName = "runaround_helper_1::/res/scripts/ghost_real.script@tiltingTrain.updateParticleSystemFn",
			params = {},
		},
	}
end
