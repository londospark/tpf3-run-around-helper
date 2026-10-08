# AGENTS.md — Runaround Railways

Handover notes for whoever (human or agent) works on this mod next. Read this,
then `README.md` (player-facing, including the engine findings), then
`CODE_REVIEW.md`.

## What it is

A **Transport Fever 3** script mod (always "TpF3", never "TF3"). At a terminus
the player has set up, the loco uncouples, runs around its train along a route
the player clicked (a loop, headshunt or wye), and couples on at the other end,
instead of the game's instant flip.

- Published name: **Runaround Railways (ALPHA)**. Mod ID `runaround_helper_1`,
  folder `runaround_helper`.
- Author credit: **LondoSpark**.
- Wording: "runs around its train", "run-around" (never "run round").
- Repo: `git@github.com:londospark/tpf3-run-around-helper.git`, branch `master`.
- Status: 0.1.0-alpha. Works end to end live. Not yet tagged or published.

## Working rules (from the owner)

- **Investigate fully before asking the owner to test.** Reproduce with the
  offline mock, read the game's own scripts, and check traces before handing
  over a live test.
- **Fix root causes, not workarounds**, especially for regressions.
- **Keep README.md, CHANGELOG.md and MODIO.md current** with every change.
- **After each change:** run `dev/run_tests.sh`, then `dev/sync_staging.sh`
  (installs to the game), then commit and push. End commit messages with:

  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`

  (or the current model's equivalent line).
- **Say plainly that the mod is made with a lot of help from AI.** The owner
  wants nobody downloading it under false pretences and isn't ashamed of it.
  The README, MODIO.md (summary and description), `_metadata/modinfo.json` and
  CHANGELOG all say so. Keep it in every public text, and in any new one.
- Game script changes need a **full game restart**. Script mods load only at
  start-up.

## Layout

| Path | What |
|---|---|
| `res/scripts/runaround.script.lua` | game script: arrivals, route planning, the run (ghost loco, ghost rake, simple sequence), recouple, GUI command handling |
| `res/scripts/runaround_gui.script.lua` | train-window card (`RunAroundHelperVehiclePlugin`) and the route tool |
| `res/scripts/ghost_real.script.lua` | transformator and sound wrappers: stock behaviour for real trains; drives free-entity copies; hides carriages painted the flag colour |
| `ghost_build.script.lua` | load time. `runFn` (`runScript`): a `loadModel` modifier (`partsAtLoad`) that works out each rail vehicle's parts spec (`runaround_partsN` params) and adds the `runaround_yawJ` / `runaround_spinK` animations. `postRunFn` (`postRunScript`): patches every rail vehicle to use the wrappers, builds `runaround_ghost_dyn/` copies and `runaround_ghost_real/` markers |
| `res/audio/ghostwrap/` | 15 generated copies of the game's rail sound sets (absolute paths, wrapped update script) |
| `res/models/runaround_ghost/` | `real.trf.lua`, `real_tilting.trf.lua` (the game's own, wrapped); `chain.trf.lua` and `chain_emit.trf.lua` (another mod's, chained; the second also passes on the extra-model hooks); plus 55 static plain loco copies (last fallback) |
| `_metadata/` | `modinfo.json`, `0.png` logo (rendered from `logo_source.svg` with `rsvg-convert`) |
| `MODIO.md` | text for the mod.io page (the owner uploads it themselves) |
| `dev/` | **not shipped**: tests, tools, scripts (see below). `dev/tools/node_index.lua <model.mdl> [lod]` numbers a model's nodes as the game numbers user transforms |

`dev/`, `AGENTS.md` and `CODE_REVIEW.md` are excluded from the staging install
by `dev/sync_staging.sh`. Exclude them from the mod.io upload as well.

## Dev workflow

- **Tests:** `dev/run_tests.sh`. Needs `lua` 5.4 and `luac`, nothing else. Every
  test mocks the game API (`api.*`) and loads a script under test by path. The
  runner also fails on stray global reads, which is how a function used before
  its definition shows up (this crashed live once).
- **Install into the game:** `dev/sync_staging.sh [staging_area_dir]`. The
  default is `~/.local/share/Steam/userdata/*/3493540/local/staging_area/`
  (3493540 is TpF3's app ID).
- **Live log:** `~/.local/share/Steam/userdata/<id>/3493540/local/crash_dump/stdout.txt`.
  The mod's lines start with `[RunAroundHelper]`. README → "Reporting a problem"
  lists the useful lines.
- **Game files**, for reading the stock scripts: `<Steam library>/steamapps/common/Transport Fever 3/`.
  On the original machine that's `/mnt/games/SteamLibrary/...`.
  - Type definitions: `api/tealdef/api/type/*.d.tl` and `base/tealdef/`.
  - Stock scripts are zipped: `base/content/scripts.zip`, `game_mechanics.zip`,
    and so on.
  - Models are in `base/content/vehicle/{train,waggon}/*.zip`.
- **The mod ID** lives in `mod.json`. `ghost_build.script.lua`'s `MOD_ID`, the
  `.trf.lua` files and the generated sound sets must match it; the tests check.
- **`_content.json`** is the list of shipped files the game reads. After adding or
  removing a file, run `python3 dev/tools/gen_content.py`; the tests fail until
  you do.
- **Regenerating the sound wrappers** after a game update: `dev/tools/gen_snd.py`.
  Its input is `sndsrc/`, the game's 15 rail `.snd.lua` files unzipped from the
  vehicle zips, plus `_index.txt` (`<file> <resource dir>` per line). It writes
  to `res/audio/ghostwrap/`.
- `dev/tools/gen_ghost_models.lua` built the static plain loco copies in
  `res/models/runaround_ghost/`, from base-game `.mdl` files unzipped into `src/`.
- **Modding guide:** `~/tf3-mods/docs/Transport_Fever_3_Modding_Guide.pdf`, with
  a chapter of findings from this mod. Its build script (`build_pdf.py`) was in a
  temp folder and is **lost**; the PDF is the only copy. Copy it to the new
  machine. Rebuild it from a new source (Markdown, say) if it needs changing.

Note: the original tests lived in a session temp folder that was wiped. They
were rebuilt from the session transcript on 2026-10-07 and now live in `dev/`.
Keep new tests there.

## How a run works (current design)

Arrival (`OnArriveAtStop`) is only queued. `update()` moves things and returns
what needs doing. `postUpdate()` sends commands with callbacks; callbacks aren't
allowed inside `update()`.

1. Coach copies appear (each coach's own model, as a free entity).
2. The detach: the real loco and coaches stay on the train, painted
   `HIDE_COLOUR` (the coaches reversed in order and turned). Nothing is added or
   removed, so the replace buys and sells nothing. The wrapped transformator then
   scales every node to zero, bogies included. Passengers and cargo stay because
   the vehicles never leave the train.
3. The loco copy appears.
4. The hidden train is turned out of sight (`makeVehicleReverseCmd`).
5. **Pull:** the loco copy draws forward one loco length along its route, and
   the coach copies follow, ending exactly over their hidden coaches.
6. **Uncouple:** a 2.5 s pause.
7. The loco copy runs the route (reversals, facing kept). The route's last
   pieces are the **way back**, planned automatically from the last click to the
   station stop (`loop.backFrom`, route version 2). On entering it, the copy
   finds the point on it nearest its coupling place (`locateOnWayBack`), drives
   there on the track and brakes to a stop. Only what's left (centimetres) is
   the straight `approach` glide. With no ghost rake (the simple sequence), or
   coaches more than 2.5 m off the way back, it glides from where the clicked
   route ends, as before. The copy stops where the real loco's **origin will
   be once it is turned round** (`placeTarget`): the engine keeps a turned
   vehicle's extent in place, and a model's origin isn't in its middle.
   Throughout the run the copy's tender, pony truck and bogies turn to the
   track and its small axles spin: see "Tender and bogies on the copy".
8. `recoupleRake`: the real loco and coaches get their own paint back (matched
   by model and purchase time; the loco part is the same object throughout). The
   copies are destroyed.
9. The loco's facing is checked and corrected if needed, then the train is
   released.

**If a coach can't be hidden:** the simple sequence. The loco is hidden in place,
the coaches stay in view and move at the flip. **If the loco can't be hidden**
(no `runaround_ghost_hide/` marker): no run-around, and the card says why.

The creep (0.25 m stand-in steps) and the loco-for-a-stand-in swap are gone:
every replace they made bought and sold vehicles (seen live as money in the
world). The stand-in models went with them.

### Engine facts the design rests on (traced live)

The full list is in README → "Engine findings". The main ones:

- A replace keeps the train's **middle** fixed.
- A flip mirrors the train about its middle.
- Positions lag 1-2 ticks after either.
- A flip releases the hold, so hold again after each flip.
- A train with no powered part crashes the game.
- Vehicle lengths come from `metadata.extent`, which isn't centred on the
  model's origin.

### Approaches already tried and dropped

So that nobody repeats them:

- **Removing the coaches from the train and putting them back:** loses boarded
  passengers and cargo. The owner rejected it.
- **An invisible stand-in train with every coach replaced:** same problem.
  Also showed "2 locos".
- **Stand-ins added at the tail or balanced to stop the shift:** a replace
  always keeps the middle fixed, so the coaches *must* move a loco length.
  Hence the pull.
- **Swapping the loco for a stand-in:** every replace sold and bought it (money
  in the world, a loss each run). The loco stays on the train, hidden.
- **The creep as the main method:** works, but every step re-attaches the
  vehicle marker, which blinks.
- **Plain shipped copies of the loco:** no sound or paint. Using the real model
  through wrappers is far better.
- **Wheel animation frame wrapped to one turn:** blends backwards. Use a
  frame that keeps increasing, computed from a motion segment.

## Where we are (2026-10-08 evening, laptop; handing to the desktop)

All pushed. **On the desktop: `git pull`, `dev/sync_staging.sh`, restart the
game** (`mod.json` changed: there's now a `runScript`, so a full restart is
needed). On this laptop the game is at
`/data/games/SteamLibrary/steamapps/common/Transport Fever 3/`; on the desktop
`/mnt/games/...`.

The day's work, in order:

1. **Status review and alpha checklist.** Save and load mid-run passed live;
   a run without *devers* passed live; a steam loco runs without crashing.
2. **Wheels backwards on the final glide** (route ending past the points with
   no clicked reversal): the glide now takes the wheel direction from its own
   movement (`run.approachBackwards`). Fixed and seen.
3. **The way back** (route version 2): the route goes on from the last click to
   the station stop, and the copy sets back onto the coaches along the track
   instead of a straight glide. Seen live working: `way back: the loco sets
   back 25.0 m along the track to its coaches (0.12 m off the track there)`.
   Also: planned legs that double back at points (hairpins) are rejected
   (`hasHairpin`).
4. **The snap at coupling** (seen live: the loco jumped ~9 m onto the coaches
   with the Su): fixed by `placeTarget`. **Not yet seen live.** Log:
   `coupling place: turned round from the hidden loco - the loco's origin
   9.30 m from the hidden loco's`.
5. **Tender and bogies on the copy:** see the next section. In progress.

### Tender and bogies on the copy (in progress)

**The problem.** For a real train on the track, the engine places the loco
body, tender, pony truck and bogies, and spins the small axles. The run's loco
copy is a free entity: the engine does none of that, so the copy was one rigid
piece, with its tender wheels off the rails on curves. It affects every tender
loco, and the coach copies' bogies.

**What the engine does** (probed live on an A4 and a Black 5 with *devers*
off, `PROBE` lines; README → Engine findings): it places, as absolute user
transforms in world coordinates, every node that directly holds an axle and
every fake bogie group. Each keeps its centre where it is on the vehicle and
only turns to the track under its axles. It spins every axle that has no
animation of its own (not the driving wheels). User transforms are numbered
root 0, then depth first. Inferred, not probed: a part holding two or more
such parts (the Su's tender body on two bogies) turns with them.

**What we learned the hard way** (each from a live test):

- `modelRep.getAsTable` in the `postRunScript` gives **no `lods`**. Nodes can
  only be read in a `loadModel` modifier, as *devers* does.
- Params set in the modifier survive to the game (`loco params at setup: ...
  given as table ... parts spec: yes; devers rest poses: yes`). Our modifier
  runs **after** *devers*' (the Su's spec counts 39 nodes = 38 + its wrapper).
- A free entity has **no user transforms**: `getUserTransfs()` is empty and
  `setUserTransf` is accepted but does nothing. So the parts are driven by
  **animations**, which do play on a free entity (the driving wheels show it).
- An animation applies on top of the node's rest transform (the game's wheel
  `.ani` files are pure rotations about the wheel). Keyframe matrices are
  column-major (the Black 5's rod keyframes have their translation at 13-15).
- Fake bogie positions are in model coordinates (the Su's far tender sits at
  -9.14 and -13.87, its bogies' places).

**How it works now:**

- **Load** (`ghost_build`, `partsAtLoad`): `partsSpecs` finds the parts to turn
  (nodes holding axles, fake bogie groups, parts holding two or more of those;
  never the root or *devers*' single wrapper node) and the axles to spin (no
  animation of their own), per level of detail. It writes them as
  `runaround_partsN` params: `"n G A"`, then per part `idx parent x y z yaw
  (model) lx ly lz lyaw (local) px py pz pyaw (parent) a b (reference points'
  x)`, then per axle `idx radius sign`. `animateParts` adds `runaround_yawJ`
  (KEYFRAME_MATRIX, -30..+30 degrees over 0..6000 ms) to part J and
  `runaround_spinK` (a turn over 3600 ms) to axle K, J and K counting the
  full-detail spec. Lower levels get the same names on the parts at the same
  place. The dyn copies copy the params from the loaded model.
- **Game script** (`runaround.script.lua`): each tick on the route,
  `trackStrip` sends the copy 17 track points (-16..+16 m along its facing, in
  its own frame), following the route onto pieces that join and straight on
  where none does. Motion segments carry `s0`, the signed distance along the
  copy's facing, for the axles.
- **Copy** (`ghost_real`, `placeParts`): turns each part to the chord of the
  track under its reference points, relative to its parent, and plays
  `runaround_yawJ` at that angle; plays `runaround_spinK` at the signed
  distance over the axle's radius.

**State at hand-over.** Seventh live test (Su, *devers* on, turns drawn x4):
the loco body visibly turned, the tender didn't. Cause: the Su's tender body
holds no axles (they're in two bogies under it). Fixed by the "parts holding
two or more parts" rule (commit `57078fe`). **Not yet seen live.**

**Temporary things to remove once the tender is seen right:**

- `PARTS_TEST_SCALE = 4` in `ghost_real.script.lua`: the copy's part turns are
  drawn four times larger so their direction is obvious, and logged every 3 s
  (`loco copy parts: track bends X deg (left/right) over 16 m; parts turned
  ...`). Set it to 1, and the three x4 expectations in
  `dev/tests/ghost_real/test_parts.lua` back to x1.
- The `PROBE` (`runaround_probe` set in `patchLoco` for steam locos on the
  stock path; `PROBE` lines from real trains). Remove both halves.
- `loco parts: ...` (load), `loco params at setup: ...` (setup) and the
  one-off `loco copy parts: turning ...` lines can stay or go; they're capped.

**Next checks, in order** (restart first):

1. The Su's tender turns towards the inside of curves with the loco (x4 makes
   it obvious); the `track bends ... parts turned` lines list 4 parts.
2. The Black 5 and the A4 the same.
3. **Real trains are unaffected** by the added animations (never played on
   them): a real Su or Black 5 in normal running still bends its tender on
   curves. With *devers* off, the `PROBE` lines should still list the tender
   and the small axles as moved. If not, move the animations to the copies
   only (the dyn copies are built with `modelPath`, so that would need their
   own node tree; see `addGhostModel`).
4. With and without *devers* (the owner needs both).
5. The coupling: no snap (`coupling place: ...`).
6. Then x1, remove the probe, and update the README if anything changed.

**Not started, raised by the owner:** the coach copies' bogies on a curved
platform stay straight (no track is sent for coaches, and they stand there the
whole run). Plan: send each coach copy a track strip once, at the pull, from
the route's first pieces and the way back, which cover the platform; the same
`placeParts` then turns their bogies.

**Known, not looked into:** a steam loco's copy doesn't chuff (the rest of its
sound plays).

### Still to check before the public alpha

- **Everything in "Tender and bogies on the copy" above**, and the snap fix.
- **The way back** on other layouts: a wye, a balloon loop (no reversal; the
  route returns over the platform), a route whose last click is on the
  platform. Older saved routes are re-planned at the first arrival (`saved by
  an older version: planning it again`).
- **Removing the mod mid-run** (save and load mid-run passed).
- **Goods wagons with loads:** the copies should show the loads
  (`vehicleStaticInfo.carriageEntity`).
- **A curved platform (M4):** `coaches turn up to N degrees`, and the copies line
  up with the hidden coaches when they reappear.
- **The refusals:** a route whose first points head back into the train (N2), a
  train at an alternative platform (N1). Each should show the card's message and
  a normal departure.
- **Failure handling (H1-H4)** and the M5 mismatch check: offline only.
- **Bogies hidden**, and no `Could not find texture` warnings.
- **`mcs_basisset` wagons** (`mcs_gtw1_base`), chained through
  `chain_emit.trf`: the load log should no longer say `left alone` for
  `maikc_train_all.trf`. A train of them should get the ghost rake (hidden and
  drawn forward), not the simple sequence, and look and animate as before when
  shown again.
- On the first mod.io install, `loco setup: SKIPPED` must not appear.

### Seen working live

- 2026-10-07 (*devers* on): one run per arrival, the repeat arrival ignored
  (N5); the loco, not a coach, chosen (N6); the loco stays on the train,
  hidden, no money in the world (N7); *devers* chained (`368 through another
  mod's transformator`) with the ghost rake running; the start check `0.3 m
  from the route`.
- 2026-10-08: save and load mid-run; a run without *devers*; a steam loco with
  no crash; the way back (`sets back 25.0 m along the track ... 0.12 m off`);
  the final glide's wheel direction.

### Bugs found in review

`CODE_REVIEW.md` has two reviews. From the first, H1-H4, M1, M3, M4 and most
low items are fixed; M2, M5-M8 and the route-planning cost are open. The second
review (at `4230bc1`) adds N1-N4: alternative platforms, a route that starts
backwards, the card under another mod ID, and a missing stock sound function. It
also recommends splitting `runaround.script.lua` into modules, but only after a
live probe of how a mod `ug_require`s its own files (see "Structure" there).
N1 and N2 (the owner rated them high) and N4 are fixed. N3 is made explicit.

On the first mod.io install, check the log for `loco setup: SKIPPED`. If it's
there, the game loaded the mod under a different ID from `mod.json`'s (see M3).

### Limitations

These are documented in the README:

- One loco plus coaches or wagons. No multiple units or double-heading.
- The running loco ignores signals and reservations.
- Run-arounds belong to line plus stop **index**: inserting stops earlier in a
  line breaks them. Following the station instead was offered to the owner but
  not decided.
- Wheel radius is assumed to be 0.9 m.
- Modded vehicles with their own transformator or sound set can't be hidden or
  driven as themselves. They use copies; such coaches stay in view (simple
  sequence), and such a loco can't run around.
- The smooth sequence needs the loco to be part 1 of the train.

## Next steps

1. **The owner's checks** in "Still to check before the public alpha" above. Read
   their `stdout.txt` lines before changing anything.
2. Then tag `v0.1.0-alpha` on GitHub. The owner uploads to mod.io themselves
   (from the staging install, which leaves out `dev/`, `AGENTS.md`,
   `CODE_REVIEW.md` and `MODIO.md`), pastes `MODIO.md` into the page, and adds
   their video.
3. Add a chapter on the hidden-coach technique to the modding guide (new source
   needed, see above).
4. Later: loops keyed by station rather than stop index; multiple units.
