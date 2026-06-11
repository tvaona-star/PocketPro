# Pocket Pro — Real PinPal export validator.
# The in-app parser (PinPalImport.swift) was written against an ASSUMED format
# (docs/PINPAL_FORMAT.md) because PinPal's real schema was a PRD open question.
# Run this against a real export to see exactly what maps, what doesn't, and what
# the import would produce — BEFORE touching the app.
#
# Usage: powershell -File validate_export.ps1 -Path "C:\path\to\export.csv"
param(
    [Parameter(Mandatory = $true)]
    [string]$Path
)
Set-StrictMode -Version 2.0
. (Join-Path $PSScriptRoot '..\scoring\scoring.ps1')

if (-not (Test-Path $Path)) {
    Write-Host "File not found: $Path" -ForegroundColor Red
    exit 1
}

# ---- CSV tokenizer (RFC-4180-ish, mirrors PinPalImport.tokenize) ----
function Get-CsvRows([string]$text) {
    $rows = New-Object System.Collections.Generic.List[object]
    $row = New-Object System.Collections.Generic.List[string]
    $field = New-Object System.Text.StringBuilder
    $inQuotes = $false
    $i = 0
    while ($i -lt $text.Length) {
        $c = $text[$i]
        if ($inQuotes) {
            if ($c -eq '"') {
                if ($i + 1 -lt $text.Length -and $text[$i + 1] -eq '"') { [void]$field.Append('"'); $i++ }
                else { $inQuotes = $false }
            }
            else { [void]$field.Append($c) }
        }
        else {
            switch ($c) {
                '"' { $inQuotes = $true }
                ',' { $row.Add($field.ToString()); [void]$field.Clear() }
                "`r" { }
                "`n" { $row.Add($field.ToString()); [void]$field.Clear(); $rows.Add($row.ToArray()); $row.Clear() }
                default { [void]$field.Append($c) }
            }
        }
        $i++
    }
    if ($field.Length -gt 0 -or $row.Count -gt 0) {
        $row.Add($field.ToString())
        $rows.Add($row.ToArray())
    }
    return ,$rows
}

function Get-NormalizedHeader([string]$raw) {
    return (($raw.ToLower() -replace '[^a-z0-9]', ''))
}

function Get-ParsedDate([string]$raw) {
    $formats = @('yyyy-MM-dd', 'M/d/yyyy', 'M/d/yy', 'MM/dd/yyyy', 'd/M/yyyy', 'yyyy/M/d', 'MMM d, yyyy', 'd MMM yyyy')
    foreach ($fmt in $formats) {
        try {
            return [datetime]::ParseExact($raw, $fmt, [System.Globalization.CultureInfo]::InvariantCulture)
        } catch {}
    }
    try { return [datetime]::Parse($raw, [System.Globalization.CultureInfo]::InvariantCulture) } catch {}
    return $null
}

# Frame string per docs/PINPAL_FORMAT.md: frames split by '|', balls by ','.
function Get-ParsedFrames([string]$raw) {
    $parts = $raw -split '\|'
    if ($parts.Count -ne 10) { return $null }
    $frames = @()
    foreach ($p in $parts) {
        $balls = @()
        foreach ($b in ($p -split ',')) {
            $trimmed = $b.Trim()
            $n = 0
            if (-not [int]::TryParse($trimmed, [ref]$n)) { return $null }
            if ($n -lt 0 -or $n -gt 10) { return $null }
            $balls += $n
        }
        if ($balls.Count -eq 0) { return $null }
        $frames += ,$balls
    }
    return ,$frames
}

# ---- Load & analyze ----
$text = [System.IO.File]::ReadAllText($Path)
$rows = Get-CsvRows $text
Write-Host "File: $Path"
Write-Host "Rows: $($rows.Count) (including header)"
if ($rows.Count -lt 2) {
    Write-Host 'Not enough rows to analyze.' -ForegroundColor Red
    exit 1
}

$header = @($rows[0])
Write-Host ''
Write-Host '=== RAW HEADER ==='
for ($i = 0; $i -lt $header.Count; $i++) {
    Write-Host ("  [{0}] '{1}'  (normalized: {2})" -f $i, $header[$i], (Get-NormalizedHeader $header[$i]))
}

