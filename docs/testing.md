# Release test checklist

Every app version is tested by hand against a real Fuelstat installation
before it is tagged (#11). The list below is the fixed, repeatable run. It
grows with the app: **a PR that adds or changes a feature adds or changes its
steps here.**

Automated UI tests (XCUITest) for the main flows are planned later; until then
this run is the only end-to-end test.

## When and against what

Run the whole list once per release, on the release branch, with the build
that will be tagged:

1. **Hosted service** – `https://tanken.1emc.de/api/v1`, with the test account
   (not a personal account: the run creates and deletes data).
2. **Self-hosted server** – a Docker installation of the same server version
   (see below), entered under "Eigener Server" on the sign-in screen.

Sections marked **(hosted only)** need not be repeated on the self-hosted
server. Everything else is run against both.

Use a real iPhone for the full run: camera, Siri, widgets, quick actions and
location do not work properly in the simulator. Check at least one screen per
section in dark mode, with a large Dynamic Type size and with VoiceOver.

### Record the server version

Before each run, note what the server reports and put it in the result:

```sh
curl -s https://tanken.1emc.de/api/v1/health
curl -s http://<mac-ip>:3000/api/v1/health
```

`version` is the API version the release was tested with. The same value is
shown in the app under Profil → Server-Version; both must agree.

### Self-hosted server

Set up the API and database as described in FuelStat/fuelstat
(`README.md` → Installation, `docs/installation.md`), on the tag that matches
the hosted service:

```sh
git clone https://github.com/FuelStat/fuelstat.git && cd fuelstat
git checkout v<server version>
cd infra && cp .env.example .env    # set the secrets as described there
docker compose up -d --build
curl -s http://127.0.0.1:3000/api/v1/health
```

The API listens on localhost only by default. To reach it from the iPhone,
publish it in the local network (port mapping in `infra`, or a reverse proxy)
and enter that address in the app. The PHP frontend is not needed for the app
run, except for the legal pages and the news page (section 9).

Without `TANKERKOENIG_API_KEY` the station search has no results; test the
empty state there and the real search on the hosted service.

## Test data

- A test account with a confirmed e-mail address you can read, and an
  authenticator app for 2FA.
- A second account with a confirmed e-mail address: first for sharing
  (section 7c), then thrown away in the account deletion test (section 10).
- For the plan messages: the test account on Free; for own categories and the
  trip export one run on Plus (the operator sets the plan).
- One combustion vehicle with at least three full fill-ups, so consumption
  and the chart have values; one electric or plug-in hybrid vehicle for
  charging and the filter chips.

## Checklist

Tick each step per server. A step fails when the app shows something other
than what the web app shows for the same account: the API is the source of
truth, so figures must match the web app exactly.

### 1. Start and sign-in

- [ ] Fresh install: welcome screen appears; Impressum, Datenschutz and
      Nutzungsbedingungen open in the in-app Safari view before sign-in
- [ ] Wrong password: error message from the API, the app stays on the
      sign-in screen
- [ ] Sign-in with e-mail and password, without 2FA
- [ ] Sign-in with 2FA: six digit boxes, one-time-code autofill, wrong code
      shows an error and allows another try, correct code signs in
- [ ] "Eigener Server": invalid address is rejected with a message; valid
      address signs in; "Standardserver verwenden" goes back to the hosted
      service
- [ ] "Konto erstellen" registers a new account (only if
      `registration_enabled` is true in `/health`)
- [ ] "Passwort vergessen?" sends the reset mail **(hosted only)**
- [ ] Unconfirmed e-mail address: hint is shown, "Bestätigungsmail erneut
      senden" sends the mail **(hosted only)**
- [ ] New terms of use (`terms.required` in `/whoami`): prompt appears,
      "Nutzungsbedingungen lesen" opens them, accepting continues – only
      testable when the server's `terms_version` changed; otherwise note
      "not testable"

### 2. Session: renewal and sign-out

- [ ] Quit and reopen the app: still signed in, no sign-in screen
- [ ] Session renewal: leave the app for more than 30 minutes (access token
      expired), open it again; it stays signed in and loads data without a
      sign-in screen. Same for the widget and a Siri action after 30 minutes
- [ ] Next day: still signed in, widget still shows data
- [ ] Sign out on the iPhone: the device disappears from the web app's
      device list (Einstellungen → Sicherheit)
- [ ] "Abmelden" returns to the welcome screen; reopening the app does not
      sign in again; the widget shows its signed-out state
- [ ] "Auf allen Geräten abmelden" (Konto): this device is signed out; a web
      session of the same account is signed out too
- [ ] A revoked token (sign out everywhere from the web app, then use the
      app): the app goes to the sign-in screen and says why

### 3. Account (Profil → tap your name)

- [ ] Change the user name; it shows in the profile and in the web app
- [ ] Set a profile picture from the library and from the camera, then
      remove it
- [ ] Change the e-mail address: hint about the pending address, "erneut
      senden" works, after confirming the new address is shown
      **(hosted only)**
- [ ] Change the password: wrong current password gives an error and does
      **not** sign out; correct one succeeds, this device stays signed in,
      the web session is signed out
- [ ] Set up 2FA: "In Authenticator öffnen" opens the authenticator, the key
      can be copied, the QR code is shown; a wrong code gives an error, the
      correct code turns 2FA on
- [ ] Sign out and in again with the new 2FA
- [ ] Turn 2FA off with password and code; a wrong code gives an error and
      does not sign out
- [ ] Konto → Angemeldete Geräte lists this iPhone as "Dieses Gerät" with
      app version and last use; an app signed in elsewhere (second device or
      simulator) appears too and can be signed out with a swipe – that device
      then lands on the sign-in screen

### 4. Vehicles

- [ ] Empty account: "Noch keine Fahrzeuge" with a way to add one
- [ ] Create a vehicle with all fields; it appears in the list, in the
      vehicle switcher and in the web app
- [ ] Edit name and master data; changes are shown everywhere
- [ ] Vehicle switcher: the choice is remembered after restarting the app
- [ ] Plan limit: creating one vehicle more than the plan allows shows the
      API's message, the app does not block on its own
- [ ] Delete a vehicle with entries ("Fahrzeug und alle Einträge löschen"),
      with confirmation; it is gone in the app and in the web app

### 5. Vehicle photo

- [ ] Add a photo with "Foto aufnehmen" and with "Foto auswählen"; it shows
      on the vehicle page, on Start and in the web app
- [ ] Replace the photo; the new one is shown, not the cached old one
- [ ] "Foto entfernen" removes it everywhere
- [ ] Next day (signed image URLs have changed): photos still show without
      a visible reload; in flight mode the cached photo still shows

### 6. Fill-ups and charging sessions

- [ ] "+" opens the entry sheet with type chips Tanken · Laden · Ausgabe ·
      Fahrt · Kilometer, the last vehicle and the last price prefilled;
      switching the chip keeps the vehicle
- [ ] Full fill-up: enter two of amount, price per unit and total, the third
      is calculated ("berechnet"); the saved entry matches the web app
- [ ] Partial fill-up ("Teilbetankung") and a forgotten previous entry
      ("Letzten Eintrag vergessen") are saved with those flags
- [ ] Odometer lower than the previous entry: the API's warning is shown
- [ ] Decimal comma input (e.g. `45,67`) is accepted
- [ ] Charging session on the electric or plug-in vehicle, in kWh
- [ ] Entry without odometer ("Kilometerstand (optional)") is saved
- [ ] Station from "In der Nähe" is taken over into the entry
      **(hosted only)**

- [ ] Edit a fill-up younger than 14 days (Einträge → entry → Bearbeiten):
      changes are saved and match the web app
- [ ] Edit a fill-up older than 14 days: the API's message about the 14 days
      is shown, nothing is changed
- [ ] Fill-up without odometer: shows "ohne km" in the list; "Kilometerstand
      nachtragen" on its detail page works, also when it is older than 14
      days

### 7. Start, Einträge and entry details

- [ ] Start shows the vehicle hero, key figures, due dates, the cheapest
      nearby station and the latest entries for the selected vehicle
- [ ] Einträge: fill-ups, charging sessions, expenses, odometer notes and
      trips in one list, grouped by month, newest first; the month header
      shows the same costs as the web app's month total
- [ ] Filter chips show only kinds the vehicle has entries of and filter the
      list; search finds an entry by station, vendor, category or note
- [ ] More entries load while scrolling (needs more than 50 entries)
- [ ] Tapping an entry opens its details (consumption of a full fill-up,
      "Erfasst von" on a shared vehicle); Bearbeiten and Löschen work there
- [ ] Swipe to edit and to delete; key figures update after a delete
- [ ] Empty state: "Noch keine Einträge"
- [ ] Pull to refresh on Start picks up an entry made in the web app

### 7a. Expenses and categories

- [ ] "+" → Ausgabe: categories from the server with their symbols; Plus
      categories are marked "mit Plus" in the Free plan, choosing one shows
      the API's plan message when saving
- [ ] Save an expense with amount, odometer, vendor and note; it appears in
      the list and in the web app; change and delete it
- [ ] "+" → Kilometer: an odometer note without costs is saved and does not
      count in the month total
- [ ] Profil → Kategorien: with Plus create, rename and delete an own
      category; deleting one in use asks where its expenses go. In the Free
      plan the API's message is shown

### 7b. Trip log

- [ ] "+" → Fahrt: the start odometer is prefilled with the current one;
      with start and end the distance is shown; without start the distance
      is entered instead
- [ ] Purpose "Arbeitsweg" in the Free plan: the API's plan message
- [ ] Einträge → Fahrtenbuch: year and purpose filters, totals, business
      share and estimated costs equal the web app; chart "Kilometer je Monat"
- [ ] Change and delete a trip (swipe)
- [ ] Export: with Plus the share sheet offers a CSV that opens in Numbers;
      in the Free plan the API's message

### 7c. Sharing (two accounts)

- [ ] Vehicle → Daten → Fahrzeug teilen: invite the second account as
      Mitfahrer; the invitation is listed and can be withdrawn
- [ ] Second account (confirmed e-mail): Profil → Einladungen shows it;
      accepting adds the vehicle, marked "Geteilt von …"
- [ ] As Mitfahrer: record an entry, change it; an entry of the owner cannot
      be changed (API message); the photo menu and Bearbeiten are hidden
- [ ] Owner changes the role to "Nur ansehen": the "+" no longer offers the
      vehicle, the entries have no edit actions
- [ ] Member leaves the vehicle ("Fahrzeug verlassen"); owner removes a member

### 8. Statistik, Termine and reminders

- [ ] Key figures (Ø Verbrauch, Kosten pro km, Gesamtkosten, Erfasste
      Strecke) equal the web app's values for the same vehicle
- [ ] Chart "Verbrauch je Tankfüllung" shows one point per full fill-up;
      "Keine Werte in diesem Zeitraum." when there are none
- [ ] Due dates (`/reminders`) on Start and on the vehicle page match the web
      app; "Keine Termine" when there are none

- [ ] Tapping a due date opens an expense with the matching category; after
      saving, the next due date moves on
- [ ] Profil → Termine und Erinnerungen lists the due dates of all vehicles,
      most urgent first
- [ ] Switching "Auf diesem iPhone erinnern" on asks for permission only now;
      the footer shows the number of planned reminders; with a due date
      inside the lead time the notification arrives next morning at 9:00
      (or set the lead time so it falls on tomorrow)
- [ ] Tapping the notification opens the vehicle
- [ ] Switching off or signing out removes the planned reminders

### 9. Stations, location and server pages

- [ ] First use asks for location permission; denying it shows a usable
      message, not an empty screen
- [ ] "Tankstellen in der Nähe" lists stations with prices and the
      Tankerkönig attribution **(hosted only)**
- [ ] Without a Tankerkönig key: "Keine Tankstellen" (self-hosted)
- [ ] Profil → Rechtliches: Impressum, Datenschutz, Nutzungsbedingungen open
      the pages of the server in use
- [ ] Profil → Neuigkeiten opens the server's news page
- [ ] `/health` → `apps.ios`: with `minimum_version` above the app's version
      (self-hosted, `backend/src/lib/appVersions.js`) the app shows "Bitte
      aktualisiere Fuelstat"; with only `recommended_version` above it, Profil
      shows the hint; with `null` nothing appears
- [ ] Profil shows App-Version (the version being released) and
      Server-Version (equal to `/health`)
- [ ] Feedback: "Feedback senden" arrives at the server operator with app
      and iOS version **(hosted only)**
- [ ] Release notes in the app list the version being released

### 10. Delete the account

With the throwaway account only.

- [ ] "Konto löschen" explains what is deleted and asks twice
- [ ] After "Konto endgültig löschen" the app is on the welcome screen;
      signing in with that account fails
- [ ] Cached images and settings are gone (sign in with another account: no
      data of the deleted one)

### 11. Siri, Shortcuts, widgets, quick actions

On an unlocked device.

- [ ] Shortcuts app lists the Fuelstat actions; vehicles can be picked as
      a parameter
- [ ] "Tanken erfassen" and "Laden erfassen" by Siri create an entry (German
      decimals spoken, e.g. "fünfundvierzig Komma sechs"); it shows in the app
- [ ] "Nächster Termin" and "Durchschnittsverbrauch" answer with the values
      the app shows
- [ ] "Eintrag erfassen" and "Fahrzeug öffnen" open the app at the right place
- [ ] Widget "Fahrzeug": small, medium and the three Lock Screen sizes show
      the vehicle chosen in the widget settings; values equal the app's
- [ ] Medium widget: "Tanken" and "Laden" open the entry sheet
      (`fuelstat://add`)
- [ ] CarPlay (iOS 26, car or CarPlay Simulator from Xcode's Additional
      Tools): add "Fahrzeug im Auto" in Settings → General → CarPlay → the car
      → Widgets; it shows the vehicle selected in the app and its average
      consumption; switching the vehicle in the app updates it; nothing on it
      reacts to taps
- [ ] Long press on the app icon: Tanken, Laden and the vehicles open the
      right screen

### 12. Robustness and accessibility

- [ ] Flight mode: screens show an error with "Erneut versuchen", no crash;
      after reconnecting, retry loads the data
- [ ] Server unreachable (stop the Docker containers): same behaviour, and
      the app does not sign out (self-hosted)
- [ ] Dark mode: no unreadable text or white boxes on the main screens
- [ ] Largest Dynamic Type size: nothing is cut off on sign-in, the entry
      sheet and Start
- [ ] VoiceOver: tabs, the "+" button, key figures and the entry sheet's
      fields are announced with meaningful labels

## Recording the result

Copy this block into the release PR and fill it in. Failed steps get an issue
in the milestone of the release (or the next one, if the maintainer decides to
ship anyway) and are named here.

```markdown
## Test run (docs/testing.md)

- App: 0.2.0 (build 2), commit abc1234
- Device: iPhone 14 Pro, iOS 26.1
- Date: 2026-12-01

| Server | API version (`/health`) | Result |
|---|---|---|
| tanken.1emc.de | 0.12.0 | all passed / failed: … |
| self-hosted (Docker) | 0.12.0 | all passed / failed: … |

Not testable in this run: …
Failed steps and issues: …
```
