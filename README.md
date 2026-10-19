# SteelSeries Config

Unofficial, **login-free** macOS configuration tool for SteelSeries peripherals, built by
reverse-engineering the SteelSeries GG client.

Menu bar app: click the mouse icon → a popover with CPI presets, the CPI ladder and
polling-rate controls → a Settings window with the full editor (CPI ladder, sensor flags,
illumination, backups). Edits reach the mouse as they happen; **Save persists and
deploys** in one action.

Not affiliated with SteelSeries.

---

## Why this exists

SteelSeries GG requires an account and ships an Electron UI on top of a native core.
Everything the UI does, it does through a local HTTP API on `127.0.0.1` that needs no
authentication at all for reads and writes. This app talks to that API directly.

**No SteelSeries login. No SteelSeries servers. No Electron.**

## Safety model

The API is a footgun, and this app was written after demonstrating exactly how. This is
the one part worth reading before using it.

`PUT /configuration/{id}` **replaces** the fields present in the request body. Sending an
empty body `{} ` to that endpoint with the engine answering `200 OK` permanently wipes
`name`, `settings` and `undeployedSettings`. The engine will not warn you, and the GG
client does not protect against it either — the wipe this project was seeded by was
produced exactly that way.

The guarantees below are enforced in code, not by convention:

| Guarantee | Where | What it blocks |
|---|---|---|
| Read-modify-write only | `ConfigurationStore.save()` | Every write re-reads the configuration from the engine first and merges onto that, so edits made in the GG client since the window was opened are not clobbered. |
| Save persists *and* deploys | `ConfigurationStore.save()` | A write that only reaches the engine leaves the mouse running its old profile, which is indistinguishable from the save having failed. `save()` PUTs and then POSTs `/deploy`. |
| Live apply is debounced and partial | `ConfigurationStore.liveApply()` | Every edit is pushed to the mouse within 280 ms without saving, through the structural half of `WriteSafetyPolicy`. The live document strips keys carrying `no_live_deploy` (this mouse marks `button_mappings`), and the stored copy is re-read afterwards to put them back if the engine treated the omission as a replacement. |
| No empty settings body | `WriteSafetyPolicy` | `""`, whitespace, non-JSON, and non-object documents are rejected before the request is built. |
| No suspicious shrinkage | `WriteSafetyPolicy` | A write that would shrink `settings` by more than 90 % (and below 1 000 bytes) is rejected — the fingerprint of a wipe rather than an edit. |
| Automatic pre-write backup | `BackupStore` | The engine's *current* state is snapshotted to `~/Library/Application Support/SteelSeriesConfig/backups/` immediately before every write, not the state the window was opened from. |
| Confirm-then-deploy | `BarActionsView` | `POST .../deploy` needs a second tap within 4 s; it rewrites the device's live profile. |
| Unreadable schema ⇒ read-only | `ConfigurationStore.apply()` | If a device's `settings` document does not parse into the typed model, the UI stays visible but every control is disabled, rather than editing a document it does not understand. |

Backups are plain JSON, keyed by configuration id and timestamp. They survive a GG
uninstall and can be read without this app. Deleting the app does not touch the engine's
data, and deleting the engine's data does not delete the backups.

## Architecture

