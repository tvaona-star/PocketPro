# Pocket Pro — Leave Classifier rules engine (reference implementation)
# PRD 5.5.1–5.5.3. This file is the single source of truth for leave classification.
# generate.ps1 runs tests.ps1 against these rules, then emits the pre-resolved Swift
# lookup table (LeaveTable.swift). The app performs no rule evaluation at runtime.
#
# Pin geometry (rows back-to-front, x2 = doubled board offset so all values are integers):
#         7  8  9  10     row 3   x2: -3 -1 +1 +3
#          4  5  6        row 2   x2: -2  0 +2
#           2  3          row 1   x2: -1 +1
#            1            row 0   x2:  0
Set-StrictMode -Version 2.0

$script:PinRow = @(0, 0, 1, 1, 2, 2, 2, 3, 3, 3, 3)  # index by pin number; index 0 unused
$script:PinX2  = @(0, 0, -1, 1, -2, 0, 2, -3, -1, 1, 3)

# 12-inch neighbor pairs on the pin deck (physical adjacency, including diagonals)
$script:AdjacentPairs = @(
    @(1,2), @(1,3), @(2,3),
    @(2,4), @(2,5), @(3,5), @(3,6),
    @(4,5), @(5,6),
    @(4,7), @(4,8), @(5,8), @(5,9), @(6,9), @(6,10),
    @(7,8), @(8,9), @(9,10)
)

# USBC Rule 2(b): a downed pin immediately ahead of a side-by-side standing pair makes a split.
# Key = "lo,hi" of the same-row adjacent pair, value = the pin immediately ahead of (between) them.
$script:AheadPin = @{
    '2,3' = 1; '4,5' = 2; '5,6' = 3;
    '7,8' = 4; '8,9' = 5; '9,10' = 6
}

# Category identifiers — order is badge/primary priority AND the Swift bit position.
$script:Categories = @('washout','seven_ten','big_four','bucket','corner_pin','single_pin','sleeper','baby_split','big_split','split','cluster','other')

# Named leaves (mask key built from sorted pins). Names coexist with any category.
function Get-NameMap {
    $m = @{}
    $m[(Get-Mask @(7,10))]        = '7-10'
    $m[(Get-Mask @(4,6,7,10))]    = 'Big Four'
    $m[(Get-Mask @(2,4,5,8))]     = 'Bucket'
    $m[(Get-Mask @(3,5,6,9))]     = 'Bucket'
    $m[(Get-Mask @(2,7))]         = 'Baby Split'
    $m[(Get-Mask @(3,10))]        = 'Baby Split'
    $m[(Get-Mask @(1,5))]         = 'Sleeper'
    $m[(Get-Mask @(2,8))]         = 'Sleeper'
    $m[(Get-Mask @(3,9))]         = 'Sleeper'
    $m[(Get-Mask @(5,10))]        = 'Woolworth'
    $m[(Get-Mask @(5,7,10))]      = 'Sour Apple'
    $m[(Get-Mask @(4,6,7,8,10))]  = 'Greek Church'
    $m[(Get-Mask @(4,6,7,9,10))]  = 'Greek Church'
    $m[(Get-Mask @(1,2,4,7))]     = 'Picket Fence'
    $m[(Get-Mask @(1,3,6,10))]    = 'Picket Fence'
    foreach ($p in 1..10) { $m[(Get-Mask @($p))] = "$p Pin" }
    return $m
}

function Get-Mask([int[]]$pins) {
    $mask = 0
    foreach ($p in $pins) { $mask = $mask -bor (1 -shl ($p - 1)) }
    return $mask
}

function Get-Standing([int]$mask) {
    # NOTE: single-element results unwrap to a scalar on return — callers must wrap with @().
    $pins = @()
    foreach ($p in 1..10) { if ($mask -band (1 -shl ($p - 1))) { $pins += $p } }
    return $pins
}

function Test-SetEquals([int[]]$a, [int[]]$b) {
    return (($a -join ',') -eq ($b -join ','))
}

