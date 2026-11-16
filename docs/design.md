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

**Structure, names and homes of content are defined in the shared document,
[section 7](https://github.com/FuelStat/fuelstat/blob/main/docs/design.md#7-navigation-und-aufbau)**
(FuelStat/fuelstat#206): the five areas (7.1), vehicle choice and the extra
views of a vehicle (7.2), quick entry (7.3), Profil groups (7.4), the glossary
(7.5, source for `Localizable.xcstrings`) and the "home of every content" table
(7.6). This file only says how SwiftUI shows them. Do not add areas, tabs,
segments or labels that are not in section 7; put new content in the table
there first.

| Shared (section 7) | iOS |
|---|---|
| Leiste: Start · Einträge · ＋ · Statistik · Profil (7.1) | `TabView` with four tabs; the "＋" sits in the middle of the tab bar as a prominent filled circle in `Brand` (not a tab: it opens the quick-entry sheet; long press offers the entry types). Accessibility label "Eintrag erfassen" |
| Vehicle switcher (7.2) | `VehicleSwitcher` at the top of Start, Einträge and Statistik ("VW Golf ▾"), opens a sheet with the active vehicles and "Fahrzeuge verwalten" (goes to Profil → Fahrzeuge). The choice lives in memory for the session only; after launch the default vehicle (first in `sortOrder`) is selected |
| Start with fleet plan (7.2) | With `features.fleet` and two or more active vehicles Start is a list of compact vehicle cards; a tap selects the vehicle and pushes its overview. No comparison |
| Extra views Service · Fahrten · Fahrzeugdaten (7.2) | `NavigationStack` push from the "Mehr zum Fahrzeug" rows on Start and from Profil → Fahrzeuge → [vehicle]. No segmented control, no tab bar change |
| Berichte und Export (7.1, 7.6) | One toolbar menu on Einträge |
| Profil groups (7.4) | Grouped `List`: Konto, Fahrzeuge, Daten, Benachrichtigungen, Über, Darstellung |
| Archive (7.2) | Profil → Fahrzeuge → Archiv, read-only |

Rules that stay iOS-specific:

- System tab bar and navigation bar, no custom replacements. Back is the
  system back button and the swipe gesture.
- One "＋" per screen (shared rule): the tab-bar circle is it, no extra
  floating button.
- Number inputs use `NumberField`; `CodeField` is for the 2FA code only.

**Current state:** the app still has the older structure (vehicle detail with
the segments Übersicht · Einträge · Statistik · Daten, vehicle switcher
remembered across launches). It is moved to the structure above in
FuelStat/fuelstat-ios#84 (milestone 0.4.0, the profile grouping and the terms
earlier if possible).

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
7. **Mehr zum Fahrzeug:** three rows with icon and chevron: Service, Fahrten,
   Fahrzeugdaten (pushed views, see Navigation).

### Vehicle views (Service, Fahrten, Fahrzeugdaten)
There is no vehicle detail page with segments: **Start is the vehicle overview**
(shared section 7.2). The three further views are pushed onto the navigation
stack:

- Full-width photo at the top only where it helps (Fahrzeugdaten), content in a
  **sheet-style card that overlaps the photo** with rounded top corners. Back
  and, where relevant, edit as round buttons on the photo.
- **Service:** parts with intervals and replacements, upcoming dates (full list;
  Start shows at most three).
- **Fahrten:** trip log with purpose, evaluation and export.
- **Fahrzeugdaten:** master data in grouped sections (Allgemein, Technik, Kauf,
  Wartung, Versicherung und Steuer), then Status (aktiv, verkauft,
  stillgelegt), Teilen ("Geteilt mit") and Löschen. This is the only place for
  editing, status, sharing and deleting.

### Quick entry (sheet)
- Type picker at the top as large chips with icons: Tanken, Laden, Ausgabe,
  Kilometerstand. Chips are `CardTint` with the icon in the energy colour,
  the selected one `Brand`; never a coloured tile with white text.
- Nearby stations as horizontal cards with name, distance and price; the
  selected one is highlighted. Recently used stations first.
- Big numeric fields (`NumberField`, never `CodeField`) for amount, price per unit and total (any two fill the
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
- `NumberField` – big numeric field with visible label and unit (odometer,
  quantity, price, amount); to be built with the quick-entry sheet
- `CodeField` – six-digit input, **2FA only**

Every component gets a SwiftUI preview in light and dark mode and at a large
Dynamic Type size.

## Do not

- No custom fonts, no hard-coded colours or sizes in views.
- No information conveyed by colour only.
- No placeholder text as the only label of a field.
- No custom tab bars or toolbars that replace the system ones.
- No marketing banners on the Start screen; the space belongs to the user's data.
