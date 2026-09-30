# Runaround Railways

**Your locomotive runs round its train at the terminus, instead of the game's
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

> **Status: early release.** It works end to end in a live game, but it has
> only been tried on a few layouts. Please report problems. See
> [Reporting a problem](#reporting-a-problem).

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
   train is at first. Click the station where the loco should run round. The
   run-around is named after the station.
3. **Draw the route.** Click **Edit route on map**, then click a few points on
   the track where the loco should go, in order. For a simple loop that's
   usually:
   1. a piece of track beyond the points, where the loco will stop and reverse;
   2. a piece of the loop, or the other road through the station;
   3. a piece of track beyond the far end of the train.

   You don't click every piece of track, the station, or the exact reversing
   spot. The route is planned with the game's pathfinder, and the loco reverses
   just clear of the points (10 m past them). Right-click, **Esc** or **Done**
   when finished.
4. **Check it.** The card shows the route's length, reversals and points. A
   warning says which two points could not be joined.
5. **That's it.** The next time a train on that line arrives there, its loco
   runs round.

## The Run-around card

In the train window, one card per run-around on the train's line.

- **Route line**: length, reversals and points, or what's missing.
- **While a run-around is happening**: a progress bar and what the loco is doing
  (running round, turning the train, coupling on).
- **Edit route on map / Done**: draws the route and adds clicked points.
  - **Undo point** and **Clear points** appear while editing.
- **Show / Hide**: draws the route without editing.
- **Settings** (the collapsible part):
  - **Name**: click the pencil to rename.
  - **Speed** and **Acceleration** of the loco while it runs round.
  - **Loco**: *automatic* (the default) or a chosen part of the train.
    Automatic picks the part standing nearest the first route point, which works
    for trains with different locos on the same line.
  - **Delete run-around**: asks for confirmation first.
- **Add a run-around at...**: buttons for the line's other stops.

### The route on the map

While editing or showing:

- the route is coloured from **blue** at the start to **orange** at the end;
- the pieces where the loco reverses are **purple**;
- the pieces you clicked have a **white line**.

## What happens during a run-around

1. The train arrives and is held.
2. The loco uncouples. An invisible stand-in takes its place, because a train
   without a powered vehicle crashes the game.
3. The loco drives the route, reversing where planned. It keeps facing the way
   it was facing.
4. Meanwhile the coaches creep forward by one loco length, and the train is
   turned round. See [The coaches creep forward](#the-coaches-creep-forward).
5. The loco comes back, brakes to a stop against the far coach, and couples on.
6. The train leaves, with the loco leading.

## Tips and limitations

- **One loco plus coaches or wagons.** Multiple units and double-heading are not
  handled.
- **The running loco ignores signals** and doesn't reserve track. Use a loop
  that other trains won't be on at the same time.
- **Run-arounds belong to a line and a stop, not to a train.** Every train on
  the line does it there, clones included. A train moved to another line only
  does it where that line has its own run-around.
- **Stop numbers:** a run-around remembers its stop by its position in the line.
  If you insert or remove stops earlier in the line, check it still points at
  the right station.

### The coaches creep forward

When the loco couples on at the far end, the train is a loco length further
along the track than it was. In this game that can only happen by the coaches
moving. A vehicle swap keeps the middle of the train fixed, and the flip mirrors
the train about its middle.

So instead of the coaches jumping, they creep forward a quarter of a metre at a
time while the loco is away. The flip happens at the halfway point, when the
train is exactly symmetrical, so it moves nothing. A small invisible part stays
at the front throughout, so the game's vehicle marker keeps still.

### Modded locos

Every rail loco is prepared when the game loads, including modded ones.

- **Uses the game's own sound set and train animation script:** runs round as
  itself, with its own sound, smoke, wheels and paint. That's every base-game
  and DLC loco, and many mods.
- **Brings its own sound set or animation script:** runs round as a copy of its
  own model, with its smoke, wheels and paint. It has sound only if it uses one
  of the game's sound sets. The game doesn't let mods create sound sets while
  it runs, so only sound sets shipped as files can be wrapped.

### Wheels

The wheels turn with the distance the loco travels. Scripts can't read a loco's
driving-wheel radius, so a typical 0.9 m is assumed. Wheels on very large or
very small driving wheels may turn a little too fast or too slow.

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
| `loco setup: N locos; M can be their own ghost, ...` | at start-up, how many locos were prepared |
| `ghost model: using the loco's OWN model` | the loco runs round as itself |
| `ghost first step N m from where the loco stood` | should be about 0 |
| `creep: ...` | the coaches moving and the train being turned |
| `trace ...` | carriage positions at each step (set `LOG_TRACES = false` to silence) |

## Advanced settings

These are in the files, for tinkering. Most people won't need them.

`res/scripts/runaround.script.lua`, `CONFIG`:

| Setting | Default | What it does |
|---|---|---|
| `detachEnabled` | `true` | turns the run-around off entirely |
| `reverseBeforeRecouple` | `true` | turn the train before the loco couples on, so the game doesn't flip it back |
| `creepLayout` | `true` | creep the coaches forward; `false` = they jump once at the flip |
| `creepStep` | `0.25` | metres per creep step: bigger = fewer, larger steps |
| `creepStartDistance` | `30` | how far the loco drives before the creep starts |
| `useRealModel` | `true` | run round as the loco's own model when possible |
| `useEffectGhosts` | `true` | otherwise use the copy with smoke and sound |
| `verifyFacing` | `true` | check the loco's facing after coupling, and correct it |
| `LOG_ARRIVALS`, `LOG_TRACES` | `true` | logging |

`ghost_build.script.lua`: set `PATCH_LOCOS = false` to leave every loco
untouched. Only the copies are then used.

---

## For modders: how it works

| File | Role |
|---|---|
| `res/scripts/runaround.script.lua` | the game script: queues a run when a train arrives, swaps the loco for a stand-in, drives the "ghost" along the planned route, creeps and flips the train, recouples |
| `ghost_build.script.lua` | the load-time script (`postRunScript`): prepares every rail loco |
| `res/scripts/ghost_real.script.lua` | wrappers for the game's sound and train transformator functions |
| `res/audio/ghostwrap/*.snd.lua` | the game's own rail sound sets, generated with absolute sound paths and the update script wrapped |
| `res/models/runaround_ghost/` | `real*.trf.lua` (the stock train and tilting-train transformators, wrapped), plus plain silent copies of the base locos as a last fallback |
| `res/models/runaround_standin/` | the invisible 1 kW stand-ins, 0.25 to 44 m in 0.25 m steps |
| `res/scripts/runaround_gui.script.lua`, `runaround_vehicle.res.lua` | the train window card and the route tool |

More detail:

- **The ghost.** A free entity (`makeCustomEntityCreateCmd`) drawn from the
  loco's own model. That needs `ghost_build` to have pointed the loco's sound set
  and transformator at the wrappers. The wrappers behave exactly as the game's
  functions for a real train. For the ghost, they build vehicle data from its
  custom entity state and run the game's own functions on it. The state is
  `{ speed01, power01, state = { speed, power, vx, vy, color, dir, seg } }`.
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
- **Reversed flag.** A part's `reversed` flag is relative to the train's head.
- **Model repository.**
  - `modelRep.getAsTable` works in a load script but not in a game script, where
    `modelRep.get` works.
  - `modelRep.addAsTable{..., modelPath}` makes a model from another's meshes, and
    `modelRep.setAsTable` works.
  - `soundSetRep.addAsTable`/`setAsTable` throw `std::exception`.
- **Free entities.** A free entity's custom state reaches its scripts as
  `currentInfo.customState`. `setModelInstanceAttributeVec3f(0, colour)` paints
  it.
- **Scripting.**
  - `util.useFn` fails in the transformator scope. Use `ug_require` instead.
  - A `.script.lua` must define `data()`.
  - In a `.snd.lua`, sound paths are relative to its own folder, or absolute
    with `::/`.
- **GUI.** A plugin recipe's own child must be a layout.

## Credits

Made by LondoSpark. Built by reading the game's own scripts. Thanks to
Urban Games for shipping them readable.
