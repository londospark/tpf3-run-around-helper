# Changelog

## 0.1.0-alpha (first public test release)

- Made with a lot of help from AI: most of the code, tests and documentation
  were written by an AI assistant (Anthropic's Claude, using Claude Code),
  directed and tested in game by LondoSpark.

- Locos run around their train at any terminus you set up, instead of the
  instant flip.
- Set up in the train window. Click a few points on the track: the route and the
  reversing spots are planned for you. The route is drawn on the track while you
  edit.
- The loco runs around as itself, with its own sound, smoke, wheel animation and
  paint. That covers every base-game and DLC loco, and modded locos that use the
  game's sound sets and train scripts.
- The loco keeps its facing: it couples on at the far end, the right way round.
- While the loco is away, the loco and coaches are shown as copies of
  themselves. The real coaches and wagons stay in the train, hidden, so
  passengers and goods stay aboard. The hidden train is turned out of sight, and
  the train draws forward a loco length with the loco still coupled, stops, and
  the loco uncouples, instead of the coaches jumping.
  Copies of goods wagons show the wagon's load.
- A run-around never leaves a train stuck or broken. If a run can't start, the
  train is put back exactly as it was. If the loco can't be coupled back on, the
  train stays held and the mod keeps trying, with **Stuck** on the card. A run
  that stalls is given up after a time limit, and the train is put back. The
  copies are always cleared away, also when a train is sold mid-run.
- The run-around card says what the train is doing: turning, drawing forward,
  uncoupling, running around, coupling on, or stuck.
- A light engine (a loco on its own) is left alone.
- On a curved platform, the coaches follow the curve as the train draws
  forward, instead of sliding straight.
- Two mods with a loco of the same file name no longer get in each other's way:
  such locos are left untouched and run around as a generic copy, rather than
  one taking the other's place.
- Safe if installed under an unexpected mod ID: trains are then left untouched.
  The run-around card won't appear in that case, and the log says so.
- A train that stops at another platform than the route starts from, or whose
  route would set off towards its own coaches, doesn't run around that time. It
  leaves the normal way, and the card says why.
- Works alongside mods that give trains their own animation script, such as
  *devers*: the coaches are hidden and the train draws forward, with no flashing,
  and the other mod's animation is kept. Only scripts that this mod can check at
  start are chained; anything else is left exactly as it was.
- Also works with animation scripts that add extra models to a vehicle, such as
  `mcs_basisset`'s (used by its goods wagons): those vehicles can now be hidden
  too, their extra models are kept, and they vanish with the vehicle while it is
  hidden.
- Fixed: a run-around sold the loco and bought it back each time (it was taken
  off the train for an invisible stand-in), with the money shown in the world.
  The loco now stays on the train, hidden, like the coaches. Nothing is bought
  or sold. The step-by-step coach creep, which did the same, is gone: coaches
  that can't be hidden now stay in view and move once.
- Fixed: straight after a run-around, the game reports the train arriving
  again, and a second run-around started on the turned train, running a coach
  around as the "loco". Repeat arrivals at the same stop are now ignored.
- The route now goes on from your last point back into the station by itself,
  reversing past the points if it has to. The loco sets back onto its coaches
  along the track, instead of sliding there in a straight line (which cut
  across points and curves). The card's route summary ends with "back to the
  station". Routes made with an earlier version are planned again the next
  time a train arrives.
- While the loco runs around, its tender, pony truck and bogies follow the
  track on curves, and their wheels turn. Before, the moving loco was one rigid
  piece, with the tender's wheels off the rails on curves.
- Planned routes no longer double back from one branch of a set of points to
  the other (a move no train can make).
- Fixed: the wheels turned the wrong way on the last stretch back to the
  coaches when the route ended past the points, beyond the end of the platform,
  so the reverse back into the station wasn't one of the clicked reversals.
- The automatic loco choice only ever picks a part with an engine, at an end of
  the train. With no loco at either end, there's no run-around, and the card
  says why.
- The progress bar on the card follows the distance the loco actually drives
  (it used to stop short on routes with reversals).
- If a game update ever moves the game's train sound script, trains go quiet
  instead of filling the log with errors.
