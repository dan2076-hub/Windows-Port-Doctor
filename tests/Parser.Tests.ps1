$parserFixtures = Get-Content -Raw -Encoding UTF8 (Join-Path $PSScriptRoot 'fixtures\netsh.json') | ConvertFrom-Json

Test-Case 'Excluded tables preserve arrays with zero, one and many rows' {
    foreach ($sample in @(
        @{ Text = $parserFixtures.excludedEmpty; Count = 0 },
        @{ Text = $parserFixtures.excludedOne; Count = 1 },
        @{ Text = $parserFixtures.excludedMany; Count = 3 }
    )) {
        $actual = ConvertFrom-ExcludedPortRanges -Text $sample.Text -ExitCode 0
        Assert-Equal 'ok' $actual.Status
        Assert-True ($actual.Ranges -is [array])
        Assert-Equal $sample.Count $actual.Ranges.Count
        Assert-Equal $null $actual.ErrorCode
    }
}

Test-Case 'Excluded rows preserve inclusive boundaries and administered markers' {
    $actual = ConvertFrom-ExcludedPortRanges $parserFixtures.excludedMany
    Assert-Equal 1 $actual.Ranges[0].Start
    Assert-Equal 1 $actual.Ranges[0].End
    Assert-Equal 65535 $actual.Ranges[2].End
    Assert-True (-not $actual.Ranges[0].Administered)
    Assert-True $actual.Ranges[1].Administered
    Assert-True (-not $actual.Ranges[2].Administered)
}

Test-Case 'Synthetic localized exclusions support CRLF tabs and footnotes' {
    $actual = ConvertFrom-ExcludedPortRanges $parserFixtures.excludedLocalized
    Assert-Equal 'ok' $actual.Status
    Assert-Equal 8000 $actual.Ranges[0].Start
    Assert-Equal 8010 $actual.Ranges[0].End
    Assert-True $actual.Ranges[0].Administered
}

Test-Case 'Excluded malformed rows never return partial success' {
    $header = "Protocol tcp Port Exclusion Ranges`nStart Port    End Port`n----------    --------`n"
    foreach ($row in @('0 1', '65535 65536', '10 9', '-1 5', '1 2 bad', '1 2 **', '1', '1 99999999999999999', '1 2.5', 'broken')) {
        $actual = ConvertFrom-ExcludedPortRanges ($header + "8000 8010`n" + $row)
        Assert-Equal 'parse_error' $actual.Status $row
        Assert-Equal 0 $actual.Ranges.Count
        Assert-True (-not [string]::IsNullOrEmpty($actual.ErrorCode))
    }
}

Test-Case 'Excluded unknown text missing structure and misplaced footnotes fail' {
    foreach ($text in @('', " `r`n", 'Unknown command', '8000 8010',
        "Title`n----------    --------`n1 2",
        "Title`nStart    End`n1 2",
        "Title`nStart    End`n----------    --------`n* - Footnote`n1 2",
        ($parserFixtures.excludedOne + 'trailing warning'))) {
        Assert-Equal 'parse_error' (ConvertFrom-ExcludedPortRanges $text).Status
    }
}

Test-Case 'Dynamic English and synthetic localized labels return ordered values' {
    $actual = ConvertFrom-DynamicPortRange $parserFixtures.dynamic
    Assert-Equal 'ok' $actual.Status
    Assert-Equal 49152 $actual.Start
    Assert-Equal 16384 $actual.Count
    Assert-Equal 65535 $actual.End
    Assert-Equal $null $actual.ErrorCode
    $localized = ConvertFrom-DynamicPortRange $parserFixtures.dynamicLocalized
    Assert-Equal 'ok' $localized.Status
    Assert-Equal 1024 $localized.Start
    Assert-Equal 64511 $localized.Count
    Assert-Equal 65534 $localized.End
}

Test-Case 'Dynamic boundaries accept single ports and full domain' {
    foreach ($pair in @(@{Start=1;Count=1;End=1}, @{Start=65535;Count=1;End=65535}, @{Start=1;Count=65535;End=65535})) {
        $actual = ConvertFrom-DynamicPortRange ("Title`n----------------`nStart : " + $pair.Start + "`nCount : " + $pair.Count)
        Assert-Equal 'ok' $actual.Status
        Assert-Equal $pair.End $actual.End
    }
}

Test-Case 'Dynamic malformed counts boundaries and trailing rows fail closed' {
    foreach ($tail in @("Start: 0`nCount: 1", "Start: 1`nCount: 0", "Start: 65535`nCount: 2",
        "Start: 65536`nCount: 1", "Start: -1`nCount: 2", "Start: 1`nCount: 99999999999999999",
        "Start: 1`nCount: 1.5", "Start: 1`nCount: 2`nExtra: 3", "Start: 1", "Start: 1`nCount: 2 trailing")) {
        $actual = ConvertFrom-DynamicPortRange ("Title`n----------------`n" + $tail)
        Assert-Equal 'parse_error' $actual.Status $tail
        Assert-Equal $null $actual.Start
        Assert-Equal $null $actual.Count
        Assert-Equal $null $actual.End
    }
}

Test-Case 'Dynamic blank unknown and missing separators are parse errors' {
    foreach ($text in @('', "`r`n ", 'garbled output', "Title`nStart: 1`nCount: 2", "Title`n----`n1: 1`n2: 2")) {
        Assert-Equal 'parse_error' (ConvertFrom-DynamicPortRange $text).Status
    }
}

Test-Case 'Native nonzero exits take precedence over plausible or empty output' {
    foreach ($text in @('', 'Access is denied.', $parserFixtures.excludedOne, $parserFixtures.dynamic)) {
        $excluded = ConvertFrom-ExcludedPortRanges -Text $text -ExitCode 5
        $dynamic = ConvertFrom-DynamicPortRange -Text $text -ExitCode 5
        Assert-Equal 'error' $excluded.Status
        Assert-Equal 'error' $dynamic.Status
        Assert-Equal 0 $excluded.Ranges.Count
        Assert-Equal $null $dynamic.Start
        Assert-Equal 'netsh_failed' $excluded.ErrorCode
        Assert-Equal 'netsh_failed' $dynamic.ErrorCode
    }
}
