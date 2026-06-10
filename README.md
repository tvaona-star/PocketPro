# Pocket Pro

The competitive bowler's game intelligence platform — frame-by-frame scoring,
PBA-broadcast-style stats, and the most complete ball/layout management system in
any bowling app. Built from **PRD v4.5** (`docs/PocketPro_PRD_v4_5.docx`).

iOS 17+, SwiftUI + SwiftData, dark-mode-first. Implementation decisions and PRD
deviations are logged in [DECISIONS.md](DECISIONS.md).

## Repository layout

```
PocketPro.xcodeproj/      Xcode project (synchronized folders — no file-list upkeep)
PocketPro/                iOS app target (SwiftUI views, SwiftData models, services)
│   ├── Models/           @Model classes (PRD §6), frame→leave derivation
│   ├── Services/         persistence, ball DB, arsenal actions, PinPal import
│   ├── Views/            Bowl · Sessions · Stats · Arsenal · Spares · Settings
│   └── Resources/        balldb.json (seed), asset catalog
PocketProCore/            Pure Swift package — all bowling domain logic, zero UI imports.
│                         This is the Android porting spec (PRD 8.2).
│   ├── ScoringEngine     ten-pin scoring, fresh-rack deliveries, streaks
│   ├── LeaveClassifier   lookup-table classifier + generated LeaveTable.swift
│   ├── StatsEngine       dashboard stats, spare aggregations, trends
│   ├── Notation          bowling notation (50° x 4 3/4" x 40°)
│   ├── PinPalImport      CSV parser + integrity hashing
│   └── Tests/            XCTest suites mirroring the Windows-verified vectors
tools/                    Windows-runnable reference implementations + generators
│   ├── classifier/       rules engine, test suite, LeaveTable.swift generator
│   ├── scoring/          scoring/stats executable spec (test vectors V1–V10)
│   └── lint/             structural Swift lint
docs/                     PRD, leave audit table, CloudKit + PinPal format guides
```

## Building (macOS)

1. Open `PocketPro.xcodeproj` in Xcode 16+.
2. Select the **PocketPro** scheme and an iOS 17+ simulator.
3. **⌘R**. No signing team or network needed — iCloud sync is off by default
   (enable per [docs/CLOUDKIT.md](docs/CLOUDKIT.md)).

## Testing

**On a Mac** — the full native suite (classifier table invariants, scoring vectors,
stats math, notation, CSV import):

```bash
cd PocketProCore && swift test        # or ⌘U on the PocketPro scheme
```

**On any machine (including Windows)** — the reference implementations that
generated and validated the shipped lookup table:

```powershell
powershell -File tools/classifier/tests.ps1       # 1,334 assertions: PRD 5.5.2 decision log + invariants
powershell -File tools/scoring/scoring_tests.ps1  # scoring/stat vectors (300 game, 10th-frame cases, ...)
powershell -File tools/lint/swift_lint.ps1        # structural lint over all Swift sources
```

`tools/classifier/generate.ps1` re-emits `LeaveTable.swift` + `docs/leave_audit.csv`
after any taxonomy change — it refuses to generate unless the test suite is green.

## Status vs PRD phasing

**v1.0 scope: complete**, plus three v1.5 items pulled forward (arsenal chart,
ball comparison, pin-leave heatmap — DECISIONS.md D5).

Deliberately deferred with scaffolding in place: server scraper pipeline (seed
ball DB ships in-app; loader already handles versioned OTA replacement), StoreKit
(FeatureGate stub), 3D layout visualization and PDF export (v1.5+ per PRD).

Before shipping: replace `balldb.json` seed specs with verified pipeline output,
add a real app icon, set a bundle ID/team, and validate the leave audit table
(`docs/leave_audit.csv`) against real-world leave data (PRD §15).