# USBC-style split test. Caller guarantees: head pin down, 2+ pins standing.
function Test-Split([int[]]$standing) {
    $standingSet = @{}
    foreach ($p in $standing) { $standingSet[$p] = $true }
    $downed = @()
    foreach ($p in 1..10) { if (-not $standingSet.ContainsKey($p)) { $downed += $p } }

    # (a) A downed pin lies spatially between two standing pins: x strictly inside the
    #     pair's horizontal span, row within the pair's row band (inclusive).
    for ($i = 0; $i -lt $standing.Count; $i++) {
        for ($j = $i + 1; $j -lt $standing.Count; $j++) {
            $p = $standing[$i]; $q = $standing[$j]
            $loX = [Math]::Min($script:PinX2[$p], $script:PinX2[$q])
            $hiX = [Math]::Max($script:PinX2[$p], $script:PinX2[$q])
            $loR = [Math]::Min($script:PinRow[$p], $script:PinRow[$q])
            $hiR = [Math]::Max($script:PinRow[$p], $script:PinRow[$q])
            foreach ($d in $downed) {
                if ($script:PinX2[$d] -gt $loX -and $script:PinX2[$d] -lt $hiX -and
                    $script:PinRow[$d] -ge $loR -and $script:PinRow[$d] -le $hiR) {
                    return $true
                }
            }
        }
    }
    # (b) A downed pin immediately ahead of a side-by-side standing pair (4-5, 5-6, etc.)
    foreach ($key in $script:AheadPin.Keys) {
        $pair = $key -split ','
        $a = [int]$pair[0]; $b = [int]$pair[1]
        if ($standingSet.ContainsKey($a) -and $standingSet.ContainsKey($b)) {
            $ahead = $script:AheadPin[$key]
            if (-not $standingSet.ContainsKey($ahead)) { return $true }
        }
    }
    return $false
}

# True when all standing pins form a single physically-adjacent component.
function Test-Connected([int[]]$standing) {
    if ($standing.Count -le 1) { return $true }
    $standingSet = @{}
    foreach ($p in $standing) { $standingSet[$p] = $true }
    $visited = @{}
    $queue = New-Object System.Collections.Queue
    $queue.Enqueue($standing[0])
    $visited[$standing[0]] = $true
    while ($queue.Count -gt 0) {
        $cur = $queue.Dequeue()
        foreach ($pair in $script:AdjacentPairs) {
            $nbr = -1
            if ($pair[0] -eq $cur) { $nbr = $pair[1] }
            elseif ($pair[1] -eq $cur) { $nbr = $pair[0] }
            if ($nbr -gt 0 -and $standingSet.ContainsKey($nbr) -and -not $visited.ContainsKey($nbr)) {
                $visited[$nbr] = $true
                $queue.Enqueue($nbr)
            }
        }
    }
    return ($visited.Count -eq $standing.Count)
}

# Returns the ordered category tag array for a standing-pin set.
# First element is the primary (badge) category — order follows PRD priority.
function Get-Categories([int[]]$standing) {
    $s = @($standing | Sort-Object)
    $n = $s.Count
    $has1 = ($s -contains 1)

    if ($n -eq 1) {
        if ($s[0] -eq 7 -or $s[0] -eq 10) { return @('corner_pin','single_pin') }
        return @('single_pin')
    }
    # PRD 5.5.2 decision log: 1-5 is a Sleeper — the single exception to the washout rule.
    if (Test-SetEquals $s @(1,5)) { return @('sleeper') }
    if ($has1) { return @('washout') }
    if (Test-SetEquals $s @(7,10))     { return @('seven_ten','big_split','split') }
    if (Test-SetEquals $s @(4,6,7,10)) { return @('big_four','big_split','split') }
    if ((Test-SetEquals $s @(2,4,5,8)) -or (Test-SetEquals $s @(3,5,6,9))) { return @('bucket') }
    if ((Test-SetEquals $s @(2,8)) -or (Test-SetEquals $s @(3,9))) { return @('sleeper') }
    if ((Test-SetEquals $s @(2,7)) -or (Test-SetEquals $s @(3,10))) { return @('baby_split','split') }
    if (Test-Split $s) {
        if (-not (Test-Connected $s)) { return @('big_split','split') }
        return @('split')
    }
    if ($n -ge 3 -and (Test-Connected $s)) { return @('cluster') }
    return @('other')
}

function Get-CategoryBit([string]$cat) {
    return [Array]::IndexOf($script:Categories, $cat)
}

# Packed UInt16: bit i set = category i applies (bit order = $Categories order).
function Get-PackedCategories([int[]]$standing) {
    $packed = 0
    foreach ($cat in (Get-Categories $standing)) {
        $packed = $packed -bor (1 -shl (Get-CategoryBit $cat))
    }
    return $packed
}
