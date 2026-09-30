-- Transformator for the effects ghosts built by ghost_build.script.lua. The
-- scripts read the ghost's own custom entity state (the way the base game's
-- fireworks do) because a free entity has no vehicle data.
function data()
	return {
		updateScript = {
			fileName = "runaround_helper_1::/res/models/runaround_ghost/ghost.script@ghost.updateFn",
			params = {},
		},
		updateParticleSystemScript = {
			fileName = "runaround_helper_1::/res/models/runaround_ghost/ghost.script@ghost.updateParticleSystemFn",
			params = {},
		},
	}
end
