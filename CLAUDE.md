# Fuelstat iOS – notes for Claude and other agents

Native iPhone app for Fuelstat (SwiftUI, iOS 17+). The backend, the web app and
the central planning live in [FuelStat/fuelstat](https://github.com/FuelStat/fuelstat).

## Scope and goal

- **Feature reference: [#15](https://github.com/FuelStat/fuelstat-ios/issues/15).**
  The app must cover everything the web app does, and do more where native iOS
  allows it. Read #15 before starting a feature; tick items off there and link
  the issue or PR when done. If the web app gains a feature, add it to #15.
- Planning is central: milestones exist only in FuelStat/fuelstat. App issues
  live here and hang as sub-issues under a tracking issue per version there
  (2.0.0: FuelStat/fuelstat#116). Do not create milestones in this repo.

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

## Workflow

- Branch per feature, PR into `main`; reference the issue (`Fixes #5`) and,
  for API work, the FuelStat/fuelstat issue it depends on.
- Head branches are deleted automatically after merge.
- Keep the README section "Current state" in sync with what the app can do.
