# Pocket Pro — structural Swift lint (Windows-side sanity check; not a compiler).
# Strips comments and string literals, then verifies brace/paren/bracket balance
# and clean end-of-file state. Catches gross structural errors before Mac compilation.
# Usage: powershell -File swift_lint.ps1 [-Root <path>]
param(
    [string]$Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
)
Set-StrictMode -Version 2.0

$files = Get-ChildItem -Path $Root -Recurse -Filter *.swift | Where-Object { $_.FullName -notmatch '\\\.build\\' }
$failures = @()

foreach ($file in $files) {
    $text = [System.IO.File]::ReadAllText($file.FullName)
    $braces = 0; $parens = 0; $brackets = 0
    $state = 'code'        # code | line_comment | block_comment | string | multiline_string
    $blockDepth = 0
    $interpolationStack = New-Object System.Collections.Stack
    $i = 0
    $n = $text.Length
    $line = 1
    $firstError = $null

    while ($i -lt $n) {
        $c = $text[$i]
        $next = if ($i + 1 -lt $n) { $text[$i + 1] } else { [char]0 }
        if ($c -eq "`n") { $line++ }

        switch ($state) {
            'code' {
                if ($c -eq '/' -and $next -eq '/') { $state = 'line_comment'; $i++ }
                elseif ($c -eq '/' -and $next -eq '*') { $state = 'block_comment'; $blockDepth = 1; $i++ }
                elseif ($c -eq '"' -and $next -eq '"' -and ($i + 2 -lt $n) -and $text[$i + 2] -eq '"') { $state = 'multiline_string'; $i += 2 }
                elseif ($c -eq '"') { $state = 'string' }
                elseif ($c -eq '{') { $braces++ }
                elseif ($c -eq '}') {
                    $braces--
                    if ($braces -lt 0 -and $null -eq $firstError) { $firstError = "negative brace depth at line $line" }
                }
                elseif ($c -eq '(') { $parens++ }
                elseif ($c -eq ')') {
                    if ($interpolationStack.Count -gt 0 -and $parens -eq [int]$interpolationStack.Peek()) {
                        # closing a string interpolation — return to string state
                        [void]$interpolationStack.Pop()
                        $state = 'string'
                    }
                    else {
                        $parens--
                        if ($parens -lt 0 -and $null -eq $firstError) { $firstError = "negative paren depth at line $line" }
                    }
                }
                elseif ($c -eq '[') { $brackets++ }
                elseif ($c -eq ']') {
                    $brackets--
                    if ($brackets -lt 0 -and $null -eq $firstError) { $firstError = "negative bracket depth at line $line" }
                }
            }
            'line_comment' {
                if ($c -eq "`n") { $state = 'code' }
            }
            'block_comment' {
                if ($c -eq '/' -and $next -eq '*') { $blockDepth++; $i++ }
                elseif ($c -eq '*' -and $next -eq '/') {
                    $blockDepth--
                    $i++
                    if ($blockDepth -eq 0) { $state = 'code' }
                }
            }
            'string' {
                if ($c -eq '\') {
                    if ($next -eq '(') {
                        # string interpolation: switch to code, remember paren depth
                        $interpolationStack.Push($parens)
                        $state = 'code'
                        $i++
                    }
                    else { $i++ }  # escaped char
                }
                elseif ($c -eq '"') { $state = 'code' }
                elseif ($c -eq "`n") {
                    if ($null -eq $firstError) { $firstError = "newline inside single-line string at line $line" }
                    $state = 'code'
                }
            }
            'multiline_string' {
                if ($c -eq '"' -and $next -eq '"' -and ($i + 2 -lt $n) -and $text[$i + 2] -eq '"') {
                    $state = 'code'
                    $i += 2
                }
                elseif ($c -eq '\' -and $next -eq '(') {
                    $interpolationStack.Push($parens)
                    $state = 'code'
                    $i++
                }
            }
        }
        $i++
    }

    $problems = @()
    if ($null -ne $firstError) { $problems += $firstError }
    if ($braces -ne 0) { $problems += "unbalanced braces ($braces)" }
    if ($parens -ne 0) { $problems += "unbalanced parens ($parens)" }
    if ($brackets -ne 0) { $problems += "unbalanced brackets ($brackets)" }
    if ($state -eq 'string' -or $state -eq 'multiline_string') { $problems += 'unterminated string at EOF' }
    if ($state -eq 'block_comment') { $problems += 'unterminated block comment at EOF' }

    if ($problems.Count -gt 0) {
        $rel = $file.FullName.Substring($Root.Length + 1)
        $failures += "{0}: {1}" -f $rel, ($problems -join '; ')
    }
}

Write-Host "Checked $($files.Count) Swift files under $Root"
if ($failures.Count -gt 0) {
    Write-Host "LINT FAILURES:" -ForegroundColor Red
    foreach ($f in $failures) { Write-Host "  $f" -ForegroundColor Red }
    exit 1
}
Write-Host 'All files structurally balanced.' -ForegroundColor Green
exit 0
