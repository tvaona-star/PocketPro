# Pocket Pro — Build Decisions Log

Decisions made while implementing PRD v4.5 (June 2026). Each entry notes the PRD reference,
the decision, and why. These are the answers to the clarifying questions I would otherwise
have asked — flagged here so they're easy to reverse.

## Platform & architecture

**D1. Minimum deployment target: iOS 17 (PRD 8.1 says iOS 16).**
The PRD asks for iCloud sync, local-first offline, and an Android-portable data layer.
SwiftData (iOS 17+) delivers CloudKit sync nearly for free and keeps persistence code thin —
Core Data + `NSPersistentCloudKitContainer` on iOS 16 would roughly double the data-layer
code for a target that is four major versions old by the PRD's own date (June 2026).
If iOS 16 support is a hard requirement, the model layer is isolated enough to port to Core Data.

**D2. Two-layer architecture: `PocketProCore` Swift package + app target.**
PRD 8.2 wants Android (Kotlin) to be "a port, not a rewrite." All bowling domain logic —
scoring, leave classification, stats, notation, PinPal CSV parsing — lives in `PocketProCore`
with zero UIKit/SwiftUI/SwiftData imports. The package is the Kotlin porting spec; the app
target contains only UI and persistence bindings.

**D3. Leave classifier is a build-time generated lookup table (PRD 5.5.3 requirement).**
`tools/classifier/` contains the rules engine (PowerShell, runnable on any machine including
this Windows box), the boundary-case test suite from PRD 5.5.2, and a generator that emits
`LeaveTable.swift` (all 1,023 combinations pre-resolved) plus JSON fixtures consumed by the
Swift XCTests. The Swift side does **no rule evaluation at runtime** — exactly as specified.
Regenerate with `tools/classifier/generate.ps1` after any rule change; tests run automatically.

**D4. CloudKit ships dark by default.**
Enabling CloudKit requires a paid developer team + container ID, which would break first
build for anyone cloning the project. The `ModelContainer` tries CloudKit when the
entitlements file is present and falls back to local-only otherwise. `docs/CLOUDKIT.md`
has the two-minute enable path. Models follow all CloudKit constraints (defaults on every
property, optional relationships, no unique constraints) so flipping it on is config-only.

## Scope

**D5. Pulled three v1.5 items into v1.0: arsenal chart, ball comparison, pin-leave heatmap.**
All three are fully specified in the PRD (5.4.9, 5.4.10, 5.5.4), high-value, and cheap once
the data model exists. Hook/Length user ratings (1–10) ship with the chart since the chart
spec references them. Practice bags also included (the bag model needs the type enum anyway).

**D6. Deferred, with scaffolding:**
- *Ball DB scraper pipeline (PRD 9)* — server-side system, separate deliverable. The app ships
  with a seed database (`balldb.json`, ~50 balls, 11 brands) behind a `BallDatabase` service
  whose loader already handles versioned replacement files (the OTA update contract).
  Seed specs are dev data: real models with representative numbers, `db_status: "seed"`,
  to be replaced by the verified pipeline output before launch.
- *Monetization (PRD 14)* — `FeatureGate` stub, everything unlocked. Wiring StoreKit before
  a product ID exists is dead code; the free/paid boundary from the PRD is encoded in the gate.
- *3D layout visualization, PDF export* — v1.5/v2 per PRD phasing; not scaffolded.
- *Score entry: pin-by-pin default with direct-score toggle* — both implemented (PRD 5.1).

**D7. PinPal CSV format is an assumption.**
PRD 13.1 lists exported fields but no column spec (and flags format feasibility as an open
question). The parser accepts a documented format (`docs/PINPAL_FORMAT.md`) with tolerant
header matching, and the whole import path is fixture-tested. If real PinPal exports differ,
only `PinPalImport.swift` field mapping changes.

## Domain rulings (PRD internal conflicts)

