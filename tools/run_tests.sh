#!/usr/bin/env bash
# Runs every headless test suite and prints one line per suite.
# A suite fails if it exits non-zero, prints a SCRIPT ERROR / ERROR line, or leaks.
#
#   tools/run_tests.sh            # all suites (about 3 minutes)
#   tools/run_tests.sh quick      # skip the whole-game sims and the soak test
#   GODOT=/path/to/godot tools/run_tests.sh
#
# Full output of each suite goes to .test-logs/<suite>.log
set -u
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
MODE="${1:-all}"
mkdir -p .test-logs

# name | script | args | seconds allowed
SUITES=(
	"data|tests/test_data.gd||120"
	"rules|tests/test_rules.gd||300"
	"net|tests/test_net.gd||120"
	"smooth|tests/test_smooth.gd||120"
	"play|tests/test_play.gd||300"
	"save|tests/test_save.gd||180"
	"rejoin|tests/test_rejoin.gd||180"
	"features|tests/test_features.gd||300"
)
if [ "$MODE" != "quick" ]; then
	SUITES+=(
		"sim|tests/test_sim.gd|meadow normal adventure frostlotus,snapdragon|600"
		"clash|tests/test_clash.gd|normal boomshroom,bubblelily 1|600"
		"soak|tests/test_soak.gd|6|600"
	)
fi

# the class cache must exist before scripts that use class_name compile
"$GODOT" --headless --path . --import >/dev/null 2>&1

failed=0
for s in "${SUITES[@]}"; do
	IFS='|' read -r name script args secs <<<"$s"
	[ -f "$script" ] || continue
	log=".test-logs/$name.log"
	start=$(date +%s)
	# shellcheck disable=SC2086
	perl -e 'alarm shift; exec @ARGV' "$secs" "$GODOT" --headless --path . -s "$script" -- $args >"$log" 2>&1
	code=$?
	took=$(( $(date +%s) - start ))
	why=""
	if [ $code -eq 142 ]; then
		why="timed out after ${secs}s"
	elif [ $code -ne 0 ]; then
		why="exit code $code"
	elif grep -qE "SCRIPT ERROR|^ERROR:|USER ERROR" "$log"; then
		why="$(grep -m1 -E "SCRIPT ERROR|^ERROR:|USER ERROR" "$log")"
	elif grep -qE "leaked at exit|resources still in use" "$log"; then
		why="leak: $(grep -m1 -E "leaked at exit|resources still in use" "$log")"
	fi
	if [ -z "$why" ]; then
		printf "  ok    %-9s %4ss  %s\n" "$name" "$took" "$(grep -E "passed|FAILED|->|SOAK" "$log" | tail -1)"
	else
		printf "  FAIL  %-9s %4ss  %s  (see %s)\n" "$name" "$took" "$why" "$log"
		failed=$((failed + 1))
	fi
done
if [ $failed -eq 0 ]; then
	echo "All test suites passed."
else
	echo "$failed test suite(s) failed."
fi
exit $failed
