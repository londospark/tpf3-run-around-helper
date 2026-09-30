-- Load-time script (mod.json postRunScript): builds an "effects ghost" for every
-- rail locomotive model the game knows about, INCLUDING modded ones, by reading
-- each loco's own model metadata rather than from a fixed list.
--
-- The ghost is a new model that reuses the loco's meshes (modelPath) but carries
-- none of its vehicle metadata. It keeps the loco's particle emitters (smoke,
-- steam) and a converted copy of its sound set, and gets a small transformator
-- (res/models/runaround_ghost/ghost.trf.lua) that feeds them from the ghost's
-- own custom entity state (speed) instead of from vehicle data, which a free
-- entity doesn't have. This is the way the base game's fireworks, which are free
-- entities with their own particles and sound, are built.
--
-- Everything here is wrapped in pcall: if the game rejects any part of it, that
-- loco simply has no effects ghost and the run-around falls back to the plain
-- (silent, smokeless) ghost models shipped in res/models/runaround_ghost/.

local mod = {}

local function log(...)
	print("[RunAroundHelper]", ...)
end

local MOD_ID = "runaround_helper_1"
-- Point every loco's sound set and transformator at wrappers so the loco's OWN model
-- can be the run-around ghost (see patchRealModelSupport). Set false to leave the
-- game's sound sets and models untouched (then only the ghost copies work).
local PATCH_FOR_REAL_MODEL = true
local STATE_KEY = "customState" -- where a free entity's state shows up in currentInfo
local ALLOWED_PARAMS = { speed01 = true, power01 = true, speed = true, power = true }

local function clone(v)
	if type(v) ~= "table" then return v end
	local o = {}
	for k, x in pairs(v) do o[k] = clone(x) end
	return o
end

-- A sound function's parameter table with its data source pointed at the ghost's
-- state; nil if it needs something a ghost cannot provide.
local function convertSampleParams(p)
	if type(p) ~= "table" then return {} end
	local out = clone(p)
	for _, which in ipairs({ "gain", "pitch" }) do
		local keyField, nameField = which .. "ScriptingInfoKey", which .. "ParamName"
		if out[keyField] ~= nil then
			if out[keyField] ~= "vehicle" or not ALLOWED_PARAMS[out[nameField] or ""] then
				return nil
			end
			out[keyField] = STATE_KEY
		end
	end
	return out
end

local function sampleFn(gainCurve, pitchCurve, gainParam)
	return {
		type = "SampleCurve",
		params = {
			gainCurve = gainCurve,
			pitchCurve = pitchCurve,
			gainScriptingInfoKey = STATE_KEY,
			gainParamName = gainParam or "speed01",
			pitchScriptingInfoKey = STATE_KEY,
			pitchParamName = "speed01",
		},
	}
end

