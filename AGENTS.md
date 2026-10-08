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
| `ghost_build.script.lua` | load-time `postRunScript`: patches every rail vehicle to use the wrappers, builds `runaround_ghost_dyn/` copies and `runaround_ghost_real/` markers |
| `res/audio/ghostwrap/` | 15 generated copies of the game's rail sound sets (absolute paths, wrapped update script) |
| `res/models/runaround_ghost/` | `real.trf.lua`, `real_tilting.trf.lua` (the game's own, wrapped); `chain.trf.lua` and `chain_emit.trf.lua` (another mod's, chained; the second also passes on the extra-model hooks); plus 55 static plain loco copies (last fallback) |
| `_metadata/` | `modinfo.json`, `0.png` logo (rendered from `logo_source.svg` with `rsvg-convert`) |
| `MODIO.md` | text for the mod.io page (the owner uploads it themselves) |
| `dev/` | **not shipped**: tests, tools, scripts (see below) |

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
   route ends, as before.
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

## Where we are (2026-10-08, handing back to the other machine)

Latest work, done on the second machine (desktop), all pushed. **On the other
machine: `git pull`, then `dev/sync_staging.sh`, then restart the game.**

- Reviewed the other machine's 13 commits of 2026-10-07 (`50c57a2`..`606ecd5`):
  they were sound. Fixed two slips in this file (`751a745`).
- **Extra-model hooks passed on** (`daa8bcb`). A transformator that declares
  `getEmittableModelsScript` and `computeEmittedModelsScript` is now chained
  through `chain_emit.trf.lua`, and can be hidden. While hidden, it emits nothing.
  - Signatures checked against the game's hot-air balloon, `transformator_util.tl`
    and `mcs_basisset`'s `maikc_train_all.script.tl`.
  - In the owner's mods, the only users are 15 **goods wagons** in
    `mcs_gtw1_base` (mod.io 5690808, needs `mcs_basisset`, 5684258). No loco in
    the owner's mods was unhideable.
  - None of those wagons sets `randomGroups`, so they emit nothing today. The
    forwarding itself won't be seen working with them.
  - **Live test pending:** see "`mcs_basisset` wagons" under "Still to check".
- **AI disclosure** (`ff36b88`). The README, MODIO.md, `modinfo.json` and the
  CHANGELOG say the mod was made with a lot of help from AI. This is now a
  working rule (above).
- Also on the desktop: the owner's mod.io downloads are in
  `~/mod.io/common/10640/mods/<id>/` (handy for reading other mods' scripts).
  The game is at `/mnt/games/SteamLibrary/steamapps/common/Transport Fever 3/`.
- Ideas raised but not started:
  - A live probe of whether full model names match between load time and the
    game script. If they do, vehicles that share a file name could be keyed by
    full name (M1).
  - A list of API requests for Urban Games. The main three: a per-carriage
    visibility command, a replace that doesn't buy or sell, and vehicle info for
    free entities. Then mod-relative paths, model metadata readable from game
    scripts, stackable transformators, hook documentation, and a "shunt N metres"
    command.

## Known issues

### Seen working live (2026-10-07, owner's save with the *devers* mod: Real Track Cant, mod ID `devers_1`, mod.io 6418700)

- One run per arrival; the game's repeat arrival is ignored (N5); the loco, not
  a coach, is chosen (N6).
- The loco stays on the train, hidden: `money: the detach/recouple changed the
  balance by 0`, no money in the world (N7). No crash after the sound fix.
- Chaining *devers*' transformator: `368 through another mod's transformator`,
  and the ghost rake ran (`train drawn up 23.8 m; loco ghost 0.35 m from where it
  would be coupled`).
- The start check on a normal arrival: `0.3 m from the route`.

### Still to check before the public alpha

Offline-tested only:

- ~~Save and load mid-run (M7)~~: **passed live** (2026-10-08). Removing the
  mod mid-run is still untested.
- ~~A steam loco~~: **no crash live** (2026-10-08), so the silenced output keeps
  the track count. Seen, both documented as known in the README and MODIO.md:
  - **No chuffing** on the running copy; the rest of its sound plays. Not looked
    into yet. A guess: the chuff needs state the copy's sound update doesn't get.
  - **The tender's wheels don't follow the track exactly.** Also without
    *devers*, so it's this mod (see "The tender" below).
  - Wheels turned backwards on the approach glide when the route ended past the
    points with no reversal (the last reverse into the platform is the glide,
    not a route reversal). **Fixed:** the glide sets the wheel direction from
    its own movement against the loco's facing (`run.approachBackwards`,
    `test_flow.lua`). Needs a live re-check.
- **The way back** (2026-10-08, offline only): after the last click the route
  goes on to the station stop, and the loco copy sets back onto the coaches
  along the track instead of the straight glide. Check: the card's route ends
  "back to the station"; the log says `way back: the loco sets back N m along
  the track`, not `glided instead`; the copy follows the points into the
  platform and stops against the far coach. Older saved routes are re-planned
  at the first arrival (`saved by an older version: planning it again`).
  Also new: planned legs that double back at points (a hairpin) are rejected
  (`hasHairpin`); the pathfinder starts from a node, so it never knew which
  piece the loco came in on. `findPath` (from an edge with direction) exists
  in the API but nothing uses it, so it wasn't relied on.
- **The tender** (Black 5): the owner says the loco and tender move as one
  rigid object; seen without *devers* too, so it's this mod. Not looked into
  yet.
- **Goods wagons with loads:** the copies should show the loads
  (`vehicleStaticInfo.carriageEntity`).
- **A curved platform (M4):** `coaches turn up to N degrees`, and the copies line
  up with the hidden coaches when they reappear.
- ~~Without *devers*~~: **passed live** (2026-10-08), one run on the stock-wrapped path.
- **The refusals:** a route whose first points head back into the train (N2), a
  train at an alternative platform (N1). Each should show the card's message and
  a normal departure.
- **Failure handling (H1-H4)** and the M5 mismatch check: offline only.
- **Bogies hidden**, and no `Could not find texture` warnings.
- **`mcs_basisset` wagons** (`mcs_gtw1_base`), now chained through
  `chain_emit.trf`: the load log should no longer say `left alone` for
  `maikc_train_all.trf`. A train of them should get the ghost rake (hidden and
  drawn forward), not the simple sequence, and look and animate as before when
  shown again.

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
