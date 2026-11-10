# Fuelstat iOS – notes for Claude and other agents

Native iPhone app for Fuelstat (SwiftUI, iOS 17+). The backend and the web app
live in [FuelStat/fuelstat](https://github.com/FuelStat/fuelstat).

## Scope and goal

- **Feature reference: [#15](https://github.com/FuelStat/fuelstat-ios/issues/15).**
  The app must cover everything the web app does, and do more where native iOS
  allows it. Read #15 before starting a feature; tick items off there and link
  the issue or PR when done. If the web app gains a feature, add it to #15.
- **Planning: one milestone per app version in this repo** (`0.2.0 – Foundation`
  … `1.0.0 – App Store`, plus `Later`), see the README section "Roadmap". Every
  open issue has a milestone; new issues get one when they are created.
- Backend prerequisites stay in FuelStat/fuelstat (milestone 2.0.0 there) and
  are named in the app issue ("Benötigt: FuelStat/fuelstat#…"). App issues up
  to 1.0.0 also hang as sub-issues under FuelStat/fuelstat#116, so the backend
  planning sees what the app needs.

## Rules

- **The API is the source of truth.** Consumption, costs, CO₂, due dates and
  plan limits come from the API. Do not re-implement calculations in the app.
  If the API lacks something, open an issue in FuelStat/fuelstat instead.
- **Plan rules are enforced by the API only** (FuelStat/fuelstat#102). The app
  shows limits and API messages, it never decides on its own.
- API docs: `docs/api.md` and `docs/openapi.1.0.0.yaml` in FuelStat/fuelstat.
  Base URL `https://tanken.1emc.de/api/v1`; self-hosted servers are entered on
  the sign-in screen.
- Image URLs from the API are signed and change daily; cache by file name
  (see `Fuelstat/Images/ImageCache.swift`).
- UI language is German; all user-facing strings go through
  `Localizable.xcstrings`. Code, comments, commit messages and this repo's docs
  are in English.
- Accessibility is part of every feature: VoiceOver labels, Dynamic Type,
  dark mode.
- **Design: follow [`docs/design.md`](docs/design.md)** (navigation, screens,
  colour and spacing tokens, shared components in `Fuelstat/Design/`).
- Signing uses a **free Apple developer account** (Personal Team). Do not add
  capabilities that need the paid program (Push Notifications, iCloud, Sign in
  with Apple, App Groups …) without asking first – the device build breaks.
  Local notifications are fine.
- Never commit secrets (API keys, tokens, `.p8` files) or `xcuserdata/`.

## Project layout

- `Fuelstat.xcodeproj` – app target and scheme `Fuelstat`
- `Fuelstat/` – app sources: `API/` (client and models), `Auth/` (session,
  Keychain), `Views/`, `Vehicles/`, `Location/`, `Images/`
- `Packages/FuelstatCore` – platform-independent logic with tests. Put pure
  logic (parsing, calculations that are not the API's job, formatting helpers)
  here so it can be tested without a simulator.

## Build and test

Core tests:

```sh
cd Packages/FuelstatCore && swift test
```

App build, same as CI:

```sh
xcodebuild build -project Fuelstat.xcodeproj -scheme Fuelstat -configuration Debug \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO
```

Run both before every PR. Add tests in `FuelstatCore` for new logic.

**Cloud sessions run on Linux:** `xcodebuild` and the simulator are not
available there. Edit the code, run what runs (`swift test` only if a Swift
toolchain is installed), and rely on the CI workflow (`.github/workflows/ci.yml`,
macOS runner) for the app build. Say so in the PR instead of claiming a local
build.

## Release process

The app has its own version, independent of the web app/API version.

- `MARKETING_VERSION` (e.g. `0.1.0`, Semantic Versioning, `0.x` during the
  beta) is what users see; `CURRENT_PROJECT_VERSION` is the build number and
  must increase with every build that leaves a developer's machine (TestFlight,
  App Store). Both are set in `Fuelstat.xcodeproj` (Debug and Release).
- **App releases do not bump the backend.** If a release needs a new API
  feature, the backend release (FuelStat/fuelstat, `docs/betrieb.md`) must be
  tagged and deployed first; say so in the release notes.

Steps:

1. Feature PRs keep the README section "Current state" up to date. The
   planned versions are the milestones; a release ships its milestone.
2. **Prepare** a release PR: bump `MARKETING_VERSION` and
   `CURRENT_PROJECT_VERSION`, update the README, run the tests and the CI build.
3. **Merge** the PR.
4. **Tag** the merged `main` and create the GitHub release (no workflow yet –
   create it on GitHub from the tag, notes = what changed for users, marked
   as pre-release while `0.x`):

   ```sh
   git tag -a vX.Y.Z -m "Fuelstat iOS X.Y.Z"
   git push origin vX.Y.Z
   ```

5. **Distribute:** with the free developer account only by running from Xcode
   on the device (valid 7 days). TestFlight and App Store need the paid
   program, see #12.

**Remind the maintainer** at the end of a task when merged changes are not yet
in a tagged release, when a release PR is merged but its tag is missing, or
when the app depends on a backend change that is merged but not yet released
and deployed. Only create or push tags when the maintainer explicitly asks.

## Checklist for every PR

Check before opening the PR, and remind the maintainer at the end of a task of
anything still missing:

- **Milestone:** the issue (and the PR) is in the milestone of the app
  version it ships with.
- **Feature reference:** items in #15 ticked off (with a link to the PR) or
  added when the web app gained something new.
- **README:** section "Current state" matches what the app can do.
- **API gaps:** anything the app needs but the API does not provide has an
  issue in FuelStat/fuelstat (no workaround calculations in the app); the PR
  names it.
- **Backend dependency:** if the PR relies on a backend change, that change is
  merged, released (tag) and deployed – check `GET /api/v1/health` – before the
  app release that needs it.
- **Strings:** new user-facing text is in `Localizable.xcstrings` (German).
- **Design:** new screens and components follow `docs/design.md`.
- **Tests:** new logic in `FuelstatCore` has tests; CI is green.

## Workflow

- Branch per feature, PR into `main`; reference the issue (`Fixes #5`) and,
  for API work, the FuelStat/fuelstat issue it depends on. Work on the earliest
  open milestone first.
- Head branches are deleted automatically after merge.
- Keep the README section "Current state" in sync with what the app can do.
