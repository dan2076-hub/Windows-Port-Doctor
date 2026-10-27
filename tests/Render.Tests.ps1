Test-Case 'JSON retains zero, one and many endpoint arrays' {
    foreach ($count in @(0, 1, 3)) {
        $evidence = New-TestEvidence
        $evidence.Tcp.Items = @(1..$count | Where-Object { $count -gt 0 } | ForEach-Object { New-TestEndpoint })
        $report = ConvertTo-PortDiagnostic -Port 8888 -Evidence $evidence
        $roundTrip = (ConvertTo-PortDoctorJson -Report $report) | ConvertFrom-Json
        Assert-True ($roundTrip.endpoints -is [array])
        Assert-Equal $count @($roundTrip.endpoints).Count
        Assert-True ($roundTrip.ranges -is [array]); Assert-Equal 1 $roundTrip.schema_version
    }
}
Test-Case 'Text exposes process attribution and collection gaps without private extras' {
    $evidence = New-TestEvidence
    $evidence.Tcp.Items = @((New-TestEndpoint)); $evidence.Processes.Items = @(New-TestProcesses)
    $evidence.Udp.Status = 'access_denied'
    $evidence | Add-Member NoteProperty ErrorMessage 'PRIVATE_RENDER_SENTINEL'
    $text = ConvertTo-PortDoctorText -Report (ConvertTo-PortDiagnostic -Port 8888 -Evidence $evidence)
    Assert-True ($text -match 'python\.exe \(100\).*launcher\.exe \(200\)')
    Assert-True ($text -match 'udp_endpoints: access_denied')
    Assert-True ($text -match 'MaxUserPort: 65534')
    Assert-True ($text -notmatch 'PRIVATE_RENDER_SENTINEL')
    Assert-True ($text -match 'Bind availability was not tested')
}
Test-Case 'Explain adds documented guidance without modifying the original report' {
    $report = ConvertTo-PortDiagnostic -Port 50000 -Evidence (New-TestEvidence)
    $explained = Add-PortDoctorExplanation -Report $report
    Assert-Equal $null $report.PSObject.Properties['explanations']
    Assert-True (@($explained.explanations).Count -gt 0)
    Assert-True (($explained.explanations.meaning -join ' ') -match 'not a prohibition')
    foreach ($item in $explained.explanations) {
        Assert-True ($item.documentation_url -match '^https://learn\.microsoft\.com/')
    }
    $json = (ConvertTo-PortDoctorJson -Report $explained) | ConvertFrom-Json
    Assert-True ($json.explanations -is [array])
    Assert-True ((ConvertTo-PortDoctorText -Report $explained) -match 'Explanation:')
}
Test-Case 'Explain ignores irrelevant private fields and handles unknown finding codes' {
    $evidence = New-TestEvidence; $evidence | Add-Member NoteProperty CommandLine 'PRIVATE_EXPLAIN_SENTINEL'
    $report = ConvertTo-PortDiagnostic -Port 8888 -Evidence $evidence
    $report.findings += [pscustomobject]@{ code = 'FUTURE_FINDING'; severity = 'info'; message = 'Observed test condition.' }
    $explained = Add-PortDoctorExplanation -Report $report
    Assert-True ((ConvertTo-PortDoctorJson -Report $explained) -notmatch 'PRIVATE_EXPLAIN_SENTINEL')
    $unknown = @($explained.explanations | Where-Object code -eq FUTURE_FINDING)[0]
    Assert-True ($unknown.meaning -match 'undetermined')
}
