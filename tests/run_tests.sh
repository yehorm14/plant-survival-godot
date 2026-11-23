#!/usr/bin/env bash
# Runs every headless gameplay test in tests/*_test.gd and fails if any fails.
# Usage: GODOT=/path/to/godot tests/run_tests.sh   (GODOT defaults to `godot`)
set -u
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"

# Make sure imported resources exist (no-op when .godot/ is already populated).
"$GODOT" --headless --path . --import >/dev/null 2>&1

status=0
for t in tests/*_test.gd; do
	echo "=== $t"
	if ! "$GODOT" --headless --path . --script "res://$t"; then
		echo "*** FAILED: $t"
		status=1
	fi
done
exit $status
