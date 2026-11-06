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

### Current state (v0.1)

A first, offline-only version:

- Manage vehicles (petrol, diesel, LPG, electric)
- Record fuel / charging entries (date, odometer, volume, cost, full tank)
- Statistics per vehicle: average consumption (full-tank method),
  cost per km, average price per unit, total cost, tracked distance

Data is stored locally with SwiftData.

### Fuelstat API (in progress)

The app talks to the Fuelstat API (`https://tanken.1emc.de/api/v1` by default;
self-hosted servers can be entered on the sign-in screen):

- Sign in / register (incl. 2FA code), token stored in the Keychain, renewed
  once a day while the app is used (`/auth/refresh`), sign out revokes it
- Vehicle list with photo, fuel type and current odometer
- Vehicle page with key figures (`/stats`), latest fill-ups, master data
- Create, edit and delete vehicles; plan limits from the API are shown as a message
- Vehicle photo from the camera or photo library; images are cached on the device
  by file name, because the signed image URLs change daily

The offline views from v0.1 are currently not shown; their code stays for the
upcoming fill-up and statistics screens.

### Project structure

- `Fuelstat.xcodeproj` – iOS app (SwiftUI, iOS 17+)
- `Fuelstat/` – app sources (models, views)
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

## License

See LICENSE.