**D8. Split detection follows USBC Rule 2 semantics, validated against the PRD decision log.**
The PRD's prose rule ("any gap between them") contradicts two of its own examples. Implemented:
head pin down AND (a) a downed pin lies spatially between two standing pins (row-band rule), or
(b) a downed pin sits immediately ahead of a side-by-side standing pair (makes 4-5, 5-6, 7-8,
8-9, 9-10, 2-3 splits — matching USBC and the PRD decision log's 4-5/5-6 rulings).
Divergences from PRD *examples* (the 5.5.2 decision log is declared authoritative and is
matched 100%):
- `4-7` listed as a Split example in 5.5.1 — classified **Other** (pins are physically adjacent;
  no gap by USBC or by the PRD's own "any gap" rule; not in the decision log).
- `6-7-10` listed under plain Split — classified **Big Split + Split** (the 7 has no adjacent
  path to the 6-10; this matches the PRD's own Big Split rule "no adjacent path between
  outermost remaining pins").

**D9. `1-5` is a Sleeper, not a Washout.**
Washout rule says "head pin standing overrides all," but the decision log and sleeper examples
both classify 1-5 as Sleeper. Decision log wins (it's declared authoritative). Encoded as the
single exception to the washout rule.

**D10. Baby splits and big splits also carry the `split` tag.**
The data-model enum in PRD §6 omits a plain `split` category, but Split % (5.3) is defined as
"splits left / total first balls," the Spares filter chips include "Splits," and bowling
convention counts baby/big splits as splits. Added `split` to the category enum; Split % counts
any split-tagged leave. The Stats spare-breakdown panel gains a "Splits" row (plain splits would
otherwise vanish into Other — clearly unintended).

**D11. "First balls" = fresh-rack deliveries.**
Strike %, Split %, and first-ball average use deliveries at a full rack: ball 1 of frames 1–9
and 10th-frame deliveries that follow a strike/spare re-rack. This matches PBA convention and
makes 10th-frame strikes count properly.

**D12. Frames support count-only data (PinPal import).**
PinPal exports pin *counts*, not pin identity, so imported frames can't be leave-classified.
`Frame` stores optional pin-identity arrays plus authoritative counts; count-only frames are
included in scoring/average/strike stats and excluded from leave-type breakdowns (PRD 13.4
already requires this split for final-score-only games).

**D13. Season definition is user-configurable (PRD 15 open question).**
Settings → Season: USBC season (Aug 1 – Jul 31, default) or rolling 12 months. "This Season"
date filter honors it.

**D14. Stats threshold (PRD 7.4): tiles show "--" below 5 games**, with the "Bowl more
sessions" note. The trend strip needs 2+ sessions; it shows what exists once past threshold.

**D15. Accent color: electric blue (#3B82F6).** PRD 7.1 leaves it "deep navy or electric blue
TBD." Electric blue reads better against #0F1117 at WCAG-acceptable contrast for text-on-accent.
One token (`Theme.accent`) to change.

**D16. SpareLeave is derived, not stored.**
PRD §6 lists a SpareLeave entity, but every field except the manual category override is
fully derivable from Frame pin data, and classification is a table lookup (cheap). Storing it
would duplicate state across CloudKit sync. The override lives on `Frame.leaveOverrideRaw`;
`Game.derivedLeaves()` (FrameLogic.swift) materializes `LeaveRecord` values on demand,
including the 10th-frame multi-rack walk. Imported PinPal data goes through the same path —
the PRD's "re-process imported frames through the classifier" happens implicitly and stays
consistent forever.

## Verification strategy on this machine

iOS apps can't compile on Windows. What's machine-verified here, today:
1. Classifier rules engine: full 1,023-combination generation, boundary-case suite (5.5.2),
   category-count invariants — PowerShell, run green before `LeaveTable.swift` is emitted.
2. Scoring + stats engine: reference implementation with known-game vectors (300 game,
   all-spares 190, PRD example summaries) — PowerShell, exported as JSON fixtures.
3. Swift sources: structural lint (brace/paren/bracket balance, string-literal sanity).

The same vectors ship as XCTests in `PocketProCore/Tests`, so `swift test` (or Cmd+U) on a
Mac re-verifies everything natively. First Mac build checklist is in README.md.
