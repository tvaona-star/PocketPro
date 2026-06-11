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
        $row["game$($i+1)"] = if ($i -lt $wkGames.Count) { $wkGames[$i].score } else { '' }
    }
    [void]$rows.Add([pscustomobject]$row)
    $totalGames += $wkGames.Count
}

$rows | Export-Csv -Path $OutFile -NoTypeInformation -Encoding UTF8
Write-Host ""
Write-Host ("Wrote {0} sessions ({1} games, up to {2} games/session) to:" -f $rows.Count, $totalGames, $maxGames)
Write-Host "  $OutFile"
Write-Host ""
Write-Host "Next: validate with  tools/pinpal/validate_export.ps1 -Path `"$OutFile`""
