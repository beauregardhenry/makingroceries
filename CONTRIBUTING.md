# Contributing to Makin' Groceries

Thanks for helping improve the app. Bug reports, tests, accessibility fixes and small features are welcome.

## Before opening a change

- Search existing issues and pull requests for related work.
- For a bug, say which iPhone and iOS version you used, what you expected, what happened, and the smallest steps that reproduce it.
- Never put real grocery lists, receipts, photos, locations, API keys or your Apple team ID in an issue, a test or a screenshot. Use small made-up fixtures.
- Keep builds, archives and personal data out of the repository.

## Build and test

You need Xcode 26 or later (the app targets iOS 26) and [XcodeGen](https://github.com/yonaskolb/XcodeGen). The Xcode project is generated from `Grocery/project.yml` and also checked in, so change settings in `project.yml`, never in Xcode.

```sh
brew install xcodegen
./scripts/regenerate-xcode-project.sh
./scripts/test.sh
```

`scripts/test.sh` builds the app, widget and share extension and runs the unit tests on an iPhone simulator it finds on your machine. `scripts/ui-test.sh` runs the UI smoke tests, which drive the real app and take a few minutes. Set `SIMULATOR_ID` to a device's UDID to use a specific simulator. `scripts/build-watch.sh` builds the Apple Watch app, which the iPhone app doesn't embed yet, so `test.sh` never compiles it; it needs the watchOS platform installed in Xcode.

Pull requests and pushes to `main` run the same tests in CI, plus the checks below. Run any of them yourself first:

```sh
./scripts/check-banned-patterns.sh
./scripts/check-test-count.sh
./scripts/verify-xcode-project.sh
./scripts/check-coverage.sh
./scripts/build-watch.sh
```

## Where the tests live

`Grocery/Tests/GroceryTests` holds XCTest unit tests for everything in `Grocery/Shared`: parsing, receipts, prices, route learning, trip planning, spending, list sharing and the other logic. The test bundle compiles `Shared` directly, so the logic is tested without launching the app. Keep new logic in `Shared` (and screens in `Sources`) so it can be tested.

Tests use made-up data and a fresh, empty store for each test (see `StoreTestCase`). Network code takes its `URLSession` as a parameter so tests can answer requests with `StubProtocol`; no test reaches the internet.

`Grocery/Tests/GroceryUITests` holds UI smoke tests: launch, adding items, checking off and undo, switching stores, opening and closing every screen in the menu, and importing a recipe. The app runs with the `-ui-testing` launch argument, which starts it from the sample list in a throwaway folder with default settings. Find elements by their accessibility labels or by the `item-<name>` and `quickAddField` identifiers, and keep each test under the per-test time limit in `scripts/ui-test.sh`. They run as a separate CI job, and don't count toward coverage.

## Banned patterns

`as!`, `fatalError(`, `print(` and `TODO`/`FIXME` comment markers hold at zero in the app sources. A forced downcast or `fatalError` should be a real error path instead, a `print(` is leftover debug output, and a TODO/FIXME is deferred work that should be a tracked issue. This is a fixed floor of zero, not a ratchet. (`try!` is not banned: its only uses compile a literal, known-good regular expression once at startup.)

## Test coverage

Line coverage over `Grocery/Shared` only moves up. CI measures it after the tests and fails when it drops below the floor in [coverage-baseline.txt](coverage-baseline.txt), so a change that adds untested logic has to account for it. Screens (`Sources`, `Widget`, `ShareExtension`, `Watch`) are excluded because the unit tests never reach them, as are three files that only run inside the system and can't execute in a unit test: `ShoppingActivity.swift` (Live Activities), `GroceryIntents.swift` (Siri and widget App Intents) and `AisleAI.swift` (Apple Intelligence).

Don't edit `coverage-baseline.txt` or `test-count-baseline.txt` in a feature branch. A `coverage-ratchet` and a `test-count-ratchet` workflow re-measure on every push to `main` and commit the raised numbers themselves, so two pull requests open at once never conflict over the same line. Lowering a baseline is allowed but never incidental: do it in its own commit with `--update` and say why.

## Test count

The number of unit tests and of UI tests only moves up too: CI fails if either drops below its floor in [test-count-baseline.txt](test-count-baseline.txt). A raw count catches a test quietly commented out or renamed away from the `testFoo()` pattern even when coverage barely moves. It counts `func test...()` methods statically, so it runs in seconds.

## Project drift

CI fails when a Swift file exists in the source folders but isn't referenced by the checked-in Xcode project. Run `./scripts/regenerate-xcode-project.sh` after adding or removing files, and commit the result.

## Branch protection (optional)

CI doesn't need any repository settings. To make it required, add a branch ruleset on `main` that requires a pull request and the **Unit tests and app build** and **UI smoke tests** status checks. The ratchet workflows push straight to `main` with the workflow token while there is no ruleset. If you add one that requires pull requests, create a write-enabled deploy key, add its private half as the `RATCHET_DEPLOY_KEY` repository secret, and allow deploy keys to bypass the ruleset. Without that, the ratchets still measure but their push is rejected.

## Pull requests

Keep each pull request focused. Explain the user-visible result, any privacy or data-migration implications, and the tests you added or ran. Update the README (and its screenshots, taken in light mode with demo data) when behavior changes.
