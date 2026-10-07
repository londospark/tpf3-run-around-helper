# Code review — Runaround Railways 0.1.0-alpha

Reviewed: every script in the mod (`res/scripts/runaround.script.lua`,
`runaround_gui.script.lua`, `ghost_real.script.lua`, `ghost_build.script.lua`,
the `.gs.lua`/`.res.lua`/`.trf.lua` descriptors), at commit `5c10bed`, on
2026-10-07. Line numbers refer to that commit.

Each finding says how it was established: **reproduced** (shown with the offline
mock), **checked** (against game files), or **by reading** (traced through the
code, not yet run).

Nothing here has been fixed yet. The run-around works end to end live; most of
the findings are about what happens when something goes wrong.

---

## High: failure paths can leave a train broken

### H1. Coach copies are left behind when a run doesn't start — reproduced

`startRunAround` (`runaround.script.lua:2106-2145`) shows the coach copies
first, then sends the detach. If the detach is refused (`sendReplace`, line
2125), or the loco copy can't be created (line 2134), the train is released but
the coach copies are never destroyed. They stay in the world as free entities,
probably for good.

Reproduced with the start-up mock (detach callback reporting failure):
`3 coach ghosts created, 0 destroyed, runs started: 0`.

`finishRun` (line 1662) has the same gap: if the train has been sold or deleted
mid-run, only the loco copy is destroyed.

**Fix:** one `destroyCoachGhosts(rakeInfo)` helper, called on every failure path
and in `finishRun` when the train is gone.

### H2. A failed loco copy in ghost-rake mode leaves the coaches invisible — by reading

When the loco copy can't be created (line 2134), the loco is put back with
`buildConfigWithLocoReattached(..., false, standId)`, with no `origRev`. In
ghost-rake mode the train at that point is the *hidden* rake: the coaches are in
reverse order, turned, and painted the hide colour. That restore keeps all of
that. The train leaves with coaches that are invisible (or teal, if the mod is
later removed), back to front, and with their own paint lost.

**Fix:** in ghost-rake mode, restore with `buildRealRakeConfig(..., flipped = false)`,
which already puts the coaches back in order with their paint.

### H3. A failed recouple leaves the train running on the stand-in — by reading

