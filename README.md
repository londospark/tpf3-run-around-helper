# Run Around Helper

A Transport Fever 3 script mod that makes a locomotive run around its train at a
station you choose, instead of the game's instant "flip" at the terminus. The
loco is detached from the consist, driven round a loop you define (as a free
model entity, animated along the real track geometry), then re-attached at the
other end. The other terminus of the line keeps the normal vanilla behaviour.

**Status: work in progress, not published.** The setup UI works; the actual
run-around animation has not yet been run end to end in a live game.

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