-- Converted copy of a sound set, or nil. Keeps every continuous track that can
-- be driven by speed/power; drops one-shot events (horn, clacks, chuffs) and the
-- squeal/brake tracks, which need vehicle data. A steam set's idle and fast
-- tracks (produced by its "Chuffs" function) become two speed-driven tracks.
local function convertSoundSet(t, dir)
	local uf = t.updateScript and t.updateScript.params and t.updateScript.params.updateFunctions
	if type(uf) ~= "table" or type(t.tracks) ~= "table" then return nil end
	local out = {
		tracks = {},
		events = {},
		attrs = t.attrs,
		updateScript = {
			fileName = t.updateScript.fileName,
			params = { updateFunctions = {} },
		},
	}
	local function add(track, fn)
		local c = clone(track)
		-- Track names are relative to the sound set's own folder; a set added
		-- at run time has no folder, so make them absolute.
		if dir ~= nil and type(c.name) == "string" and not string.find(c.name, "::", 1, true) and string.sub(c.name, 1, 1) ~= "/" then
			c.name = dir .. c.name
		end
		out.tracks[#out.tracks + 1] = c
		out.updateScript.params.updateFunctions[#out.updateScript.params.updateFunctions + 1] = fn
	end
	local ti = 1
	for _, f in ipairs(uf) do
		if f.type == "Chuffs" then
			local idle, fast = t.tracks[ti], t.tracks[ti + 1]
			ti = ti + 2
			if idle then add(idle, sampleFn({ { 0.0, 1.0 }, { 0.35, 0.8 }, { 0.6, 0.2 }, { 1.0, 0.0 } }, { { 0.0, 0.9 }, { 1.0, 1.1 } })) end
			if fast then add(fast, sampleFn({ { 0.25, 0.0 }, { 0.6, 1.0 }, { 1.0, 1.0 } }, { { 0.0, 1.0 }, { 1.0, 1.2 } })) end
		elseif f.eventKey ~= nil then
			-- a one-shot event: dropped
		else
			local track = t.tracks[ti]
			ti = ti + 1
			if track ~= nil and (f.type == "SampleCurve" or f.type == "Custom") then
				local params = f.type == "Custom" and (f.params and f.params.customParams) or f.params
				local converted = convertSampleParams(params)
				if converted ~= nil then add(track, { type = "SampleCurve", params = converted }) end
			end
		end
	end
	if #out.tracks == 0 then return nil end
	return out
end

local soundCache = {}

local function ghostSoundSetName(soundSetName, prefix)
	if soundSetName == nil then return nil end
	if soundCache[soundSetName] ~= nil then return soundCache[soundSetName] or nil end
	local newName = nil
	local ok, err = pcall(function()
		-- The name in a model's metadata may be relative to the package that
		-- declared it ("/vehicle/..." inside the base game or inside a mod), so
		-- try it as written and then with the model's own package prefix.
		local candidates = { soundSetName }
		if string.sub(soundSetName, 1, 1) == "/" then candidates[#candidates + 1] = (prefix or "") .. "::" .. soundSetName end
		local id, resolved = -1, nil
		for _, c in ipairs(candidates) do
			local found = api.res.soundSetRep.find(c)
			if found ~= nil and found >= 0 then id, resolved = found, c break end
		end
		if resolved == nil then error("sound set not found") end
		local dir = string.match(resolved, "^(.*/)[^/]*$") or ""
		local file = string.match(resolved, "([^/]+)$") or "set.snd"
		local original = api.res.soundSetRep.getAsTable(id)
		-- The new set goes in the SAME folder as the original, because a set's
		-- track names are relative to the folder its own file is in (adding it
		-- elsewhere failed with std::exception, the game not finding the sound files).
		local name = dir .. "runaround_ghost_" .. file
		if api.res.soundSetRep.find(name) < 0 then
			local converted = convertSoundSet(original, nil)
			if converted == nil then error("nothing to convert") end
			api.res.soundSetRep.addAsTable(name, converted)
		end
		newName = name
	end)
	if not ok then log("ghost sound: none for", soundSetName, "-", tostring(err)) end
	soundCache[soundSetName] = newName or false
	return newName
end

local function isRailEngine(meta)
	local tv = meta and meta.transportVehicle
	local lv = meta and meta.landVehicle
	return tv ~= nil and tv.carrier == "RAIL" and lv ~= nil and lv.engines ~= nil and #lv.engines > 0
end

local function build(modelId, modelName, trfName, namePrefix)
	local ok, src = pcall(api.res.modelRep.getAsTable, modelId)
	if not ok or type(src) ~= "table" or not isRailEngine(src.metadata) then return false end
	local file = string.match(modelName, "([^/]+)%.mdl$")
	if file == nil or string.find(modelName, "runaround_", 1, true) then return false end
	local ghostName = (namePrefix or "runaround_ghost_dyn/") .. file .. ".mdl"
	if api.res.modelRep.find(ghostName) >= 0 then return true end

	local meta = src.metadata
	local md = {
		transformatorConfig = {
			skipFromLod = -1,
			transformator = { name = trfName },
		},
	}
	if meta.particleSystem ~= nil then md.particleSystem = clone(meta.particleSystem) end
	local soundName = meta.soundConfig and meta.soundConfig.soundSet and meta.soundConfig.soundSet.name
	local ghostSound = ghostSoundSetName(soundName, string.match(modelName, "^(.-)::") or "")
	if ghostSound ~= nil then md.soundConfig = { soundSet = { name = ghostSound } } end

	local okAdd, res = pcall(api.res.modelRep.addAsTable, ghostName, {
		metadata = md,
		boundingInfo = src.boundingInfo,
		collider = src.collider,
		modelPath = modelName,
	})
	if not okAdd then
		log("ghost model: could not add", ghostName, "-", tostring(res))
		return false
	end
	return true
end

-- ---------------------------------------------------------------------
-- Support for drawing the ghost from the loco's OWN model (no ghost copy). The
-- loco's sound set and transformator are pointed at wrappers (res/scripts/
-- ghost_real.script.lua) that behave exactly as before for a real vehicle and
-- work from the ghost's custom entity state for a free entity.
-- ---------------------------------------------------------------------
local BASE_SOUND_UPDATE = "::/scripts/soundset_default.script@updateSoundSet"
local patchedSoundSets = {}
local realReady = {} -- model id -> true when the loco can be its own ghost
local patchStats = { sounds = 0, soundFailed = 0, trfs = 0, trfFailed = 0, skipped = 0 }

local skipLogs = 0
local function skipLog(...)
	skipLogs = skipLogs + 1
	if skipLogs <= 6 then log("real-model support:", ...) end
	patchStats.skipped = patchStats.skipped + 1
end

local function patchSoundSet(soundSetName, prefix, wrapperRef)
	if soundSetName == nil then return end
	if patchedSoundSets[soundSetName] ~= nil then return end
	patchedSoundSets[soundSetName] = false
	local candidates = { soundSetName }
	if string.sub(soundSetName, 1, 1) == "/" then candidates[#candidates + 1] = (prefix or "") .. "::" .. soundSetName end
	local id
	for _, c in ipairs(candidates) do
		local found = api.res.soundSetRep.find(c)
		if found ~= nil and found >= 0 then id = found break end
	end
	if id == nil then skipLog("sound set not found:", soundSetName, "(tried", table.concat(candidates, ", ") .. ")") return end
	local t = api.res.soundSetRep.getAsTable(id)
	local us = t.updateScript
	if type(us) ~= "table" or type(us.fileName) ~= "string" then skipLog("sound set", soundSetName, "has no readable update script:", type(us)) return end
	if us.fileName ~= BASE_SOUND_UPDATE then skipLog("sound set", soundSetName, "has its own update script:", us.fileName) return end -- left alone
	us.fileName = wrapperRef
	local ok, res = pcall(api.res.soundSetRep.setAsTable, id, t)
	if ok and res ~= false then
		patchedSoundSets[soundSetName] = true
		patchStats.sounds = patchStats.sounds + 1
	else
		patchStats.soundFailed = patchStats.soundFailed + 1
		if patchStats.soundFailed <= 3 then log("real-model support: could not patch sound set", soundSetName, "-", tostring(ok and res or res)) end
	end
end

local function patchModelTransformator(modelId, src, realTrf)
	local md = src.metadata
	local name = md.transformatorConfig and md.transformatorConfig.transformator and md.transformatorConfig.transformator.name
	if type(name) ~= "string" or not string.find(name, "default_train.trf", 1, true) then
		skipLog("model", modelId, "has its own transformator:", tostring(name))
		return false
	end
	md.transformatorConfig.transformator.name = realTrf
	local ok, res = pcall(api.res.modelRep.setAsTable, modelId, src)
	if ok and res ~= false then
		patchStats.trfs = patchStats.trfs + 1
		return true
	else
		patchStats.trfFailed = patchStats.trfFailed + 1
		if patchStats.trfFailed <= 3 then log("real-model support: could not patch the transformator of", modelId, "-", tostring(res)) end
	end
	return false
end

local function patchRealModelSupport(modId, all)
	local soundWrapper = modId .. "::/res/scripts/ghost_real.script@sound.updateSoundSet"
	local realTrf = modId .. "::/res/models/runaround_ghost/real.trf"
	for id, name in pairs(all) do
		if type(name) == "string" and not string.find(name, "runaround_", 1, true) then
			local ok, src = pcall(api.res.modelRep.getAsTable, id)
			if ok and type(src) == "table" and isRailEngine(src.metadata) then
				local md = src.metadata
				local prefix = string.match(name, "^(.-)::") or ""
				local soundName = md.soundConfig and md.soundConfig.soundSet and md.soundConfig.soundSet.name
				pcall(patchSoundSet, soundName, prefix, soundWrapper)
				local okT, trfDone = pcall(patchModelTransformator, id, src, realTrf)
				-- A loco is ready to be the ghost itself only if its transformator and (if it
				-- has one) its sound set both went through the wrappers.
				if okT and trfDone and (soundName == nil or patchedSoundSets[soundName] == true) then realReady[id] = true end
			end
		end
	end
	log(string.format("real-model support: patched %d sound sets and %d loco transformators (%d failed, %d left alone)",
		patchStats.sounds, patchStats.trfs, patchStats.soundFailed + patchStats.trfFailed, patchStats.skipped))
end

mod.postRunFn = function(_configDict, _allModParams)
	local modId = MOD_ID
	if getCurrentModId ~= nil then
		local okId, id = pcall(getCurrentModId)
		if okId and id then modId = id end
	end
	local trfName = modId .. "::/res/models/runaround_ghost/ghost.trf"
	local built, tried = 0, 0
	local okAll, all = pcall(api.res.modelRep.getAll, true)
	if not okAll or all == nil then
		log("ghost models: could not list models -", tostring(all))
		return
	end
	if PATCH_FOR_REAL_MODEL then
		local okP, errP = pcall(patchRealModelSupport, modId, all)
		if not okP then log("real-model support failed:", tostring(errP)) end
	end
	for id, name in pairs(all) do
		if type(name) == "string" then
			tried = tried + 1
			local ok, res = pcall(build, id, name, trfName)
			if ok and res then built = built + 1 end
			-- A marker the run script can see (it cannot read model metadata): this loco
			-- may be used as its own ghost.
			if realReady[id] then pcall(build, id, name, trfName, "runaround_ghost_real/") end
		end
	end
	log("ghost models: built effects ghosts for", built, "of", tried, "models")
end

-- A .script.lua file must define data() and return its functions from it
-- (a plain `return mod` fails with "function data() not defined").
function data()
	return mod
end
