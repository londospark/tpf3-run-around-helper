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
- **Checking tenders and bogies offline:** `lua dev/tools/parts_sim.lua
  ghost_build.script.lua res/scripts/ghost_real.script.lua <radius> <model.mdl>...`
  prints, per level of detail, the worst wheel's distance off the track beyond
  its rigid part's own sag. Run it on the game's models (unzipped from
  `base/content/vehicle/train/*.zip`) and on mods' (`~/mod.io/common/10640/mods/`
  on the desktop) after changing anything in the parts code.
  `dev/tools/node_index.lua <model.mdl> [lod]` prints a model's node tree.
  `lua dev/tools/parts_audit.lua ghost_build.script.lua <model.mdl>...` checks
  the load step leaves each model as it was apart from our additions, and
  counts the keyframes added.
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

## Where we are (2026-10-09, desktop: tenders fixed offline)

All pushed. **On the other machine: `git pull`, `dev/sync_staging.sh`,
restart the game** (`mod.json` has a `runScript`: a full restart is needed). On this laptop the game is at
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
5. **Tender and bogies on the copy:** see the next section. Fixed offline on
   2026-10-09 (desktop); waiting for the live check.

### Tender and bogies on the copy (fixed offline; live check pending)

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

**What was wrong** (found 2026-10-09 on the desktop, offline, from the game's
models and the mod.io models; all generic, none model-specific):

