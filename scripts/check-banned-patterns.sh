#!/bin/zsh
set -euo pipefail

# Four patterns that should never appear in shipped app code, all currently at zero. This ratchets
# structurally rather than numerically: the floor is just 0, forever, with no baseline file. There
# is no legitimate reason for any of these counts to rise, so the check fails the moment one does.
#
# try! is deliberately not included. Its only uses here compile a literal, known-good
# NSRegularExpression once at static-initialization time, which can only fail on a malformed literal
# and would be caught the first time that file runs. A try! on data from disk, the network or the
# user deserves the same scrutiny as as! or fatalError, but a blanket ban would be noise.

PROJECT_ROOT="${0:A:h:h}"
typeset -a source_dirs
source_dirs=(
    "$PROJECT_ROOT/Grocery/Sources"
    "$PROJECT_ROOT/Grocery/Shared"
    "$PROJECT_ROOT/Grocery/Widget"
    "$PROJECT_ROOT/Grocery/ShareExtension"
    "$PROJECT_ROOT/Grocery/Watch"
)

typeset -a findings
findings=()

check_pattern() {
    local label="$1"
    local grep_pattern="$2"
    local matches
    matches="$(grep -rnE "$grep_pattern" "${source_dirs[@]}" --include='*.swift' || true)"
    if [[ -n "$matches" ]]; then
        findings+=("$label")
        print -u2 ""
        print -u2 "Found ${label}:"
        print -r -- "$matches" | while IFS= read -r line; do
            print -u2 "  ${line#$PROJECT_ROOT/}"
        done
    fi
}

check_pattern "as! (forced downcast)" '\bas!'
check_pattern "fatalError(" 'fatalError\('
check_pattern "print( (debug output left in)" '\bprint\('
check_pattern "TODO/FIXME comment markers" '//\s*(TODO|FIXME)'

if (( ${#findings} > 0 )); then
    print -u2 ""
    print -u2 "Banned-pattern check failed: ${#findings} pattern(s) found in the app sources."
    print -u2 "Replace a forced downcast or fatalError with a real error path, remove leftover debug"
    print -u2 "print() calls, and finish or file any TODO/FIXME as a tracked issue before merging."
    exit 1
fi

print "Banned-pattern check passed: no as!, fatalError(, print(, or TODO/FIXME in the app sources."
