<#
.SYNOPSIS
  Build PocketPro's balldb.json from the public bowwwl.com bowling ball database.

.DESCRIPTION
  Crawls the server-rendered bowwwl.com ball database (robots.txt allows
  /bowling-ball-database) and parses each ball's Drupal field markup into the
  BallDBRecord schema that PocketProCore decodes. Politely throttled and cached,
  so re-runs are cheap and don't re-hit the server.

  balldb.json is a RUNTIME resource -- a malformed file or an out-of-enum
  coverstock_type makes the in-app database silently empty (Codable throws and
  the loader swallows it). So every record is validated before the file is
  written; the script refuses to emit an invalid database.

.PARAMETER OutFile
  Destination JSON. Defaults to the app's bundled resource.

.PARAMETER Limit
  Stop after N balls (0 = all). Use a small number to validate parsing first.

.PARAMETER ThrottleSec
  Delay between network requests (politeness). Cached pages are free.

.EXAMPLE
  pwsh ./fetch_bowwwl.ps1 -Limit 5          # validate parsing on 5 balls
  pwsh ./fetch_bowwwl.ps1                    # full crawl -> balldb.json
#>
[CmdletBinding()]
param(
    [string]$OutFile   = "$PSScriptRoot/../../PocketPro/Resources/balldb.json",
    [int]   $Limit     = 0,
    [double]$ThrottleSec = 0.4,
    [int]   $MaxPages  = 80,
    [string]$CacheDir  = "$PSScriptRoot/.cache",
    [switch]$NoCache,
    [switch]$Preview,    # write to balldb.generated.json next to the script instead of OutFile
    [string]$TestUrl = ''  # parse a single /bowling-ball-database/<brand>/<ball> path and stop
)

$ErrorActionPreference = 'Stop'
$Base = 'https://www.bowwwl.com'
$UA   = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36'
$ValidCovers = @('solid','pearl','hybrid','urethane','polyester')

if (-not (Test-Path $CacheDir)) { New-Item -ItemType Directory -Path $CacheDir -Force | Out-Null }

function Get-Html {
    param([string]$Url)
    $hash = [System.BitConverter]::ToString(
        [System.Security.Cryptography.MD5]::Create().ComputeHash(
            [System.Text.Encoding]::UTF8.GetBytes($Url))).Replace('-','')
    $cacheFile = Join-Path $CacheDir "$hash.html"
    if (-not $NoCache -and (Test-Path $cacheFile)) {
        return Get-Content -Path $cacheFile -Raw -Encoding UTF8
    }
    $resp = Invoke-WebRequest -Uri $Url -UseBasicParsing -UserAgent $UA -TimeoutSec 40
    $content = $resp.Content
    Set-Content -Path $cacheFile -Value $content -Encoding UTF8
    Start-Sleep -Seconds $ThrottleSec
    return $content
}

# --- Enumerate every ball detail URL by paging the listing until a page is empty.
function Get-BallUrls {
    $all = [System.Collections.Generic.HashSet[string]]::new()
    for ($page = 0; $page -lt $MaxPages; $page++) {
        $html = Get-Html "$Base/bowling-ball-database?page=$page"
        $matches = [regex]::Matches($html, '/bowling-ball-database/[a-z0-9\-]+/[a-z0-9\-]+')
        $before = $all.Count
        foreach ($m in $matches) { [void]$all.Add($m.Value) }
        $added = $all.Count - $before
        Write-Host ("  page {0,2}: +{1} (total {2})" -f $page, $added, $all.Count)
        if ($added -eq 0) { break }
    }
    return @($all)
}

function Strip-Html {
    param([string]$s)
    if ($null -eq $s) { return '' }
    return (($s -replace '(?is)<[^>]+>', ' ') -replace '\s+', ' ').Trim()
}

# First field__item text inside the named Drupal field div.
function Get-FieldItem {
    param([string]$Html, [string]$Name)
    # Require the field name to end at a space or quote so 'core' doesn't match
    # 'core-type', 'coverstock' doesn't match 'coverstock-type', etc.
    $m = [regex]::Match($Html,
        "(?is)field--name-field-$Name(?=[\s`"]).*?<div class=`"field__item[^`"]*`">(.*?)</div>")
    if ($m.Success) { return Strip-Html $m.Groups[1].Value }
    return ''
}

