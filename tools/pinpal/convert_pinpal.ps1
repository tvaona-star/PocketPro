<#
.SYNOPSIS
  Convert a PinPal ".pinpal" backup into the CSV that PocketPro's PinPal import reads.

.DESCRIPTION
  A .pinpal backup is NOT a CSV. It is a small XML settings plist, zero-padded to
  offset 4096, followed by an embedded SQLite database holding the real data
  (league / week / game / frame + ball / house / pattern lookups). This tool
  extracts that SQLite DB and emits one CSV row per PinPal "week" (a dated session
  in a league): date, location, league, pattern, ball, and each game's score.

  This first version is SCORE-ONLY: it imports every game's final score with full
  session/league/date/ball/center context. Frame-by-frame pinfall (for spare/leave
  history) is a separate, score-validated pass -- PinPal stores frames as a packed
  bitmask with "pins down by default" for un-played frames, so it needs care.

.PARAMETER Path     The .pinpal backup file.
.PARAMETER OutFile  Destination CSV (defaults next to the input).

.EXAMPLE
  pwsh ./convert_pinpal.ps1 -Path "C:\path\backup.pinpal"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string]$Path,
    [string]$OutFile
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $Path)) { throw "File not found: $Path" }
if (-not $OutFile) {
    $OutFile = [System.IO.Path]::ChangeExtension($Path, '.csv')
}

# --- 1. Extract the embedded SQLite database (starts at offset 4096). -------
$bytes = [System.IO.File]::ReadAllBytes($Path)
$marker = [System.Text.Encoding]::ASCII.GetBytes('SQLite format 3')
$start = -1
for ($i = 0; $i -lt [Math]::Min($bytes.Length, 65536); $i++) {
    $ok = $true
    for ($j = 0; $j -lt $marker.Length; $j++) {
        if ($bytes[$i + $j] -ne $marker[$j]) { $ok = $false; break }
    }
    if ($ok) { $start = $i; break }
}
if ($start -lt 0) { throw "No embedded SQLite database found in $Path -- is this a PinPal backup?" }
$dbPath = Join-Path $env:TEMP ("pinpal_" + [System.IO.Path]::GetFileNameWithoutExtension($Path) + ".sqlite")
[System.IO.File]::WriteAllBytes($dbPath, $bytes[$start..($bytes.Length-1)])
Write-Host "Extracted SQLite ($($bytes.Length - $start) bytes) from offset $start."

# --- 2. Locate sqlite3.exe (download the official tools if absent). ---------
function Get-Sqlite3 {
    $cmd = Get-Command sqlite3 -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $existing = Get-ChildItem "$env:TEMP\sqlite-tools" -Recurse -Filter sqlite3.exe -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($existing) { return $existing.FullName }
    Write-Host "Downloading sqlite3 tools from sqlite.org ..."
    $ua = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)'
    $page = (Invoke-WebRequest -Uri 'https://sqlite.org/download.html' -UseBasicParsing -UserAgent $ua -TimeoutSec 40).Content
    $rel = ([regex]::Match($page, '(\d{4}/sqlite-tools-win-x64-\d+\.zip)')).Groups[1].Value
    if (-not $rel) { throw "Could not find sqlite-tools download URL." }
    $zip = "$env:TEMP\sqlite-tools.zip"
    Invoke-WebRequest -Uri "https://sqlite.org/$rel" -UseBasicParsing -UserAgent $ua -OutFile $zip -TimeoutSec 120
    Expand-Archive -Path $zip -DestinationPath "$env:TEMP\sqlite-tools" -Force
    return (Get-ChildItem "$env:TEMP\sqlite-tools" -Recurse -Filter sqlite3.exe | Select-Object -First 1).FullName
}
$sqlite = Get-Sqlite3

function Query-Json {
    param([string]$Sql)
    $out = & $sqlite -json $dbPath $Sql
    if (-not $out) { return @() }
    return ($out | ConvertFrom-Json)
}