# Header mapping exactly as PinPalImport.swift attempts it.
$normalized = @($header | ForEach-Object { Get-NormalizedHeader $_ })
function Find-Column([string[]]$candidates) {
    foreach ($c in $candidates) {
        $idx = [Array]::IndexOf($normalized, $c)
        if ($idx -ge 0) { return $idx }
    }
    return -1
}

$map = [ordered]@{
    'Date (REQUIRED)' = Find-Column @('date')
    'Location'        = Find-Column @('location', 'center', 'centerlocation', 'bowlingcenter')
    'League'          = Find-Column @('league', 'leaguename')
    'Pattern'         = Find-Column @('pattern', 'oilpattern')
    'Ball'            = Find-Column @('ball', 'ballname')
    'Notes'           = Find-Column @('notes', 'note')
}
$gameCols = @()
for ($n = 1; $n -le 12; $n++) {
    $scoreIdx = Find-Column @("game$n", "g$n", "game${n}score")
    $framesIdx = Find-Column @("game${n}frames", "g${n}frames")
    if ($scoreIdx -ge 0) { $gameCols += ,@{ N = $n; Score = $scoreIdx; Frames = $framesIdx } }
}

Write-Host ''
Write-Host '=== PARSER MAPPING (as PinPalImport.swift would see it) ==='
foreach ($key in $map.Keys) {
    $idx = $map[$key]
    $status = if ($idx -ge 0) { "column $idx ('$($header[$idx])')" } else { 'NOT FOUND' }
    $color = if ($idx -ge 0) { 'Green' } elseif ($key -like '*REQUIRED*') { 'Red' } else { 'Yellow' }
    Write-Host ("  {0,-18} {1}" -f $key, $status) -ForegroundColor $color
}
Write-Host ("  {0,-18} {1}" -f 'Game columns', "$($gameCols.Count) found") -ForegroundColor $(if ($gameCols.Count -gt 0) { 'Green' } else { 'Red' })

$unmappedCols = @()
$mappedIdx = @($map.Values | Where-Object { $_ -ge 0 }) + @($gameCols | ForEach-Object { @($_.Score, $_.Frames) }) | Where-Object { $_ -ge 0 }
for ($i = 0; $i -lt $header.Count; $i++) {
    if ($mappedIdx -notcontains $i -and $header[$i].Trim() -ne '') { $unmappedCols += "[$i] $($header[$i])" }
}
if ($unmappedCols.Count -gt 0) {
    Write-Host ''
    Write-Host '=== UNMAPPED COLUMNS (data the parser would currently ignore) ===' -ForegroundColor Yellow
    $unmappedCols | ForEach-Object { Write-Host "  $_" -ForegroundColor Yellow }
}

# ---- Row-by-row dry run ----
$ok = 0; $badDate = 0; $noGames = 0; $frameOK = 0; $frameMismatch = 0; $frameUnreadable = 0; $scoreOnly = 0
$dates = @(); $balls = @{}; $patterns = @{}; $locations = @{}
$sampleIssues = @()