```
SteelSeriesConfig/
├── SSConfigApp.swift            App + AppDelegate, Settings window scene
├── Models/
│   ├── AnyJSONValue.swift       Untyped JSON tree; preserves unknown keys verbatim
│   ├── MouseSettings.swift      Typed accessors over AnyJSONValue; CPI/polling encodings
│   ├── Device.swift             GET /devices item; categorisation by deviceTypeName
│   ├── DeviceConfiguration.swift GET /configuration/{id}; the PUT body builder
│   ├── DeviceLinkState.swift    rf_status → LinkPhase; charge_status → BatteryStatus
│   ├── CoreProps.swift          coreProps.json model
│   ├── FlexibleBool.swift       The engine is inconsistent: `1`, `true`, `"1"`
│   └── SyncStatus.swift         isSync/isSynced probe
├── Services/
│   ├── EngineClient.swift       actor; the only network type in the app
│   ├── CorePropsLocator.swift   file discovery → engine URL
│   ├── ConfigurationStore.swift @MainActor @Observable orchestration, polling, live apply
│   ├── WriteSafetyPolicy.swift  pre-write validation, see table above
│   ├── BackupStore.swift        pre-write snapshots
│   ├── EngineProcessGuard.swift locate / launch the GG app
│   └── LocalhostTrustDelegate.swift TLS: accept the engine's self-signed cert, and only that cert
├── Views/
│   ├── Bar/                     menu bar popover (incl. BarStatusIndicators.swift)
│   └── Settings/                device editor, backups, engine info
└── Utils/
    └── StatusBarController.swift NSStatusItem + non-activating NSPanel
```

### The one interesting type

`MouseSettings` wraps `AnyJSONValue` (an untyped JSON tree) with typed accessors. It is
**not** a `Codable` struct, deliberately: the engine's documents contain keys this app has
never heard of, and a `Codable` round-trip would silently drop every one of them on save.
This way, `setBrightness(7)` touches one leaf and everything else survives byte-for-byte.
`MouseSettingsTests.testUnknownKeysSurviveMutation` exists to keep it that way.

### Endpoint semantics

Decoded from the client bundle, where the API is described by `verb` rather than HTTP
method:

| Client verb | HTTP | Endpoint | Used here |
|---|---|---|---|
| `fetch` | GET | `/devices` | device discovery |
| `fetch` | GET | `/device/{id}/configurations` | configuration list |
| `fetch` | GET | `/configuration/{id}` | read |
| `fetch` | GET | `/device/{id}/isSyncAndSynced` | hardware sync status |
| `update` | **PUT** | `/configuration/{id}` | **the only persistence mutation** |
| `submit` | **POST** | `/configuration/{id}/deploy` | push to hardware |
| `submit` | **POST** | `/configuration/liveDeploy` | live apply while editing |
| `submit` | **POST** | `/device/command` | `rf_status` / `charge_status` status reads |

`device/writeCommand` — the write half of `/device/command` — is deliberately unimplemented.
Every status value this app shows comes from reading it.

`GET /device/{id}` is deliberately not used — it returns `deviceTypeName: ''`, so the list
endpoint is the only reliable source for categorisation.

### Encodings

Both verified against the GG client's own renderer (webpack module `28352`, `render/166.js`)
and against a live Aerox 3 Wireless:

- **CPI** — stored as `resolution_n` in engine units; the client displays `resolution_i * 50`.
  Allowed range 50…18000 CPI, step 50, ladder length 1…5, active step in `active_level_index`.
  A mouse reporting `[4, 9, 13, 27, 38]` is offering 200 / 450 / 650 / 1350 / 1900 CPI.
  The quick presets (1000 / 2000 / 5000 / 6000) all sit exactly on that grid and rewrite
  **only the step you are currently on** — the rest of the ladder is your tuning and is
  left alone.
- **Polling rate** — stored as a small code, not the rate: `0 → 1000 Hz`, `1 → 500`,
  `2 → 250`, `3 → 125`.
- **Booleans** — the engine is inconsistent (`connected: 1` beside `hidden: false`).
  `FlexibleBool` accepts all of it. Values the client stores as `0`/`1` integers are
  written back as `0`/`1`, never as JSON `true`/`false`, so a write does not change a
  value's type.

## Status and live sync

### The status line

Connection and battery come from `POST /device/command` with `{id, command}`; the reply
carries its payload as a *JSON string* under `command_data`, and an empty string means
"unavailable", never 0 %.

`rf_status` returns `{rf_mode, rf_status}`. The GG client's own `rfModeToText` table was
the basis for the mapping used here:

