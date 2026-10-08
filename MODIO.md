# mod.io listing

## Name

Runaround Railways (ALPHA)

## Author

LondoSpark

## Summary (max 250 characters)

ALPHA, made with a lot of help from AI. Your loco runs around its train at the terminus instead of the instant flip. Click a few points on the track: it uncouples, runs around with its own sound, smoke and paint, and couples on at the other end.

## Tags

Script Mod, Trains, Gameplay, Alpha

## Search keywords (put these in the description so people find it)

run around, run-around, runaround, run round, run-round loop, locomotive, loco, terminus, flip, reverse, shunting, headshunt, wye, steam

## Description (paste into the description field; it is HTML)

<p><strong>ALPHA - an early test release. It works, but it has only been tried on a few layouts: please try it and tell me what breaks.</strong></p>

<p><strong>Made with a lot of help from AI.</strong> Most of the code, tests and documentation for this mod were written by an AI assistant (Anthropic's Claude, using Claude Code). I set the direction, made the decisions and tested it in game. I'm saying so up front so that nobody downloads it under a false impression; if you'd rather not use AI-assisted mods, that's completely fair.</p>

<p><strong>Your locomotive runs around its train at the terminus, instead of the game's instant flip.</strong> A proper run-around (run round, run-round loop) for Transport Fever 3.</p>

<p>When a train arrives at a terminus you've set up, the loco uncouples and drives off along the route you picked: into a loop, onto a headshunt or round a wye. It reverses where it needs to, comes back down the other road and couples on at the far end. Then the train leaves with the loco leading.</p>

<p>The loco uses its own model, with its own <strong>sound, smoke, wheel animation and paint</strong>, including custom liveries. It never turns round on the way, so a tank engine that arrived bunker-first leaves chimney-first, as it would for real.</p>

<p><em>[Video: how to set up a run-around - link here]</em></p>

<h2>Features</h2>
<ul>
<li>Set up entirely in game: click a few points on the track and the route is worked out for you with the game's own pathfinder, including where to reverse.</li>
<li>The route is drawn on the track while you edit it.</li>
<li>Any number of stations, on any number of lines. Every train on the line does it, clones included.</li>
<li>Your loco runs around as itself: its own model, sound, smoke, turning wheels and paint.</li>
<li>Works with every base-game and DLC locomotive, and with modded locos (see below).</li>
</ul>

<h2>How to set up a run-around</h2>
<ol>
<li><strong>Open a train's window.</strong> Pick any train on the line. It has a new <strong>Run-around</strong> card.</li>
<li><strong>Add a run-around.</strong> The card lists the stops of that line, with the one the train is at first. Click the station where the loco should run around.</li>
<li><strong>Draw the route.</strong> Click <strong>Edit route on map</strong>, then click a few points on the track where the loco should go, in order. For a simple loop that's usually:
  <ol>
  <li>a piece of track beyond the points, where the loco will stop and reverse;</li>
  <li>a piece of the loop, or the other road through the station;</li>
  <li>a piece of track beyond the far end of the train.</li>
  <li>After your last point, the route goes back into the station by itself, so the loco sets back onto its coaches along the track.</li>
  </ol>
You don't click every piece of track, the station, or the exact reversing spot. The loco reverses just clear of the points. Right-click, Esc or <strong>Done</strong> when finished.</li>
<li><strong>Check it.</strong> The card shows the route's length, reversals and points. A warning says which two points couldn't be joined.</li>
<li><strong>That's it.</strong> The next time a train on that line arrives there, its loco runs around.</li>
</ol>

<p>On the map, the route runs from <strong>blue</strong> at the start to <strong>orange</strong> at the end. The pieces where the loco reverses are <strong>purple</strong>, and the pieces you clicked have a <strong>white line</strong>. The card's settings hold the name, the loco's speed and acceleration, which part of the train is the loco (automatic by default), and delete.</p>

<h2>Good to know</h2>
<ul>
<li><strong>One loco plus coaches or wagons.</strong> Multiple units and double-heading are not handled yet.</li>
<li><strong>The running loco ignores signals.</strong> Use a loop that other trains won't be on at the same time.</li>
<li><strong>The train draws forward one loco length before the loco uncouples.</strong> A train that has had its loco run around really is a loco length further along the track. In this game that can only happen by the coaches moving, so the train pulls up first, with the loco still coupled, and then stays put.</li>
<li><strong>Nothing is bought or sold, and passengers and goods stay aboard.</strong> The loco, coaches and wagons never leave the train. They're only hidden while their copies are shown, and copies of goods wagons show their load.</li>
<li><strong>The loco must be at one end of the train.</strong> For the smooth sequence (the train drawing forward, then the loco uncoupling) it should be at the front when the train arrives, as it is at a terminus.</li>
<li><strong>The card tells you when an arrival didn't run around, and why:</strong> the train stopped at a different platform from the one the route starts at, the route's first points head back into the train, or there's no loco at either end. The train then simply leaves as normal.</li>
<li><strong>Modded locos</strong> that use the game's own sound sets and train animation script run around as themselves. Those with their own sound or animation scripts run around as a copy of themselves, with their smoke, wheels and paint, but without sound unless they use one of the game's sound sets. A loco this mod can't hide doesn't run around (the card says so).</li>
<li><strong>Works alongside mods that change trains' animation</strong>, such as Real Track Cant: those trains still lean on curves.</li>
<li><strong>Nothing is left stuck.</strong> If a run-around can't start or stalls, the train is put back as it was and goes on its way. If the loco can't couple back on, the train waits and the card says so.</li>
<li><strong>Steam locos, known in this alpha:</strong> no chuffing while the loco runs around (the rest of its sound plays), and the tender's wheels can sit slightly off the track.</li>
<li>Run-arounds belong to a line and a stop. If you insert or remove stops earlier in the line, check the run-around still points at the right station.</li>
<li>Install, then <strong>restart the game fully</strong>: script mods are only loaded at start-up.</li>
<li><strong>Don't remove the mod while a run-around is happening.</strong> The train is hidden at that moment and would stay hidden (it shows up teal without the mod). Let the run-around finish first.</li>
</ul>

<h2>Status and feedback</h2>
<p>Early release: it works end to end, but it has only been tried on a few layouts. Please report problems, with a short video if you can and the lines starting <code>[RunAroundHelper]</code> from the game's log (<code>.../userdata/&lt;id&gt;/3493540/local/crash_dump/stdout.txt</code>), on the <a href="https://github.com/londospark/tpf3-run-around-helper/issues">issue tracker</a>.</p>

<p>Source and documentation: <a href="https://github.com/londospark/tpf3-run-around-helper">github.com/londospark/tpf3-run-around-helper</a></p>