for ($r = 1; $r -lt $rows.Count; $r++) {
    $row = @($rows[$r])
    $allEmpty = $true
    foreach ($cell in $row) { if ($cell.Trim() -ne '') { $allEmpty = $false; break } }
    if ($allEmpty) { continue }

    function Get-Field([int]$idx) {
        if ($idx -lt 0 -or $idx -ge $row.Count) { return $null }
        $v = $row[$idx].Trim()
        if ($v -eq '') { return $null }
        return $v
    }

    $dateRaw = Get-Field $map['Date (REQUIRED)']
    $date = if ($null -ne $dateRaw) { Get-ParsedDate $dateRaw } else { $null }
    if ($null -eq $date) {
        $badDate++
        if ($sampleIssues.Count -lt 8) { $sampleIssues += "Row $($r + 1): unparseable date '$dateRaw'" }
        continue
    }
    $dates += $date

    $gamesInRow = 0
    foreach ($gc in $gameCols) {
        $scoreRaw = Get-Field $gc.Score
        if ($null -eq $scoreRaw) { continue }
        $score = 0
        if (-not [int]::TryParse($scoreRaw, [ref]$score)) {
            if ($sampleIssues.Count -lt 8) { $sampleIssues += "Row $($r + 1): non-numeric score '$scoreRaw'" }
            continue
        }
        $gamesInRow++
        $framesRaw = if ($gc.Frames -ge 0) { Get-Field $gc.Frames } else { $null }
        if ($null -ne $framesRaw) {
            $frames = Get-ParsedFrames $framesRaw
            if ($null -eq $frames) {
                $frameUnreadable++
                if ($sampleIssues.Count -lt 8) { $sampleIssues += "Row $($r + 1) G$($gc.N): unreadable frame string '$($framesRaw.Substring(0, [Math]::Min(50, $framesRaw.Length)))...'" }
            }
            else {
                $computed = (Score-Game $frames).Final
                if ($computed -eq $score) { $frameOK++ }
                else {
                    $frameMismatch++
                    if ($sampleIssues.Count -lt 8) { $sampleIssues += "Row $($r + 1) G$($gc.N): frames score to $computed but export says $score" }
                }
            }
        }
        else { $scoreOnly++ }
    }
    if ($gamesInRow -eq 0) { $noGames++; if ($sampleIssues.Count -lt 8) { $sampleIssues += "Row $($r + 1): no game scores" } }
    else { $ok++ }

    $b = Get-Field $map['Ball'];     if ($null -ne $b) { $balls[$b] = $true }
    $p = Get-Field $map['Pattern'];  if ($null -ne $p) { $patterns[$p] = $true }
    $l = Get-Field $map['Location']; if ($null -ne $l) { $locations[$l] = $true }
}

Write-Host ''
Write-Host '=== DRY-RUN RESULT (what the in-app import would produce) ==='
Write-Host "  Sessions importable:        $ok"
Write-Host "  Rows skipped (bad date):    $badDate" -ForegroundColor $(if ($badDate -gt 0) { 'Yellow' } else { 'Green' })
Write-Host "  Rows skipped (no games):    $noGames" -ForegroundColor $(if ($noGames -gt 0) { 'Yellow' } else { 'Green' })
Write-Host "  Games with valid frames:    $frameOK"
Write-Host "  Games score-only:           $scoreOnly"
Write-Host "  Frame/score mismatches:     $frameMismatch" -ForegroundColor $(if ($frameMismatch -gt 0) { 'Yellow' } else { 'Green' })
Write-Host "  Unreadable frame strings:   $frameUnreadable" -ForegroundColor $(if ($frameUnreadable -gt 0) { 'Yellow' } else { 'Green' })
if ($dates.Count -gt 0) {
    $sorted = $dates | Sort-Object
    Write-Host "  Date range:                 $($sorted[0].ToString('yyyy-MM-dd')) -> $($sorted[-1].ToString('yyyy-MM-dd'))"
}
Write-Host "  Distinct balls:             $($balls.Keys.Count)  ($(@($balls.Keys | Select-Object -First 6) -join ', '))"
Write-Host "  Distinct patterns:          $($patterns.Keys.Count)  ($(@($patterns.Keys | Select-Object -First 6) -join ', '))"
Write-Host "  Distinct locations:         $($locations.Keys.Count)"

if ($sampleIssues.Count -gt 0) {
    Write-Host ''
    Write-Host '=== SAMPLE ISSUES ===' -ForegroundColor Yellow
    $sampleIssues | ForEach-Object { Write-Host "  $_" -ForegroundColor Yellow }
}

Write-Host ''
if ($map['Date (REQUIRED)'] -lt 0 -or $gameCols.Count -eq 0 -or ($frameUnreadable -gt 0) -or ($badDate -gt ($rows.Count / 4))) {
    Write-Host 'VERDICT: format differs from the assumed mapping — PinPalImport.swift header/frame parsing needs adapting to this file. Share this output.' -ForegroundColor Yellow
    exit 2
}
Write-Host 'VERDICT: this export is compatible with the in-app importer as written.' -ForegroundColor Green
exit 0
