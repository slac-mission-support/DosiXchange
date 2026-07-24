# LocationApp Version Notes

## 3.1 (July 2026)

- Uploads refused by the server are kept and retried instead of being dropped (#73)
- Recovery pass restores previously stranded collections with their original worker names and dates (#73)
- Daily reconcile against the server catches records missed by incremental sync (#73)
- Reconcile also removes records deleted from the server from the local cache (#74)
- Warning at launch when no iCloud account is signed in (#73)
- Expanded automated test suite covering sync, recovery, and reconcile (#73)

## 3.0 (June 2026)

- Rebuilt Reset Cache with a confirmation prompt, safe full re-download, and upload guards against data loss (#58)
- Fixed collections made from the Edit Record popup being silently dropped (#58)
- Removed the unused Coordinates screen (#59)
- Fixed a crash when scanning while offline (#60)
- Added the Delete Old Cycles tool for purging prior-cycle records (#61)
- Replaced the hidden tap-to-refresh with a visible Refresh Count button (#62)
- Fixed the doubled "sent" sound after emailing a report (#62)
- Fixed a crash when exporting records with no creation date (#63)
- Added a passcode gate on Reset Cache, Delete Old Cycles, and Edit Record save (#64)
- Relabeled Mismatch to RGD in the UI and CSV exports (#65)
- Rebuilt pop-up alerts to display correctly across iOS versions and iPad (#66, #67)
- Fixed the Records header spinner animating constantly (#68)
- Worker name now fills in automatically from the Jamf managed-app configuration (#70)
- Map and Nearest Locations views can refresh to show changes from other devices (#71)
- System date columns no longer export blank for device-created records (#72)
- Restored the "sent" sound on iOS 26 mail sheets (#72)
