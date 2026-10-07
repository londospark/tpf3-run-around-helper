-- The creep sequence: symmetrical at the flip, one stand-in of the full length at the end, total length constant.
math.atan2 = math.atan2 or math.atan
api = {}
local M = assert(load(io.open(arg[1]):read("*a").."\nreturn {adv=advanceLayout, CONFIG=CONFIG}","s"))()
local run = { gdist = 0, layout = { len = 12.5, a = 12.5, b = 0, stage = "waiting", timer = 0, busy = false } }
local seq, flipAt = {}, nil
for i = 1, 4000 do
  run.gdist = i
  if M.adv(run, 0.1) then
    local L = run.layout
    if L.action == "flip" then flipAt = { L.a, L.b }; L.stage = "B" else seq[#seq + 1] = L.a .. "+" .. L.b end
    assert(math.abs(L.a + L.b - 12.5) < 1e-9, "constant length")
    L.busy = false
  end
end
print("steps:", #seq, "first", seq[1], "last", seq[#seq], "| flip at", flipAt[1], flipAt[2], "| final stage", run.layout.stage)
assert(math.abs(flipAt[1] - 6.25) < 1e-9 and math.abs(flipAt[2] - 6.25) < 1e-9 and run.layout.stage == "done" and math.abs(run.layout.a - 12.5) < 1e-9 and run.layout.b < 1e-9 and #seq == 50)
print("creep ok")
