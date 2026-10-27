function New-TestEvidence {
    $groups = @()
    foreach ($family in @('IPv4', 'IPv6')) { foreach ($transport in @('TCP', 'UDP')) {
        $groups += [pscustomobject]@{
            Family = $family; Protocol = $transport
            Excluded = [pscustomobject]@{ Status = 'ok'; Ranges = @(); ErrorCode = $null }
            Dynamic = [pscustomobject]@{ Status = 'ok'; Start = 49152; Count = 16384; End = 65535; ErrorCode = $null }
        }
    } }
    [pscustomobject]@{
        DataKind = 'synthetic'
        Tcp = [pscustomobject]@{ Status = 'ok'; Items = @(); ErrorCode = $null }
        Udp = [pscustomobject]@{ Status = 'ok'; Items = @(); ErrorCode = $null }
        Processes = [pscustomobject]@{ Status = 'ok'; Items = @(); ErrorCode = $null }
        Services = [pscustomobject]@{ Status = 'ok'; Items = @(); ErrorCode = $null }
        Ranges = $groups
        Registry = [pscustomobject]@{ Status = 'ok'; Value = 65534; Kind = 'DWord'; ErrorCode = $null }
    }
}
function New-TestEndpoint {
    param([string]$Address = '127.0.0.1', [string]$State = 'Listen', [int]$Owner = 100)
    [pscustomobject]@{ LocalPort = 8888; LocalAddress = $Address; State = $State; OwningProcess = $Owner }
}
function New-TestProcesses {
    @(
        [pscustomobject]@{ ProcessId = 100; ParentProcessId = 200; Name = 'python.exe'; CreationDate = [datetime]'2026-01-01T12:00:00Z' },
        [pscustomobject]@{ ProcessId = 200; ParentProcessId = 0; Name = 'launcher.exe'; CreationDate = [datetime]'2026-01-01T11:59:00Z' }
    )
}

