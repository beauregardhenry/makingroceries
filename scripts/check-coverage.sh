#!/bin/zsh
set -euo pipefail

# Test coverage only ratchets one way. This measures line coverage over the app's logic (Grocery/Shared)
# and fails when it slips below the number in coverage-baseline.txt, so a change that adds untested
# code has to say so out loud instead of quietly diluting the suite.
#
# Left out on purpose:
#   - The SwiftUI screens in Grocery/Sources, Widget, ShareExtension and Watch. They are views, not logic,
#     and the unit tests never reach them (the same split as excluding Views/ elsewhere).
#   - Files in Shared that only run inside the system and can't execute in a unit test:
#     ShoppingActivity.swift (Live Activities), GroceryIntents.swift (Siri and the widget's App Intents),
#     and AisleAI.swift and CookAI.swift (Apple Intelligence, which the test simulators don't have).
#
# Do NOT bump coverage-baseline.txt from a feature branch. The coverage-ratchet workflow re-measures
# on every push to main and commits the raised number itself, so two PRs in flight never conflict
# over the same line. A feature branch only needs the plain (no-flag) form to pass.
#
#   ./scripts/check-coverage.sh                    run the tests and enforce the baseline (what a PR runs)
#   ./scripts/check-coverage.sh --from-results     reuse .build/TestResults.xcresult from scripts/test.sh
#   ./scripts/check-coverage.sh --update-if-higher raise the baseline if coverage climbed past the slack;
#       never lowers it. Run by the post-merge workflow.
#   ./scripts/check-coverage.sh --update           rewrite the baseline unconditionally, for deliberately
#       lowering it (with a reason in the commit).
# Flags combine, for example: --from-results --update-if-higher

PROJECT_ROOT="${0:A:h:h}"
BASELINE_FILE="$PROJECT_ROOT/coverage-baseline.txt"
RESULTS="$PROJECT_ROOT/.build/TestResults.xcresult"
EXCLUDE_REGEX='/(ShoppingActivity|GroceryIntents|AisleAI|CookAI)\.swift$'

# How far coverage may drift below the baseline before the build fails, and how far above it has to
# climb before the baseline is raised.
TOLERANCE="${COVERAGE_TOLERANCE:-0.25}"
RATCHET_SLACK="${COVERAGE_RATCHET_SLACK:-0.5}"

mode=check
reuse=0
for arg in "$@"; do
    case "$arg" in
        --update) mode=update ;;
        --update-if-higher) mode=update-if-higher ;;
        --from-results) reuse=1 ;;
        *)
            print -u2 "Usage: ${0:t} [--from-results] [--update|--update-if-higher]"
            exit 2
            ;;
    esac
done

cd "$PROJECT_ROOT"

if (( ! reuse )) || [[ ! -d "$RESULTS" ]]; then
    print "Running the test suite with a fresh coverage profile."
    ./scripts/test.sh
fi

if [[ ! -d "$RESULTS" ]]; then
    print -u2 "Coverage check failed: $RESULTS was not produced."
    exit 1
fi

measured="$(xcrun xccov view --report --json "$RESULTS" | EXCLUDE_REGEX="$EXCLUDE_REGEX" /usr/bin/python3 -c '
import json, os, re, sys

exclude = re.compile(os.environ["EXCLUDE_REGEX"])
report = json.load(sys.stdin)
covered = count = 0
files = []
for target in report["targets"]:
    for entry in target["files"]:
        path = entry["path"]
        if "/Grocery/Shared/" not in path or exclude.search(path):
            continue
        covered += entry["coveredLines"]
        count += entry["executableLines"]
        files.append((entry["lineCoverage"] * 100, entry["executableLines"], path))

if count == 0:
    sys.stderr.write("No coverage data for Grocery/Shared. Did the tests run?\n")
    sys.exit(1)

print("%.2f %d %d" % (100.0 * covered / count, covered, count))
files = [f for f in files if f[1] >= 20]
files.sort()
for pct, lines, path in files[:5]:
    print("%s\t%.1f\t%d" % (path, pct, lines))
')"

percent="$(print -r -- "$measured" | head -1 | cut -d" " -f1)"
covered="$(print -r -- "$measured" | head -1 | cut -d" " -f2)"
total_lines="$(print -r -- "$measured" | head -1 | cut -d" " -f3)"

print "Line coverage (Grocery/Shared logic): ${percent}% (${covered}/${total_lines} lines)"
print "Least-covered files:"
print -r -- "$measured" | tail -n +2 | while IFS=$'\t' read -r file pct count; do
    printf "  %5s%%  %5s lines  %s\n" "$pct" "$count" "${file#$PROJECT_ROOT/}"
done

write_baseline() {
    cat > "$BASELINE_FILE" <<BASELINE
# Line coverage floor for the app's logic (Grocery/Shared; screens and system-only files are excluded,
# see scripts/check-coverage.sh). Raised automatically by .github/workflows/coverage-ratchet.yml on
# every push to main; don't bump it from a feature branch. Lower it only deliberately, with a reason
# in the commit.
coverage=$1
BASELINE
}

baseline="$(sed -n 's/^coverage=//p' "$BASELINE_FILE" 2>/dev/null | tail -1 | tr -d '[:space:]' || true)"

if [[ "$mode" == "update" ]]; then
    write_baseline "$percent"
    print "Baseline updated to ${percent}%. Commit coverage-baseline.txt."
    exit 0
fi

if [[ -z "$baseline" ]]; then
    if [[ "$mode" == "update-if-higher" ]]; then
        write_baseline "$percent"
        print "No baseline recorded yet; seeded it at ${percent}%."
    else
        print "No coverage baseline recorded yet, so nothing to enforce."
    fi
    exit 0
fi

if [[ ! "$baseline" =~ '^[0-9]+(\.[0-9]+)?$' ]]; then
    print -u2 "Coverage check failed: coverage-baseline.txt does not contain a number ('$baseline')."
    exit 1
fi

floor="$(/usr/bin/python3 -c "print('%.2f' % max(0.0, $baseline - $TOLERANCE))")"
verdict="$(/usr/bin/python3 -c "print('below' if $percent < $floor else ('above' if $percent > $baseline + $RATCHET_SLACK else 'held'))")"

print

case "$verdict" in
    below)
        print -u2 "Coverage check failed: ${percent}% is below the ${baseline}% baseline (floor ${floor}%)."
        print -u2 "Add tests for the new code, or lower coverage-baseline.txt deliberately and say why in the commit."
        exit 1
        ;;
    above)
        if [[ "$mode" == "update-if-higher" ]]; then
            write_baseline "$percent"
            print "Baseline raised from ${baseline}% to ${percent}%. Committing coverage-baseline.txt."
        else
            print "Coverage rose to ${percent}% from the ${baseline}% baseline."
            print "No action needed: the post-merge coverage-ratchet workflow will raise the baseline on main."
        fi
        ;;
    held)
        print "Coverage holds at ${percent}% against the ${baseline}% baseline."
        ;;
esac
