-- Wrappers that let a locomotive's own model run as a free entity - the run-around
-- "ghost" - with its own sound, smoke, wheel animation and paint.
--
-- The game's sound and transformator scripts for locos read vehicle data
-- (currentInfo.vehicle / railVehicle / landVehicle) that a free entity does not
-- have. ghost_build.script.lua points each loco's sound set (a wrapped copy in
-- res/audio/ghostwrap/) and transformator (res/models/runaround_ghost/real*.trf)
-- at the functions here at load time.
--
--   * For a real train they do exactly what the game's own functions do.
--   * For a free entity they read the ghost's custom entity state, sent by the
--     run-around script:
--         { speed01, power01,                       (top level: read by sound sets)
--           state = { speed, power, vx, vy, color, dir, seg = {...} } }
--     and feed the game's own sound function synthesised vehicle data, drive the
--     wheel animation, set the smoke and put the loco's paint on.
--
-- Scripts are called directly (ug_require of the module), not through util.useFn:
-- in the transformator scope useFn fails ("attempt to index global 'loaderHelper'
-- (a boolean value)", seen live on every train).

local transformator_util = ug_require "::/scripts/transformator_util.tl"

local okSound, soundModule = pcall(ug_require, "::/scripts/soundset_default.script.tl")
local baseUpdateSoundSet = okSound and type(soundModule) == "table" and soundModule.updateSoundSet or nil
if baseUpdateSoundSet == nil then
	-- The sound scope does have a working util.useFn (the game's own sound script uses it).
	local okUtil, util = pcall(ug_require, "::/scripts/util.tl")
	if okUtil and type(util) == "table" then
		baseUpdateSoundSet = function(...)
			return util.useFn("::/scripts/soundset_default.script@updateSoundSet")(...)
		end
	end
end

-- Wheel animation ("wheels", steam locos): one revolution is 5000 ms of animation
-- time in every base-game steam loco (ani/wheels/*.ani). The driving wheel radius is
-- not available to a script, so a typical one is used.
local WHEEL_RADIUS = 0.9
local WHEEL_ANIMATION_MS = 5000

local function stateOf(currentInfo)
	local cs = currentInfo.customState
	return cs and cs.state or nil
end

-- Distance the ghost has travelled, from its current motion segment
-- (seg = { d0, v0, acc, vmax, t0 }): accelerating from v0 at acc up to vmax, or
-- braking at a negative acc down to a stop, starting at game time t0 (ms) with
-- distance d0. Worked out from the clock on every call, so the wheels turn
-- smoothly between the ghost's state updates; the segment only changes when the
-- motion does (start, stop, reversal, final approach).
local function segmentDistance(st, now)
	local seg = st.seg
	if seg == nil or seg.t0 == nil or now == nil then return st.dist or 0.0 end
	local t = math.max(now - seg.t0, 0.0) / 1000.0
	local d0, v0, a, vmax = seg.d0 or 0.0, seg.v0 or 0.0, seg.acc or 0.0, seg.vmax or 0.0
	if a > 0 then
		local tAcc = math.max((vmax - v0) / a, 0.0)
		if t <= tAcc then return d0 + v0 * t + 0.5 * a * t * t end
		return d0 + v0 * tAcc + 0.5 * a * tAcc * tAcc + vmax * (t - tAcc)
	elseif a < 0 then
		local tStop = v0 / -a
		if t > tStop then t = tStop end
		return d0 + v0 * t + 0.5 * a * t * t
	end
	return d0 + v0 * t
end

local function applyColor(st, transfsOutput)
	local c = st.color
	if c ~= nil then
		transfsOutput:setModelInstanceAttributeVec3f(transformator_util.colorAttributePostition,
			api.type.Vec3f.new(c[1] or 0.0, c[2] or 0.0, c[3] or 0.0))
	end
end

-- Free entity: paint, drive and wheel animation from the ghost's state.
local function ghostUpdate(params, transfsOutput)
	local ci = params.currentInfo
	local st = stateOf(ci)
	if st == nil then return end
	applyColor(st, transfsOutput)
	local dist = segmentDistance(st, ci.world and ci.world.gameTime)
	local reversed = (st.dir or 1) < 0
	transformator_util.addDriveAnimationState(dist, reversed, transfsOutput)
	-- The frame keeps increasing (the animation loops by itself); wrapping it to one
	-- turn made the renderer blend backwards through a whole turn at every wrap.
	local frame = math.floor(dist / (2.0 * math.pi * WHEEL_RADIUS) * WHEEL_ANIMATION_MS + 0.5)
	transfsOutput:addAnimationState("wheels", -1, frame, true, reversed)
end

-- The stock train transformator (vehicle/train/shared/transformator_train.script.tl),
-- copied so that real trains do not depend on calling another script.
local function stockTrainUpdate(params, transfsOutput)
	local ci = params.currentInfo
	local lv = ci.landVehicle
	local time = transformator_util.getEntityTime(ci.world.gameTime, params.entityId)
	transformator_util.addAnimationStatesRailVehicles(lv.side, lv.reversed, transfsOutput)
	transformator_util.addDriveAnimationState(lv.wheelAnimationInfo.totalDist, lv.reversed, transfsOutput)
	transformator_util.addDrivingWheelAnimationState(lv.wheelAnimationInfo.drivingWheelRadius,
		lv.wheelAnimationInfo.totalDist, lv.wheelAnimationInfo.wheelDuration, lv.reversed, transfsOutput)
	transformator_util.addDoorAnimationState(ci.vehicle.doorAnimationInfo, transfsOutput)
	transformator_util.addBrakeLightsAnimationState(lv.brakingTimer, time, transfsOutput)
	transformator_util.scaleUserTransfIndicesLoadConfig(ci.vehicle.indicesLoadConfig, transfsOutput)
end

local function trainUpdateFn(_captureParams, params, transfsOutput)
	if params.currentInfo.landVehicle ~= nil then
		return stockTrainUpdate(params, transfsOutput)
	end
	return ghostUpdate(params, transfsOutput)
end

-- The stock tilting-train transformator (transformator_tiltingTrain.script.tl).
local function tiltingTrainUpdateFn(_captureParams, params, transfsOutput)
	if params.currentInfo.landVehicle == nil then
		return ghostUpdate(params, transfsOutput)
	end
	stockTrainUpdate(params, transfsOutput)
	local ci = params.currentInfo
	local tilt = transformator_util.calculateTilt(params.landVehicleApi, ci.vehicle.speed, 80.0, ci.landVehicle.reversed)
	transfsOutput:addAnimationState("tilt", -1, tilt * 5000, false, false) -- 5000: length of tilt.ani
end

local function clamp(x, lo, hi)
	if x < lo then return lo end
	if x > hi then return hi end
	return x
end

-- Smoke: the stock function for a vehicle; for a free entity, drift and size from
-- the ghost's state.
local function particleFn(captureParams, params, particleSystem)
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

-- A stand-in params table: the same currentInfo with vehicle data on top.
local function withInfo(params, extra)
	return {
		currentInfo = setmetatable(extra, { __index = params.currentInfo }),
		previousInfo = params.previousInfo,
		entityId = params.entityId,
	}
end

-- Sound: the game's own function; for a free entity it gets vehicle data built
-- from the ghost's state, so the loco sounds as a real one moving that way would.
local function updateSoundSet(captureParams, params, soundTransfOutput)
	local ci = params.currentInfo
	if ci.vehicle ~= nil then
		return baseUpdateSoundSet(captureParams, params, soundTransfOutput)
	end
	local cs = ci.customState
	local st = stateOf(ci) or {}
	local extra = {
		vehicle = {
			speed = st.speed or 0.0,
			speed01 = (cs and cs.speed01) or 0.0,
			power01 = (cs and cs.power01) or 0.0,
			power = st.power or 0.0,
		},
		railVehicle = {
			chuffStep = 1.5, -- metres per chuff: puts the steam idle/fast crossfade where a ghost runs
			weight = 1.0e6,  -- heavy, so the chuffs play at full gain
			sideForce = 0.0,
			maxSideForce = 1.0,
			brakeDecelSmoothed = 0.0,
			numAxles = 4,
			gameSpeedUp = 1.0,
		},
	}
	return baseUpdateSoundSet(captureParams, withInfo(params, extra), soundTransfOutput)
end

function data()
	return {
		sound = { updateSoundSet = updateSoundSet },
		train = { updateFn = trainUpdateFn, updateParticleSystemFn = particleFn },
		tiltingTrain = { updateFn = tiltingTrainUpdateFn, updateParticleSystemFn = particleFn },
	}
end
