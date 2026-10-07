#!/usr/bin/env bash
# Offline tests for Runaround Railways: mocked game API, plain Lua 5.4.
# Usage: dev/run_tests.sh   (from anywhere)
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
S="$ROOT/res/scripts"
fail=0
run() { # name, dir, args...
	local name="$1" dir="$2"; shift 2
	if out=$(cd "$dir" && lua "$name" "$@" 2>&1); then
		printf 'ok    %s\n' "$name"
	else
		printf 'FAIL  %s\n%s\n' "$name" "$(echo "$out" | tail -5)"; fail=1
	fi
}
for t in "$ROOT"/dev/tests/plan/test_*.lua; do
	b=$(basename "$t")
	if [ "$b" = test_segment.lua ]; then
		run "$b" "$ROOT/dev/tests/plan" "$S/runaround.script.lua" "$S/ghost_real.script.lua"
	else
		run "$b" "$ROOT/dev/tests/plan" "$S/runaround.script.lua"
	fi
done
run test_hide.lua "$ROOT/dev/tests/ghost_real" "$S/ghost_real.script.lua"
run test_chain.lua "$ROOT/dev/tests/ghost_real" "$S/ghost_real.script.lua"
run test_gui.lua "$ROOT/dev/tests/gui" "$S/runaround_gui.script.lua"
run test_build.lua "$ROOT/dev/tests/build" "$ROOT/ghost_build.script.lua"

# Every "<mod id>::" path the mod ships must use mod.json's modId: the wrapped
# transformators and sound sets can't look it up (see ghost_build.script.lua).
modid=$(sed -n 's/.*"modId": *"\([^"]*\)".*/\1/p' "$ROOT/mod.json")
bad=$(grep -rhoE '"[A-Za-z0-9_]+::' "$ROOT/res" "$ROOT/ghost_build.script.lua" "$ROOT/mod.json" | sort -u | grep -vxF "\"$modid::")
if [ -n "$bad" ]; then echo "FAIL  mod ID: expected $modid, found: $bad"; fail=1; else echo "ok    mod ID $modid used throughout"; fi
grep -q "MOD_ID = \"$modid\"" "$ROOT/ghost_build.script.lua" || { echo "FAIL  ghost_build MOD_ID is not $modid"; fail=1; }

# _content.json lists every shipped file (see dev/tools/gen_content.py).
if python3 "$ROOT/dev/tools/gen_content.py" --check; then echo "ok    _content.json up to date"; else echo "FAIL  _content.json out of date: run dev/tools/gen_content.py"; fail=1; fi

# Every script must parse, and read no globals beyond the expected ones (a
# global read is usually a local used before it is defined - that crashed live).
allowed='api|data|ipairs|pairs|math|string|table|tostring|tonumber|type|pcall|print|select|next|setmetatable|ug_require|getCurrentModId'
for f in "$S"/*.lua "$ROOT"/ghost_build.script.lua; do
	if ! luac -p "$f"; then echo "FAIL  syntax $f"; fail=1; continue; fi
	extra=$(luac -l -p "$f" | grep -oE '_ENV "[A-Za-z_]+"' | grep -oE '"[A-Za-z_]+"' | tr -d '"' | sort -u | grep -vxE "$allowed")
	if [ -n "$extra" ]; then echo "FAIL  globals in $(basename "$f"): $extra"; fail=1; fi
done
[ $fail = 0 ] && echo "all tests passed"
exit $fail