| mode | status | Result | Editable |
|---|---|---|---|
| 4 | 1 | `ready` — wireless link up | yes |
| 16 | 2 | `wired` — on its cable, powered on | yes |
| 17 | 2 | `wiredIdle` — on its cable, powered off | no |
| 2 | * | `connecting` — pairing in progress | no |
| other | other | `linkLost` — receiver present, mouse not answering | no |
| — | — | no payload at all | `offline` |

`rf_status` is a *refinement*, not the source of truth: attachment comes from
`GET /devices`, whose `connected` flag the engine maintains for every device class. A
keyboard has no `rf_status` to ask about, and folding the two signals naively is what
would leave it stuck saying "Connecting…".

**Bluetooth needs the same treatment.** `rf_status` describes the 2.4 GHz dongle link, so
a mouse paired over Bluetooth answers an empty `command_data` while `/devices` reports
`connected: 1` — observed live, with `connected_product_id` pointing at
`aerox_3_wireless_bluetooth`. GG itself paints nothing in that case: its
`updateDeviceStatus` is guarded by `if (null != i)`, so the query is simply dropped. This
app reads it as `ready` instead, because a working mouse should not announce itself as
absent just because it is not on the dongle.

`charge_status` has **two encodings** and they disagree about what mode `2` means:

- **Level-code family** — the one this mouse uses. `battery_level` is a coarse
  0/1/2/4 code (there is no `3`; the sibling table fills in `3 → 75 %`) and
  `charge_mode` is `1 = remaining, 2 = charging, 4 = charged, 8 = error`. Taken from the
  helper module the mouse's own device card imports, not from the percentage card.
- **Percentage family** — `battery_level` is 0…100, `charge_mode` is 0/1/2
  (idle / charging / charged), driven through a ≤10 / ≤30 / ≤50 / ≤100 table.

They are told apart by range (`level ≤ 4` ⇒ code family). Known ceiling: a genuine 0–4 %
reading on a percentage-family device will be read as 100 %.

There is no third channel to fall back on. `device/{id}/function/read_battery_status`
exists, but the engine answers `Something bad happened` for this mouse — it is a headset
endpoint. Over Bluetooth there is no battery reading at all, here or in GG.

### Polling and animation

There is no server-sent event channel: `device_event` arrives over the native CEF bridge,
which is unavailable to third-party clients. Status is therefore polled — every **3 s
while the popover is open**, every **8 s** otherwise, plus once immediately when it opens.

The panel re-anchors itself when the content changes underneath it, and the controls
**collapse** while the device is unreachable rather than being rendered greyed out: a
disabled slider invites the user to keep fiddling, a sentence tells them what to do. The
connection dot breathes while the link is live, spins while it negotiates, and stops
moving entirely when the device is gone — an animation that keeps running while nothing
is connected would be lying.

The battery badge turns red at ≤ 25 % and only while not charging. That number is *not*
GG's to copy: the client has no red state, its indicator is a sprite whose width changes
per level (0 / 6 / 10 / 14 px), so there is neither a threshold nor a colour in the
stylesheet to match. 25 % is chosen for the reason GG does encode — on the mouse's coarse
level-code scale it is the second-lowest code, the one the client labels
`iconBatteryDepleted`. The badge is also absent rather than empty on Bluetooth, since
nothing in the stack has a reading to show.

## Building

Requires Xcode 16+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
brew install xcodegen
xcodegen generate
xcodebuild -project SteelSeriesConfig.xcodeproj \
           -scheme SteelSeriesConfig \
           -configuration Release \
           build
