#!/bin/zsh
set -euo pipefail

# Grocery.xcodeproj is generated from Grocery/project.yml but checked in, so a source file added
# without regenerating leaves the app unbuildable on someone else's machine. Catch that drift here
# instead of in a build failure several minutes into CI.

PROJECT_ROOT="${0:A:h:h}"
PBXPROJ="$PROJECT_ROOT/Grocery/Grocery.xcodeproj/project.pbxproj"

cd "$PROJECT_ROOT/Grocery"

if [[ ! -f "$PBXPROJ" ]]; then
    print -u2 "Xcode project verification failed: $PBXPROJ is missing."
    exit 1
fi

typeset -a sources missing
sources=(Sources/**/*.swift(.N) Shared/**/*.swift(.N) Widget/**/*.swift(.N) ShareExtension/**/*.swift(.N) Watch/**/*.swift(.N) Tests/**/*.swift(.N))

for source in $sources; do
    if ! grep -qF "/* ${source:t} */" "$PBXPROJ"; then
        missing+=("Grocery/$source")
    fi
done

if (( ${#missing} > 0 )); then
    print -u2 "Xcode project verification failed: Grocery.xcodeproj is out of date with the sources."
    for source in $missing; do
        print -u2 "  missing: $source"
    done
    print -u2 "Regenerate it with ./scripts/regenerate-xcode-project.sh and commit the result."
    exit 1
fi

print "Grocery.xcodeproj references all ${#sources} Swift sources."