# Label-hidden entity fields (core, coverstock) render the name as the first
# card link inside the field: ...field__item ...><article|div>...<a>NAME</a>.
function Get-LabelHiddenItem {
    param([string]$Html, [string]$Name)
    $m = [regex]::Match($Html,
        "(?is)field--name-field-$Name(?=[\s`"])[^>]*field__item[^`"]*`">.{0,500}?<a\b[^>]*>(.*?)</a>")
    if ($m.Success) { return Strip-Html $m.Groups[1].Value }
    return ''
}

# Inline fields render as "Label value"; grab the value after the known label.
function Get-InlineValue {
    param([string]$Html, [string]$Name, [string]$Label)
    $i = $Html.IndexOf("field--name-field-$Name")
    if ($i -lt 0) { return '' }
    $chunk = $Html.Substring($i, [Math]::Min(400, $Html.Length - $i))
    $txt = Strip-Html $chunk
    if ($txt -match [regex]::Escape($Label) + '\s*(.+)') {
        # take up to the next field's label noise -- first ~40 chars is plenty
        return ($matches[1]).Trim()
    }
    return $txt
}

function ConvertTo-CoverEnum {
    param([string]$s)
    $t = $s.ToLowerInvariant()
    if ($t -match 'pearl')               { return 'pearl' }
    if ($t -match 'hybrid')              { return 'hybrid' }
    if ($t -match 'solid')               { return 'solid' }
    if ($t -match 'urethane')            { return 'urethane' }
    if ($t -match 'polyester|plastic')   { return 'polyester' }
    return 'solid'   # safe enum fallback -- never emit an out-of-enum value
}

function Parse-Ball {
    param([string]$Html, [string]$Url)

    $slug = $Url -replace '^.*/bowling-ball-database/', ''
    $parts = $slug -split '/'
    $brandSlug = $parts[0]
    $ballSlug  = $parts[1]
    $id = "$brandSlug-$ballSlug"

    # Brand display name from the breadcrumb JSON-LD (position 3), else title-case the slug.
    $brand = ''
    $bc = [regex]::Match($Html, '"position":\s*3,\s*"name":\s*"([^"]+)"')
    if ($bc.Success) { $brand = $bc.Groups[1].Value }
    if ([string]::IsNullOrWhiteSpace($brand)) {
        $brand = (Get-Culture).TextInfo.ToTitleCase(($brandSlug -replace '-', ' '))
    }

    $model = Strip-Html ([regex]::Match($Html,
        '(?is)<h1 class="title">.*?field--name-title[^>]*>(.*?)</span>').Groups[1].Value)
    if ([string]::IsNullOrWhiteSpace($model)) {
        $model = (Get-Culture).TextInfo.ToTitleCase(($ballSlug -replace '-', ' '))
    }

    $coverName = Get-LabelHiddenItem $Html 'coverstock'
    $coverType = Get-InlineValue $Html 'coverstock-type' 'Type'
    $coreName  = Get-LabelHiddenItem $Html 'core'
    $coreType  = Get-InlineValue $Html 'core-type' 'Core Type'
    $finish    = Get-FieldItem  $Html 'factory-finish'
    $release   = Get-InlineValue $Html 'release-date' 'Release Date'

    $asym = ($coreType -match '(?i)asym')
    $year = $null
    $ym = [regex]::Match($release, '(\d{4})')
    if ($ym.Success) { $year = [int]$ym.Groups[1].Value }

    # Ball photo: the <img> inside field-ball-image. Use the token-free original
    # (strip the Drupal image-style path + ?itok= token) so the URL doesn't expire.
    $imgUrl = $null
    $imgM = [regex]::Match($Html, '(?is)field--name-field-ball-image.*?<img\b[^>]*\ssrc="([^"]+)"')
    if ($imgM.Success) {
        $src = $imgM.Groups[1].Value
        $src = $src -replace '\?.*$', ''
        $src = $src -replace '/styles/[^/]+/public/', '/'
        if ($src -notmatch '^https?://') { $src = "$Base$src" }
        $imgUrl = $src
    }

    # Per-weight specs: split the core-specs region on each "N pounds" card.
    $specs = [ordered]@{}
    $specRegionMatch = [regex]::Match($Html, '(?is)field--name-field-core-specs(.*?)(?:</article>|field--name-field-coolwick|footer)')
    $specRegion = if ($specRegionMatch.Success) { $specRegionMatch.Groups[1].Value } else { $Html }
    $cards = [regex]::Split($specRegion, '(?i)(?=<h6[^>]*>\s*\d+\s*pounds)')
    foreach ($card in $cards) {
        $wm = [regex]::Match($card, '(?i)<h6[^>]*>\s*(\d+)\s*pounds')
        if (-not $wm.Success) { continue }
        $w = $wm.Groups[1].Value
        $rgM   = [regex]::Match($card, '(?is)field--name-field-rg\b.*?<div class="field__item[^"]*">\s*([\d.]+)')
        $diffM = [regex]::Match($card, '(?is)field--name-field-differential\b.*?<div class="field__item[^"]*">\s*([\d.]+)')
        if ($rgM.Success -and $diffM.Success) {
            $entry = [ordered]@{
                rg   = [double]$rgM.Groups[1].Value
                diff = [double]$diffM.Groups[1].Value
            }
            $mbM = [regex]::Match($card, '(?is)field--name-field-(?:mass-bias|intermediate-differential|int-diff)\b.*?<div class="field__item[^"]*">\s*([\d.]+)')
            if ($mbM.Success) { $entry['int_diff'] = [double]$mbM.Groups[1].Value }
            $specs[$w] = $entry
        }
    }

    return [ordered]@{
        id              = $id
        manufacturer    = $brand
        brand           = $brand
        brand_status    = 'active'
        model           = $model
        year            = $year
        coverstock_type = (ConvertTo-CoverEnum $coverType)
        coverstock_name = if ($coverName) { $coverName } else { $null }
        core_name       = if ($coreName) { $coreName } else { $null }
        asymmetric      = [bool]$asym
        factory_finish  = if ($finish) { $finish } else { $null }
        image_url       = $imgUrl
        specs_by_weight = $specs
        shared_core_id  = $null
        db_status       = 'bowwwl'
    }
}

