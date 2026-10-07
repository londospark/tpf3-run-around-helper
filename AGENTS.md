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
- Game script changes need a **full game restart**. Script mods load only at
  start-up.

## Layout

| Path | What |
|---|---|
| `res/scripts/runaround.script.lua` | game script: arrivals, route planning, the run (ghost loco, ghost rake, creep fallback), recouple, GUI command handling |
| `res/scripts/runaround_gui.script.lua` | train-window card (`RunAroundHelperVehiclePlugin`) and the route tool |
| `res/scripts/ghost_real.script.lua` | transformator and sound wrappers: stock behaviour for real trains; drives free-entity copies; hides carriages painted the flag colour |
| `ghost_build.script.lua` | load-time `postRunScript`: patches every rail vehicle to use the wrappers, builds `runaround_ghost_dyn/` copies and `runaround_ghost_real/` markers |
| `res/audio/ghostwrap/` | 15 generated copies of the game's rail sound sets (absolute paths, wrapped update script) |
| `res/models/runaround_standin/` | 176 invisible 1 kW stand-ins `standin_cm<cm>.mdl`, 0.25-44 m, plus blank icons |
| `res/models/runaround_ghost/` | `real.trf.lua`, `real_tilting.trf.lua`, plus 55 static plain loco copies (last fallback) |
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
2. The detach: the loco becomes a stand-in of the same length, and the real
   coaches stay coupled, painted `HIDE_COLOUR`. The wrapped transformator then
   scales every node to zero, bogies included. Passengers and cargo stay because
   the vehicles never leave the train.
3. The loco copy appears.
4. The hidden train is turned out of sight (`makeVehicleReverseCmd`).
5. **Pull:** the loco copy draws forward one loco length along its route, and
   the coach copies follow, ending exactly over their hidden coaches.
6. **Uncouple:** a 2.5 s pause.
7. The loco copy runs the route (reversals, facing kept) and brakes against the
   far coach.
8. `recoupleRake`: the real loco replaces the stand-in, and the coaches get their
   own paint back (matched by model and purchase time). The copies are destroyed.
9. The loco's facing is checked and corrected if needed, then the train is
   released.

**Fallback (the creep):** if any coach can't be hidden (its transformator wasn't
wrapped), the real coaches creep forward in 0.25 m replace steps. It works, but
the vehicle marker jitters.

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
- **The creep as the main method:** works, but every step re-attaches the
  vehicle marker, which blinks.
- **Plain shipped copies of the loco:** no sound or paint. Using the real model
  through wrappers is far better.
- **Wheel animation frame wrapped to one turn:** blends backwards. Use a
  frame that keeps increasing, computed from a motion segment.

## Known issues

### Waiting for a live test

These were just changed and pass offline, but haven't been seen in game:

- **The start check (N1, N2):** the log should say
  `ghost starts on route piece N, M m along it (0.x m from the route)`. A
  normal arrival must NOT log `run-around NOT started`. If it does, the reason
  says which check fired; read the distance it gives before changing
  `ON_ROUTE_M`.

- **Bogies hidden.** All nodes are now scaled to zero, not just the root. The
  owner's last test showed bogies still visible with root-only scaling.
- **The pull and uncouple sequence** (steps 5-6).
  - `ghost rake: train drawn up ... loco ghost N m from where it would be coupled`
    should be about 0.
  - It assumes the route leaves the platform forwards.
- **Wagon loads on copies**, now keyed by `vehicleStaticInfo.carriageEntity`.
- **Loco length from `metadata.extent`.**
  - The log should say `(from its model)`.
  - Trains with a single coach, or mixed wagons, now use the ghost rake too.
- **Blank stand-in icons:** no more "Could not find texture ... _icon20.tga"
  warnings.
- **Failure handling (H1-H4)**, tested offline only (`test_failures.lua`): the
  restore after a failed start, recouple retries and "Stuck" on the card, the
  watchdog. None of these paths has been hit live.
- **Shared file names (M1):** the load summary now ends with
  `N left alone (file name shared)`. It should be 0 with no other mods. Markers
  and copies are still named by file name: that's proven live, while full names
  are not shown to match between load and game script, so don't switch to them
  without a live check.
- **Coach copies follow a curved platform (M4)** during the pull. The log line
  `ghost rake: the train draws forward ... (coaches turn up to N degrees)` gives
  the turn. On a curve, check the copies line up with the hidden coaches when
  they reappear.
- **`_content.json` now lists the stand-in icons.** If the
  "Could not find texture ... _icon20.tga" warnings came from the stale list,
  they should be gone now.

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
  driven as themselves. They use copies, and the coaches use the creep.
- The smooth sequence needs the loco to be part 1 of the train.

## Next steps

1. **The owner's next live test** of the above. Read their `stdout.txt` lines
   before changing anything.
2. Check the first mod.io install's log for `loco setup: SKIPPED` (M3).
3. Tag `v0.1.0-alpha` on GitHub. Help the owner publish using `MODIO.md`; they
   upload to mod.io themselves and will add a video link later.
4. Add a chapter on the hidden-coach technique to the modding guide (new source
   needed, see above).
5. Later: loops keyed by station rather than stop index; multiple units.
