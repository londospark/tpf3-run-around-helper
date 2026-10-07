# Writes _content.json, the list of the mod's files the game reads (the DLCs ship
# one too): everything under res/ plus the load script. Run after adding or
# removing a file; dev/run_tests.sh fails while the list is out of date.
import json, os, sys
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
files = ["ghost_build.script.lua"]
for d, _, names in os.walk(os.path.join(ROOT, "res")):
    for n in names:
        files.append(os.path.relpath(os.path.join(d, n), ROOT).replace(os.sep, "/"))
text = json.dumps({"archives": None, "files": sorted(files)}, indent=4) + "\n"
path = os.path.join(ROOT, "_content.json")
if "--check" in sys.argv:
    sys.exit(0 if open(path).read() == text else 1)
open(path, "w").write(text)
print(len(files), "files")
