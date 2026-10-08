-- As chain.trf, for another mod's transformator that also emits extra models
-- (getEmittableModelsScript and computeEmittedModelsScript, as mcs_basisset's
-- does): ghost_build.script.lua points such a vehicle here instead. Both extra
-- hooks are passed on to the original; while the vehicle is hidden it emits none.
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
		getEmittableModelsScript = {
			fileName = "runaround_helper_1::/res/scripts/ghost_real.script@chain.getEmittableModelsFn",
			params = {},
		},
		computeEmittedModelsScript = {
			fileName = "runaround_helper_1::/res/scripts/ghost_real.script@chain.computeEmittedModelsFn",
			params = {},
		},
	}
end
