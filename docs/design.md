# Fuelstat iOS – design

**The shared design lives in
[FuelStat/fuelstat `docs/design.md`](https://github.com/FuelStat/fuelstat/blob/main/docs/design.md)**
(German): direction, brand, colour tokens with light and dark values, type
roles, spacing grid, radii, shared components, platform guardrails and the
accessibility baseline. It is the single source of truth for Web/PWA, iOS and
Android (FuelStat/fuelstat#153). Never define a token value here; change it
there first, then in the asset catalog and `Fuelstat/Design/Theme.swift`.

This file only covers what is specific to iOS: how the shared structure is
built in SwiftUI. Feature scope is in #15.

## Navigation (iOS)

Tab bar with four tabs and a central log action:

| Tab | Content |
|---|---|
| **Start** | Selected vehicle: hero, key figures, upcoming dates, nearby stations, latest entries |
| **Einträge** | All entries, grouped by month, search and filters |
| **＋ Erfassen** | Not a tab: opens the quick-entry sheet (Tanken, Laden, Ausgabe, Kilometerstand) |
| **Statistik** | Charts and yearly overview for the selected vehicle |
| **Profil** | Account, vehicles, reminders, import/export, settings, about |

- **Vehicle switcher** at the top of Start, Einträge and Statistik: vehicle name
  with a chevron ("VW Golf ▾"), opens a sheet with all vehicles (photo, name,
  plate). The choice is remembered.
- The "+" is a prominent filled circle in the brand colour, centred in or
  floating just above the tab bar. Long press offers the four entry types
  directly. It must have the accessibility label "Eintrag erfassen".
- Vehicle management (list, add, sort) lives under Profil → Fahrzeuge and is
  reachable from the switcher sheet ("Fahrzeuge verwalten").

## Screens (iOS layout)

### Start
1. Header: vehicle switcher left, profile picture right (small circle).
2. **Vehicle hero card:** photo (rounded, slight gradient at the bottom for
   legibility), name, plate, current odometer, fuel type badge.
3. **Stat tiles** in a row of three: Ø Verbrauch, Kosten/km, Kosten diesen Monat.
   Big value, small unit, short label – like the "5 seats · 4 doors · Diesel"
   tiles of the inspiration, filled with our figures.
4. **Nächste Termine:** up to three rows (TÜV, Wartung, Versicherung, Steuer)
   with status badge; "Alle anzeigen".
5. **In der Nähe:** card with a small map thumbnail and the cheapest nearby
   station or charger ("Diesel 1,689 € · 350 m"); tap opens the map.
6. **Letzte Einträge:** the latest three to five entries; "Alle anzeigen".

### Vehicle detail
- Full-width photo at the top, content in a **sheet-style card that overlaps
  the photo** with a grab handle look (rounded top corners). Back and edit as
  round buttons on the photo.
- Segmented control below the title: Übersicht · Einträge · Statistik · Daten.
- "Daten" shows master data in grouped sections (Allgemein, Technik, Kauf,
  Wartung, Versicherung und Steuer).

### Quick entry (sheet)
- Type picker at the top as large chips with icons: Tanken, Laden, Ausgabe,
  Kilometerstand.
- Nearby stations as horizontal cards with name, distance and price; the
  selected one is highlighted. Recently used stations first.
- Big numeric fields for amount, price per unit and total (any two fill the
  third), odometer with the plausibility hint from the API inline.
- Chips for Voll / Teil. Primary button full width at the bottom: "Speichern".
- Works offline; an unsent entry shows a small "wartet auf Übertragung" badge.

### Entries
- Search field at the top, **filter chips** below (Alle, Tanken, Laden,
  Ausgaben, Kilometer).
- Filter button opens a **bottom sheet** with chip groups (type, category),
  a range slider for the amount, sort (Neueste, Älteste, Betrag) and
  "Zurücksetzen" top right; full-width "Anwenden" button.
- List grouped by month with a sticky month header and month total. Rows: icon
  in a tinted circle, title (station or category), date and odometer, amount
  right-aligned. Swipe to edit or delete.

### Statistics
- Range chips: 6 Monate · Jahr · Gesamt.
- Cards with Swift Charts: consumption per month, costs per month, cost
  structure by category, CO₂. Each chart has an accessibility summary.
- Year overview as a card list, not a wide table.

### Map (stations and chargers)
- Map fills the screen; a bottom sheet with the list can be dragged between
  peek, half and full height.
- **Price bubbles as map pins** for fuel stations ("1,689"), power and plug
  icons for chargers. The current location button sits top right.

### Onboarding, sign-in, 2FA
- Welcome: one full-colour brand screen in both modes: navy background
  (see "Marke" in the shared document) like the app icon, white text, teal accents, the gauge motif of
  the icon as illustration; then "Anmelden" / "Konto erstellen".
- Sign-in and registration on a plain background: title, short subtitle,
  fields with visible labels, primary button, secondary link. Server address
  under "Eigener Server" (collapsed).
- 2FA: six separate digit boxes, auto-advance, paste support, one-time-code
  autofill (`.textContentType(.oneTimeCode)`).
- First-run flow afterwards: add first vehicle → log first entry (as in the
  web app's onboarding).

## iOS mapping of the shared tokens

- **Colours:** named colours in `Assets.xcassets` with light and dark
  variants, same names as the tokens (`Brand`, `OnBrand`, `BrandDeep`,
  `Background`, `Card`, `CardTint`, `Status*`, `Energy*`), accessed only via
  `Theme`. `Text`, `TextSecondary` and `Separator` use the system colours
  (`.primary`, `.secondary`, `separator`) so "Increase Contrast" keeps working.
  The widget extension keeps copies of the colours it uses in its own asset
  catalog; update both.
- **Spacing and radii:** `Theme.Spacing` (`xxs` … `xl`) and `Theme.Radius`
  (`card` 20, `tile` 14) with continuous corners (`.card`, `.tile` shapes);
  chips and badges use `Capsule()`.
- **Type roles → Dynamic Type:** `screenTitle` `.largeTitle` bold (navigation
  large title), `figureHero` `.title` bold rounded, `sectionTitle` `.title3`
  bold, `figure` `.title2` bold rounded, `headline` `.headline`, `body`
  `.body`, `label` `.subheadline`, `footnote` `.footnote`, `unit` `.caption`.
  Figures use `.fontDesign(.rounded)` and `.monospacedDigit()`. Only text
  styles, no fixed sizes.

## iOS specifics

- **System chrome:** on iOS 26 tab bar, navigation bar and sheets pick up
  Liquid Glass automatically; do not paint over them with custom backgrounds.
- **Icons:** SF Symbols throughout (`fuelpump`, `bolt.car`,
  `gauge.with.needle`, `wrench.and.screwdriver`,
  `calendar.badge.exclamationmark` …). Without a vehicle photo: tinted
  placeholder with `car.side` in the vehicle's energy colour. Entry icons sit
  in a 36 pt tinted circle.
- **Motion and haptics:** standard SwiftUI transitions; matched geometry from
  vehicle card to detail hero is welcome. Haptic success after saving an
  entry, warning for plausibility hints (`Haptics`). Respect Reduce Motion.
- **Charts:** Swift Charts with `accessibilityChartDescriptor` or an
  accessibility summary per chart.

## Components to build

The shared components from the central document live in `Fuelstat/Design/`:

- `Theme` – colour and spacing tokens
- `CardContainer` – background, radius, padding
- `StatTile` – value, unit, label, optional trend
- `SectionHeader` – title with optional "Alle anzeigen"
- `FilterChip` and `ChipGroup`
- `StatusBadge` – OK / bald fällig / überfällig with icon
- `VehicleHero` – photo, name, plate, odometer, energy badge
- `VehicleSwitcher` – header button and sheet
- `EntryRow` – icon circle, title, subtitle, amount
- `PrimaryButton` – full width, brand colour, loading state
- `CodeField` – six-digit 2FA input

Every component gets a SwiftUI preview in light and dark mode and at a large
Dynamic Type size.

## Do not

- No custom fonts, no hard-coded colours or sizes in views.
- No information conveyed by colour only.
- No placeholder text as the only label of a field.
- No custom tab bars or toolbars that replace the system ones.
- No marketing banners on the Start screen; the space belongs to the user's data.
