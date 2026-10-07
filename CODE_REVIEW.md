# Code review — Runaround Railways 0.1.0-alpha

Two reviews so far:

- **First review** at `5c10bed`. Its findings and how each was resolved are
  summarised below. The full text is in git history (this file at `4230bc1`).
- **Second review** at `4230bc1` (2026-10-07). It covers every script in the
  mod (`runaround.script.lua` 2655 lines, `runaround_gui.script.lua` 583,
  `ghost_real.script.lua` 264, `ghost_build.script.lua` 225, and the
  `.gs.lua`/`.res.lua`/`.trf.lua` descriptors), checked against the game's files
  and type definitions where possible. Line numbers refer to `4230bc1`.

Each finding says how it was established: **reproduced** (offline mock),
**checked** (against the game's files or type definitions), or **by reading**
(traced through the code, not run).

The run-around works end to end live. The second review found no problems
that break a train. The owner rated N1 and N2 high, since they make a run look
broken in ordinary set-ups. N1-N4 are fixed or made explicit (see each). Its findings are about unusual set-ups (alternative platforms, routes
that start backwards, a mismatched mod ID), robustness against game updates,
and tidiness. It also answers whether the mod should be split up (see
[Structure](#structure-one-file-or-several)).

---

## First review: status

| | Finding | Status |
|---|---|---|
| H1 | Coach copies left behind when a run doesn't start, or the train is deleted | Fixed: `destroyCoachGhosts` on every path (`test_failures.lua`) |
| H2 | Failed loco copy leaves the coaches hidden and back to front | Fixed: a restore run goes through `finishRun` / `buildRealRakeConfig` |
| H3 | Failed recouple releases the train on the stand-in | Fixed: held and retried; "Stuck" on the card |
| H4 | No watchdog for stalled runs | Fixed: `watchdog`, time limit from route length and speed |
| M1 | Markers and copies collide on file name | Fixed: rail vehicles sharing a file name are left alone. Full-path keys were **not** used, because nothing shows `getAll` names match between load and game script |
| M2 | Every rail vehicle's scripts are replaced | Open (design). The copied transformators were **checked** identical to the game's current `transformator_train.script.tl` and `transformator_tiltingTrain.script.tl` |
| M3 | Mod ID hard-coded in generated files | Made safe for trains: `ghost_build` patches nothing under another ID. See N3: the GUI isn't covered |
| M4 | Coach copies don't turn on curves | Fixed: `pullFrame`, Hermite curve (`test_curve.lua`) |
| M5 | Copies not checked against the coaches they're matched to | Open |
| M6 | Hiding relies on the undocumented `vehicle.color` | `hiddenLoads` leak fixed; the field is still relied on |
| M7 | Saving or removing the mod mid-run | Open, untested |
| M8 | Only a loco at the front gets the smooth sequence | Open, documented in the README |
| Low | Leftover code, stale comments, `isStandIn` scan, card stages, light engine, `_content.json` | Fixed |
| Low | Route-planning cost on dense networks; `LOG_TRACES` on by default | Open |

---

## Second review: new findings

### High (raised by the owner: N1, N2) and medium (N3, N4)

#### N1 (high). A train at an alternative platform runs the route from the wrong platform — checked (types), by reading

Line stops can have `alternativeTerminals` (`api/engine.d.tl:533`), and the
game may send a train to any of them. `getStopNode` (line 960) plans the route
from `stop.terminal` only. When a train stops at an alternative platform:

- `locateOnRoute` finds the loco more than 40 m from the route (line 2328). The
  run carries on anyway: "the ghost starts at the route's first piece", on the
  planned platform.
- The loco copy runs the route over there, then `advanceApproach` glides it in a
  straight line across the tracks to the stand-in on the real platform.
- With the ghost rake, the coach copies are pulled on the real platform while
  the loco copy draws forward on the other one.

The train ends up correct, because the recouple uses the real stand-in, but the
run looks broken. The check also happens too late: line 2328 runs inside the
loco-copy callback, after the detach.

**Fix:** call `locateOnRoute` in `startRunAround` before the train is held, as
the other preparation does. If the loco isn't on the route, skip the run with a
log line ("not at the platform the route was planned from"). Optionally, plan
one route per terminal later.

**Fixed:** `checkStartOnRoute` runs in `startRunAround` before the train is
held. The loco must stand within `ON_ROUTE_M` = 2.5 m of the route's first leg,
which is half the game's track spacing (**checked**: `trackDistance = 5` for
all 13 track types in the base game and DLC). On the planned platform it's
about 0 m; on any other platform it's 5 m or more. Otherwise the run is skipped
and the train leaves the normal way. The reason is logged
(`run-around NOT started ...`) and shown on the card ("Last arrival didn't run
around: ..."); the note clears at the next start. This deliberately uses only
position facts already seen live (the `ghost starts on route piece ... m from
...` line), not the untested `arrivalStationTerminal` or `vehicleEdges`.
`test_failures.lua`: 5 m off is refused, 2 m off runs.

#### N2 (high). The pull assumes the route leaves forwards, away from the coaches — by reading

The ghost rake's pull (`advanceGhost` lines 1242-1256 and 1302-1313, `advanceRake` settle)
moves the coach copies towards their targets. The engine fixes that direction:
the turned train's coaches sit a loco length towards where the loco was. The
loco copy, meanwhile, moves `pullLen` along the **route**. Nothing checks that
the route's first move goes the same way. The planner can start in either
direction (`STATES`, `leg0`), so a route that first goes back past the train
would make the loco copy drive into the coach copies during the pull. The
`loco ghost N m from where it would be coupled` line would then read about
2 × `pullLen`. `AGENTS.md` lists this as an assumption; there is no guard.

**Fix:** at settle, compare the route's initial direction at the ghost's start
(`pos` minus the loco position, after its first steps) with the coaches' shift
(`target - start`). If they point opposite ways, skip the pull: set stage
`"done"`, and the copies take their places at the uncouple, the old jump. Log
it.

**Fixed, more broadly than suggested:** the same check also compares the route's
direction where the loco stands (`routeDirectionAt`) with "away from the
coaches" (from the neighbouring carriage to the loco). If the route heads into
the train, the run is skipped, as for N1, with "the route sets off towards the
coaches". This covers every mode, not just the ghost rake's pull: in any mode,
the loco copy would otherwise drive through the coaches. A loco in the middle of
the train (manual choice) has no single "away", so it isn't checked.
`test_failures.lua` covers it.

#### N3. Under another mod ID, the train-window card doesn't load — by reading

M3's fix stops `ghost_build` touching trains when the mod is loaded under an
unexpected ID, and the review said "the run-around still works". Two more
hard-coded references undo part of that claim:

- `runaround_vehicle.res.lua` has `filePath = "runaround_helper_1::/res/scripts/runaround_gui.script@..."`.
  Under another ID the card doesn't load, so no run-around can be set up or
  edited.
- `runaround_gui.script.lua:57` looks the game script up as
  `runaround_helper_1::/res/scripts/runaround.gs` first, though it falls back
  to `"runaround"`.

Existing run-arounds in a save still run. Nothing breaks, but the mod is
unusable for new set-ups. The tests' mod-ID check passes because these use the
same ID; it guards consistency, not this case.

**Fix:** make the `SKIPPED` log line and the README say so: "the run-around card
won't appear". Whether a `.res.lua` `filePath` can be written relatively (like
`runaround.gs.lua`'s `res/scripts/...`) is untested. Try it in a live test
before relying on it.

**Made explicit (can't be fixed without an untested assumption):** every
react-plugin descriptor in the game (44, all base-game, **checked**) names its
owner, and none shows a mod-relative form working. So the card's `filePath`
keeps the ID. The `SKIPPED` log line now says the card won't appear. The README
explains it and lists the GUI's `GUI registered` line as the check that the card
loaded. The stale comment in `runaround_vehicle.res.lua` is rewritten. The real
answer comes from the first mod.io install: subscribe to the upload and look for
`SKIPPED` and `GUI registered`.

#### N4. A missing stock sound function would raise errors on every train — by reading

`ghost_real.script.lua:24-34` looks up the game's `soundset_default.script.tl`,
with `util.useFn` as a fallback. If both fail, `baseUpdateSoundSet` is nil.
`updateSoundSet` (line 234) then calls nil for **every patched vehicle, every
frame**: an error stream and no train sound anywhere. Today the file exists
(**checked**: `base/content/scripts.zip`), so this only matters after a game
update moves or renames it. That is exactly M2's risk, but louder.

**Fix:** if `baseUpdateSoundSet` is nil, return without doing anything (silence)
and print one line at load. Better still, `ghost_build` could check it too and
not patch sound sets at all, but it runs in another scope, so the check would
have to be repeated there.

**Fixed:** the `util.useFn` fallback is used only if `useFn` exists, and if
neither is found, `updateSoundSet` returns at once (silent trains, no errors).
One line is printed at load. `test_hide.lua` loads the script with both
missing; the old script fails it with `attempt to call a nil value (field
'useFn')`.


### Found in the first smoke test (2026-10-07) — high

#### N5. The game reports the train arriving again straight after a run-around — seen live

The log shows `run-around complete`, then, in the same second and with the
train not having moved, `arrival: ... stop= 0` again. Nothing ignored it, so a
second run started on the train that had just been turned. **Fixed:**
`finalizeRun` records the line and stop per vehicle (`data.ranAt`), and
`handleEvent` ignores an arrival there until the train has arrived at another
stop. `test_failures.lua` replays it.

#### N6. The automatic loco choice could pick a coach — seen live

"The part nearest the first route point" took no account of engines. On the
turned train from N5 it picked `streamlined_nyc` (a coach), ran its copy around
the route and coupled it on as the loco. From then on the train was coach-first.
**Fixed:** `isPowered` reads `landVehicle.engines[1].power` (**checked**: locos
list engines with a power, coaches `engines = { }`). The automatic choice
considers only powered parts at either end of the train; a manual choice must
be powered too. If it can't be told, or there's no loco at an end, there's no
run, and the card says why. `checkStartOnRoute` also now says "the loco is at the
other end of the train" when another part of the train is on the route but the
loco isn't. `test_failures.lua` covers each case; the old script fails the N5
replay.

#### Also learned from the smoke test

- **The other mods' mod IDs** (`~/mod.io/common/10640/mods/<n>/mod.json`, 40
  installs): the folder is the mod.io number, the ID is the mod's own `modId`.
  So the case behind M3 and N3 doesn't arise with mod.io. The safety net stays.
- **`0 can be their own ghost`** at load came from the *devers* mod, which
  replaces every rail vehicle's transformator through
  `addModifier("loadModel", ...)`. That is M2's conflict, seen for real. The run
  fell back to plain copies and the creep, which flashes. **Now chained:**
  `ghost_build` points a vehicle with another transformator at `chain.trf` and
  keeps the original's name in `transformatorConfig.params.runaround_trf`, with
  the other mod's params kept. *devers* itself shows params reaching the
  transformator as `params.transformatorConfigParams`. `ghost_real`'s chain
  functions hide or drive ghosts, or call the original. The original is resolved
  once per name: `ug_require` the `.trf.lua`, read its `data()` (restoring our
  own), then the `file@path.fn` script relative to it. The live log confirmed
  the name arrives as `devers_1::/vehicle/train/devers/devers_train.trf`. If the
  original isn't found, the stock animation is used and logged once.
  `test_chain.lua` and `test_build.lua` cover it. Not yet seen live.
- **A mod can `ug_require` its own module:** *devers* loads
  `devers_1::/vehicle/train/devers/devers_core.lua` that way, and it runs in the
  owner's game. That answers the "Structure" section's open question. The live
  probe there is no longer needed, though the form names the mod ID (fine:
  mod.io keeps it, see above).

### Low

- **`releaseTrain` isn't guarded** (line 1379). Its first command is sent
  outside `pcall`, unlike the second. In `verifyRun` → `finalizeRun`, a train
  deleted during the four verify ticks would make the command maker throw
  inside a callback. `holdTrain` has the same shape. Wrap both like the
  stopped-by-user line.
- **The progress bar stops short on routes with reversals.** `routeLength`
  (line 1012) counts every route piece in full, so a reversal piece counts
  twice. The ghost only drives `CLEAR_M` (10 m) into a reversal piece, and
  starts part-way along the route (`locateOnRoute`). The card's bar
  (`gdist / routeLength`, GUI line 389) then reaches maybe 60-80% and jumps to
  100% at "Coupling on". The watchdog limit also uses `routeLength`, where
  overestimating is harmless. **Fix:** record the length actually driven while
  planning (reversal pieces as `2 × CLEAR_M`), and use that for the bar.
- **The GUI's numbers are trusted.** `SetLoopNumberField` stores `speed` and
  `accel` unchecked. The sliders bound them (10-100 km/h, 0.5-4 m/s²), but a
  command from the console or another mod could set 0, and the ghost would
  never move until the watchdog stepped in. Clamp them in the handler.
- **Stale comments.**
  - Line 1423, "Puts the real loco back. attachAtRear/why say where", is a
    leftover above `traceNow`.
  - `runaround_vehicle.res.lua` mentions `runaround_button.res.lua`, a "capture
    edge" action and a "dev-console fallback in the GUI header", none of which
    exist any more.
  - `captureLocoTransform`'s "ASSUMES ... verify this the first time you run
    it" was verified long ago (live runs start where the loco stood).
- **Repeated carriage reads.** `getComponent(c, MODEL_INSTANCE_LIST).fatInstances[1].transf`
  appears 11 times in `runaround.script.lua` (`carriagePos`, `carriageFrames`,
  `headDirection`, `chooseAttachEnd`, `traceNow`, `verifyRun`, ...). One
  `carriageTransf(c)` helper would do. There are also three copies of the
  `[RunAroundHelper]` log function, one per script, which is unavoidable while
  they run in separate scopes (see below).
- **A run strategy reachable only by settings.** `reverseBeforeRecouple = false`
  leads to `chooseAttachEnd` and the no-flip recouple. It isn't the default, was
  last used live before the flip was added, and no test covers it. Either test
  it or remove it, together with the setting.
- **Speed and acceleration in the run's own copy.** A run keeps the loop as it
  was at the start (`run.loop`), so changing the speed or route mid-run has no
  effect until the next arrival. That's reasonable, but worth one line in the
  README.

### Checked and fine

- **Watchdog ages** use game `dt`, so they scale with game speed, like the
  ghost.
- **A restore run with the creep active** (H2's path) goes straight to
  `finishRun`. `advanceLayout` isn't called once a run is in `finishes`, and
  `buildConfigWithLocoReattached` removes both creep stand-ins.
- **A recouple retry after the train is sold:** `finishRun`'s `tv == nil` branch
  clears every ghost.
- **Late callbacks after the watchdog:** `updateRun` skips aborted runs, and the
  `done()` callbacks only re-hold a live run (`test_failures.lua`).
- **Both copied transformators** match the game's current ones (see M2 above).

---

## Structure: one file or several?

### What there is now

Four scripts, and they are split the way TpF3 requires. Each one runs in a
**different scope** and can't share code with the others at run time:

| Script | Scope | Lines |
|---|---|---|
| `ghost_build.script.lua` | load time (`postRunScript`) | 225 |
| `runaround.script.lua` | game script (`.gs.lua`) | 2655 |
| `runaround_gui.script.lua` | GUI (`react-plugin`) | 583 |
| `ghost_real.script.lua` | transformator and sound, every rail vehicle, every frame | 264 |

That part is right and should stay. The question is
`runaround.script.lua`. At 2655 lines it holds about eight separate concerns:

| Concern | Lines (approx.) | Depends on |
|---|---|---|
| settings, logging, loop lookup | 30-180 | — |
| consists: snapshots, load configs, stand-ins, `build*Config`, model lookup | 180-600 | settings |
| route planning: pathfinder legs, reversal search, `planRoute`, `locateOnRoute` | 600-1060 | geometry helpers only |
| ghost motion: segments, ghost state, `advanceGhost`, approach | 440-480, 1090-1370 | route, settings |
| run lifecycle: hold, release, recouple, retries, watchdog, finish, verify | 1370-1770 | consists, ghost |
| creep | 510-530, 1580-1690 | consists, lifecycle |
| ghost rake: hidden consist, `pullFrame`, `advanceRake`, `recoupleRake` | 1770-2075 | consists, lifecycle |
| start-up, GUI commands, entry points | 2075-2655 | everything |

### Recommendation

**Yes, split it, but only after one live check, and not before the alpha
feedback is in.**

Why split:

- **Route planning** (about 450 lines) is self-contained: it needs only the
  pathfinder and edge geometry, and its tests (`test_plan3.lua`,
  `test_locate.lua`) already treat it as a unit. It's the clearest module.
- **Consist building** (about 400 lines) is the other clean unit. It's pure
  apart from `api.type` constructors, and both the creep and the rake use it.
- The rest would read better as lifecycle, ghost, rake and creep files. There,
  the boundaries follow how a run proceeds.
- The tests reach internal functions by appending
  `return {startRunAround = startRunAround, ...}` to the file's text. Modules
  with real exports would make that explicit, and less fragile.

Why not yet:

- **Loading a mod's own module is unproven.** The base game splits its game
  scripts (`company.script.tl` uses `company.tl`, `company_legacy_util.tl`) and
  loads them with `ug_require "::/..."` or `"/..."`. But `::/` means the base
  game, and the DLC (**checked**) never loads a module of its own: every DLC
  script is self-contained. For this mod, the working form would be either
  `ug_require "runaround_helper_1::/res/scripts/runaround/route.lua"` (yet
  another hard-coded ID, see M3/N3), or `"/res/scripts/..."`, whose meaning
  inside a mod is unknown. A failed require at start-up would stop the whole
  game script.
- **Dependency cycles have to be untangled.** `finishRun` calls `recoupleRake`,
  which calls `recoupleFailed` and `finalizeRun`, which belong to the lifecycle.
  `recoupleRake` is forward-declared today. Modules would need the lifecycle
  functions passed in, or one shared `run` module. That's not hard, but every
  call path changes.
- **Players see no benefit, and there's a load-time risk**, while the alpha's
  live tests are still pending.

### How to do it safely

1. **Live probe.** Add a one-line module, say
   `res/scripts/runaround/probe.lua` returning `{ ok = true }`, and
   `ug_require` it from the game script in both path forms, logging which one
   works. Note the result in the README's engine findings. Prefer a form
   without the mod ID.
2. **Move route planning first**, unchanged. Its tests switch from text-append
   to the module's exports. The test harness would need a `ug_require` that
   reads from `res/scripts/`.
3. **Move consist building next.**
4. Only then the run parts, with `CONFIG` and `logInfo` in a small shared module
   (`runaround/common.lua`). Keep `CONFIG` easy to find, since the README sends
   tinkerers to it.

Keep `ghost_real.script.lua` exactly as one small file. It runs for every rail
vehicle in the game every frame, so it should stay minimal and depend on as
little as possible.

---

## What's solid

- The engine rules the mod depends on are written down where they're used, and
  were traced live: replace keeps the middle fixed, flip mirrors, positions lag,
  a flip releases the hold.
- Everything that can fail before the train is held is prepared first. N1 is
  the one check that still happens too late.
- Every failure path ends in one place, `finishRun`, which puts the real train
  back. The watchdog makes sure every run gets there.
- Vehicle configs are always built from real game objects, with load configs
  matched to each model's compartments.
- Facing comes from start geometry, not from carriage positions, which lag after
  a flip.
- The offline suite covers planning, detach, creep, the ghost rake (start, pull,
  curve, uncouple, recouple), every failure path, facing, wheels, hiding, the
  load script, the GUI, mod-ID consistency, the file list, and stray global
  reads.

## Suggested order

1. ~~N1-N6~~ (done; N5 and N6 seen in the smoke test).
2. **The `releaseTrain`/`holdTrain` guard.** A small robustness fix.
3. A relative `filePath` for the card, only if a live test shows it works.
4. **M5.** Check copies against their coaches' models.
5. The low items as tidying.
6. The module split, after the live probe and the alpha feedback.
7. Later: route-planning cost, `LOG_TRACES` off for a non-alpha release, M7
   (test a save and a mod removal mid-run).
