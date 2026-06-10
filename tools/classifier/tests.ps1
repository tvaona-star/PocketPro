# Pocket Pro — Leave Classifier test suite.
# Run directly: powershell -File tests.ps1   (exit 0 = green)
# Covers: PRD 5.5.2 decision log (authoritative), 5.5.1 taxonomy examples,
# documented divergences (DECISIONS.md D8), and whole-table invariants.
Set-StrictMode -Version 2.0
. (Join-Path $PSScriptRoot 'classifier.ps1')

$script:Failures = @()
$script:Passes = 0

function Assert-Tags([int[]]$pins, [string[]]$expected, [string]$label) {
    $actual = @(Get-Categories $pins)
    $a = ($actual | Sort-Object) -join '+'
    $e = ($expected | Sort-Object) -join '+'
    if ($a -eq $e) { $script:Passes++ }
    else { $script:Failures += "TAGS  $label  [$($pins -join '-')]  expected=[$e]  actual=[$a]" }
}

function Assert-Primary([int[]]$pins, [string]$expected, [string]$label) {
    $tags = @(Get-Categories $pins)
    $actual = $tags[0]
    if ($actual -eq $expected) { $script:Passes++ }
    else { $script:Failures += "PRIM  $label  [$($pins -join '-')]  expected=$expected  actual=$actual" }
}

function Assert-Name([int[]]$pins, [string]$expected, [string]$label) {
    $names = Get-NameMap
    $mask = Get-Mask $pins
    $actual = ''
    if ($names.ContainsKey($mask)) { $actual = $names[$mask] }
    if ($actual -eq $expected) { $script:Passes++ }
    else { $script:Failures += "NAME  $label  [$($pins -join '-')]  expected='$expected'  actual='$actual'" }
}

function Assert-True([bool]$cond, [string]$label) {
    if ($cond) { $script:Passes++ } else { $script:Failures += "COND  $label" }
}

# ---------- PRD 5.5.2 Decision Log (authoritative — must match 100%) ----------
Assert-Tags @(1,5)      @('sleeper')                          'DL: 1-5 sleeper (washout exception)'
Assert-Tags @(2,5)      @('other')                            'DL: 2-5 other'
Assert-Tags @(3,5)      @('other')                            'DL: 3-5 other'
Assert-Tags @(1,2,4)    @('washout')                          'DL: 1-2-4 washout overrides cluster'
Assert-Tags @(1,3,6)    @('washout')                          'DL: 1-3-6 washout overrides cluster'
Assert-Tags @(2,4,5,8)  @('bucket')                           'DL: 2-4-5-8 bucket, cluster suppressed'
Assert-Tags @(3,5,6,9)  @('bucket')                           'DL: 3-5-6-9 bucket, cluster suppressed'
Assert-Tags @(4,5)      @('split')                            'DL: 4-5 split (not baby, not cluster)'
Assert-Tags @(5,6)      @('split')                            'DL: 5-6 split (not baby, not cluster)'
Assert-Tags @(7,10)     @('seven_ten','big_split','split')    'DL: 7-10 named + big split'
Assert-Tags @(4,6,7,10) @('big_four','big_split','split')     'DL: big four named + big split'
Assert-Tags @(2,7)      @('baby_split','split')               'DL: 2-7 baby split'
Assert-Tags @(3,10)     @('baby_split','split')               'DL: 3-10 baby split'

# ---------- 5.5.1 taxonomy examples ----------
foreach ($p in 1..10) {
    if ($p -eq 7 -or $p -eq 10) { Assert-Tags @($p) @('corner_pin','single_pin') "TX: single corner $p" }
    else { Assert-Tags @($p) @('single_pin') "TX: single $p" }
}
Assert-Tags @(2,8) @('sleeper') 'TX: 2-8 sleeper'
Assert-Tags @(3,9) @('sleeper') 'TX: 3-9 sleeper'
foreach ($c in @(@(2,4,5), @(3,5,6), @(2,4,7), @(3,6,10), @(4,7,8), @(6,9,10))) {
    Assert-Tags $c @('cluster') "TX: cluster $($c -join '-')"
}
foreach ($w in @(@(1,2,4,10), @(1,3,6,7), @(1,2,10), @(1,2), @(1,10))) {
    Assert-Tags $w @('washout') "TX: washout $($w -join '-')"
}
foreach ($b in @(@(4,6), @(7,9), @(8,10))) {
    Assert-Tags $b @('big_split','split') "TX: big split $($b -join '-')"
}
Assert-Tags @(4,6,7,9,10) @('big_split','split') 'TX: 4-6-7-9-10 big split'

# ---------- Documented divergences from 5.5.1 examples (DECISIONS.md D8) ----------
Assert-Tags @(4,7)   @('other')              'D8: 4-7 adjacent pair -> other (PRD example divergence)'
Assert-Tags @(6,7,10) @('big_split','split') 'D8: 6-7-10 -> big split (matches PRD big-split rule)'

# ---------- USBC rule 2(b) splits: ahead pin down ----------
foreach ($s in @(@(2,3), @(7,8), @(8,9), @(9,10), @(4,5,6), @(7,8,9))) {
    Assert-Tags $s @('split') "2b: $($s -join '-') split via ahead pin"
}

