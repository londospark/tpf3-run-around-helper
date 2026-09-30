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
3. Record the path the loco should drive, in order, using either:
   - **Pick edges on map** - toggles a click-to-pick tool. Click the track
     pieces of your loop in the world, one per edge, in order. *(Newly rebuilt,
     see "Known issues".)*
   - **Capture edge here** - records the edge the selected train is currently
     on (needs a train physically sitting on the loop track).
4. **Undo edge** removes the last captured edge. **Loco end** and
   **Flip on recouple** control which end of the consist the loco rejoins and
   whether its facing flips; **Speed** bumps the ghost loco's speed. If the loco
   comes back on the wrong end or facing the wrong way, toggle these.

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
- Clicks cannot tell direction, so picked edges default to `forward = true`.
- **The first real run-around crashed the game** (`!m_betweenChanges`): commands
  were being sent from inside the arrival-event handler, which the engine
  forbids. Starts are now queued by the handler and sent from the next
  `update()`. This fix has not been run in game yet, so the detach / animate /
  recouple sequence is still untested end to end;
  the loco-end and flip-on-recouple toggles exist because the correct values
  are not known ahead of time.
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
