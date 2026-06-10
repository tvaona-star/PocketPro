# Pocket Pro — Ten-pin scoring + stats test vectors.
# The engine lives in scoring.ps1 (shared with tools/pinpal/validate_export.ps1);
# this file is the executable spec for ScoringEngine.swift / StatsEngine.swift.
# The Swift XCTests assert the same vectors; any change here must be mirrored there.
# Run: powershell -File scoring_tests.ps1   (exit 0 = green)
Set-StrictMode -Version 2.0
. (Join-Path $PSScriptRoot 'scoring.ps1')

$script:Failures = @()
$script:Passes = 0

function Assert-Eq($actual, $expected, [string]$label) {
    $a = "$actual"; $e = "$expected"
    if ($a -eq $e) { $script:Passes++ }
    else { $script:Failures += "$label  expected=$e  actual=$a" }
}

# V1: Perfect game
$perfect = @(,@(10)) * 9 + ,@(10,10,10)
$r = Score-Game $perfect
Assert-Eq $r.Final 300 'V1 perfect game final'
Assert-Eq ($r.FrameScores -join ',') '30,30,30,30,30,30,30,30,30,30' 'V1 frame scores'
Assert-Eq (@(Get-FreshDeliveries $perfect).Count) 12 'V1 fresh deliveries'
Assert-Eq ((Get-GameSummary $perfect).Strikes) 12 'V1 strike count'
Assert-Eq (@(Get-Streaks $perfect) -join ',') '12' 'V1 streak'

# V2: All spares, 9 first ball, 9 fill
$allSpares = @(,@(9,1)) * 9 + ,@(9,1,9)
$r = Score-Game $allSpares
Assert-Eq $r.Final 190 'V2 all spares final'
Assert-Eq ($r.Cumulative -join ',') '19,38,57,76,95,114,133,152,171,190' 'V2 cumulative'
$s = Get-GameSummary $allSpares
Assert-Eq $s.Spares 10 'V2 spare count'
Assert-Eq $s.Strikes 0 'V2 strike count'
Assert-Eq $s.Opens 0 'V2 opens'

# V3: All gutters
$gutters = @(,@(0,0)) * 10
$r = Score-Game $gutters
Assert-Eq $r.Final 0 'V3 gutter final'

# V4: Mixed game — X | 7/ | 9- | X | -8 | 8/ | -6 | X | X | X8/  => 168
$mixed = @(
    ,@(10)
    ,@(7,3)
    ,@(9,0)
    ,@(10)
    ,@(0,8)
    ,@(8,2)
    ,@(0,6)
    ,@(10)
    ,@(10)
    ,@(10,8,2)
)
$r = Score-Game $mixed
Assert-Eq $r.Final 168 'V4 mixed final'
Assert-Eq ($r.FrameScores -join ',') '20,19,9,18,8,10,6,30,28,20' 'V4 frame scores'
$s = Get-GameSummary $mixed
Assert-Eq $s.Strikes 5 'V4 strikes (X count)'
Assert-Eq $s.Spares 3 'V4 spares'
Assert-Eq $s.Opens 3 'V4 opens'
$fresh = @(Get-FreshDeliveries $mixed)
Assert-Eq $fresh.Count 11 'V4 fresh deliveries'
$sum = 0; foreach ($d in $fresh) { $sum += $d.Pinfall }
Assert-Eq $sum 82 'V4 first-ball pinfall sum'
$d = Get-Doubles $mixed
Assert-Eq $d.Num 2 'V4 doubles num'
Assert-Eq $d.Den 5 'V4 doubles den'
Assert-Eq (@(Get-Streaks $mixed) -join ',') '1,1,3' 'V4 streaks'

# V5: Nine opens 9-0 then 10th spare + fill of 7  => 81 + 17 = 98
$spareTenth = @(,@(9,0)) * 9 + ,@(9,1,7)
$r = Score-Game $spareTenth
Assert-Eq $r.Final 98 'V5 final'
$fresh = @(Get-FreshDeliveries $spareTenth)
Assert-Eq $fresh.Count 11 'V5 fresh deliveries (ball 3 after spare is fresh)'
$s = Get-GameSummary $spareTenth
Assert-Eq $s.Spares 1 'V5 spares'
Assert-Eq $s.Opens 9 'V5 opens'

# V6: Tenth frame turkey => 9 opens of 9 + 30
$tenthTurkey = @(,@(9,0)) * 9 + ,@(10,10,10)
$r = Score-Game $tenthTurkey
Assert-Eq $r.Final 111 'V6 final'
Assert-Eq (@(Get-Streaks $tenthTurkey) -join ',') '3' 'V6 streak of 3 in tenth'
$s = Get-GameSummary $tenthTurkey
Assert-Eq $s.Strikes 3 'V6 strikes'
Assert-Eq $s.Opens 9 'V6 opens'

# V7: Incomplete game (live scoring): X, 7/, then 8 (one ball into frame 3)
$partial = @(,@(10), @(7,3), @(8))
$r = Score-Game $partial
Assert-Eq $r.FrameScores[0] 20 'V7 frame 1 resolved (10+7+3)'
Assert-Eq $r.FrameScores[1] 18 'V7 frame 2 resolved (10+8)'
Assert-Eq "$($r.FrameScores[2])" '' 'V7 frame 3 unresolved'
Assert-Eq "$($r.Final)" '' 'V7 no final yet'

# V8: Strike awaiting bonuses at the very end of entry
$partial2 = @(,@(10))
$r = Score-Game $partial2
Assert-Eq "$($r.FrameScores[0])" '' 'V8 strike unresolved without bonus balls'

# V9: 10th frame double then 9 (X X 9) => valid 3-ball tenth, all fresh
$tenthDouble = @(,@(9,0)) * 9 + ,@(10,10,9)
$r = Score-Game $tenthDouble
Assert-Eq $r.Final 110 'V9 final (81 + 29)'
Assert-Eq (@(Get-FreshDeliveries $tenthDouble).Count) 12 'V9 all three tenth balls fresh'
$d = Get-Doubles $tenthDouble
Assert-Eq $d.Num 1 'V9 doubles num (10b1->10b2)'
Assert-Eq $d.Den 2 'V9 doubles den (10b2 strike followed by 9)'

# V10: Spare-heavy game => 192
$spareGame = @(
    ,@(9,1)    # converted
    ,@(9,0)    # missed (open)
    ,@(10)
    ,@(8,2)    # converted
    ,@(7,2)    # missed (open)
    ,@(10)
    ,@(10)
    ,@(9,1)    # converted
    ,@(10)
    ,@(10,9,1) # strike then 9/ spare
)
$s = Get-GameSummary $spareGame
Assert-Eq $s.Spares 4 'V10 spares (3 in frames + tenth 9/)'
Assert-Eq $s.Opens 2 'V10 opens'
Assert-Eq $s.Strikes 5 'V10 strikes'
$r = Score-Game $spareGame
Assert-Eq $r.Final 192 'V10 final'
Assert-Eq ($r.FrameScores -join ',') '19,9,20,17,9,29,20,20,29,20' 'V10 frame scores'

Write-Host ''
if ($script:Failures.Count -gt 0) {
    Write-Host "FAILED: $($script:Failures.Count) failures, $script:Passes passes" -ForegroundColor Red
    foreach ($f in $script:Failures) { Write-Host "  $f" -ForegroundColor Red }
    exit 1
}
Write-Host "PASSED: $script:Passes assertions green." -ForegroundColor Green
exit 0