If the final replace is refused (`recoupleRake`, lines 1924-1934, and `recouple`,
1412-1430), the train is released as it is: a 1 kW invisible stand-in pulling
(in ghost-rake mode) hidden, hide-coloured coaches. The loco copy is left
standing where it stopped. This is deliberate ("the ghost is the only copy of the
loco"), but the train is effectively broken and the player has no way to recover
it.

**Fix:** retry the replace a few times. If it still fails, keep the train held
and say so on the run-around card, rather than releasing a broken train.

### H4. No watchdog: a stalled run holds the train for ever — by reading

Every stage waits for a command callback (`busy` flags in `advanceRake` and
`advanceLayout`, `flipSent`, the settle tick counts). If a callback never arrives,
or a stage never reaches its exit condition, the train stays held (manual
departure plus stopped-by-user) indefinitely, and nothing tells the player.
Examples: a vehicle deleted while `busy`, or a route the ghost can't finish.

**Fix:** record a start time per run. After a generous limit (for example
route length ÷ speed × 3 + 60 s), put the real train back with
`buildRealRakeConfig` or the plain restore, destroy every copy and release the
train, with a log line.

---

## Medium

### M1. Models are identified by file name only — by reading; checked for base game

`ghost_build.script.lua` names its markers and copies
`runaround_ghost_real/<file>.mdl` and `runaround_ghost_dyn/<file>.mdl`, using
the model's file name without its folder. `addGhostModel` returns early when that
name already exists (line 132). `realModelReady` and `findGhostModelId` look
models up by the same file name.

Two mods that both ship, say, `.../foo/loco.mdl` collide. Whichever loads second
gets no copy of its own, and the marker can say "ready" for a model that was
never patched. Using an unpatched model as a free entity is the
`attempt to index local 'vehicleInfo'` error, raised every frame.

The base game and DLC have no duplicate vehicle file names (checked), so this
only happens with mods.

**Fix:** key the markers and copies by the full model path (escaped), or by a
hash of it.

### M2. The mod replaces every rail vehicle's scripts — by reading

At load, every loco, coach and wagon is pointed at the mod's transformator and
sound wrappers (`ghost_build`, `patchLoco`). Three consequences:

- A bug in `ghost_real.script.lua` affects every train in the game, not only
  ones running around.
- `stockTrainUpdate` and the 15 files in `res/audio/ghostwrap/` are copies of
  the game's own. When Urban Games changes those, the copies go out of date
  silently. Regenerate them after game updates: see `dev/tools/gen_snd.py`.
- Another mod that also changes vehicle transformators or sound sets conflicts
  with this one; whichever loads last wins.

`PATCH_LOCOS = false` turns the patching off.

### M3. The mod ID is hard-coded in generated files — by reading

`res/models/runaround_ghost/real*.trf.lua` and all 15 `ghostwrap/*.snd.lua`
reference `runaround_helper_1::/res/scripts/ghost_real.script@...`. If a mod.io
install ends up with a different mod ID or folder, every patched vehicle's
transformator and sound script fails to resolve, which would affect every train.
`ghost_build` already works out its own ID with `getCurrentModId()`, but these
files can't. Check this on the first mod.io install, before announcing it.

### M4. Coach copies don't turn on curves — by reading

The copies are placed with `rotZTransl(c.start.yaw, ...)` throughout
(lines 1857-1859, 2117). On a curved platform the train draws forward along the
curve, but each copy keeps its starting angle. Afterwards the copies sit at a
slightly different angle from the hidden real coaches beneath them, so any
bogie that still shows won't line up.

The copies also move along the straight line between start and target, while
the loco copy follows the track. On a tight curve the coupled train therefore
separates a little during the pull.

**Fix:** interpolate the angle from `c.start.yaw` to `c.target.yaw` (the shortest
way round) together with the position.

### M5. Copies aren't checked against the coaches they're matched to — by reading

`advanceRake`'s settle step (lines 1816-1828) pairs copies with hidden coaches by
distance from the loco's old position. It only checks that the counts match. A
`coachFrames[i].modelId == c.snap.modelId` check would catch a mismatch (for
example from a wrong assumption about the flip) and fail safely, instead of
loading a wagon's load onto the wrong copy.

### M6. Hiding relies on an undocumented field — by reading

`ghost_real.script.lua`'s `isHidden` reads `currentInfo.vehicle.color`.
`VehicleScriptingInfo` in the game's type definitions has no `color` field. It
works live (coach bodies did vanish), but it could disappear in a game update.
`hiddenLoads` is also never cleared, which is small but grows over a long session.

### M7. Saving, or removing the mod, mid-run — by reading

Runs are kept in the script state, so they continue after a reload. Whether the
game saves the free entities (the copies) is unknown. If the mod is removed while
a run is in progress, the train is left with the stand-in and with coaches
painted the hide colour, which shows as teal because the hiding wrapper is gone.
Untested.

### M8. Only a loco at the front of the train gets the smooth sequence — by reading

The ghost rake and the creep both require `locoIdx == 1`. A loco elsewhere (for
example, propelling from the rear, or chosen manually) falls back to the old
method, where the coaches jump at the flip. The README doesn't say this.

---

## Low

- **Leftover code.** `AddLoopFromVehicle`, `AddLoopEdgeFromVehicle` and
  `readVehicleCurrentEdge` (lines 2235-2307, 2313-2339, 2389-2404) are never sent
  by the current GUI. `noDepartNow` (line 1404) is never set any more.
  `buildConfigWithStandIn`'s `addTail` is always false.
- **Out-of-date comments.**
  - The header (steps 3-4) describes the old glide.
  - `creepLayout` says "1 m steps"; the step is 0.25 m.
  - `carriageLength` says metadata can't be read here; `modelLength` now reads
    it.
- **`isStandIn`** scans all 176 stand-in IDs on every call, and it's called in
  loops. Invert the map once.
- **Route planning cost.** A click with no direct route can mean up to
  100 candidates × 2 pathfinder calls, per leg and direction pair, with
  `estimateEdgeLength` recomputed each time. On a dense network this may cause a
  hitch on click. Cache the edge lengths.
- **Run-around card.** The pull and uncouple stages show as "Running around",
  and the progress bar counts the pull distance as route distance.
- **`LOG_TRACES = true`** by default is useful during the alpha but noisy;
  turn it off for a non-alpha release.
- **Light engine.** A train that's only a loco "runs around" nothing, through the
  plain path. Harmless, but pointless: skip it.

---

## What's solid

- The engine rules the mod depends on are written down where they're used and
  were traced live: replace keeps the middle fixed, flip mirrors, positions lag,
  a flip releases the hold.
- Everything that can fail before the train is held is prepared first
  (`startRunAround`, "can't leave it stuck at the station").
- Vehicle configs are always built from real game objects, with load configs
  matched to each model's compartments, which avoids the asserts the game
  enforces.
- Facing comes from start geometry, not from carriage positions, which lag after
  a flip.
- The offline suite (`dev/run_tests.sh`) covers planning, detach, creep, the
  ghost rake (start, pull, uncouple, recouple), facing, wheels, hiding and the
  GUI, plus a check for stray global reads (the class of bug that crashed live).

## Suggested order

1. H1-H4. These are all failure handling and can share one helper, "put the real
   train back and clear every copy".
2. M3, before publishing on mod.io.
3. M1 and M4.
4. The low items as tidying.
