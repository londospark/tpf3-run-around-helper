-- Wrappers that let a locomotive's OWN model run as a free entity (the run-around
-- "ghost") with its own sound, smoke and wheel animation.
--
-- The game's sound and transformator scripts for locos read vehicle data
-- (params.currentInfo.vehicle / railVehicle / landVehicle) that a free entity does
-- not have; the sound script then dies with "attempt to index local 'vehicleInfo'
-- (a nil value)". ghost_build.script.lua points every rail loco's sound set and
-- (where it uses the stock train transformator) its transformator at these
-- wrappers at load time. For a real vehicle they call the game's own function
-- unchanged. For a free entity they build the vehicle data from the ghost's
-- custom entity state (speed, distance, direction - sent by the run-around
-- script) and run the game's own function on that, so what plays is exactly what
-- the game would play for a loco moving that way.

local util = ug_require "::/scripts/util.tl"
local transformator_util = ug_require "::/scripts/transformator_util.tl"

local BASE_SOUND = "::/scripts/soundset_default.script@updateSoundSet"
local BASE_TRAIN_UPDATE = "::/vehicle/train/shared/transformator_train.script@train.updateFn"

local baseCache = {}
local function base(ref)
	if baseCache[ref] == nil then baseCache[ref] = util.useFn(ref) end
	return baseCache[ref]
end

-- The loco's paint: the ghost's state carries the colour the real loco had, and it
-- is put on the model instance as the colour attribute (position 0), the way
-- the game's transformators are written to (see the commented-out line in
-- transformator_train.script).
local function applyColor(st, transfsOutput)
	local c = st.color
	if c ~= nil then
		transfsOutput:setModelInstanceAttributeVec3f(transformator_util.colorAttributePostition, api.type.Vec3f.new(c[1] or 0.0, c[2] or 0.0, c[3] or 0.0))
	end
end

local function stateOf(currentInfo)
	local cs = currentInfo.customState
	return cs and cs.state or nil
end

-- A stand-in params table: the same currentInfo with extra vehicle data on top.
local function withInfo(params, extra)
	return {
		currentInfo = setmetatable(extra, { __index = params.currentInfo }),
		previousInfo = params.previousInfo,
		entityId = params.entityId,
	}
end

local function updateSoundSet(captureParams, params, soundTransfOutput)
	local ci = params.currentInfo
	if ci.vehicle ~= nil then
		return base(BASE_SOUND)(captureParams, params, soundTransfOutput)
	end
	local st = stateOf(ci) or {}
	local speed = st.speed or 0.0
	local extra = {
		vehicle = {
			speed = speed,
			speed01 = st.speed01 or (ci.customState and ci.customState.speed01) or 0.0,
			power01 = st.power01 or (ci.customState and ci.customState.power01) or 0.0,
			power = st.power or 0.0,
		},
		railVehicle = {
			chuffStep = 1.5,   -- metres per chuff, chosen so the idle/fast crossfade falls where a ghost runs
			weight = 1.0e6,    -- heavy: full-gain chuffs
			sideForce = 0.0,
			maxSideForce = 1.0,
			brakeDecelSmoothed = 0.0,
			numAxles = 4,
			gameSpeedUp = 1.0,
		},
	}
	return base(BASE_SOUND)(captureParams, withInfo(params, extra), soundTransfOutput)
end

-- Rail vehicle transformator: the stock one, plus wheels for a free entity.
local function trainUpdateFn(captureParams, params, transfsOutput)
	local ci = params.currentInfo
	if ci.landVehicle ~= nil then
		return base(BASE_TRAIN_UPDATE)(captureParams, params, transfsOutput)
	end
	local st = stateOf(ci)
	if st == nil then return end
	-- The state is only sent now and then, so carry the distance forward from
	-- when it was sent, at the speed it was sent with.
	local dist = st.dist or 0.0
	local now = ci.world and ci.world.gameTime
	if st.t0 ~= nil and now ~= nil then
		dist = dist + (st.speed or 0.0) * math.max(now - st.t0, 0.0) / 1000.0
	end
	applyColor(st, transfsOutput)
	local reversed = (st.dir or 1) < 0
	transformator_util.addDriveAnimationState(dist, reversed, transfsOutput)
	-- radius and duration of the loco's driving wheels are not available to a
	-- script, so these are typical values; the wheels turn at about the right rate.
	transformator_util.addDrivingWheelAnimationState(0.9, dist, 1000.0, reversed, transfsOutput)
end

local function clamp(x, lo, hi)
	if x < lo then return lo end
	if x > hi then return hi end
	return x
end

-- Smoke: the stock function for a vehicle; for a free entity, drift and rate
-- from the ghost's state.
local function trainParticleFn(captureParams, params, particleSystem)
	local ci = params.currentInfo
	if ci.vehicle ~= nil then
		return transformator_util.updateParticleSystemFn(captureParams, params, particleSystem)
	end
	local st = stateOf(ci)
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

function data()
	return {
		sound = { updateSoundSet = updateSoundSet },
		train = { updateFn = trainUpdateFn, updateParticleSystemFn = trainParticleFn },
	}
end
