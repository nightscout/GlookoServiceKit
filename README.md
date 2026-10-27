# GlookoServiceKit

LoopKit remote-data-service plugin that uploads Trio (and Loop) diabetes data to Glooko.
It conforms to `Service` / `ServiceUI` / `RemoteDataService`, so Trio's `PluginManager`
discovers it and a native manager drives the uploads (same pattern as TidepoolServiceKit).

Reverse-engineered from the Glooko apps for pushing a patient's own data. Check Glooko's
terms before any production use.

## Two backends

The service exposes one variant at a time (`Configuration.variant`):

- **XT** — `srv.glookoxt.com`. JWT auth, Socket.IO moments, plus a server-side `.ibf` upload.
- **Classic** — `*.patient-api.glooko.com`. Cookie auth, REST `/api/v2` and `/api/v3`.

They are different systems with different APIs. Routing is not shared.

## Routing

What each data type uses, per variant:

| Data | XT | Classic |
|---|---|---|
| CGM glucose | moments (`ADD_MANY_RECORDS`) | CSV (`device/file/upload`, LibreviewCSV) |
| manual glucose | moments | `/api/v2/readings` (value = mg/dL x100) |
| carbs | moments | `/api/v2/foods` (standalone `QuickAdd`, no meal) |
| bolus | IBF | `/api/v2/insulins` (`insulinType: bolus`) |
| basal | IBF | `/api/v2/insulins` (`insulinType: basal`, delivered units per UTC hour) |
| delete | not supported | same guid with `softDeleted: 1` (bolus, carbs) |
| pump events / alarms | not sent | not sent |

Classic records carry a name-based guid (SHA-256 of a namespaced seed such as
`trio-insulin-bolus|<syncIdentifier>`), so every resend, edit or delete upserts the same record.
After insulin or carb writes Classic posts `/api/v3/users/activities_and_event_data_sync/complete`
(best effort). XT moments have no guid and no delete: each sample must be sent once, and
`uploadDoseData` sends nothing on XT because doses ride in the `.ibf`.

Pump data (basal, and bolus on XT) goes through `uploadPumpSnapshot(basal:boluses:carbs:now:)`.
Two rules drive that:

- A basal renders in the `.ibf` as a segment closed by the next basal. A single delta does
  not show. The snapshot must carry the whole window (Trio sends ~24h), as a contiguous timeline
  of `.basal`, `.tempBasal` and `.suspend` segments.
- The snapshot resends that window every cycle. The `.ibf` is deduplicated by date server-side,
  so resending is safe. The moments API is not deduplicated, which is why bolus stays in the
  `.ibf` on XT rather than going through moments.
- On Classic the same timeline becomes one basal record per UTC hour, sent only once the hour is
  fully covered and 15 minutes past its end. An hour that delivered nothing is soft-deleted, so a
  recomputed hour never keeps a stale total. Mutable boluses are held back.

Within a snapshot the sends are independent: a failure on one (bolus, carbs) does not block
the others (the basal `.ibf` is sent first).

## Auth

- **XT**: `POST /api/users/patient-login/` (email + password) sends an OTP, then
  `POST /api/users/code-auth` returns a JWT. Used as `Bearer` on REST, `token=` on the socket.
- **Classic**: region resolved from the email hash, then `POST /api/v3/users/sign_in`
  (`{"user":{email,password}}`), falling back to `/api/v2/users/sign_in` (`{"userLogin":{...}}`),
  returns the `_logbook-web_session` cookie. 401/403/423/429 stop without trying the fallback.
  2FA supported. An expired session (401/421) triggers one shared re-sign-in, at most once per
  5 minutes; after that uploads fail with "sign in again".
- Requests identify as `GlookoServiceKit (<host>/<version>; +<repo>)`. No Glooko app identity,
  device information or app keys are sent.

Credentials live in the Keychain (`KeychainCredentialStore`, via LoopKit's `KeychainManager`).

## Timestamps

XT timestamps are UTC. Classic timestamps are local (the CSV and `.ibf` paths are local, so the
`/api/v2` paths match them; UTC there shows carbs/bolus shifted by the offset).

## Layout

- `Core/` — constants, date/deflate/log utilities, unit helpers. No business logic.
- `Domain/` — `GlookoBackend` protocol, the `.ibf` generator, the CSV generator, models, the
  upload coordinator. Transport-agnostic.
- `Data/` — HTTP and Socket.IO transport, Keychain, and the two backends with their wire DTOs.
- `Service/` — `GlookoService` (the `RemoteDataService`), auth, sign-in error mapping.
- `UI/` — settings screen.

## Build

The `.xcodeproj` is committed and maintained in Xcode (same as TidepoolService). New source
files must be added to their target in Xcode.

It builds three frameworks (`GlookoServiceKit`, `GlookoServiceKitUI`, `GlookoServiceKitPlugin`)
against the same LoopKit the host app uses. Add the plugin to Trio's plugin set. The Kit does
not build standalone (it needs LoopKit from the host workspace).

## Known constraints

- XT: CGM and pump products are hardcoded (FreeStyle Libre, Omnipod) and the `.ibf` carries a
  synthetic Omnipod identity. No device detection.
- Events and alarms are not uploaded on either variant (Glooko does not display them from this
  path).
- Data Trio has but Glooko has no field for (IOB/COB, predictions, overrides, loop decisions)
  is dropped: `dosingDecisionDataLimit` and `settingsDataLimit` are 0.
