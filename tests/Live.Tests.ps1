Test-Case 'Live TCP loopback listener is observed with its owning PID' {
    $listener = New-Object Net.Sockets.TcpListener([Net.IPAddress]::Loopback, 0)
    try {
        $listener.Start()
        $report = Get-PortDiagnostic -Port $listener.LocalEndpoint.Port -Protocol TCP -AddressFamily IPv4
        $observed = @($report.endpoints | Where-Object { $_.state -eq 'Listen' -and $_.process_id -eq $PID -and $_.address -eq '127.0.0.1' })
        Assert-True ($observed.Count -ge 1)
    } finally { $listener.Stop() }
}
Test-Case 'Live UDP loopback endpoint is observed and disposed' {
    $socket = New-Object Net.Sockets.UdpClient
    try {
        $socket.Client.Bind((New-Object Net.IPEndPoint([Net.IPAddress]::Loopback, 0)))
        $report = Get-PortDiagnostic -Port $socket.Client.LocalEndPoint.Port -Protocol UDP -AddressFamily IPv4
        Assert-True (@($report.endpoints | Where-Object { $_.protocol -eq 'UDP' -and $_.process_id -eq $PID }).Count -ge 1)
    } finally { $socket.Dispose() }
}
Test-Case 'Live CLI returns only a parseable JSON report and a truthful exit code' {
    $result = Invoke-TestCli '-Port 8888 -Protocol TCP -AddressFamily IPv4 -Format Json'
    Assert-True ($result.ExitCode -in @(0, 1)); Assert-Equal '' $result.Error
    $report = $result.Output | ConvertFrom-Json
    Assert-Equal 1 $report.schema_version; Assert-Equal 'live' $report.data_kind
    Assert-Equal 0 @($report.sources | Where-Object { $_.status -eq 'parse_error' }).Count 'Native netsh output must decode and parse on the test host.'
    $expectedExit = if ($report.completeness -eq 'complete') { 0 } else { 1 }
    Assert-Equal $expectedExit $result.ExitCode
}
Test-Case 'Live Explain CLI adds guidance to a valid JSON report' {
    $result = Invoke-TestCli '-Port 8888 -Protocol TCP -AddressFamily IPv4 -Format Json -Explain'
    Assert-True ($result.ExitCode -in @(0, 1)); Assert-Equal '' $result.Error
    $report = $result.Output | ConvertFrom-Json
    Assert-True ($report.explanations -is [array])
    Assert-True (@($report.explanations).Count -gt 0)
}
