# Run Around Helper

A Transport Fever 3 script mod that makes a locomotive run around its train at a
station you choose, instead of the game's instant "flip" at the terminus. The
loco is detached from the consist, driven round a loop you define (as a free
model entity, animated along the real track geometry), then re-attached at the
other end. The other terminus of the line keeps the normal vanilla behaviour.

**Status: early release.** The whole thing works in a live game, at both ends
of a line: click a few points, and the loco detaches at the station, runs round
your loop as a ghost, and couples on at the other end of the train, tender
first, which then leaves. It has only been tested on a few layouts so far, so
expect rough edges (see below), and please report what you find on the
[issue tracker](https://github.com/londospark/tpf3-run-around-helper/issues).

## What to expect

- **One loco plus wagons.** Multiple units and double-headed trains are not
  handled. The loco is picked automatically (the part nearest your first click).
- **You set it up by clicking a few loose points** on the track (see below); the
  mod works out the route, and where to reverse, itself. It only reverses once
  it is 10 m past the points, not at the end of the piece.
- **The wagons stay where they are.** To stop the game flipping the loco back
  to the buffer end when the train sets off, the mod uses the game's own flip
  on the train while the loco is away, and then puts the wagons back exactly as
  they were (same places, same order, same facing). The flip itself shows for a
  frame or two just as the loco couples on. (Versions before 2026-09-30 let the
  wagons jump one loco length and swap end for end: see below.)
- **The ghost is a copy of the loco's model, with smoke and engine sound but still wheels.** While the loco runs round, it is drawn
  from a copy of a base-game loco model (the exact one if it's a base-game loco,
  otherwise one of the same engine type - steam, diesel or electric). So a
  modded loco will look like a base-game one for those few seconds, and paint
  colours are not shown on the ghost. The real loco, with its own model and
  colours, is what goes back on the train.
- **The ghost does not use signals**, so it can't reserve track. Use a loop no
  other train uses, or watch for collisions.
- **An invisible, tiny stand-in loco** holds the wagons together while the real
  loco is away (a train with no power crashes the game). It shows up in the
  vehicle window during a run-around and is removed afterwards.
- **Install, then fully restart the game.** Script mods are not reloaded by
  loading a save.
- Made by one person, by reverse-engineering the game's Lua API. If it does
  something odd, the log (`stdout.txt`) has lines starting `[RunAroundHelper]`
  that say exactly what it did: please attach them to a bug report.

## Setting up a loop (in game)

Everything is configured in game - no editing Lua.

1. Open a train's window while it is at the terminus you want to use. The
   **Run Around Helper** panel is inside the vehicle window (there is also a
   **Run-Around** button in the main mod-button area, which can rename, tune and
   delete loops but cannot add new ones - it has no vehicle to read from).
2. **Add loop from this vehicle** captures the line and the stop. The
   locomotive is chosen **automatically**: when the run-around starts, it is the
   part of the train standing nearest your first route point (the front of the
   train, the end nearest the points). The panel says "Loco: automatic", and the
   log records which part was picked and how far it was from that point. To
   override it, **Change loco choice** steps through automatic and each part of
   the train in turn, showing "part N of M" and the model name.
3. Give the loop its route by clicking a few points. You do not click every
   track piece, and you do not click the station: the route starts at the stop
   the loop was created from. Turn on **Pick route points on map**, then click
   a few points along where the loco should go, in order - for example a piece
   of the loop, then track at the far end of the train. Clicks are loose
   waypoints. The mod works out the track between them with the game's
   pathfinder, chooses the direction of travel, and finds where the loco should
   stop and reverse: if two points can't be joined going forward, it searches
   the nearby track for the cheapest place to set back (a stub beyond the points,
   a headshunt, and so on), so you don't have to click the reversing spot. Add
   more clicks to steer it (for example through one side of a wye). The panel
   shows the result on the **Route:** line (points, track pieces, reversals,
   length), or says which pair of points it couldn't join. **Add point at this
   train** does the same using the track piece a train is sitting on. **Undo
   last point** removes the last click and re-plans.
   **Finishing:** press **Esc** or **right-click** to leave pick mode, or press
   the toggle button again. The train's information window stays open while you
   pick (the pick tool is stacked on top of the game's own tool, and the window
   is re-shown if the game hides it), so the panel's **Route:** line updates as
   you click. If the window ever does close, click the train to bring it back.
4. **Speed** bumps the ghost loco's speed. Nothing needs setting for the
   re-coupling: a loco can't pass through its consist, so it goes back on at the
   end of the train nearest your **last** route point (the end it has just
   arrived at), facing outward so it can pull. In the parts list that is the
   first part (not reversed) or the last part (reversed). The log says which end
   was chosen and how far each end was from that point.

Any number of independent loops (different lines/termini) can be configured;
they are saved in the savegame.

Tight loops are fine: only the detached loco travels the loop, the wagons stay
at the platform, so a loop only long enough for the loco works.

## Installing

Copy this folder into your Transport Fever 3 local mods staging area
(`.../userdata/<id>/3493540/local/staging_area/`), then activate it in the
in-game Mod Hub and **fully restart the game** - script mods are not reloaded by
just reloading a save. Loops are stored in the save, so a save that has been
through earlier versions of this mod is fine.

## Known issues / not yet verified

- **A train of only wagons crashes the game, so the loco is swapped for an
  invisible stand-in.** When the loco was simply removed, the game exited about
  25 seconds later with `Assertion (trainMoveInfo.availPower)>(0.0f) failed`
  in `calculateFallbackPowerOutput`: every land vehicle's model scripts (sound,
  smoke, animation) are handed a per-render-step `powerOutput`, and a consist
  with no powered part asserts as soon as its wagons are drawn. So the mod ships
  its own tiny models, `res/models/runaround_standin/standin_<length>.mdl` (invisible, sized to match the loco,
  no meshes, 1 kW, no sound or lights, hidden from the purchase lists), puts it
  in the loco's place while the ghost loco is away, and takes it out again when
  the real loco is coupled back on. If the model isn't found, the run is
  refused (logged) rather than risking the crash. The first live try of the
  stand-in tripped two model problems, both fixed: it declared no compartments
  (the game asserts that a part's load configs match its model's compartments,
  and every base-game loco has exactly one, so the model now copies the standard
  loco compartment and the part's load configs are built from the model's own
  metadata: the count always comes from the model, so a modded loco that declares
  a different number of compartments works, and the settings each compartment of
  the real loco had are saved and restored when it is put back), and its
  game also asserts three more things about every vehicle part, all now satisfied:
  the part's load configs match the model's compartments in number, its
  `autoLoadConfig` list (one true/false per compartment, empty on a freshly
  created part, saved from the real loco and restored) matches too, and each
  compartment's chosen load-config index is below the number of load configs the
  model offers there (clamped, since the stand-in inherits the loco's values).
  Its transformator reference (it needs `::/vehicle/...` to reach the base game). Whether the game accepts a
  model with an empty mesh node, and whether it can be used in a consist swap,
  is unconfirmed until a live run; `detachEnabled` in `runaround.script.lua` is
  the kill switch.
- **Smoke and sound on the ghost (untested).** At load time
  (`ghost_build.script.lua`) the mod reads every rail locomotive model the game
  has, modded ones included, and builds a "ghost" of each: a new model that
  reuses the loco's meshes but none of its vehicle data, keeping the loco's own
  particle emitters (chimney smoke, cylinder steam, exhaust) and a converted copy
  of its own sound set (the continuous engine tracks, driven by speed and power;
  horn, clacks and squeal are dropped). During the run the mod feeds the ghost
  its speed as custom entity state, and a small transformator
  (`res/models/runaround_ghost/ghost.trf.lua`) turns that into smoke frequency,
  size and drift and into engine sound. This is how the base game's own free
  entities (fireworks, rockets) get particles and sound. The log says
  `ghost models: built effects ghosts for N of M models` at load and
  `ghost model: effects ghost ...` when a run starts. If a loco has no effects
  ghost, or the game refuses one, it falls back to the plain silent ghost.
  `useEffectGhosts` in `runaround.script.lua` turns the effects off. Wheels do
  not turn yet.
- **Third live run: smoke works, sound does not yet, loco facing now checked
  (untested).** The log showed `built effects ghosts for 58 of 4586 models` and
  smoke on the ghost. Every sound set failed to add (`std::exception` from
  `soundSetRep.addAsTable`, no detail), so the ghosts run silent. The builder now
  tries the track names both as absolute paths and as the game gave them, and
  logs both errors and the first track's name, so the next log will say why. The
  loco appeared to flip round at coupling even though the log's facing check
  passed, so the mod no longer trusts the part's `reversed` flag: once the loco
  is back on the train it reads the loco's real facing off its carriage, compares
  it with the ghost's, and flips the flag once if they differ
  (`verifyFacing`; log lines `verify: loco facing against ghost facing, dot =`
  and `loco at start: part reversed=..., facing dot train head direction =`).
- **Load error "function data() not defined", fixed.** The first effects build
  crashed the game at load: a `.script.lua` file must define `data()` and return
  its functions from it, unlike the base game's `.tl` scripts, which can return a
  table directly. Both new scripts now do.
- **Wagon jump fixed (untested).** A video of the live run showed the wagons
  jumping about one loco length and swapping end for end when the train was
  flipped. The flip mirrors the train around its own extent, so with an
  invisible stand-in only at the loco's end the wagons are shifted. Now there is
  a stand-in at each end (the second one, the "tail", where the loco will couple
  on), so the mirror leaves the wagons' extent unchanged; the ghost drives to the
  tail stand-in first, then the train is flipped and, in the same step, the loco
  replaces the head stand-in, the tail goes, and the wagons are re-listed in the
  opposite order with their reversed flags toggled, which undoes the mirror. Only
  when the loco is the first part of the train (the usual case); otherwise it
  falls back to coupling on without the flip. Also confirmed from the video:
  the loco arriving tender first is correct.
- **Second live run: the flip works, three things fixed (untested).** The log
  showed the train flipping with the parts order kept ("Swwww"), so the game's
  flip is confirmed. Then: (1) the ghost snapped from the last point to where
  the loco reappeared. The run now waits for the flip, reads the invisible
  stand-in's real position off its carriage, and the ghost glides there in a
  straight line before the loco replaces it. (2) The loco turned round. The ghost
  now starts with the real loco's own facing and keeps it through every reversal
  (a loco that reverses does not turn), and the loco goes back on the train
  facing the same way, so it pulls tender first: its `reversed` flag is worked
  out from that facing against the train's head direction (log: "facing dot head
  direction"). (3) Reversals no longer run to the end of the clicked piece: the
  ghost goes 10 m into it (`CLEAR_M`), i.e. just clear of the points, and comes
  back from there. Pieces shorter than 15 m are still driven to the end. This
  assumes the points are at the start of that piece, which is the usual case for
  a stub beyond a junction.
- **First full live run: it worked, with two glitches, both fixed but untested.**
  (1) The ghost appeared in the middle of the consist. The wagons did not move
  (a first guess, that the 1 m stand-in let them close up, was wrong; the
  stand-in is now sized to the loco anyway, in 2 m steps, `standin_4.mdl` to
  `_44.mdl`). The real cause: the route's first piece is the stop's track node,
  about the middle of the platform, and the ghost was moved there on its first
  step. It now starts at the point on the route nearest the loco's real
  position (log: "ghost starts on route piece ..."). (2) The loco snapped back to its original end when the
  train set off. The game flips a train that must leave a terminus the way it
  came - it mirrors the consist end for end, keeping the parts-list order - and
  it does that at departure, so a loco coupled on at the exit end was flipped
  straight back to the buffer end. Now the mod flips the train itself, with the
  game's own `makeVehicleReverseCmd`, while only the wagons and the stand-in are
  on it, then swaps the stand-in for the loco at the head of the train. The
  head then already faces the exit, so nothing is flipped at departure. The
  wagons do change end for end at that moment, as the game's flip always does.
  `reverseBeforeRecouple` in `runaround.script.lua` turns this off (the loco
  then goes on at the end nearest the last route point, as before). Unconfirmed
  in a live game; the log line "train reversed; parts now" shows what the game
  did to the parts list.
- **The ghost loco is drawn from a "ghost" copy of the loco's model, not the
  loco model itself.** A free entity has no vehicle behind it, but a loco model's
  sound and animation scripts read vehicle data (the steam "chuffs" sound script
  reads speed and chuff step with no nil check), so spawning the real model was a
  risk. The base game's own free entities (ufo, cows, fireworks) all use models
  with empty metadata, so `res/models/runaround_ghost/` holds 55 generated ghosts:
  the meshes and materials of each base-game loco and multiple unit (checked: all
  5,936 referenced files exist), with no metadata, sound, particles, lights or
  animations. The run picks the ghost with the same file name as the loco's model.
  **Modded locos** have no ghost of their own, so they get the ghost of a base
  loco of the same engine type (steam, diesel or electric): the ghost will look
  like a different loco while it runs round, but the real loco, with its own model
  and colours, is what goes back on the train. **Colours:** custom entities
  cannot be coloured, so the ghost shows the model's default colours; the real
  loco's colour is saved and restored exactly. If no ghost is found, or the ghost
  fails to spawn, the loco is not detached (or is put straight back).
- **Click-to-pick works, with a caveat.** The first version put a
  `builtin.Selector` inside the panel, which the UI cannot render (hard crash).
  It now lives in a registered tool pushed onto the tool stack, as the base game
  does, and a live test captured a track click. A click on track delivers the
  track segment's entity with no edge details, so the mod uses edge index 0 of
  that segment (fine for single track; it logs
  `pick: clicked entity=... kind=...` and the fallback it took). Double track
  or two-direction segments can't yet be told apart.
- **Route planning has run in a live game, but the route hasn't been driven yet.**
  With real clicks it planned routes such as "3 points, 23 track pieces,
  1 reversal, about 647 m"; whether the loco then drives them correctly is still
  untested. It was first checked against a mock track layout (platform, stubs either side of the points, a
  passing loop) with a pathfinder that refuses hairpin turns at junctions, where
  two loose clicks produced a complete run-around with two reversals. The real
  pathfinder and real switch rules may behave differently, and the search for a
  reversing spot looks within 300 m and tries at most 100 nearby track nodes. The
  route starts at the stop's track node (found via line, stop, station group,
  station and terminal), and the ghost loco jumps there from where the real loco
  stood, a short hop along the platform. If the stop's node can't be found, the
  route starts at the first click instead. Direction of travel at each click is
  chosen automatically (shortest total, reversals cost extra).
