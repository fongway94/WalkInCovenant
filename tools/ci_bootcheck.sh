#!/bin/sh
# ci_bootcheck.sh — boot the real project headless and fail on any script error.
#
# WHY NOT PER-FILE: `godot --check-only --script <one file>` checks a script
# with no autoloads registered, so every reference to GameState, I18n, EventBus
# or AudioDirector reports "Identifier not found". That kills the script, which
# kills every class_name it declares, which reports as "Could not parse global
# class Player" in innocent files and "Could not resolve external class member"
# two files away. Nearly all of its output was cascade noise.
#
# Booting the whole project instead gives the engine the context the game
# actually runs in: autoloads exist, global classes resolve, and the main scene
# is instantiated — so this is simultaneously a parse check and a smoke test
# that the world builds. --quit-after counts FRAMES, not seconds.
#
# POSIX sh only — the CI image has no bash.

set -u

LOG=/tmp/bootcheck.log
FRAMES=${1:-10}

godot --headless --path . --quit-after "$FRAMES" > "$LOG" 2>&1
RC=$?

sed 's/\x1b\[[0-9;]*m//g' "$LOG" > /tmp/bootcheck.clean
BAD=$(grep -aE "Parse Error|Compile Error|Failed to load script|SCRIPT ERROR|Identifier not found|Could not resolve" /tmp/bootcheck.clean | head -20)

if [ -n "$BAD" ]; then
	echo "boot check FAILED (godot exit $RC):"
	printf '%s\n' "$BAD"
	# one joined annotation: GitHub caps annotations per run, and Godot prints
	# progress lines after the error, so a filtered tail loses the reason
	JOINED=$(printf '%s\n' "$BAD" | tr '\n' '|' | cut -c1-3000)
	printf '::error::%s\n' "$JOINED"
	exit 1
fi

echo "boot check: project booted $FRAMES frames headless with no script errors (godot exit $RC)"
grep -aE "region:|Model|elah" /tmp/bootcheck.clean | head -3
exit 0