# --- Frame decode (PinPal packs standing pins: ball1 in low 10 bits, ball2 in
#     high 10 bits; bit (pin-1) set = pin standing; 0 = strike; 0x3FFFFFFF =
#     unplayed). Verified: every complete game re-scores to its stored score. ---
$SENTINEL = 1073741823
function PinCount([int64]$mask) {
    $c = 0; for ($i = 0; $i -lt 10; $i++) { if (($mask -shr $i) -band 1) { $c++ } }; return $c
}

# Minimal ten-pin scorer (mirrors tools/scoring/scoring.ps1) for self-validation.
function Score-Counts($frames) {
    $fs = @()
    for ($f = 0; $f -lt 10; $f++) {
        $b = @($frames[$f])
        $after = @(); for ($k = $f + 1; $k -lt $frames.Count; $k++) { foreach ($x in @($frames[$k])) { $after += $x } }
        if ($f -lt 9) {
            if ($b[0] -eq 10) { if ($after.Count -ge 2) { $fs += (10 + $after[0] + $after[1]) } else { return $null } }
            elseif ($b.Count -ge 2) {
                if (($b[0] + $b[1]) -eq 10) { if ($after.Count -ge 1) { $fs += (10 + $after[0]) } else { return $null } }
                else { $fs += ($b[0] + $b[1]) }
            } else { return $null }
        } else {
            $sum = 0; foreach ($x in $b) { $sum += $x }; $fs += $sum
        }
    }
    $tot = 0; foreach ($x in $fs) { $tot += $x }; return $tot
}

# Decode one game's frame rows -> @{ Str = "count:mask|..."; Counts = [[..]] } or $null.
function Decode-GameFrames($r) {
    $counts = @(); $strFrames = @()
    for ($f = 0; $f -le 8; $f++) {
        if (-not $r.ContainsKey($f)) { return $null }
        $p = $r[$f]; if ($p -eq $SENTINEL) { return $null }
        $low = $p -band 1023; $high = ($p -shr 10) -band 1023
        if ($low -eq 0) { $counts += , @(10); $strFrames += "10:0" }
        else {
            $c1 = 10 - (PinCount $low); $c2 = (PinCount $low) - (PinCount $high)
            $counts += , @($c1, $c2); $strFrames += "$($c1):$low,$($c2):$high"
        }
    }
    if (-not $r.ContainsKey(9) -or $r[9] -eq $SENTINEL) { return $null }
    $tBalls = @()
    $p9 = $r[9]; $low9 = $p9 -band 1023; $high9 = ($p9 -shr 10) -band 1023
    $c1 = 10 - (PinCount $low9); $tBalls += @{ c = $c1; m = $low9 }
    if ($low9 -ne 0) {
        $c2 = (PinCount $low9) - (PinCount $high9); $tBalls += @{ c = $c2; m = $high9 }
        if (($c1 + $c2) -eq 10 -and $r.ContainsKey(10) -and $r[10] -ne $SENTINEL) {
            $low10 = $r[10] -band 1023; $tBalls += @{ c = (10 - (PinCount $low10)); m = $low10 }
        }
    } elseif ($r.ContainsKey(10) -and $r[10] -ne $SENTINEL) {
        $low10 = $r[10] -band 1023; $high10 = ($r[10] -shr 10) -band 1023
        $tBalls += @{ c = (10 - (PinCount $low10)); m = $low10 }
        if ($low10 -eq 0) {
            if ($r.ContainsKey(11) -and $r[11] -ne $SENTINEL) {
                $low11 = $r[11] -band 1023; $tBalls += @{ c = (10 - (PinCount $low11)); m = $low11 }
            } else { $tBalls += @{ c = (10 - (PinCount $high10)); m = $high10 } }
        } else { $tBalls += @{ c = ((PinCount $low10) - (PinCount $high10)); m = $high10 } }
    }
    $tCounts = @(); $tStr = @()
    foreach ($b in $tBalls) { $tCounts += $b.c; $tStr += "$($b.c):$($b.m)" }
    $counts += , $tCounts; $strFrames += ($tStr -join ',')
    return @{ Str = ($strFrames -join '|'); Counts = $counts }
}