- **Starting a run-around failed with "Callbacks are currently disallowed", now
  fixed.** The game does not allow a command callback inside `update`, and
  arrival events are delivered while the engine is mid-change, so the work is
  split the way the base game's own scripts do it: the arrival handler only
  queues a request, `update` moves the ghost and returns what needs doing, and
  `postUpdate` (now registered in `runaround.gs.lua`) sends the detach / spawn /
  recouple commands with their callbacks. Not yet confirmed in a live game.
- **The detach step has been reached in a live game and failed, now fixed.**
  The first real run-around crashed the game (`!m_betweenChanges`): commands
  were being sent from inside the arrival-event handler, which the engine
  forbids, so starts are now queued there and sent from the next `update()`.
  That got the run as far as the detach, which failed with a Lua error: the
  consist passed to `makeVehicleReplaceCmd` was a plain Lua table, and the game
  needs real `TransportVehicleConfig` / `TransportVehiclePart` objects. They are
  now copied from the live config, with the loco rebuilt from a saved snapshot
  so it keeps its age and condition. The failed attempt also left the train held
  at the station on manual departure; every failure path now releases the train,
  and it is only held after everything that can fail has been prepared. If the
  recouple itself fails, the loco ghost is left in place because it is the only
  copy of the loco. The fixed detach / animate / recouple sequence has not yet
  been confirmed end to end in a live game.
