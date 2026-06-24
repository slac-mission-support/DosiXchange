# DosiXchange — Deployment Instructions

Draft replacement for `Dosi Xchange Deployment Instructions.docx`. Format into
the .docx deliverable before sending. Goal: anyone on the team (Ryan, Josh, or
Daniel) can produce an **identical, working `.ipa`** that launches via JAMF Self
Service and reads the production CloudKit data.

> Why this doc was revised: a build that crashed on launch traced to **export-time
> signing settings**, not the code. The old instructions listed the steps but not
> the settings that matter. The sections marked **Critical** below are what keep
> the exported app launching and talking to the right CloudKit data.

---

## 1. Prerequisites

- **Xcode 26.x** (the project builds against the iOS 26.x SDK; deployment target is iOS 16.0).
- Membership in the SLAC Apple Developer **enterprise (in-house) program**, signing team **`KHM26R2G73`**.
- Access to the CloudKit container **`iCloud.com.SLAC.LocationApp`** (Production environment).
- The shared **OneDrive** location used to hand the export folder to the Apple administrator (Josh).

## 2. Pull the latest code

1. `git checkout master`
2. `git pull` (so the build matches what's merged).

## 3. Verify Signing & Capabilities — **Critical**

Open the project → target **LocationApp** → **Signing & Capabilities**:

- **Automatically manage signing** — ON. (Xcode mints a current managed provisioning
  profile at export; this is what avoids the stale/expired-profile crash.)
- **Team** = `KHM26R2G73`.
- **iCloud** capability present, with **CloudKit** checked and the container
  **`iCloud.com.SLAC.LocationApp`** selected.
- **Push Notifications** capability present.

If any of these are missing, the exported app loses CloudKit access or refuses to
launch on a managed device.

## 4. Bump version & build number

In **General → Identity** (or Build Settings):

- Increment **Version** (`MARKETING_VERSION`) for each release.
- Increment the **Build** number.

Notes:
- The **Main view** version label reads the version automatically — no manual edit.
- The **Tools view** date is now auto-derived from the build date (no manual edit).

## 5. Archive

1. Set the run destination to **Any iOS Device (arm64)** (not a simulator).
2. **Product → Archive.**
3. When the Organizer opens, select the new archive.

## 6. Distribute & export — **Critical**

1. **Distribute App** → **Enterprise** (in-house).
2. Signing: **Automatically manage signing** (lets Xcode mint a fresh managed profile).
3. Export to a **new folder** (e.g. on OneDrive).

The resulting **`ExportOptions.plist`** must read:

| Setting | Required value |
|---|---|
| `method` | `enterprise` |
| `signingStyle` | `automatic` |
| `iCloudContainerEnvironment` | **`Production`** |
| `teamID` | `KHM26R2G73` |

`iCloudContainerEnvironment = Production` is the setting that points the build at
the live data. If it is Development, the app installs and launches but shows empty
or wrong counts.

## 7. Verify the export before handing it off — **Critical**

Open **`DistributionSummary.plist`** (and/or the exported `.ipa`) and confirm:

- The embedded **provisioning profile is freshly minted** (expiry roughly one year out),
  not an old/expired one.
- A valid SLAC **distribution certificate** (either the team's cloud-managed
  iOS Distribution cert or a valid manual iOS Distribution cert).
- **`iCloudContainerEnvironment` = Production** and the `iCloud.com.SLAC.LocationApp`
  container + CloudKit + push entitlements are present.

**Do a fresh export for every release** so Xcode mints a current profile. This single
habit prevents the expired-profile crash that looks like a crash-on-open.

## 8. Hand off to the Apple administrator

1. Share the export **folder** (the `.ipa` plus the plists) via OneDrive with Josh.
2. Josh uploads the `.ipa` into **JAMF**; the app then appears in **Self Service**.

## 9. Confirm on a device

1. Install from **Self Service** on a managed iPad.
2. App **launches without crashing**.
3. The location/dosimeter **count matches** a known-good device (confirms it is reading
   the Production CloudKit data).

---

## Troubleshooting — known failure modes

| Symptom | Likely cause | Fix |
|---|---|---|
| Crashes immediately on launch (managed device) | Expired / stale provisioning profile baked into the export | Re-archive and re-export with automatic signing so Xcode mints a fresh profile |
| Launches but shows no/empty or wrong counts | `iCloudContainerEnvironment` was Development at export | Re-export with **Production** |
| CloudKit not working at all | iCloud container / CloudKit entitlement missing from the signing profile | Restore the iCloud capability + container in Signing & Capabilities, re-export |
| "Different person's build works, mine doesn't" | Export settings differ between machines | Compare `ExportOptions.plist` against the table in §6 — they must match exactly |

## Note on environments (for reference)

The repository entitlements may point the CloudKit container at **Development** for
day-to-day Xcode builds. Distribution exports select **Production** via the export
option above. Moving the repo's default to Production (and the matching CloudKit
**schema deploy** + production signing) is a separate, SLAC-side step — coordinate
with the Apple administrator before changing it.

## Deployment Notes
Include the $USERNAME for the managed config (apple admin JAMF deployment)

```json
<dict>
    <key>workerName</key>
    <string>$USERNAME</string>
</dict>
```
Keep in mind the username, because we standardized on Azure for the iPads the UPN will resemble their email address. So josh2@slac.stanford.edu for example. 

This config will place the username in the performedby column at each new or revised cloudkit record.