```

The app is signed ad-hoc (`CODE_SIGN_IDENTITY: "-"`), which is enough for a local build.
Copy `SteelSeriesConfig.app` from the build products into `/Applications` to install it.

### Tests

```sh
xcodebuild -project SteelSeriesConfig.xcodeproj -scheme SteelSeriesConfig test
```

The fixtures are real data pulled from the engine for an Aerox 3 Wireless (device `203`,
configuration `ce00433a-eb6c-4cfd-8eab-417077533753`) with the lighting colour-sequence
arrays trimmed where a test does not depend on them. `BackupStoreTests` redirects the
backup root to a temporary directory, so the suite never touches real Application Support.
`DeviceLinkStateTests` pins the status protocols against payloads copied out of the GG
renderer — `rf_status` phase mapping, both `charge_status` encodings, the low-battery
rule (second-lowest level code, never while charging), the empty-`command_data` case that
also covers a healthy Bluetooth mouse, `no_live_deploy` stripping, and the CPI presets
sitting on the quantisation grid.

`EngineIntegrationTests` runs against the **live** engine on the machine. It is strictly
read-only — it never PUTs, never deploys, never writes to hardware — and every test skips
rather than fails when no engine is reachable, so the suite still runs on a machine without
GG. It covers device discovery, decoding a real configuration and round-tripping it without
losing a key, sync status, and device artwork through the self-signed TLS endpoint.

```sh
xcodebuild test -only-testing:SteelSeriesConfigTests/EngineIntegrationTests
```

## Requirements

- macOS 14.0 or later (for `@Observable`).
- SteelSeries GG installed, with its engine running. The app can launch GG for you, but
  it does not manage the engine's lifecycle.
- A SteelSeries device connected through GG.

## Limitations

- **Mouse-focused.** Aerox 3 Wireless is the only schema this app models. Other mice are
  very likely to work; keyboards and headsets are shown read-only, with their raw JSON in
  the Backups and App tabs for inspection. This is intentional — the controls are disabled
  rather than guessed.
- **Button remapping is read-only.** The button list is parsed and labelled, but the
  action-code table (`button_mappings.buttons[].function`) has not been reverse-engineered.
  Codes 1–5 are B1–B5 and 48/49/50 are the scroll wheel; what the *actions* attached to
  those buttons look like is still unknown, and guessing would silently rebind a mouse.
- **Lighting is partially editable.** Brightness, idle brightness, idle timeout, smart,
  default and reactive lighting are editable. Per-zone colour sequences are not; they are
  large step arrays whose format has not been mapped.
- **`deploy` and `liveDeploy` have not been exercised against hardware yet.** The read
  half is confirmed against the running engine — the request shape, the endpoint and the
  empty-answer cases were all probed live while writing the status code — but neither
  write path has been issued to the mouse, because the configuration on it was already
  correct throughout development. Treat the first save and the first live edit as an
  experiment; the app snapshots the engine's state automatically before either.
- **No battery on a Bluetooth mouse.** `charge_status` is only queried once `rf_status`
  answers, and a Bluetooth connection has no `rf_status` to answer. The badge is
  therefore absent rather than empty there — which is what GG does too — so the low-
  battery animation appears only over the dongle or a cable.
- **Battery percentages on the percentage family are exact only above 5 %.** See the
  `charge_status` note in *Status and live sync*: 0–4 % reads as 100 % because the code
  family's `4` means "full".
- **`syncFromDevice` is not used.** It is PrismSync-specific and errors on a plain mouse;
  `POST /device/{id}/readconfigurations` returns `{}` (no onboard profiles on this device).

## Provenance

Reverse-engineered with [REA](https://github.com/mildaniel/rea) against
`/Applications/SteelSeries GG/SteelSeries GG.app`. The Electron client was extracted from
`Resources/app.asar`; the relevant modules are `render/166.js` (CPI and polling encodings,
button HID codes) and `render/162.js` (endpoint literals and the PUT body builder).

The UI follows the menu-bar-popover pattern of
[nothing-bar](https://github.com/bestK1ngArthur/nothing-bar): a borderless non-activating
`NSPanel` with a glass backdrop, a 320 pt control column, and a separate Settings window
with a sidebar. Credit for that structure belongs to its author.

## License

MIT.
