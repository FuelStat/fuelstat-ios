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

The app now talks to the Fuelstat API (`https://tanken.1emc.de/api/v1`):

- Sign in / register (incl. 2FA code), token stored in the Keychain, sign out
- Vehicle list, vehicle master data (no statistics yet) and creating vehicles

The offline views from v0.1 are currently not shown; their code stays for the
upcoming fill-up and statistics screens.

### Project structure

- `Fuelstat.xcodeproj` – iOS app (SwiftUI, iOS 17+)
- `Fuelstat/` – app sources (models, views)
- `Packages/FuelstatCore` – platform-independent logic (consumption calculation) with tests

### Build & test

Open `Fuelstat.xcodeproj` in Xcode and run the `Fuelstat` scheme.

Core logic tests:

```sh
cd Packages/FuelstatCore
swift test
```

## License

See LICENSE.
