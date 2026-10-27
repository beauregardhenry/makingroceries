#!/bin/zsh
set -euo pipefail

PROJECT_ROOT="${0:A:h:h}"

if ! command -v xcodegen >/dev/null 2>&1; then
    print -u2 "XcodeGen is required to regenerate Grocery.xcodeproj."
    print -u2 "Install it with Homebrew: brew install xcodegen"
    exit 1
fi

cd "$PROJECT_ROOT/Grocery"
xcodegen generate --spec project.yml
print "Regenerated Grocery.xcodeproj from project.yml."
