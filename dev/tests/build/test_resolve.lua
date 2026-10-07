-- ghost_build (load time) and ghost_real (run time) each resolve another mod's
-- transformator; they run in separate scopes, so each has its own copy of the
-- rules. They must agree: whatever ghost_build checked is what ghost_real calls.
local target = function() end
ug_require = function(p)
  if p == "devers_1::/vehicle/train/devers/devers_train.script.lua" then return { any = { updateFn = target } } end
  if p == "::/vehicle/train/shared/x.script.tl" then return { train = { updateFn = target } } end
  if p:find("transformator_util", 1, true) then return setmetatable({}, { __index = function() return function() end end }) end
  error("module not found: " .. p)
end
api = { res = { modelRep = {} }, type = {} }
local B = assert(load(io.open(arg[1]):read("*a") .. "\nreturn {trfFiles=trfFiles, scriptFunction=scriptFunction}", "b"))()
local R = assert(load(io.open(arg[2]):read("*a") .. "\nreturn {trfFiles=trfFiles, scriptFunction=scriptFunction}", "r"))()
local cases = {
  { "devers_1::/vehicle/train/devers/devers_any.trf", "::/vehicle/train/br89/br89.mdl" },
  { "/vehicle/train/shared/own.trf", "mod_a_1::/vehicle/train/a/loco.mdl" },
  { "own.trf", "mod_a_1::/vehicle/train/a/loco.mdl" },
}
for _, c in ipairs(cases) do
  assert(table.concat(B.trfFiles(c[1], c[2]), "|") == table.concat(R.trfFiles(c[1], c[2]), "|"), "same candidate files for " .. c[1])
end
local refs = {
  { "devers_train.script@any.updateFn", "devers_1::/vehicle/train/devers/devers_any.trf.lua" },
  { "/vehicle/train/shared/x.script@train.updateFn", "mod_a_1::/vehicle/train/a/own.trf.lua" },
}
for _, c in ipairs(refs) do
  local fb, fr = B.scriptFunction(c[1], c[2]), R.scriptFunction(c[1], c[2])
  assert(fb == target and fr == target, "both find " .. c[1])
end
assert(B.scriptFunction("nope.script@x.y", "devers_1::/a/b.trf.lua") == nil and R.scriptFunction("nope.script@x.y", "devers_1::/a/b.trf.lua") == nil, "neither invents one")
print("resolve: load-time check and run-time call agree")
