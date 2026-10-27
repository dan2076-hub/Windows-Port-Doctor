function Invoke-TestCli {
    param([string]$Arguments)
    $info = New-Object Diagnostics.ProcessStartInfo
    $info.FileName = (Get-Process -Id $PID).Path
    $info.Arguments = '-NoProfile -ExecutionPolicy Bypass -File "' + (Join-Path $root 'port-doctor.ps1') + '" ' + $Arguments
    $info.UseShellExecute = $false; $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true; $info.RedirectStandardError = $true
    $process = New-Object Diagnostics.Process; $process.StartInfo = $info
    try {
        $null = $process.Start()
        $stdout = $process.StandardOutput.ReadToEndAsync(); $stderr = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(60000)) { $process.Kill(); throw 'CLI test exceeded its timeout.' }
        [pscustomobject]@{ ExitCode = $process.ExitCode; Output = $stdout.GetAwaiter().GetResult(); Error = $stderr.GetAwaiter().GetResult() }
    } finally { $process.Dispose() }
}
Test-Case 'CLI help is noninteractive and does not collect evidence' {
    $result = Invoke-TestCli '-Help'
    Assert-Equal 0 $result.ExitCode; Assert-True ($result.Output -match 'Usage:')
    Assert-Equal '' $result.Error
}
Test-Case 'CLI rejects missing, nonnumeric, out-of-range and unsupported arguments' {
    foreach ($arguments in @('', '-Port abc', '-Port 0', '-Port 65536', '-Port 1.5', '-Port 80 -Protocol SCTP', '-Port 80 -AddressFamily IPX', '-Port 80 -Format XML')) {
        $result = Invoke-TestCli $arguments
        Assert-Equal 2 $result.ExitCode $arguments
        Assert-Equal '' $result.Output
        Assert-True ($result.Error -match 'Invalid arguments')
    }
}
