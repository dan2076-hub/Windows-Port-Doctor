Set-StrictMode -Version 2

function ConvertFrom-ExcludedPortRanges {
    [CmdletBinding()]
    param([AllowNull()][AllowEmptyString()][string]$Text, [int]$ExitCode = 0)

    $result = [pscustomobject]@{ Status = 'parse_error'; Ranges = @(); ErrorCode = 'unrecognized_output' }
    if ($ExitCode -ne 0) {
        $result.Status = 'error'
        $result.ErrorCode = 'netsh_failed'
        return $result
    }
    $lines = @($Text -split '\r\n|\n|\r' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    # The title and column labels vary by language. Their layout must still be present.
    if ($lines.Count -lt 3 -or
        $lines[0] -notmatch '\p{L}' -or
        $lines[1] -notmatch '^\s*\S.*?(?: {2,}|\t+)\S.*?\s*$' -or
        $lines[1] -notmatch '\p{L}' -or
        $lines[2] -notmatch '^\s*-{2,}\s+-{2,}\s*$') { return $result }

    $ranges = @()
    for ($index = 3; $index -lt $lines.Count; $index++) {
        $line = $lines[$index]
        # A localized administered-range footnote may occur only at the end.
        if ($line -match '^\s*\* - \S.*$' -and $index -eq ($lines.Count - 1)) { continue }
        if ($line -notmatch '^\s*([0-9]+)\s+([0-9]+)\s*(\*)?\s*$') { return $result }
        $administered = $Matches[3] -eq '*'
        [int]$start = 0
        [int]$end = 0
        if (-not [int]::TryParse($Matches[1], [ref]$start) -or
            -not [int]::TryParse($Matches[2], [ref]$end) -or
            $start -lt 1 -or $end -gt 65535 -or $start -gt $end) { return $result }
        $ranges += [pscustomobject]@{ Start = $start; End = $end; Administered = $administered }
    }
    $result.Status = 'ok'
    $result.Ranges = @($ranges)
    $result.ErrorCode = $null
    return $result
}

function ConvertFrom-DynamicPortRange {
    [CmdletBinding()]
    param([AllowNull()][AllowEmptyString()][string]$Text, [int]$ExitCode = 0)

    $result = [pscustomobject]@{ Status = 'parse_error'; Start = $null; Count = $null; End = $null; ErrorCode = 'unrecognized_output' }
    if ($ExitCode -ne 0) {
        $result.Status = 'error'
        $result.ErrorCode = 'netsh_failed'
        return $result
    }
    $lines = @($Text -split '\r\n|\n|\r' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($lines.Count -ne 4 -or $lines[0] -notmatch '\p{L}' -or
        $lines[1] -notmatch '^\s*-{2,}\s*$') { return $result }
    $values = @()
    foreach ($line in $lines[2..3]) {
        if ($line -notmatch '^\s*([^:]+\S|\S)\s*:\s*([0-9]+)\s*$' -or $Matches[1] -notmatch '\p{L}') { return $result }
        # Match again because the label validation also updates PowerShell's $Matches.
        $null = $line -match ':\s*([0-9]+)\s*$'
        [int]$value = 0
        if (-not [int]::TryParse($Matches[1], [ref]$value) -or $value -lt 1 -or $value -gt 65535) { return $result }
        $values += $value
    }
    $end = [long]$values[0] + [long]$values[1] - 1
    if ($end -gt 65535) { return $result }
    $result.Status = 'ok'
    $result.Start = $values[0]
    $result.Count = $values[1]
    $result.End = [int]$end
    $result.ErrorCode = $null
    return $result
}

Export-ModuleMember -Function ConvertFrom-ExcludedPortRanges, ConvertFrom-DynamicPortRange
