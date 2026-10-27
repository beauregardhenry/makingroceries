#!/bin/zsh
set -euo pipefail

# Builds the app, widget and share extension, then runs the unit tests on an iPhone simulator with
# code coverage. The result bundle is left in .build/TestResults.xcresult for check-coverage.sh.

PROJECT_ROOT="${0:A:h:h}"
RESULTS="$PROJECT_ROOT/.build/TestResults.xcresult"

cd "$PROJECT_ROOT"
mkdir -p .build
rm -rf "$RESULTS"

destination="$(./scripts/resolve-destination.sh)"

xcodebuild \
    -project Grocery/Grocery.xcodeproj \
    -scheme Grocery \
    -destination "$destination" \
    -derivedDataPath "$PROJECT_ROOT/.build/DerivedData" \
    -resultBundlePath "$RESULTS" \
    -enableCodeCoverage YES \
    test
