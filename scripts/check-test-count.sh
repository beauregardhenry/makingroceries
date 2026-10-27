#!/bin/zsh
set -euo pipefail

# The number of tests only ratchets one way: this fails when the count of unit or UI test methods
# drops below the number recorded in test-count-baseline.txt. Coverage mostly catches a deleted test too,
# but a raw count is a more direct signal: a test quietly commented out, renamed away from the
# testFoo() pattern, or lost in a merge conflict shows up here even when coverage barely moves.
#
# Counting is static, a grep over `func test...()` in Grocery/Tests/GroceryTests and GroceryUITests, so
# it is fast and needs no Xcode, simulator or built product. It matches the "Executed N tests" xcodebuild reports.
#
# Do NOT bump test-count-baseline.txt from a feature branch. The test-count-ratchet workflow
# re-measures on every push to main and commits the raised number itself, so exactly one place
# owns writing to the file.
#
#   ./scripts/check-test-count.sh                  measure and enforce the baseline (what a PR runs)
#   ./scripts/check-test-count.sh --update-if-higher
#       raise the baseline if the count climbed; never lowers it. Run by the post-merge workflow.
#   ./scripts/check-test-count.sh --update         rewrite the baseline unconditionally, for
#       deliberately lowering it (with a reason in the commit).

PROJECT_ROOT="${0:A:h:h}"
BASELINE_FILE="$PROJECT_ROOT/test-count-baseline.txt"
count_tests() {
    grep -rhoE 'func test[A-Za-z0-9_]+\(\)' "$1"/*.swift 2>/dev/null | wc -l | tr -d '[:space:]'
}

count="$(count_tests "$PROJECT_ROOT/Grocery/Tests/GroceryTests")"
ui_count="$(count_tests "$PROJECT_ROOT/Grocery/Tests/GroceryUITests")"
print "Unit test count: ${count}"
print "UI test count: ${ui_count}"

mode=check
case "${1:-}" in
    --update) mode=update ;;
    --update-if-higher) mode=update-if-higher ;;
    "") ;;
    *)
        print -u2 "Usage: ${0:t} [--update|--update-if-higher]"
        exit 2
        ;;
esac

write_baseline() {
    cat > "$BASELINE_FILE" <<BASELINE
# Test-method-count floors for the unit and UI test suites. Raised automatically by
# .github/workflows/test-count-ratchet.yml on every push to main; don't bump them from a feature
# branch (see the header of scripts/check-test-count.sh). Lower one only deliberately, with a
# reason in the commit.
tests=$1
ui=$2
BASELINE
}

read_baseline() {
    sed -n "s/^$1=//p" "$BASELINE_FILE" 2>/dev/null | tail -1 | tr -d '[:space:]' || true
}

baseline="$(read_baseline tests)"
ui_baseline="$(read_baseline ui)"

if [[ "$mode" == "update" ]]; then
    write_baseline "$count" "$ui_count"
    print "Baseline updated to tests=${count}, ui=${ui_count}. Commit test-count-baseline.txt."
    exit 0
fi

failed=0
new_baseline="$baseline"
new_ui_baseline="$ui_baseline"

# A suite with no recorded floor yet isn't enforced; the post-merge workflow seeds it.
check_suite() {
    local label="$1" current="$2" floor="$3"
    if [[ -z "$floor" ]]; then
        print "${label} test count ${current}: no baseline recorded yet."
    elif (( current < floor )); then
        print -u2 "Test count check failed: ${label} count ${current} is below the ${floor} baseline."
        print -u2 "A test was removed, renamed away from the testFoo() pattern, or commented out."
        print -u2 "Add tests back, or lower test-count-baseline.txt deliberately and say why in the commit."
        failed=1
    elif (( current > floor )); then
        print "${label} test count rose to ${current} from the ${floor} baseline."
    else
        print "${label} test count holds at ${current}."
    fi
}

print
check_suite "Unit" "$count" "$baseline"
check_suite "UI" "$ui_count" "$ui_baseline"

if [[ "$mode" == "update-if-higher" ]]; then
    [[ -z "$baseline" ]] || (( count > baseline )) && new_baseline="$count"
    [[ -z "$ui_baseline" ]] || (( ui_count > ui_baseline )) && new_ui_baseline="$ui_count"
    if [[ "$new_baseline" != "$baseline" || "$new_ui_baseline" != "$ui_baseline" ]]; then
        write_baseline "$new_baseline" "$new_ui_baseline"
        print "Baseline raised to tests=${new_baseline}, ui=${new_ui_baseline}. Committing test-count-baseline.txt."
    else
        print "Nothing to update."
    fi
    exit "$failed"
fi

(( failed )) || print "No action needed: the post-merge ratchet workflow raises the baselines on main."
exit "$failed"
