# CloudKit `Settings` Record — Configurable Fields

The app reads a single **`Settings`** record from the CloudKit **public database**
(`_defaultZone`) to pick up a few runtime values. This lets an administrator tune
behavior — fallback scan location, the super-user access code, dosimeter number
length — from the CloudKit Dashboard **without shipping an app update**.

## How it works

- The app **only reads** the `Settings` record (`LocationsCK.updateSettings()`).
  It never writes, creates, or deletes it. Editing the record is done by hand in
  the CloudKit Dashboard.
- Every field below is **optional**. When a field is absent, the app uses a
  **built-in default**, so the app works correctly whether or not the field
  exists on the record. The app is never blocked by a missing field.
- Because the app never writes these fields, CloudKit does **not** create them
  automatically. A field appears in the Dashboard (and in a "Query Records"
  result) only after it has been **added to the record by hand**.
- Settings are re-read on every **sync** — app launch, the periodic timer, and on
  reconnect — so a Dashboard change reaches a device on its **next sync**.

## Fields

| Field name | Type | Built-in default | Purpose |
|---|---|---|---|
| `dosimeterMinimumLength` | Int (Int64) | `11` | Minimum valid dosimeter number length |
| `dosimeterMaximumLength` | Int (Int64) | `11` | Maximum valid dosimeter number length |
| `defaultLatitude` | Double | `37.41927542738301` | Fallback scan latitude when there is no GPS fix |
| `defaultLongitude` | Double | `-122.20517033784913` | Fallback scan longitude when there is no GPS fix |
| `superUserPasscode` | Int (Int64) | `4299` | Access code for the **Delete Old Cycles** super-user screen |

Notes:
- Field names are **case-sensitive** and must match exactly.
- The fallback coordinates are **two separate `Double` fields** — not a single
  CloudKit `Location` field.
- `superUserPasscode` is an integer; the app reads it as a number. The default
  `4299` is built into the app, so the access code works even if this field is
  not present. Add the field only to **change** the code.

## Adding or changing a field in the CloudKit Dashboard

1. Open **CloudKit Database → your container → environment** (the app currently
   targets **Development**).
2. **Data → Records**, set **Record Type = `Settings`**, and query. There should
   be one `Settings` record.
3. Open the record, **add the field** with the exact name and type from the table
   above, set its value, and **Save**.
4. In **Development**, saving the record with a new field auto-evolves the schema.
   For **Production**, the schema change must be **deployed** (Deploy Schema
   Changes) before production builds can read it.

After saving, devices pick up the new value on their next sync.