function Test-Record {
    param($r)
    $issues = @()
    foreach ($k in 'id','manufacturer','brand','brand_status','model','coverstock_type','asymmetric','db_status') {
        if ($null -eq $r[$k] -or "$($r[$k])" -eq '') { $issues += "missing $k" }
    }
    if ($ValidCovers -notcontains $r['coverstock_type']) { $issues += "bad coverstock_type '$($r['coverstock_type'])'" }
    return $issues
}

# ----------------------------------------------------------------------------
if ($TestUrl) {
    $urls = @($TestUrl)
    Write-Host "Test mode: parsing $TestUrl"
} else {
    Write-Host "Enumerating ball URLs from $Base ..."
    $urls = Get-BallUrls | Sort-Object -Unique
    Write-Host ("Found {0} unique ball URLs." -f $urls.Count)
    if ($Limit -gt 0 -and $urls.Count -gt $Limit) { $urls = $urls[0..($Limit-1)] }
}

$records = New-Object System.Collections.ArrayList
$badCount = 0
$i = 0
foreach ($u in $urls) {
    $i++
    try {
        $rec = Parse-Ball (Get-Html "$Base$u") $u
        $problems = Test-Record $rec
        if ($problems.Count -gt 0) {
            $badCount++
            Write-Warning ("[{0}] {1}: {2}" -f $i, $u, ($problems -join '; '))
        } else {
            [void]$records.Add($rec)
        }
    } catch {
        $badCount++
        Write-Warning ("[{0}] {1}: {2}" -f $i, $u, $_.Exception.Message)
    }
    if ($i % 50 -eq 0) { Write-Host ("  parsed {0}/{1} (good {2})" -f $i, $urls.Count, $records.Count) }
}

$withSpecs = ($records | Where-Object { $_.specs_by_weight.Count -gt 0 }).Count
Write-Host ""
Write-Host ("Parsed {0} balls ({1} with weight specs, {2} skipped)." -f $records.Count, $withSpecs, $badCount)

if ($records.Count -eq 0) { throw "No valid records parsed -- refusing to write an empty database." }

$top = [ordered]@{
    version      = 2
    generated_at = (Get-Date -Format 'yyyy-MM-dd')
    source       = 'bowwwl.com (per-ball pages; robots.txt-permitted crawl)'
    balls        = @($records)
}
$json = $top | ConvertTo-Json -Depth 12

# Round-trip validation: must re-parse, and every coverstock_type must be in-enum.
$check = $json | ConvertFrom-Json
$badEnum = @($check.balls | Where-Object { $ValidCovers -notcontains $_.coverstock_type })
if ($badEnum.Count -gt 0) { throw "Validation failed: $($badEnum.Count) records have an out-of-enum coverstock_type." }

$dest = if ($Preview) { Join-Path $PSScriptRoot 'balldb.generated.json' } else { $OutFile }
Set-Content -Path $dest -Value $json -Encoding UTF8
Write-Host ("Wrote {0} balls to {1}" -f $check.balls.Count, $dest)
