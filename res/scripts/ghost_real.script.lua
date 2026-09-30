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

local transformator_util = ug_require "::/scripts/transformator_util.tl"

-- The game's own sound update script, called directly (a module that returns its
-- functions). NOT through util.useFn: in the transformator scope that fails with
-- "attempt to index global 'loaderHelper' (a boolean value)" (seen live, on every
-- real train).
local okSound, soundModule = pcall(ug_require, "::/scripts/soundset_default.script.tl")
local baseUpdateSoundSet = okSound and type(soundModule) == "table" and soundModule.updateSoundSet or nil
local okUtil, util = pcall(ug_require, "::/scripts/util.tl")
if baseUpdateSoundSet == nil and okUtil and type(util) == "table" then
	-- the sound scope does have a working util.useFn (the game's own script uses it)
	baseUpdateSoundSet = function(...)
		return util.useFn("::/scripts/soundset_default.script@updateSoundSet")(...)
	end
end

-- The stock train transformator's update, copied from
-- vehicle/train/shared/transformator_train.script.tl so that real trains don't
-- depend on calling another script.
local function stockTrainUpdate(_captureParams, params, transfsOutput)
	local ci = params.currentInfo
	local time = transformator_util.getEntityTime(ci.world.gameTime, params.entityId)
	transformator_util.addAnimationStatesRailVehicles(ci.landVehicle.side, ci.landVehicle.reversed, transfsOutput)
	transformator_util.addDriveAnimationState(ci.landVehicle.wheelAnimationInfo.totalDist, ci.landVehicle.reversed, transfsOutput)
	transformator_util.addDrivingWheelAnimationState(
		ci.landVehicle.wheelAnimationInfo.drivingWheelRadius,
		ci.landVehicle.wheelAnimationInfo.totalDist,
		ci.landVehicle.wheelAnimationInfo.wheelDuration,
		ci.landVehicle.reversed,
		transfsOutput)
	transformator_util.addDoorAnimationState(ci.vehicle.doorAnimationInfo, transfsOutput)
	transformator_util.addBrakeLightsAnimationState(ci.landVehicle.brakingTimer, time, transfsOutput)
	transformator_util.scaleUserTransfIndicesLoadConfig(ci.vehicle.indicesLoadConfig, transfsOutput)
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

local WHEEL_RADIUS = 2.5 -- metres. A real driving wheel is about 0.9, but a script only sees the game time in whole simulation ticks, and at the true rate the wheel jumps a large part of a turn each tick (jerky); this turns them at about a third of the true rate
local WHEEL_ANIMATION_MS = 5000 -- one revolution of the wheel animation

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
		return baseUpdateSoundSet(captureParams, params, soundTransfOutput)
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
	return baseUpdateSoundSet(captureParams, withInfo(params, extra), soundTransfOutput)
end

-- Rail vehicle transformator: the stock one, plus wheels for a free entity.
local function trainUpdateFn(captureParams, params, transfsOutput)
	local ci = params.currentInfo
	if ci.landVehicle ~= nil then
		return stockTrainUpdate(captureParams, params, transfsOutput)
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
	-- The wheels' animation ("wheels", steam locos) is one revolution in 5000 ms of
	-- animation time for every base-game steam loco (ani/wheels/*.ani), and the
	-- frame is given directly in milliseconds. The driving wheel radius is not
	-- available to a script, so a typical one is used: the wheels turn at about the
	-- rate of the ground speed. (The game's own helper rounds this to whole
	-- seconds, which for a ghost hides the motion.)
	local rev = dist / (2.0 * math.pi * WHEEL_RADIUS)
	local frame = math.floor((rev % 1.0) * WHEEL_ANIMATION_MS + 0.5)
	transfsOutput:addAnimationState("wheels", -1, frame, true, reversed)
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