- **Which end the loco couples to, and which way it faces, are now worked out
  from geometry, but how the game then drives the rebuilt train is unconfirmed.**
  The loco goes on the end nearest the last route point, reversed only if that is
  the rear of the parts list. Whether the game then sets off with the loco
  leading (it normally flips the whole train at a terminus) has not been seen yet.
- Multiple-unit consists are not handled (assumes one loco plus separate wagons).
- Edge length is estimated by sampling the geometry; the animation is a free
  model, so it does not use signals and cannot reserve track - use a loop no
  other train routes over.

## How it works (for the curious)

- `runaround.gs.lua` + `runaround.script.lua`: the engine-side game script. It
  listens for `OnArriveAtStop`, keeps the configured loops in persistent state,
  and does the detach/animate/recouple with `makeVehicleReplaceCmd` and the
  custom-entity commands. Its `fileName` references resolve from the mod root.
- `runaround_gui.script.lua` + the three `*.res.lua` descriptors: the React
  panels (mounted on the vehicle window, main mod-button area and mod entry
  point) and the click-to-pick tool. GUI code only ever sends commands to the
  game script through one event channel (`makeScriptingSendEventCmd` with the
  fixed channel name as the *name* argument, since subscriptions match on name).
- The full write-up of what was learned building this is in
  `../docs/Transport_Fever_3_Modding_Guide.pdf`.
