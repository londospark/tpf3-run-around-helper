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
run test_gui.lua "$ROOT/dev/tests/gui" "$S/runaround_gui.script.lua"

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
