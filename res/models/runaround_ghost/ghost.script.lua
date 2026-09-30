-- Scripts for ghost.trf.lua. The ghost's state, sent by the run-around script
-- with makeCustomEntityUpdateStateCmd, looks like
--   { speed01 = 0..1, power01 = 0..1, state = { speed, power, vx, vy } }
-- (speed01/power01 sit at the top level because the sound sets read
-- currentInfo.customState[<name>] directly).

local function clamp(x, lo, hi)
	if x < lo then return lo end
	if x > hi then return hi end
	return x
end

local updateFn = function(_captureParams, _params, _transfsOutput)
	-- nothing to animate yet
end

local updateParticleSystemFn = function(_captureParams, params, particleSystem)
	local cs = params.currentInfo.customState
	local st = cs and cs.state
	if st == nil then return end
	local ef = clamp(st.power or 0.5, 0.25, 1.0)
	local velocity = api.type.Vec3f.new(st.vx or 0.0, st.vy or 0.0, 0.0)
	for i = 0, particleSystem:getSize() - 1 do
		particleSystem:setSizeScale01(i, ef, ef)
		particleSystem:setFrequencyScale(i, 1.0)
		particleSystem:setLifeTimeScale(i, ef)
		particleSystem:setVelocity(i, velocity)
	end
end

return {
	ghost = {
		updateFn = updateFn,
		updateParticleSystemFn = updateParticleSystemFn,
	},
}