Test-Case 'Empty complete evidence keeps arrays and an undetermined cause' {
    $report = ConvertTo-PortDiagnostic -Port 8888 -Evidence (New-TestEvidence)
    Assert-Equal 'complete' $report.completeness
    Assert-Equal 0 @($report.endpoints).Count
    Assert-Equal 4 @($report.ranges).Count
    Assert-Equal 13 @($report.sources).Count
    Assert-True (@($report.findings.code) -contains 'NO_MATCHING_ENDPOINT_OR_EXCLUSION')
    Assert-True (($report.findings.message -join ' ') -match 'cause remains undetermined')
}
Test-Case 'Dynamic membership alone is informational' {
    $report = ConvertTo-PortDiagnostic -Port 50000 -Evidence (New-TestEvidence)
    Assert-Equal 4 @($report.findings | Where-Object code -eq DYNAMIC_RANGE_MEMBER).Count
    Assert-Equal 0 @($report.findings | Where-Object code -eq EXCLUDED_RANGE).Count
    Assert-True (($report.findings.message -join ' ') -match 'not a bind prohibition')
    Assert-Equal 65534 $report.registry.max_user_port
}
Test-Case 'Matching exclusions remain distinct from dynamic allocation' {
    $evidence = New-TestEvidence
    $evidence.Ranges[0].Excluded.Ranges = @([pscustomobject]@{ Start = 8800; End = 8899; Administered = $true })
    $report = ConvertTo-PortDiagnostic -Port 8888 -Evidence $evidence
    Assert-Equal 1 @($report.findings | Where-Object code -eq EXCLUDED_RANGE).Count
    Assert-True $report.ranges[0].matching_excluded_ranges[0].administered
    Assert-Equal 0 @($report.findings | Where-Object code -eq NO_MATCHING_ENDPOINT_OR_EXCLUSION).Count
}
Test-Case 'Non-listening TCP states are retained without becoming listeners' {
    $evidence = New-TestEvidence
    $evidence.Tcp.Items = @('Bound', 'TimeWait', 'Established' | ForEach-Object { New-TestEndpoint -State $_ })
    $report = ConvertTo-PortDiagnostic -Port 8888 -Evidence $evidence
    Assert-Equal 3 @($report.endpoints).Count
    Assert-Equal 0 @($report.findings | Where-Object code -eq TCP_LISTENER).Count
    Assert-Equal 3 @($report.findings | Where-Object code -eq TCP_ENDPOINT).Count
}
Test-Case 'Protocol and address-family filters keep wildcard and loopback distinct' {
    $evidence = New-TestEvidence
    $evidence.Tcp.Items = @((New-TestEndpoint -Address '0.0.0.0'), (New-TestEndpoint -Address '::'), (New-TestEndpoint -Address '::1'))
    $evidence.Udp.Items = @((New-TestEndpoint -Address '127.0.0.1'))
    $report = ConvertTo-PortDiagnostic -Port 8888 -Evidence $evidence -Protocol TCP -AddressFamily IPv6
    Assert-Equal 2 @($report.endpoints).Count
    Assert-Equal 'wildcard' $report.endpoints[0].address_kind
    Assert-Equal 'loopback' $report.endpoints[1].address_kind
    Assert-Equal 1 @($report.ranges).Count
    $udp = ConvertTo-PortDiagnostic -Port 8888 -Evidence $evidence -Protocol UDP -AddressFamily IPv4
    Assert-Equal 1 @($udp.endpoints).Count
    Assert-Equal 'UDP_ENDPOINT' $udp.findings[0].code
}
Test-Case 'Partial and denied sources are not converted to complete empty evidence' {
    $evidence = New-TestEvidence
    $evidence.Tcp.Status = 'access_denied'; $evidence.Tcp.ErrorCode = 'tcp_collection_failed'
    $evidence.Ranges[0].Excluded.Status = 'parse_error'
    $report = ConvertTo-PortDiagnostic -Port 8888 -Evidence $evidence
    Assert-Equal 'partial' $report.completeness
    Assert-True (@($report.sources.status) -contains 'access_denied')
    Assert-True (@($report.findings.code) -contains 'PARTIAL_EVIDENCE')
}
Test-Case 'Missing netsh evidence cannot masquerade as complete collection' {
    $evidence = New-TestEvidence; $evidence.Ranges = @()
    $report = ConvertTo-PortDiagnostic -Port 8888 -Evidence $evidence
    Assert-Equal 'partial' $report.completeness
    Assert-Equal 4 @($report.ranges).Count
}
Test-Case 'Process ancestry uses creation times and handles missing parents' {
    $processes = @(New-TestProcesses)
    $chain = @(Resolve-PortProcessChain -ProcessId 100 -Processes $processes)
    Assert-Equal 2 $chain.Count; Assert-Equal 'launcher.exe' $chain[1].Name
    $processes[1].CreationDate = [datetime]'2026-01-01T12:01:00Z'
    $chain = @(Resolve-PortProcessChain -ProcessId 100 -Processes $processes)
    Assert-Equal 'pid_reused' $chain[1].Reason
    Assert-True (-not $chain[1].Verified); Assert-Equal $null $chain[1].Name
    $chain = @(Resolve-PortProcessChain -ProcessId 100 -Processes @($processes[0]))
    Assert-Equal 'not_observed' $chain[1].Reason
    $processes[1].CreationDate = $null
    $chain = @(Resolve-PortProcessChain -ProcessId 100 -Processes $processes)
    Assert-Equal 'creation_time_unknown' $chain[1].Reason
}
Test-Case 'Process ancestry terminates on cycles and caps long chains' {
    $processes = @(New-TestProcesses); $processes[1].ParentProcessId = 100
    $chain = @(Resolve-PortProcessChain -ProcessId 100 -Processes $processes)
    Assert-Equal 'cycle' $chain[2].Reason
    $many = @(1..8 | ForEach-Object { [pscustomobject]@{ ProcessId = $_; ParentProcessId = ($_ + 1); Name = 'test.exe'; CreationDate = [datetime]'2026-01-01' } })
    Assert-Equal 4 @(Resolve-PortProcessChain -ProcessId 1 -Processes $many).Count
}
Test-Case 'Nonpublic interface addresses and irrelevant private fields are suppressed' {
    $evidence = New-TestEvidence
    $evidence.Tcp.Items = @((New-TestEndpoint -Address '192.0.2.15'), (New-TestEndpoint -Address '192.0.2.15'), (New-TestEndpoint -Address '2001:db8::8'))
    $evidence.Processes.Items = @(New-TestProcesses)
    foreach ($object in @($evidence, $evidence.Tcp.Items[0], $evidence.Processes.Items[0], $evidence.Registry)) {
        foreach ($key in @('CommandLine', 'ExecutablePath', 'ComputerName', 'Username', 'ErrorMessage')) {
            $object | Add-Member NoteProperty $key 'PRIVATE_SENTINEL_DO_NOT_EXPORT'
        }
    }
    $report = ConvertTo-PortDiagnostic -Port 8888 -Evidence $evidence
    Assert-Equal 'IPv4-1' $report.endpoints[0].address
    Assert-Equal 'IPv4-1' $report.endpoints[1].address
    Assert-Equal 'IPv6-1' $report.endpoints[2].address
    $json = ConvertTo-PortDoctorJson -Report $report
    Assert-True ($json -notmatch 'PRIVATE_SENTINEL|192\.0\.2\.15|2001:db8::8|CommandLine|ExecutablePath|ComputerName|Username|ErrorMessage')
}
Test-Case 'WSL and Docker context does not assert exclusion ownership' {
    $evidence = New-TestEvidence
    $evidence.Services.Items = @([pscustomobject]@{ Name = 'hns'; State = 'Running' }, [pscustomobject]@{ Name = 'com.docker.service'; State = 'Stopped' })
    $report = ConvertTo-PortDiagnostic -Port 8888 -Evidence $evidence
    Assert-Equal 1 @($report.context.wsl_evidence).Count
    Assert-Equal 1 @($report.context.docker_evidence).Count
    Assert-True (($report.findings.message -join ' ') -match 'does not prove')
}
