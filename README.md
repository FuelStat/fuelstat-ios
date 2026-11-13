# Fuelstat iOS

Native iOS application for Fuelstat.

Fuelstat is an open-source vehicle tracking and
expense management platform.

## Features

- Vehicle management
- Fuel and charging entries
- Expense tracking
- Consumption statistics
- Cost analysis
- Service and maintenance history
- Nearby fuel stations

## Requirements

- iOS 17 or later (initial target)
- Xcode
- Swift
- Fuelstat API account

## Backend

The application uses the Fuelstat REST API.

Backend repository:
https://github.com/FuelStat/fuelstat

## Development

### Current state (0.1.0 – MVP)

The app is an **MVP**, not yet an alpha: it runs only from Xcode on your own
device (free developer account, valid 7 days), there is no TestFlight or App
Store build. Version 0.1.0 marks this state; the first regular release is
[0.2.0 – Foundation](https://github.com/FuelStat/fuelstat-ios/milestone/1)
(see Roadmap). Developed against Fuelstat server 0.11.0.

The app talks to the Fuelstat API (`https://tanken.1emc.de/api/v1` by default;
self-hosted servers can be entered on the sign-in screen):

- Design from the shared design document
  ([FuelStat/fuelstat `docs/design.md`](https://github.com/FuelStat/fuelstat/blob/main/docs/design.md))
  and the iOS specifics in `docs/design.md`: colour tokens in the asset catalog
  (light and dark, dark background in navy like the app icon), shared
  components in `Fuelstat/Design/`
- Tabs Start · Einträge · Statistik · Profil with a central "+" for quick entry;
  vehicle switcher at the top, the choice is remembered
- Start: vehicle hero, key figures, due dates (`/reminders`), cheapest nearby
  station, latest entries
- Einträge: fill-ups, charging sessions, expenses, odometer notes and trips in
  one list from `/vehicles/:id/timeline`, grouped by month with the month's
  costs, filter chips per kind, search on the server (place, category, note),
  more entries load while scrolling, swipe to edit or delete
- Entry details: every entry opens a page with all its values (consumption of
  the segment, who recorded it on shared vehicles), edit and delete
- Editing: fill-ups and charging sessions (`PATCH /fillups/:id`, the API's
  14-day rule is shown as its message), expenses, odometer notes and trips;
  "Kilometerstand nachtragen" for fill-ups without a real reading works at any
  time; odometer warnings from the API are shown after saving
- The "+" sheet has type chips: Tanken, Laden, Ausgabe, Fahrt, Kilometer
- Expenses (`/entries`) with categories from `GET /categories` (name, icon and
  colour from the API, locked ones marked "mit Plus"); own categories under
  Profil → Kategorien (add, change, delete with moving the expenses)
- Trip log (Einträge or vehicle page → Fahrtenbuch): trips per year and
  purpose, totals, business share and estimated costs from `/trips/summary`,
  km per month as a chart, CSV export through the share sheet
  (`/trips/export`, plan limit as API message)
- Sharing (#34): members and roles of a vehicle, invite by e-mail, withdraw
  invitations, change roles, remove members, leave a shared vehicle; accept or
  decline invitations under Profil → Einladungen; shared vehicles are marked
  in the lists; viewers are not offered editing, the API enforces all rights
- Due dates: tap one to record it as done (opens the expense with the right
  category); Profil → Termine und Erinnerungen lists the due dates of all
  vehicles, most urgent first
- Local reminders for due dates (no push server): switched on in Profil →
  Termine und Erinnerungen, permission asked only then, lead time selectable,
  replanned whenever the due dates are loaded and at app start, removed on
  sign-out, a tap opens the vehicle
- Statistik: key figures and consumption per fill-up (segments from `/stats`)
  as a chart
- Profil: account, vehicle management, sign out, app and server version,
  feedback to the server operator (`POST /feedback`, with app and iOS version),
  the app's release notes and the server's news page
- Imprint, privacy policy and terms of use of the server in use, in an in-app
  Safari view (also on the welcome screen before sign-in)
- Account (Profil → tap your name): profile picture, user name, e-mail change
  with confirmation (`pending_email`), change password (the new token from
  `/auth/password` keeps this device signed in), set up 2FA ("In Authenticator
  öffnen" via `otpauth://`, key to copy, QR code) and turn it off, sign out on
  all devices (`/revoke-all`)
- Hint and "send again" while the e-mail address is unconfirmed; prompt for
  new terms of use when `/whoami` reports `terms.required`
- "Passwort vergessen?" on the sign-in screen (`/auth/forgot-password`)
- Delete the account in the app (`DELETE /auth/users/:userId`), with an
  explanation and a double confirmation; removes the token, cached images and
  settings from the device
- Siri and Shortcuts (App Intents, first part of #20): "Tanken erfassen" and
  "Laden erfassen" in the background (same API call as the entry sheet,
  odometer warnings from the API), "Nächster Termin" and
  "Durchschnittsverbrauch" with return values, "Eintrag erfassen" and
  "Fahrzeug öffnen" open the app; vehicles are selectable entities; German
  Siri phrases; only on an unlocked device
- Widget "Fahrzeug" (#22, first part): small (Ø consumption, next due date),
  medium (plus "Tanken"/"Laden" buttons that open the entry sheet), Lock
  Screen rectangular, circular and inline; vehicle chosen in the widget
  settings; data from `/stats` and `/reminders`, sign-in shared with the app
  through Keychain Sharing; links use `fuelstat://`
- Home Screen quick actions (long press on the icon): Tanken, Laden, vehicles
- Welcome screen, sign-in with labelled fields, 2FA as six digit boxes
  (one-time-code autofill), own server under "Eigener Server"
- Sign in / register (incl. 2FA code), token stored in the Keychain, renewed
  once a day while the app is used (`/auth/refresh`), sign out revokes it
- Vehicle page with photo, key figures, due dates, entries, chart and master data
- Create, edit and delete vehicles; plan limits from the API are shown as a message
- Record fill-ups and charging sessions: last vehicle and last price prefilled,
  any two of amount, price per unit and total give the third, odometer warnings
  from the API are shown
- Nearby fuel stations with current prices (Tankerkönig via `GET /api/v1/stations`,
  needs `TANKERKOENIG_API_KEY` on the server)
- Vehicle photo from the camera or photo library; images are cached on the device
  by file name, because the signed image URLs change daily

The first offline-only prototype (SwiftData) is no longer shown; its code
stays in the project for now.

### Project structure

- `Fuelstat.xcodeproj` – iOS app (SwiftUI, iOS 17+)
- `Fuelstat/` – app sources (models, views, App Intents)
- `Shared/` – API client, models and Keychain, used by app and widgets
- `FuelstatWidgets/` – widget extension
- `Config/` – Info.plist additions and entitlements
- `Packages/FuelstatCore` – platform-independent logic (consumption calculation,
  server address parsing, image cache keys) with tests

The UI is in German. Strings are localizable (`Localizable.xcstrings`); Xcode
fills the catalog when the app is built in the IDE.

### Build & test

Open `Fuelstat.xcodeproj` in Xcode and run the `Fuelstat` scheme.

Core logic tests:

```sh
cd Packages/FuelstatCore
swift test
```

## Roadmap

Planning uses the [milestones](https://github.com/FuelStat/fuelstat-ios/milestones)
of this repository, one per app version. The app version is independent of the
web app/API version; what the app needs from the API is planned in
[FuelStat/fuelstat](https://github.com/FuelStat/fuelstat/milestones), in backend
milestones due before the app version that needs them (shared schedule in the
tracking issue [FuelStat/fuelstat#116](https://github.com/FuelStat/fuelstat/issues/116)).
The full feature list is [#15](https://github.com/FuelStat/fuelstat-ios/issues/15).

| Version | Planned | Focus |
|---|---|---|
| [0.2.0 – Foundation](https://github.com/FuelStat/fuelstat-ios/milestone/1) | 2026-12-06 | Sign-in and account complete (2FA setup, password, devices, profile), account deletion, imprint and privacy policy, test checklist per release |
| [0.3.0 – Capture](https://github.com/FuelStat/fuelstat-ios/milestone/2) | 2027-01-10 | Record everything online: charging with nearby chargers, expenses and categories, odometer-only entries, logbook, editing entries |
| [0.4.0 – Insights & Reminders](https://github.com/FuelStat/fuelstat-ios/milestone/3) | 2027-01-31 | Full statistics and costs, local reminders, plan display, onboarding, sharing vehicles |
| [0.5.0 – Native](https://github.com/FuelStat/fuelstat-ios/milestone/4) | 2027-02-28 | More than the web: offline capture and sync, Siri/Shortcuts/Spotlight (App Intents), Face ID lock, decision on the paid developer program |
| [0.6.0 – Glance](https://github.com/FuelStat/fuelstat-ios/milestone/5) | 2027-03-31 | Widgets, camera recognition, export and report via the share sheet |
| [1.0.0 – App Store](https://github.com/FuelStat/fuelstat-ios/milestone/6) | 2027-04-30 | Parity with the web app, CSV import, push, TestFlight and App Store (paid developer program) |
| [Later](https://github.com/FuelStat/fuelstat-ios/milestone/7) | – | Ideas without a date: CarPlay, StoreKit, live trips, Apple Watch |

Guideline: first a complete, reliable app for everyday use, then what only a
native app can do. Features that need the paid Apple Developer Program
(push, TestFlight, CarPlay, StoreKit, possibly widgets) wait for the decision in
[#39](https://github.com/FuelStat/fuelstat-ios/issues/39).

## License

See LICENSE.