# ---------- Wide-leave splits and connectivity ----------
Assert-Tags @(5,7)  @('big_split','split') '5-7 big split'
Assert-Tags @(5,10) @('big_split','split') '5-10 Woolworth big split'
Assert-Tags @(4,10) @('big_split','split') '4-10 big split'
Assert-Tags @(6,7)  @('big_split','split') '6-7 big split'
Assert-Tags @(5,7,10) @('big_split','split') '5-7-10 sour apple big split'
Assert-Tags @(4,7,10) @('big_split','split') '4-7-10 big split'
Assert-Tags @(4,5,7) @('split')             '4-5-7 connected split (not big)'

# ---------- Non-split adjacent oddballs -> other ----------
foreach ($o in @(@(2,4), @(3,6), @(4,8), @(5,8), @(5,9), @(6,9), @(6,10))) {
    Assert-Tags $o @('other') "other: $($o -join '-')"
}

# ---------- Disconnected non-split clusters stay clusters when connected ----------
Assert-Tags @(2,4,8)   @('cluster') '2-4-8 connected cluster'
Assert-Tags @(2,5,8,9) @('cluster') '2-5-8-9 connected cluster'

# ---------- Names ----------
Assert-Name @(7,10)       '7-10'         'name 7-10'
Assert-Name @(4,6,7,10)   'Big Four'     'name big four'
Assert-Name @(2,4,5,8)    'Bucket'       'name bucket L'
Assert-Name @(3,5,6,9)    'Bucket'       'name bucket R'
Assert-Name @(2,7)        'Baby Split'   'name baby L'
Assert-Name @(3,10)       'Baby Split'   'name baby R'
Assert-Name @(1,5)        'Sleeper'      'name sleeper 1-5'
Assert-Name @(5,10)       'Woolworth'    'name woolworth'
Assert-Name @(5,7,10)     'Sour Apple'   'name sour apple'
Assert-Name @(4,6,7,9,10) 'Greek Church' 'name greek church'
Assert-Name @(1,2,4,7)    'Picket Fence' 'name picket fence'
Assert-Name @(10)         '10 Pin'       'name 10 pin'
Assert-Name @(7)          '7 Pin'        'name 7 pin'

# ---------- Whole-table invariants ----------
$counts = @{}
foreach ($cat in $script:Categories) { $counts[$cat] = 0 }
$primaryCounts = @{}
foreach ($cat in $script:Categories) { $primaryCounts[$cat] = 0 }
$total = 0
for ($mask = 1; $mask -le 1023; $mask++) {
    $standing = @(Get-Standing $mask)
    $tags = @(Get-Categories $standing)
    Assert-True ($tags.Count -ge 1) "mask $mask has tags"
    foreach ($t in $tags) { $counts[$t]++ }
    $primaryCounts[$tags[0]]++
    $total++

    # Structural invariants per mask
    if ($tags -contains 'big_split') { Assert-True ($tags -contains 'split') "mask $mask big_split implies split" }
    if ($tags -contains 'corner_pin') { Assert-True ($tags -contains 'single_pin') "mask $mask corner implies single" }
    if (($tags -contains 'bucket') -and ($tags -contains 'cluster')) { $script:Failures += "mask $mask bucket+cluster conflict" }
    if (($tags -contains 'washout') -and ($tags.Count -gt 1)) { $script:Failures += "mask $mask washout must be exclusive" }
    if (($tags -contains 'baby_split') -and ($tags -contains 'big_split')) { $script:Failures += "mask $mask baby+big conflict" }
}
Assert-True ($total -eq 1023) 'all 1023 combinations classified'
Assert-True ($counts['single_pin'] -eq 10) "single_pin count 10 (got $($counts['single_pin']))"
Assert-True ($counts['corner_pin'] -eq 2)  "corner_pin count 2 (got $($counts['corner_pin']))"
Assert-True ($counts['washout'] -eq 510)   "washout count 510 (got $($counts['washout']))"
Assert-True ($counts['sleeper'] -eq 3)     "sleeper count 3 (got $($counts['sleeper']))"
Assert-True ($counts['baby_split'] -eq 2)  "baby_split count 2 (got $($counts['baby_split']))"
Assert-True ($counts['bucket'] -eq 2)      "bucket count 2 (got $($counts['bucket']))"
Assert-True ($counts['seven_ten'] -eq 1)   "seven_ten count 1 (got $($counts['seven_ten']))"
Assert-True ($counts['big_four'] -eq 1)    "big_four count 1 (got $($counts['big_four']))"

$sumPrimary = 0
foreach ($cat in $script:Categories) { $sumPrimary += $primaryCounts[$cat] }
Assert-True ($sumPrimary -eq 1023) 'primary categories partition all 1023'

Write-Host ''
Write-Host "Category totals (tag counts / primary counts):"
foreach ($cat in $script:Categories) {
    Write-Host ("  {0,-12} {1,5} / {2,5}" -f $cat, $counts[$cat], $primaryCounts[$cat])
}
Write-Host ''
if ($script:Failures.Count -gt 0) {
    Write-Host "FAILED: $($script:Failures.Count) failures, $script:Passes passes" -ForegroundColor Red
    foreach ($f in $script:Failures) { Write-Host "  $f" -ForegroundColor Red }
    exit 1
}
Write-Host "PASSED: $script:Passes assertions green." -ForegroundColor Green
exit 0
