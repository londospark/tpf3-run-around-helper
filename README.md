# Runaround Railways — ALPHA

**Your locomotive runs around its train at the terminus, instead of the game's
instant flip.**

When a train arrives at a terminus you've set up, the loco uncouples and drives
off along the route you picked: into a loop, onto a headshunt or round a wye. It
reverses where it needs to, comes back down the other road and couples on at
the far end. Then the train leaves with the loco leading.

The loco uses its own model, with its own sound, smoke, wheel animation and
paint, including custom liveries. It never turns round on the way, so a tank
engine that arrived bunker-first leaves chimney-first, as it would for real.

- Set up entirely in game: click a few points on the track and the route is
  worked out for you.
- The route is drawn on the track while you edit it.
- Any number of stations, on any number of lines.
- Works with every base-game and DLC loco. Works with modded locos too; see
  [Modded locos](#modded-locos).

> **Made with a lot of help from AI.** Most of the code, tests and documentation
> for this mod were written by an AI assistant (Anthropic's Claude, using Claude
> Code). I set the direction, made the decisions and tested it in game. I'm
> saying so up front so that nobody downloads it under a false impression; if
> you'd rather not use AI-assisted mods, that's completely fair.

> **ALPHA — an early test release.** It works end to end in a live game, but
> it has only been tried on a few layouts. Expect rough edges, and please tell
> me what breaks. See [Reporting a problem](#reporting-a-problem). Saves with
> run-arounds set up stay compatible as it develops.

*Also known as: run-around, run round, runaround, run-round loop.*

---

## Installing

1. Put the `runaround_helper` folder in your Transport Fever 3 local mods
   folder: `.../Steam/userdata/<your id>/3493540/local/staging_area/`. If you
   subscribed on mod.io, the game does this for you.
2. Activate **Runaround Railways** in the in-game Mod Hub.
3. Restart the game fully. Script mods are only loaded at start-up, not when a
   save is loaded.

It can be added to an existing save. Removing it from a save that has
run-arounds set up is safe too: trains then flip as normal.

## Quick start

1. **Open a train's window.** Pick any train on the line. It gets a
   **Run-around** card.
2. **Add a run-around.** The card lists the stops of that line, with the one the
   train is at first. Click the station where the loco should run around. The
   run-around is named after the station.
3. **Draw the route.** Click **Edit route on map**, then click a few points on
   the track where the loco should go, in order. For a simple loop that's
   usually:
   1. a piece of track beyond the points, where the loco will stop and reverse;
   2. a piece of the loop, or the other road through the station;
   3. a piece of track beyond the far end of the train.

   You don't click every piece of track, the station, or the exact reversing
   spot. The route is planned with the game's pathfinder, and the loco reverses
   just clear of the points (10 m past them). After your last point, the route
   goes on back into the station by itself, reversing past the points if it
   has to, so the loco sets back onto its coaches along the track. Right-click, **Esc** or **Done**
   when finished.
4. **Check it.** The card shows the route's length, reversals and points. A
   warning says which two points could not be joined.
5. **That's it.** The next time a train on that line arrives there, its loco
   runs around.

## The Run-around card

In the train window, one card per run-around on the train's line.

- **Route line**: length, reversals and points, or what's missing.
- **While a run-around is happening**: a progress bar and what the loco is doing
  (running around, turning the train, coupling on).
- **Edit route on map / Done**: draws the route and adds clicked points.
  - **Undo point** and **Clear points** appear while editing.
- **Show / Hide**: draws the route without editing.
- **Settings** (the collapsible part):
  - **Name**: click the pencil to rename.
  - **Speed** and **Acceleration** of the loco while it runs around.
  - **Loco**: *automatic* (the default) or a chosen part of the train.
    Automatic picks the loco at whichever end of the train has one (a part with
    an engine, never a coach or wagon). With a loco at each end, it picks the
    one nearer the first route point. A chosen part must have an engine too.
  - **Delete run-around**: asks for confirmation first.
- **Add a run-around at...**: buttons for the line's other stops.

### The route on the map

While editing or showing:

- the route is coloured from **blue** at the start to **orange** at the end;
- the pieces where the loco reverses are **purple**;
- the pieces you clicked have a **white line**.

## What happens during a run-around

1. The train arrives and is held.
2. The loco and every coach or wagon are shown as exact copies of themselves,
   on the spot, with their own paint and, for wagons, their own load. The real
   loco, coaches and wagons all stay in the train, just hidden, so **passengers
   and goods stay aboard and nothing is bought or sold**. Out of sight, the
   hidden train is turned round.
3. The train draws forward one loco length, gently, with the loco still coupled,
   and stops. See [The coaches move forward](#the-coaches-move-forward).
4. A short pause while the loco uncouples.
5. The loco drives the route, reversing where planned. It keeps facing the way
   it was facing.
6. It comes back along the track, onto the platform, and brakes to a stop
   against the far coach. The real loco and
   coaches reappear exactly where their copies are, and the copies go.
7. The train loads as normal and leaves, with the loco leading.

### If something goes wrong

A train is never left stuck or broken by a run-around:

- **If the run can't start** (the game refuses a step), the train is put back
  exactly as it was, coaches in their order with their own paint, and leaves
  the normal way. The copies are cleared away.
- **If the loco can't be coupled back on**, the train stays held, rather than
  leaving without its loco showing, and the mod keeps trying. The run-around
  card says **Stuck** while this goes on.
- **If a run stalls** (for example the game never answers a step), it is given
  up after three times the route's length at the run-around's speed, plus a
  minute. The real train is put back and released.
- **If the train is sold or deleted mid-run**, the copies are cleared away.

## Tips and limitations

- **Other mods.** A mod that gives trains its own animation script (the
  transformator), such as *devers* (Real Track Cant), is chained: this mod hides
  the coaches and drives the copies, and otherwise calls that mod's script, so
  both work. The load log counts them ("N through another mod's
  transformator"). That's done only when this mod can load that script at start
  and it does nothing beyond animating, smoke and adding extra models (as
  `mcs_basisset`'s does). Extra models are passed on as well, and vanish with the
  vehicle while it's hidden. Anything else is left alone exactly as it is, and
  that vehicle runs around as a copy. Without such mods, nothing changes.
- **The card shows what's happening:** turning the train, drawing forward,
  uncoupling, running around, coupling on. It shows **Stuck** if the loco can't
  be coupled back on.
- **One loco plus coaches or wagons.** Multiple units and double-heading are not
  handled. A light engine (a loco with nothing behind it) is left alone.
- **The loco should be at the front of the train when it arrives**, which it is
  at a terminus. A loco chosen elsewhere in the train still runs around, but the
  coaches jump at the end instead of the train drawing forward.
- **The running loco ignores signals** and doesn't reserve track. Use a loop
  that other trains won't be on at the same time.
- **Don't remove the mod while a run-around is happening.** The loco and coaches
  are hidden at that moment (painted a flag colour this mod draws as nothing),
  and without the mod they'd show that colour (teal). Let the run finish first.
- **Changes during a run** (speed, route) apply from the next arrival: a run
  keeps the settings it started with.
- **The train must stop at the platform the route starts from.** A line can
  send trains to other platforms. Then there's no run-around that time: the
  train leaves the normal way, and the card says why. The same happens if the
  route would set off towards the train's own coaches (check the first
  points).
- **Run-arounds belong to a line and a stop, not to a train.** Every train on
  the line does it there, clones included. A train moved to another line only
  does it where that line has its own run-around.
- **Stop numbers:** a run-around remembers its stop by its position in the line.
  If you insert or remove stops earlier in the line, check it still points at
  the right station.

### The coaches move forward

When the loco couples on at the far end, the train is a loco length further
along the track than it was. In this game that can only happen by the coaches
moving: a vehicle swap keeps the middle of the train fixed, and the flip mirrors
the train about its middle. So before the loco uncouples, the whole train draws
forward a loco length, as if pulling up to the buffers, and the coaches don't
move again after that. The game's vehicle marker only re-attaches three times:
at the detach, the turn and the recouple.

This works for passenger coaches and goods wagons alike. Nothing is taken out of
the train: the coaches and wagons are the same vehicles throughout, so their
passengers and cargo are kept.

A coach or wagon that can't be hidden (a modded one whose animation script
can't be wrapped) means the coaches stay in view: they move a loco length in one
go when the hidden train is turned. A loco that can't be hidden doesn't run
around at all: taking it off the train would mean selling it and buying it back.
The card says why.

### Modded locos

Every rail loco is prepared when the game loads, including modded ones.

- **Uses the game's own sound set and train animation script:** runs around as
  itself, with its own sound, smoke, wheels and paint. That's every base-game
  and DLC loco, and many mods.
- **Brings its own sound set or animation script:** runs around as a copy of its
  own model, with its smoke, wheels and paint. It has sound only if it uses one
  of the game's sound sets. The game doesn't let mods create sound sets while
  it runs, so only sound sets shipped as files can be wrapped.

### Wheels

The wheels turn with the distance the loco travels. Scripts can't read a loco's
driving-wheel radius, so a typical 0.9 m is assumed. Wheels on very large or
very small driving wheels may turn a little too fast or too slow.

While the loco runs around, its tender, pony truck and bogies follow the track
on curves, and their wheels turn, as on a real train. (The game does this
itself only for a train on the track; for the moving copy the mod does it,
from the loco's model.)

Known in this alpha, seen with a steam loco:

- **No chuffing while the loco runs around.** The rest of its sound plays.

## Reporting a problem

Please use the
[issue tracker](https://github.com/londospark/tpf3-run-around-helper/issues).
Include:

- what you expected and what happened (a short video helps a lot);
- the lines starting `[RunAroundHelper]` from the game's log,
  `.../Steam/userdata/<your id>/3493540/local/crash_dump/stdout.txt`.

Useful log lines:

| Line | Meaning |
|---|---|
| `loco setup: N rail vehicles; M can be their own ghost, ...` | at start-up, how many locos, coaches and wagons were prepared |
| `ghost model: using the loco's OWN model` | the loco runs around as itself |
| `ghost first step N m from where the loco stood` | should be about 0 |
| `ghost rake: ...` | the coaches shown as copies, the pull forward (how far, and how much the coaches turn on a curved platform; the loco ghost should be about 0 m from where it would be coupled) and the uncouple |
| `trace ...` | carriage positions at each step (set `LOG_TRACES = false` to silence) |
| `recouple FAILED ... try N ... train held` | the loco couldn't be put back on; it is tried again (`STUCK` after a few tries) |
| `watchdog: ...` | a run stalled, or its train went, and was given up |
| `train put back as it was ...` | a run couldn't start and the train was restored |
| `loco setup: SKIPPED ...` | the mod was installed under an unexpected ID: no vehicle was patched, and the run-around card won't appear (run-arounds already in a save still run, with plain copies). Please report it |
| `GUI registered` | the train-window card loaded; if it's missing from the log, the card failed to load |
| `money: the detach changed the balance by N` (and `the recouple`) | should be 0: the loco stays on the train, so nothing is bought or sold |
| `... reported at the stop it has just run around at - ignored` | the game's repeat arrival straight after a run-around, ignored (normal) |
| `loco setup: ... has its own transformator, left alone: <name>` | another mod changed that vehicle's animation script, so it runs around as a copy. If every vehicle says this, a mod is replacing all train transformators (see "Other mods") |
| `run-around NOT started ...` | the train didn't run around this time, and why (also shown on the card): it's at another platform than the route starts from, or the route sets off towards the coaches |

## Advanced settings

These are in the files, for tinkering. Most people won't need them.

`res/scripts/runaround.script.lua`, `CONFIG`:

| Setting | Default | What it does |
|---|---|---|
| `detachEnabled` | `true` | turns the run-around off entirely |
| `reverseBeforeRecouple` | `true` | turn the train before the loco couples on, so the game doesn't flip it back |
| `ghostRake` | `true` | show the loco and coaches as copies, hide the real train, turn it out of sight and draw it forward before the uncouple (the smooth way) |
| `rakePullSpeed` | `2.0` | top speed, in m/s, of the train drawing forward before the uncouple |
| `uncouplePause` | `2.5` | seconds the train stands before the loco uncouples and sets off |
| `useRealModel` | `true` | run around as the loco's own model when possible |
| `useEffectGhosts` | `true` | otherwise use the copy with smoke and sound |
| `verifyFacing` | `true` | check the loco's facing after coupling, and correct it |
| `watchdogFactor`, `watchdogExtraSeconds` | `3`, `60` | a run taking longer than factor × route ÷ speed + extra seconds is given up and the train put back |
| `recoupleRetries`, `recoupleRetrySeconds`, `stuckRetrySeconds` | `3`, `1`, `30` | a refused recouple is retried this many times this far apart, then every `stuckRetrySeconds` |
| `LOG_ARRIVALS`, `LOG_TRACES` | `true` | logging |

`ghost_build.script.lua`: set `PATCH_LOCOS = false` to leave every loco
untouched. Only the copies are then used.

---

## For modders: how it works

| File | Role |
|---|---|
| `res/scripts/runaround.script.lua` | the game script: queues a run when a train arrives, shows the loco and coaches as ghosts, hides the real loco and coaches in place, turns the hidden train, draws the train forward a loco length (coach ghosts following the loco ghost), uncouples, drives the loco ghost along the planned route, puts the loco back and shows the coaches again |
| `ghost_build.script.lua` | the load-time script (`postRunScript`): prepares every rail vehicle, locos and coaches |
| `res/scripts/ghost_real.script.lua` | wrappers for the game's sound and train transformator functions; they also draw a real carriage painted the flag colour as nothing, and give its ghost the same load |
| `res/audio/ghostwrap/*.snd.lua` | the game's own rail sound sets, generated with absolute sound paths and the update script wrapped |
| `res/models/runaround_ghost/` | `real*.trf.lua` (the stock train and tilting-train transformators, wrapped), plus plain silent copies of the base locos as a last fallback |
| `res/scripts/runaround_gui.script.lua`, `runaround_vehicle.res.lua` | the train window card and the route tool |
| `dev/` (not shipped) | offline tests (`dev/run_tests.sh`), the staging install script and generators; see `AGENTS.md` |

More detail:

- **The ghost.** A free entity (`makeCustomEntityCreateCmd`) drawn from the
  loco's own model. That needs `ghost_build` to have pointed the loco's sound set
  and transformator at the wrappers. The wrappers behave exactly as the game's
  functions for a real train. For the ghost, they build vehicle data from its
  custom entity state and run the game's own functions on it. The state is
  `{ speed01, power01, state = { speed, power, vx, vy, color, dir, seg, mirror } }`,
  where `mirror` is the hidden carriage a coach ghost copies its load from.
- **Hidden coaches.** A real coach is hidden by painting its part a flag colour
  that nobody uses. The wrapped transformator sees that colour and scales every
  node of the model to zero. Scaling only the root, as the base game does to make
  fireworks vanish, leaves a vehicle's bogies showing, because the engine places
  bogies on the track itself. The
  coach's real paint is put back from a snapshot matched by model and purchase
  time.
- **Smooth wheels.** The wheel animation follows a motion segment computed from
  the game clock: start distance, speed, acceleration and start time.
- **Routes.** Routes come from `findPathNodeToNode` between the clicked pieces. A
  small search finds a place to reverse when two points can't be joined going
  forward.
- **The route tool.** It draws with `builtin.NodeViewer` and adds points with
  `builtin.Selector`. Both only work inside a tool's action.

### Engine findings

Learned while building this. The full write-up is in the modding guide.

- **Timing.** No commands from the `OnArriveAtStop` handler, and no command
  callbacks inside `update()`. Queue the work and send it from `postUpdate()`.
- **Vehicle configs.** They must be real `TransportVehicleConfig`/`Part` objects.
  A part's load configs, `autoLoadConfig` and load-config indexes must match its
  model's compartments.
- **Power.** A train with no powered part crashes the game when drawn.
- **Replaces and flips.**
  - A vehicle replace keeps the middle of the train fixed: extra length goes half
    on each end.
  - `makeVehicleReverseCmd` mirrors the train about its middle, so a symmetrical
    train stays put.
  - Carriage positions are reported late for a tick or two after either.
  - A flip releases a held train. Hold it again with manual departure and
    `makeVehicleSetStoppedByUserCmd`.
  - After a run-around, the game reports the train arriving at the same stop
    again, in the same second, without it having moved. The mod ignores that
    repeat.
- **Sound sets.** Every frame, a sound set's update function must add exactly
  one track per track of the set. Adding none (to silence a vehicle) crashes the
  game (`AudioEmitterBackend.cpp`, `trackSrcs.size() == tracks.size()`). Add
  them at zero gain instead.
- **Vehicle replace costs money.** `makeVehicleReplaceCmd` is the game's
  "replace vehicles": it buys what it puts in and refunds what it takes out, with
  the amounts shown in the world. Its command data has `applyPurchaseCost`; the
  mod sets it to false on every replace.
- **Mod IDs.** A mod.io install's folder is the mod.io number, but its mod ID is
  the `modId` from its own `mod.json` (seen on 40 installed mods).
- **Reversed flag.** A part's `reversed` flag is relative to the train's head.
- **Lengths.** Vehicles are butted together by their `metadata.extent` along x,
  which need not be centred on the model's origin. The BR 75's is -6.42 to
  6.19 m. A carriage's reported position is its origin.
- **Cargo.** Passengers and goods belong to the vehicle entity, so they stay
  aboard through replaces and flips as long as the vehicle does.
- **Model repository.**
  - `modelRep.getAsTable` works in a load script but not in a game script, where
    `modelRep.get` works. In a `postRunScript` it gives no `lods`: a model's
    nodes can only be read as it loads (`addModifier("loadModel", ...)` in a
    `runScript`). Transformator parameters set there stay on the model.
  - `modelRep.addAsTable{..., modelPath}` makes a model from another's meshes, and
    `modelRep.setAsTable` works.
  - `soundSetRep.addAsTable`/`setAsTable` throw `std::exception`.
- **Free entities.** A free entity's custom state reaches its scripts as
  `currentInfo.customState`. `setModelInstanceAttributeVec3f(0, colour)` paints
  it.
- **Parts the engine places.** For a rail vehicle on the track, the engine
  places every node that directly holds an axle (body, tender, pony truck,
  bogie) and every fake bogie group (its positions are in the model's
  coordinates), as absolute user transforms in world
  coordinates, each kept at its place on the vehicle and turned to the track
  under its axles. It turns every axle that has no animation of its own. A free
  entity gets none of this. User transforms are numbered root 0, then depth
  first (traced on an A4 and a Black 5).
- **Scripting.**
  - `util.useFn` fails in the transformator scope. Use `ug_require` instead.
  - A `.script.lua` must define `data()`.
  - In a `.snd.lua`, sound paths are relative to its own folder, or absolute
    with `::/`.
- **GUI.** A plugin recipe's own child must be a layout.

## Credits

Made by LondoSpark. Built by reading the game's own scripts. Thanks to
Urban Games for shipping them readable.
