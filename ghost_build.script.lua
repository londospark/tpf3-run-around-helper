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
		local dir = string.match(resolved, "^(.*/)[^/]*$")
		local converted = convertSoundSet(api.res.soundSetRep.getAsTable(id), dir)
		if converted == nil then error("nothing to convert") end
		local name = "runaround_ghost_sound/" .. string.gsub(soundSetName, "[^%w_%.]", "_")
		if api.res.soundSetRep.find(name) < 0 then
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

local function build(modelId, modelName, trfName)
	local ok, src = pcall(api.res.modelRep.getAsTable, modelId)
	if not ok or type(src) ~= "table" or not isRailEngine(src.metadata) then return false end
	local file = string.match(modelName, "([^/]+)%.mdl$")
	if file == nil or string.find(modelName, "runaround_", 1, true) then return false end
	local ghostName = "runaround_ghost_dyn/" .. file .. ".mdl"
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
	for id, name in pairs(all) do
		if type(name) == "string" then
			tried = tried + 1
			local ok, res = pcall(build, id, name, trfName)
			if ok and res then built = built + 1 end
		end
	end
	log("ghost models: built effects ghosts for", built, "of", tried, "models")
end

return mod
