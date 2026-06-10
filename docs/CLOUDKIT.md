# Enabling iCloud Sync (CloudKit)

The app ships with CloudKit dark so the first build needs zero signing setup
(DECISIONS.md D4). The data layer is already CloudKit-compatible — every model has
property defaults, optional relationships, and no unique constraints. Enabling sync
is configuration only:

1. In Xcode, select the **PocketPro** target → **Signing & Capabilities**.
2. Set your **Team** (requires a paid Apple Developer account for CloudKit).
3. Click **+ Capability** → **iCloud** → check **CloudKit**.
4. Add a container, e.g. `iCloud.com.pocketpro.app` (match your bundle ID).
5. Build and run. `PersistenceController.makeContainer()` tries
   `ModelConfiguration(cloudKitDatabase: .automatic)` first — with the entitlement
   present it now succeeds, and SwiftData syncs through your private database.

No code changes are required. Without the entitlement the container creation throws
and the app silently falls back to the local-only store.

## Sync conflict note (PRD §15 open question)

SwiftData + CloudKit uses CloudKit's built-in last-writer-wins at the field level
on reconnect. If true field-level merge policies become a requirement, the
migration path is `NSPersistentCloudKitContainer` with custom merge policies —
the model layer needs no changes for that move.
