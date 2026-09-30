# Run Around Helper

A Transport Fever 3 script mod: at a terminus you choose, the locomotive runs
round its train instead of the game's instant "flip". The loco uncouples, drives
round a loop or wye you pick on the map, reversing where it needs to, and couples
on at the other end. It keeps its own sound, smoke, wheel animation and paint, and
it faces the way a real loco would.

**Status: early release.** It works end to end in a live game at both ends of a
line. It has only been tried on a few layouts, so expect rough edges. Please
report problems on the
[issue tracker](https://github.com/londospark/tpf3-run-around-helper/issues)
and attach the log lines starting `[RunAroundHelper]` from `stdout.txt`.

## Setting up a run-around (in game)

1. Open the window of any train on the line. Its **Run-around** card lists
   every stop of the line that has no run-around yet, with the stop the train
   is at first. Choose the one you want. The run-around is named after the
   station, and you can rename it.
2. Choose **Edit route on map**. The route is drawn on the track while you edit:
   - the colour runs from blue at the start to orange at the end;
   - reversing pieces are purple;
   - clicked pieces carry a white line.

   Click a few points along where the loco should go, in order: for example a
   piece of the loop, then track at the far end of the train. You don't click
   every piece, the station or the reversing spot. The mod plans the route with
   the game's pathfinder and reverses just past the points. More clicks steer
   it, for example through one side of a wye. **Undo point** and
   **Clear points** fix mistakes. Right-click, Esc or **Done** to finish. The
   train's window stays open.
3. The card shows the route (length, reversals, points). While a run-around is
   happening it also shows a progress bar and what the loco is doing: running
   round, turning the train, coupling on. **Show** draws the route without
   editing.
4. The card's collapsible part holds the name, speed and acceleration sliders,
   the loco choice (automatic by default), and delete, which asks first.

Any number can be set up, on different lines and termini. They belong to the
line and stop, not to a train, so every train on the line (clones included) does
the run-around there. They are saved with the game.

## What to expect

- **One loco plus wagons.** Multiple units and double-heading are not handled.
- **The coaches creep forward by one loco length while the loco is away.**
  This can't be avoided. A vehicle replace keeps the middle of the train where
  it was, and the flip mirrors the train about that middle. So only driving can
  move the train's middle, and a real run-around moves it by a loco length: the
  loco ends up beyond the far coach. Instead of a jump, the mod moves the coaches
  gradually once the loco has driven off:
  - A stand-in in front of them shrinks 1 m at a time while one behind them
    grows, so the total length stays the same.
  - The train is flipped at the halfway point, when it is exactly symmetrical,
    so the flip moves nothing.
  - The creep then finishes on the other side, and the loco couples on where the
    remaining stand-in is.
  This happens when the loco is the first part of the train. `creepLayout` turns
  it off: the coaches then jump once, at the flip.
- The train is held (manual departure plus the vehicle window's stop) through
  every step. Otherwise it crept off on the stand-ins after the flip.
- **Your loco, not a stand-in, runs round.** Every rail loco is prepared when
  the game loads, modded ones included. Where it uses the game's own sound set
  and train transformator (all base-game and DLC locos, and many mods), the
  ghost is the loco's own model, with its own sound, smoke, wheels and paint. A
  modded loco with its own sound set or animation script runs round as a copy
  of itself, with its smoke, wheels and paint. It has sound only if it uses one
  of the game's sound sets.
- **Wheel speed is approximate.** Scripts can't read a loco's driving-wheel
  radius, so a typical one (0.9 m) is used.
- **The running loco ignores signals.** Use a loop no other train uses.
- **Invisible stand-ins** hold the train together while the loco is away, because a train with no powered part crashes the game. It
  shows in the vehicle window during a run and is gone afterwards.
- **Install, then restart the game fully.** Script mods are not reloaded by
  loading a save.

## Installing

Copy this folder into your Transport Fever 3 local mods folder,
`.../userdata/<id>/3493540/local/staging_area/`. Activate it in the in-game Mod
Hub and restart the game.

## Useful log lines

- `loco setup: N locos; M can be their own ghost, ...` at load: how many locos
  were prepared.
- `ghost model: using the loco's OWN model` or `... cannot be used - <why> -
  using a ghost copy` at the start of each run.
- `ghost first step N m from where the loco stood`: should be about 0.
- `trace ...`: carriage positions around each step (set `LOG_TRACES` to false
  in `res/scripts/runaround.script.lua` to silence them).

## Switches

In `res/scripts/runaround.script.lua`, `CONFIG`:

- `detachEnabled`: turns the run-around off.
- `reverseBeforeRecouple`: flip the train before recoupling.
- `useRealModel`: use the loco's own model when possible.
- `useEffectGhosts`: prefer the ghost copies with smoke and sound.
- `verifyFacing`: check the loco's facing after recoupling.
- `LOG_ARRIVALS` and `LOG_TRACES`: logging.

In `ghost_build.script.lua`: `PATCH_LOCOS = false` leaves every loco untouched.
Only ghost copies are then used.

## How it works

- `res/scripts/runaround.script.lua` is the game script. For each run:
  1. It queues the run when a train arrives.
  2. It swaps the loco for a stand-in of its length, and later creeps the coaches
     along (see above).
  3. It spawns the ghost (a free entity) where the loco stood and drives it
     along the planned route.
  4. It flips the train with the game's reverse command, at the creep's halfway
     point.
  5. The ghost glides and brakes to the stand-in, and the real loco replaces it.
  6. It checks the loco's facing and releases the train.
- `ghost_build.script.lua` is the load-time script. It prepares every rail
  loco, as described above.
- `res/scripts/ghost_real.script.lua` holds the wrappers. For a real train they
  do exactly what the game's own sound and transformator functions do. For the
  ghost, they build vehicle data from the ghost's state (speed, distance,
  direction and paint) and run the game's own functions on it. The wheel
  animation follows a motion segment (start distance, speed, acceleration, start
  time) computed from the game clock, so it is smooth between state updates.
- `res/audio/ghostwrap/*.snd.lua` are the game's own rail sound sets. They are
  generated from the game files with absolute sound paths, and their update
  script is pointed at the wrapper. The game refuses sound sets added or changed
  at run time, so these ship as files.
- `res/models/runaround_ghost/real*.trf.lua` are the stock train and
  tilting-train transformators, pointed at the wrappers. The folder also holds
  plain silent copies of the base-game locos, as a last fallback.
- `res/models/runaround_standin/standin_<metres>.mdl` are the invisible
  stand-ins, 1 to 44 m in 1 m steps. The loco's length is measured from the
  spacing of the carriages.
- `runaround_gui.script.lua` and `runaround_vehicle.res.lua` are the UI: the
  train window card and the route tool. The tool draws the route
  with `builtin.NodeViewer` (coloured strips on given track pieces) and
  `api.gui.spawnEphemeralHudImage` (markers), and adds clicked points with
  `builtin.Selector`. Both only work inside a tool's action. The UI talks to
  the game script through one event channel.

## Engine findings

Learned while building this. The full write-up is in
`../docs/Transport_Fever_3_Modding_Guide.pdf`.

- No commands from the `OnArriveAtStop` handler, and no command callbacks inside
  `update()`. Queue the work, and send it from `postUpdate()`.
- Vehicle configs must be real `TransportVehicleConfig`/`Part` objects. A part's
  load configs, `autoLoadConfig` and load-config indexes must match its model's
  compartments.
- A train with no powered part crashes the game when drawn.
- A vehicle replace keeps the middle of the train where it was: extra length
  goes half on each end. The flip mirrors the train about its middle. A symmetric
  train is left where it is. Carriage positions are reported late for
  a tick or two after either.
- A part's `reversed` flag is relative to the train's head.
- `modelRep.getAsTable` works in a load script but not in a game script.
  `modelRep.get` works in both.
- `soundSetRep.addAsTable`/`setAsTable` throw `std::exception`.
  `modelRep.addAsTable` with `modelPath` makes a new model from an existing
  one's meshes, and `modelRep.setAsTable` works.
- A free entity's custom state reaches its transformator and sound scripts as
  `currentInfo.customState`. `setModelInstanceAttributeVec3f(0, colour)` paints
  it.
- `util.useFn` does not work in the transformator scope. Call scripts through
  `ug_require` instead.
- In a `.snd.lua`, sound paths are relative to the file's own folder, or
  absolute with `::/`. A `.script.lua` must define `data()`.
