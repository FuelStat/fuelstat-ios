# App Privacy (App Store Connect)

Draft of the "App Privacy" answers for App Store Connect (#26, #12). Check it
against the app and the server before every submission; anything the app starts
sending to the server must be added here.

The app has **no tracking, no analytics, no ads and no third-party SDKs**. All
data goes to the Fuelstat server the user signs in to (the hosted service
`tanken.1emc.de` or a self-hosted installation). The privacy policy URL for App
Store Connect is `https://tanken.1emc.de/pages/datenschutz.php`; the app links
to the policy of the server in use (Profil → Rechtliches, and on the welcome
screen before sign-in).

## Data types

All types below are **linked to the user** (they belong to the account),
**not used for tracking**, and used for **App Functionality** only.

| App Store category | Data type | What the app sends | Where |
|---|---|---|---|
| Contact Info | Email Address | Account e-mail; also sent with feedback | Sign-in, registration, `POST /feedback` |
| User Content | Photos or Videos | Vehicle photos (the server strips metadata and stores WebP) | `POST /vehicles/:id/media/upload` |
| User Content | Other User Content | Vehicles, fill-ups, charging sessions, odometer readings, notes | Vehicle and entry endpoints |
| User Content | Customer Support | Feedback messages | `POST /feedback` |
| Identifiers | User ID | Account ID used in API paths | All signed-in requests |
| Location | Precise Location | Current position for the nearby-station search, only while the app is in use; the server forwards it to Tankerkönig and does not store it | `GET /stations?lat=&lng=` |
| Diagnostics | Other Diagnostic Data | App version, iOS version and device model, only with feedback | `page` of `POST /feedback` |

Notes:

- **Location:** App Store Connect asks whether data is collected, i.e. leaves
  the device. It does (to the server and Tankerkönig), so declare "Precise
  Location", even though it is not stored. Not linked to the user if the
  server does not log it — check the server's access logs before submitting.
- **Financial info:** fuel prices and costs are user content, not payment data.
  There are no in-app purchases yet (see #12 for plans).
- **Account deletion:** in the app under Profil → Konto löschen
  (`DELETE /auth/users/:userId`), which App Store Review Guideline 5.1.1(v)
  requires.

## Data not collected

Contacts, health, browsing history, search history (station searches are not
stored), purchases, sensitive info, crash logs (no crash reporter), usage data
(no analytics).
