# PinPal CSV Import Format

The PRD (§13, §15) lists PinPal's exported *fields* but no column specification, and
flags export-format feasibility as an open question. The parser
(`PocketProCore/Sources/PocketProCore/PinPalImport.swift`) therefore accepts the
following documented format with tolerant header matching. If a real PinPal export
differs, only the header-candidate lists in `PinPalImport.parse` change.

## Columns

| Column | Required | Accepted headers (case/space-insensitive) | Notes |
|---|---|---|---|
| Date | yes | `Date` | `yyyy-MM-dd`, `M/d/yyyy`, `M/d/yy`, `MM/dd/yyyy` |
| Location | no | `Location`, `Center`, `Bowling Center` | creates/reuses Location records |
| League | no | `League`, `League Name` | |
| Pattern | no | `Pattern`, `Oil Pattern` | free text → House Shot, flagged for review |
| Ball | no | `Ball`, `Ball Name` | name-matched to arsenal, else shell record |
| Notes | no | `Notes`, `Note` | |
| Game1…Game6 | ≥1 | `Game1`/`G1`/`Game1Score` … | integer final score 0–300 |
| Game1Frames…Game6Frames | no | `Game1Frames`/`G1Frames` … | see frame string below |

## Frame string

Ten frames separated by `|`; balls within a frame separated by `,` — pinfall counts:

```
10|9,1|7,2|10|0,8|8,2|0,6|10|10|10,8,2
```

- Frames 1–9: `10` for a strike, otherwise two counts.
- Frame 10: two counts (open) or three (after a strike or spare).
- Frame data must reproduce the exported game score; otherwise the score is kept
  and the frame data is dropped with a row issue (integrity rule, PRD 13.4).
- PinPal exports pin *counts*, not pin identity — imported games are excluded from
  leave-type breakdowns but included in averages, strike %, and spare conversion.

## Sample file

```csv
Date,Center,League,Oil Pattern,Ball,Notes,Game1,Game1Frames,Game2,Game2Frames
2024-09-12,Maple Lanes,Tuesday Classic,House,Phaze II,"Felt strong",168,"10|7,3|9,0|10|0,8|8,2|0,6|10|10|10,8,2",190,"9,1|9,1|9,1|9,1|9,1|9,1|9,1|9,1|9,1|9,1,9"
9/19/2024,Maple Lanes,Tuesday Classic,House,Phaze II,,215,,180,
```

## Integrity rules implemented (PRD 13.4)

- **Re-import safety**: each row carries an FNV-1a content hash stored on the
  imported Session; rows whose hash already exists are skipped.
- **Duplicate detection**: same calendar day + location + score set as an existing
  session → imported anyway, flagged `Possible duplicate` for the bowler to resolve.
- **Ball matching**: case-insensitive exact match against arsenal model/display
  names links to the existing ball instead of creating a shell record.
- **Score-only games**: imported with `hasFrameData = false`, excluded from
  frame-derived stats, included in average and score history.
