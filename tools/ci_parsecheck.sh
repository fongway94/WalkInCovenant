#!/bin/sh
# ci_parsecheck.sh — parse every script on its own, and name the file that fails.
#
# The boot check cannot do this. At boot only the main scene's script is loaded
# first, so when Main.gd fails, nothing downstream is ever compiled and the
# engine prints "Could not resolve external class member" for Main.gd alone.
# Per the analyzer source, that message means resolving the member pushed new
# errors into ANOTHER script — so the real fault is in a file the boot never
# reached, and its own error is never printed.
#
# Per-file checking has one known blind spot: autoload singletons are not
# registered, so "Identifier not found: GameState" and friends are expected and
# are filtered out here. Everything else is real.
#
# The autoload list must allow digits: the singleton is named I18n, and a
# [A-Za-z_]+ pattern silently omitted it, so its expected error was reported.
#
# Output is ONE line per failing file (the first error), because GitHub caps
# annotations per run and a full dump gets truncated before the interesting
# file appears.
#
# POSIX sh only — the CI image has no bash.

set -u

AUTOLOADS=$(sed -n '/^\[autoload\]/,/^\[/p' project.godot \
	| grep -oE '^[*]?[A-Za-z_][A-Za-z0-9_]*=' | tr -d '*=' | tr '\n' '|' | sed 's/|$//')
[ -n "$AUTOLOADS" ] || AUTOLOADS="__none__"
echo "parse-check: treating autoload identifiers as expected: $AUTOLOADS"

OUT=/tmp/parsecheck.log
: > "$OUT"
FAILED=0

for F in $(find scripts tests -name '*.gd' | sort); do
	RES=$(godot --headless --path . --check-only --script "$F" 2>&1 \
		| sed 's/\x1b\[[0-9;]*m//g')
	BAD=$(printf '%s\n' "$RES" \
		| grep -aE "Parse Error|Compile Error" \
		| grep -avE "Identifier not found: ($AUTOLOADS)")
	if [ -n "$BAD" ]; then
		FAILED=1
		# Godot prints the offending file:line on the "at:" line that follows
		# the error. Without it a parse error names the file but not the place,
		# which turns every failure into another CI round-trip to locate.
		WHERE=$(printf '%s\n' "$RES" | grep -a -m1 -A1 -F "$(printf '%s\n' "$BAD" | head -1)" \
			| tail -1 | grep -aoE '\(res://[^)]*\)' | head -1)
		printf '%s %s :: %s\n' "$F" "${WHERE:-}" "$(printf '%s\n' "$BAD" | head -1)" >> "$OUT"
	fi
done

if [ "$FAILED" -ne 0 ]; then
	echo "parse-check FAILED:"
	cat "$OUT"
	JOINED=$(tr '\n' '|' < "$OUT" | cut -c1-3000)
	printf '::error::%s\n' "$JOINED"
	exit 1
fi

echo "parse-check: every .gd file parses on its own"
exit 0