1. **Each part turned about its node's origin.** An animation turns a node
   about its own origin (the game's wheel `.ani` files are pure rotations). A
   part's origin can be anywhere: the A4's tender node sits at the model's
   origin (x = 0), so its tender swung about the loco's middle; the Su's sits
   at the tender's front. Turning alone also can't move a tender sideways onto
   a curve. Result: tender wheels 0.8 m (Su) to 1.2 m (A4) off a 150 m curve.
2. **Lower levels of detail matched by node origin.** The A4's loco and tender
   nodes are both at x = 0, so on lower levels the loco got the tender's turn
   (the owner saw the loco turn, not the tender).
3. **An axle name on several nodes** counted once (a modded 8F's four driving
   axles share `lod_0_body_1`).
4. **A part on parts turned by its children's node origins**, which can be
   metres from their wheels (the 8F's), not by their wheels' centres.
5. **A part's turn measured from its direct parent only**, wrong when the
   part above it isn't placed (a group between).

**How it works now:**

- **Load** (`ghost_build`: `lodPartsSpec`, `partsSpecs`, `animateParts`, at
  `loadModel` via `partsAtLoad`): finds the parts (nodes holding axles, every
  node with a listed axle name; fake bogie groups; parts holding two or more
  parts, by their wheels' centres; never the root or devers' wrapper) and the
  axles to spin. Each part gets its reference points (a, b), the nearest placed
  part above it, and a **pivot** (`pivotX`): where its line meets its parent's.
  On a curve of any radius that's exact (y = x^2/2R near the vehicle: the lines
  through p, q meet at (ab - cd)/(a + b - c - d)). `runaround_yawJ` turns part
  J about that pivot (in the keyframes, in the node's own coordinates): frame 0
  is no turn, -30..+30 degrees over 1..6001 ms. Lower levels of detail: matched
  by node name, else by wheel centre. Spec: `runaround_partsN` = `"n G A"`, then
  per part `idx parent a b pivot`, then per axle `idx radius sign`.
- **The copy's frame** (`runaround_frame` = `"a b"`): the vehicle's own
  reference points, as the game places a vehicle: axles or fake bogies on the
  root (two or more: those alone), else those plus the centres of its top
  parts (Su: loco body and tender; diesel: its two bogies; articulated car:
  shared bogie and its own). The game script (`readFrame`, `framePlacement`)
  puts the copy on the line through the track under those points; without the
  parameter, along the track at its origin, as before.
- **Track** (`trackStrip`): 25 points, -24..+24 m (a Big Boy's tender reaches
  -17.8 m), in the copy's frame. `ghost_real` reads them as a smooth curve
  (Catmull-Rom): straight lines between points made an 8F's wheels 7.6 cm off.
- **Copy** (`ghost_real`, `placeParts`): for each part, carried by the part
  above it as drawn, the turn about its pivot that puts its reference points
  nearest the track (one point: with the track's direction there too). Plays
  `runaround_yawJ` at it; `runaround_spinK` by the distance over the radius.
  The four-times test scale is gone.

**Checked offline** (`dev/tools/parts_sim.lua` runs the mod's own load step and
copy update, draws the node tree with the frames played, and measures each
wheel against the track; `dev/tests/build/test_parts_geometry.lua` does it for
a model of each structure; the previous version fails it at 0.79 m):

- Every loco and tender in the base game, the DLC and the owner's 40 mods (605
  rail vehicles): on 150 m, 80 m and -100 m curves, every wheel within 3 cm of
  where its rigid part can put it (a long rigid wheelbase can't touch a curve at
  every axle; real trains are the same). Most locos 0-3 mm. Over 3 cm: only
  multiple units and a tram (which the mod doesn't run around).
- Where the curve changes under the loco: a 30 m transition, 0.4-1.7 cm; a
  straight running into a 150 m curve, 2.4-3.9 cm; an instant S-bend, up to
  7.7 cm (Big Boy), while it passes. One turn about one fixed pivot can't fit a
  changing curve exactly; a second animation per part would, if the game
  combines two on one node (unknown).
- The A4's far level of detail (one part, fake points 9 and -0.9) is 9 cm off a
  150 m curve: its line differs from the full detail's. Seen from far away only.
- **Real trains unaffected** (`dev/tools/parts_audit.lua` on all 605): after the
  load step every model is the model before plus only our animations and
  parameters: no node added, removed, renamed or moved, no animation of its own
  changed, at most one turn and one spin per node.
- **Memory:** turns only on powered vehicles (only the loco copy gets track);
  spins on all (coach and wagon copies' wheels turn as they draw forward). Each
  part's keyframes sized to it (`turnRange`: its turn on a 30 m curve, with
  spare; steps keeping its farthest point within 1 mm). 620k keyframes -> 257k
  (turns 413k -> 50k; the spins, 207k, were there before). On a 50 m curve the
  locos are still within 3 cm.
- **A whole run** (`test_frame_run`): on a curve, out, reversal and back, the
  copy never moves more than its speed allows in a tick or turns more than the
  curve; on its wheels' line both ways; ends on the same coupling place.
- **Before it moves** (`initialTrack`): the copy has its track from the moment
  it appears (the route both ways from its start, in its own x order, either
  facing), so the tender doesn't stand straight on a curved platform and snap
  onto the curve when it sets off.
- **Far levels of detail** whose parts don't match by name or place get the
  turn on the node of the same name (the Black 5's far tender is `group_29`).

**Could be done, needs a live probe first:**

- Share the spin keyframes: one shipped `.ani` (`FILE_REF`, as the game's
  wheels) instead of 5,600 copies. How a mod's `.ani` path resolves is unknown.
- A second animation per part (two pivots) would fit a curve that changes under
  a long loco exactly (Big Boy S-bend 7.7 cm). Whether the game combines two
  animations on one node is unknown.
- During a long final glide ("glided instead") the track isn't updated: the
  parts keep their last turns.
- Coach copies' bogies (raised by the owner): they'd need turns on unpowered
  vehicles again (memory: size them as above) and a strip per coach copy.

**Temporary things to remove once seen right live:** the `PROBE` (logging
only: `runaround_probe` set in `patchLoco` for steam locos on the stock path;
`PROBE` lines from real trains). It's kept for check 3 below.

**Next checks, in order** (restart first):

1. The Su, the A4 and the Black 5: the tender follows the curve, its wheels on
   the rails, and the loco body doesn't swing. `loco copy: placed on the line
   through the track under its wheels at ...` once per run; `loco copy parts:
   track bends ... parts turned ...` every 3 s (turns now real size).
2. Up close and from far away (lower levels of detail).
3. **Real trains are unaffected** by the added animations (never played on
   them; frame 0 is no turn): a real Su or Black 5 in normal running looks as
   before. With *devers* off, the `PROBE` lines should still list the tender and
   the small axles as moved.
4. With and without *devers*.
5. The coupling: no snap (`coupling place: ...`).
6. Then remove the probe.

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
