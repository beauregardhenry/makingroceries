#!/bin/zsh
set -euo pipefail

# Runs the UI smoke tests (Grocery/Tests/GroceryUITests) on an iPhone simulator. They drive the real
# app, launched with -ui-testing so it starts from the sample list in a throwaway folder. Coverage is
# off here on purpose: these runs would otherwise inflate the unit-test coverage number.

PROJECT_ROOT="${0:A:h:h}"
RESULTS="$PROJECT_ROOT/.build/UITestResults.xcresult"

cd "$PROJECT_ROOT"
mkdir -p .build
rm -rf "$RESULTS"

destination="$(./scripts/resolve-destination.sh)"

xcodebuild \
    -project Grocery/Grocery.xcodeproj \
    -scheme GroceryUITests \
    -destination "$destination" \
    -derivedDataPath "$PROJECT_ROOT/.build/DerivedData" \
    -resultBundlePath "$RESULTS" \
    -test-timeouts-enabled YES \
    -default-test-execution-time-allowance 240 \
    -maximum-test-execution-time-allowance 300 \
    test
