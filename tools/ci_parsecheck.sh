#!/bin/sh
# ci_parsecheck.sh — make the engine itself parse every script, before export.
#
# WHY: an export can "succeed" while containing scripts that do not parse. CI
# produced a green build whose log held:
#
#   ERROR: Failed to load script "res://scripts/main/Main.gd" (Parse error)
#   SCRIPT ERROR: Parse Error: Could not resolve external class member "bind"
#
# Godot still wrote the .pck and exited 0, so the pipeline went green with a
# game that would black-screen at boot. And because GitHub keeps only ~10
# annotations per run while Godot prints ANSI progress lines after the error,
# the reason was truncated away entirely.
#
# So: parse each file individually with --check-only, and if anything fails,
# emit ONE annotation containing all of it, joined. One annotation cannot be
# crowded out by a quota.
#
# POSIX sh only — the CI image has no bash.

set -u

STATUS=0
LOG=/tmp/parsecheck.log
: > "$LOG"

for F in $(find scripts tests -name '*.gd' | sort); do
	RES=$(godot --headless --path . --check-only --script "$F" 2>&1)
	RC=$?
	if [ "$RC" -ne 0 ]; then
		STATUS=1
		{
			echo "### $F"
			printf '%s\n' "$RES" \
				| sed 's/\x1b\[[0-9;]*m//g' \
				| grep -aE "Parse Error|SCRIPT ERROR|ERROR:|Could not resolve" \
				| head -6
		} >> "$LOG"
	fi
done

if [ "$STATUS" -ne 0 ]; then
	echo "parse-check FAILED:"
	cat "$LOG"
	JOINED=$(tr '\n' '|' < "$LOG" | cut -c1-3000)
	printf '::error::%s\n' "$JOINED"
else
	echo "parse-check: every .gd file parses under Godot $(godot --version 2>/dev/null | head -1)"
fi

exit "$STATUS"
