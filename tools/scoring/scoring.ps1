# Pocket Pro — Ten-pin scoring reference engine (shared module).
# Dot-sourced by scoring_tests.ps1 (the executable spec) and
# tools/pinpal/validate_export.ps1 (real-export validation).
# Mirrors PocketProCore/Sources/PocketProCore/ScoringEngine.swift — change both together.
#
# Game model: array of 10 frames; each frame = array of ball pinfall counts.
#   Frames 1-9: [10] for a strike, otherwise [b1, b2] (or [b1] mid-entry).
#   Frame 10:   [b1, b2] open, [b1, b2, b3] after a strike or spare.
Set-StrictMode -Version 2.0

# Flattened rolls strictly after frame index $f (0-based).
function Get-RollsAfter($frames, [int]$f) {
    $rolls = @()
    for ($i = $f + 1; $i -lt $frames.Count; $i++) {
        foreach ($b in @($frames[$i])) { $rolls += $b }
    }
    return $rolls
}

# Returns @{ FrameScores = int?/null[10]; Cumulative = int?/null[10]; Final = int or $null }
function Score-Game($frames) {
    $frameScores = @($null) * 10
    for ($f = 0; $f -lt [Math]::Min(10, $frames.Count); $f++) {
        $balls = @($frames[$f])
        if ($balls.Count -eq 0) { continue }
        if ($f -lt 9) {
            if ($balls[0] -eq 10) {
                $next = @(Get-RollsAfter $frames $f)
                if ($next.Count -ge 2) { $frameScores[$f] = 10 + $next[0] + $next[1] }
            }
            elseif ($balls.Count -ge 2) {
                if (($balls[0] + $balls[1]) -eq 10) {
                    $next = @(Get-RollsAfter $frames $f)
                    if ($next.Count -ge 1) { $frameScores[$f] = 10 + $next[0] }
                }
                else { $frameScores[$f] = $balls[0] + $balls[1] }
            }
        }
        else {
            $needsThree = ($balls[0] -eq 10) -or ($balls.Count -ge 2 -and ($balls[0] + $balls[1]) -eq 10)
            $complete = $false
            if ($needsThree) { if ($balls.Count -ge 3) { $complete = $true } }
            elseif ($balls.Count -ge 2) { $complete = $true }
            if ($complete) {
                $sum = 0; foreach ($b in $balls) { $sum += $b }
                $frameScores[$f] = $sum
            }
        }
    }
    $cumulative = @($null) * 10
    $running = 0
    for ($f = 0; $f -lt 10; $f++) {
        if ($null -eq $frameScores[$f]) { break }
        $running += $frameScores[$f]
        $cumulative[$f] = $running
    }
    $final = $null
    if ($null -ne $cumulative[9]) { $final = $cumulative[9] }
    return @{ FrameScores = $frameScores; Cumulative = $cumulative; Final = $final }
}

# Fresh-rack deliveries (DECISIONS.md D11): frames 1-9 ball 1; 10th frame ball 1,
# ball 2 after a strike, ball 3 after a double or after a ball-2 spare.
function Get-FreshDeliveries($frames) {
    $out = @()
    for ($f = 0; $f -lt [Math]::Min(10, $frames.Count); $f++) {
        $balls = @($frames[$f])
        if ($balls.Count -eq 0) { continue }
        if ($f -lt 9) {
            $out += ,@{ Pinfall = $balls[0]; Frame = $f; Ball = 0 }
        }
        else {
            $out += ,@{ Pinfall = $balls[0]; Frame = $f; Ball = 0 }
            if ($balls.Count -ge 2 -and $balls[0] -eq 10) {
                $out += ,@{ Pinfall = $balls[1]; Frame = $f; Ball = 1 }
            }
            if ($balls.Count -ge 3) {
                $fresh3 = $false
                if ($balls[0] -eq 10 -and $balls[1] -eq 10) { $fresh3 = $true }
                elseif ($balls[0] -ne 10 -and ($balls[0] + $balls[1]) -eq 10) { $fresh3 = $true }
                if ($fresh3) { $out += ,@{ Pinfall = $balls[2]; Frame = $f; Ball = 2 } }
            }
        }
    }
    return $out
}

# Game summary: strike balls (X count), spare conversions, open frames.
function Get-GameSummary($frames) {
    $strikes = 0; $spares = 0; $opens = 0
    for ($f = 0; $f -lt [Math]::Min(10, $frames.Count); $f++) {
        $balls = @($frames[$f])
        if ($balls.Count -eq 0) { continue }
        if ($f -lt 9) {
            if ($balls[0] -eq 10) { $strikes++ }
            elseif ($balls.Count -ge 2) {
                if (($balls[0] + $balls[1]) -eq 10) { $spares++ } else { $opens++ }
            }
        }
        else {
            # Tenth frame: explicit case analysis on rack sequence.
            if ($balls[0] -eq 10) {
                $strikes++
                if ($balls.Count -ge 2) {
                    if ($balls[1] -eq 10) {
                        $strikes++
                        if ($balls.Count -ge 3 -and $balls[2] -eq 10) { $strikes++ }
                    }
                    elseif ($balls.Count -ge 3 -and ($balls[1] + $balls[2]) -eq 10) { $spares++ }
                }
            }
            elseif ($balls.Count -ge 2) {
                if (($balls[0] + $balls[1]) -eq 10) {
                    $spares++
                    if ($balls.Count -ge 3 -and $balls[2] -eq 10) { $strikes++ }
                }
                else { $opens++ }
            }
        }
    }
    return @{ Strikes = $strikes; Spares = $spares; Opens = $opens }
}

# Consecutive fresh-rack strike streaks within one game. Returns array of streak lengths.
function Get-Streaks($frames) {
    $streaks = @()
    $current = 0
    foreach ($d in @(Get-FreshDeliveries $frames)) {
        if ($d.Pinfall -eq 10) { $current++ }
        else { if ($current -gt 0) { $streaks += $current }; $current = 0 }
    }
    if ($current -gt 0) { $streaks += $current }
    return $streaks
}

# Doubles: among fresh-rack strikes with a following fresh delivery in the same game,
# the fraction followed by another strike. Returns @{ Num; Den }.
function Get-Doubles($frames) {
    $deliveries = @(Get-FreshDeliveries $frames)
    $num = 0; $den = 0
    for ($i = 0; $i -lt $deliveries.Count; $i++) {
        if ($deliveries[$i].Pinfall -eq 10 -and ($i + 1) -lt $deliveries.Count) {
            $den++
            if ($deliveries[$i + 1].Pinfall -eq 10) { $num++ }
        }
    }
    return @{ Num = $num; Den = $den }
}