# --- 3. Read the data. ------------------------------------------------------
$weeks = Query-Json @'
SELECT w.pk, w.date, L.name AS league, H.name AS house, P.name AS pattern, B.name AS ball
FROM week w
LEFT JOIN league  L ON L.pk = w.leagueFk
LEFT JOIN house   H ON H.pk = w.houseFk
LEFT JOIN pattern P ON P.pk = w.patternFk
LEFT JOIN ball    B ON B.pk = w.ballFk
ORDER BY w.date;
'@

$games = Query-Json @'
SELECT g.pk, g.weekFk, g.score, B.name AS ball
FROM game g
LEFT JOIN ball B ON B.pk = g.ballFk
WHERE g.score > 0
ORDER BY g.weekFk, g.pk;
'@

# Decode each game's frames; keep only those that re-score to the stored score.
$frameRows = Query-Json "SELECT gameFk, frameNum, pins FROM frame ORDER BY gameFk, frameNum;"
$framesByGame = @{}
foreach ($fr in $frameRows) {
    $gk = [int]$fr.gameFk
    if (-not $framesByGame.ContainsKey($gk)) { $framesByGame[$gk] = @{} }
    $framesByGame[$gk][[int]$fr.frameNum] = [int64]$fr.pins
}
$frameStrings = @{}
$framesGood = 0
foreach ($g in $games) {
    $gk = [int]$g.pk
    if (-not $framesByGame.ContainsKey($gk)) { continue }
    $dec = Decode-GameFrames $framesByGame[$gk]
    if ($null -eq $dec) { continue }
    if ((Score-Counts $dec.Counts) -eq [int]$g.score) { $frameStrings[$gk] = $dec.Str; $framesGood++ }
}

# Group games by week.
$gamesByWeek = @{}
foreach ($g in $games) {
    if (-not $gamesByWeek.ContainsKey($g.weekFk)) { $gamesByWeek[$g.weekFk] = New-Object System.Collections.ArrayList }
    [void]$gamesByWeek[$g.weekFk].Add($g)
}
$maxGames = 0
foreach ($v in $gamesByWeek.Values) { if ($v.Count -gt $maxGames) { $maxGames = $v.Count } }
if ($maxGames -eq 0) { throw "No games with scores found." }

# PinPal stores dates as Unix time (seconds since 1970-01-01 UTC). Convert to the
# machine's local day, which is the day the session was actually bowled.
$unixEpoch = [datetime]::SpecifyKind([datetime]'1970-01-01', [System.DateTimeKind]::Utc)

# --- 4. Emit CSV in PocketPro's PinPal import format. -----------------------
$rows = New-Object System.Collections.ArrayList
$totalGames = 0
foreach ($w in $weeks) {
    if (-not $gamesByWeek.ContainsKey($w.pk)) { continue }
    $wkGames = $gamesByWeek[$w.pk]
    $date = $unixEpoch.AddSeconds([double]$w.date).ToLocalTime().ToString('yyyy-MM-dd')
    $ball = if ($w.ball) { $w.ball } elseif ($wkGames[0].ball) { $wkGames[0].ball } else { '' }
    $row = [ordered]@{
        date     = $date
        location = $w.house
        league   = $w.league
        pattern  = $w.pattern
        ball     = $ball
    }
    for ($i = 0; $i -lt $maxGames; $i++) {
        if ($i -lt $wkGames.Count) {
            $g = $wkGames[$i]
            $row["game$($i+1)"] = $g.score
            $gk = [int]$g.pk
            $row["game$($i+1)frames"] = if ($frameStrings.ContainsKey($gk)) { $frameStrings[$gk] } else { '' }
        } else {
            $row["game$($i+1)"] = ''
            $row["game$($i+1)frames"] = ''
        }
    }
    [void]$rows.Add([pscustomobject]$row)
    $totalGames += $wkGames.Count
}

$rows | Export-Csv -Path $OutFile -NoTypeInformation -Encoding UTF8
Write-Host ""
Write-Host ("Wrote {0} sessions ({1} games, up to {2} games/session) to:" -f $rows.Count, $totalGames, $maxGames)
Write-Host ("  Frame-by-frame pinfall reconstructed for {0} of {1} games (rest import score-only)." -f $framesGood, $totalGames)
Write-Host "  $OutFile"
Write-Host ""
Write-Host "Next: validate with  tools/pinpal/validate_export.ps1 -Path `"$OutFile`""
