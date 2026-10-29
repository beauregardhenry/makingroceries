#!/bin/zsh
set -euo pipefail

# Builds the Apple Watch app for the watchOS simulator. The iPhone app doesn't embed it yet (see
# Grocery/project.yml), so scripts/test.sh never compiles it; CI runs this so a change to the shared
# list format or the watch sources can't break the watch unnoticed. Needs the watchOS platform
# installed in Xcode (Settings > Components).

PROJECT_ROOT="${0:A:h:h}"
cd "$PROJECT_ROOT"

xcodebuild \
    -project Grocery/Grocery.xcodeproj \
    -scheme GroceryWatch \
    -destination 'generic/platform=watchOS Simulator' \
    -derivedDataPath "$PROJECT_ROOT/.build/DerivedData" \
    CODE_SIGNING_ALLOWED=NO \
    build
