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
2. **Add loop from this vehicle** captures the line, the stop and a candidate
   locomotive. **Cycle loco candidate** steps through the consist's parts until
   the right locomotive model is selected.
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
   the toggle button again. While pick mode is on it replaces the normal
   click-a-train behaviour, so the vehicle window (and this panel) closes; click
   the train again afterwards to bring the panel back.
4. **Loco end** and **Flip on recouple** control which end of the consist the
   loco rejoins and whether its facing flips; **Speed** bumps the ghost loco's
   speed. If the loco comes back on the wrong end or facing the wrong way,
   toggle these.

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
