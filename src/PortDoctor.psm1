Set-StrictMode -Version 2
Import-Module (Join-Path $PSScriptRoot 'Netsh.psm1')
$script:ToolVersion = '0.1.0'

function Get-Field {
    param($Object, [string]$Name, $Default = $null)
    if ($null -eq $Object) { return $Default }
    if ($Object -is [Collections.IDictionary]) {
        if ($Object.Contains($Name)) { return $Object[$Name] }
    } elseif ($null -ne $Object.PSObject.Properties[$Name]) { return $Object.$Name }
    return $Default
}

function New-Collection {
    param([string]$Status = 'ok', [object[]]$Items = @(), $ErrorCode = $null)
    [pscustomobject]@{ Status = $Status; Items = @($Items); ErrorCode = $ErrorCode }
}

function Get-ErrorCategory {
    param($Record)
    $exception = $Record.Exception
    if ($exception -is [UnauthorizedAccessException] -or
        [string]$Record.CategoryInfo.Category -eq 'PermissionDenied' -or
        $exception.HResult -in @(-2147024891, -2147217405)) { return 'access_denied' }
    if ($exception -is [Management.Automation.CommandNotFoundException]) { return 'unavailable' }
    return 'error'
}

function Resolve-PortProcessChain {
    [CmdletBinding()]
    param([int]$ProcessId, [AllowEmptyCollection()][object[]]$Processes = @())
    $nodes = New-Object 'Collections.Generic.List[object]'
    $seen = @{}
    $currentId = $ProcessId
    $childCreated = $null
    for ($depth = 0; $depth -lt 4; $depth++) {
        if ($seen.ContainsKey($currentId)) {
            $nodes.Add([pscustomobject]@{ ProcessId = $currentId; Name = $null; Verified = $false; Reason = 'cycle' })
            break
        }
        $seen[$currentId] = $true
        $matches = @($Processes | Where-Object { (Get-Field $_ 'ProcessId' -1) -eq $currentId })
        if ($matches.Count -ne 1) {
            $nodes.Add([pscustomobject]@{ ProcessId = $currentId; Name = $null; Verified = $false; Reason = 'not_observed' })
            break
        }
        $process = $matches[0]
        $created = $null
        $creationValue = Get-Field $process 'CreationDate'
        if ($null -ne $creationValue) { try { $created = ([datetime]$creationValue).ToUniversalTime() } catch { $created = $null } }
        if ($depth -gt 0) {
            if ($null -eq $created -or $null -eq $childCreated) {
                $nodes.Add([pscustomobject]@{ ProcessId = $currentId; Name = $null; Verified = $false; Reason = 'creation_time_unknown' })
                break
            }
            if ($created -gt $childCreated) {
                $nodes.Add([pscustomobject]@{ ProcessId = $currentId; Name = $null; Verified = $false; Reason = 'pid_reused' })
                break
            }
        }
        $nodes.Add([pscustomobject]@{ ProcessId = $currentId; Name = [string](Get-Field $process 'Name'); Verified = $true; Reason = 'observed' })
        $parent = Get-Field $process 'ParentProcessId'
        if ($null -eq $parent -or [int]$parent -eq 0) { break }
        $childCreated = $created
        $currentId = [int]$parent
    }
    $nodes.ToArray()
}

function Invoke-PortNetsh {
    param([string]$Family, [string]$Protocol, [string]$Kind)
    $executable = Join-Path $env:SystemRoot 'System32\netsh.exe'
    if (-not (Test-Path -LiteralPath $executable -PathType Leaf)) {
        return [pscustomobject]@{ Status = 'unavailable'; Text = ''; ExitCode = -1; ErrorCode = 'netsh_unavailable' }
    }
    $info = New-Object Diagnostics.ProcessStartInfo
    $info.FileName = $executable
    if ($Kind -eq 'excluded') { $info.Arguments = 'interface ' + $Family.ToLowerInvariant() + ' show excludedportrange protocol=' + $Protocol.ToLowerInvariant() }
    else { $info.Arguments = 'interface ' + $Family.ToLowerInvariant() + ' show dynamicportrange protocol=' + $Protocol.ToLowerInvariant() }
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    # Native Windows utilities use the system OEM code page when redirected.
    # The hosting terminal may use UTF-8, so its encoding is not authoritative.
    try {
        $oemCodePage = [int][Microsoft.Win32.Registry]::GetValue('HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Nls\CodePage', 'OEMCP', [Globalization.CultureInfo]::InstalledUICulture.TextInfo.OEMCodePage)
        $info.StandardOutputEncoding = [Text.Encoding]::GetEncoding($oemCodePage)
        $info.StandardErrorEncoding = $info.StandardOutputEncoding
    } catch {
        return [pscustomobject]@{ Status = 'error'; Text = ''; ExitCode = -1; ErrorCode = 'query_encoding_unavailable' }
    }
    $process = New-Object Diagnostics.Process
    $process.StartInfo = $info
    try {
        $null = $process.Start()
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(10000)) {
            # Only the read-only query created by this function is cancelled.
            $process.Kill()
            $process.WaitForExit()
            return [pscustomobject]@{ Status = 'error'; Text = ''; ExitCode = -1; ErrorCode = 'query_timeout' }
        }
        $text = $stdout.GetAwaiter().GetResult()
        $null = $stderr.GetAwaiter().GetResult()
        return [pscustomobject]@{ Status = 'ok'; Text = $text; ExitCode = $process.ExitCode; ErrorCode = $null }
    } catch {
        return [pscustomobject]@{ Status = (Get-ErrorCategory $_); Text = ''; ExitCode = -1; ErrorCode = 'query_failed' }
    } finally { $process.Dispose() }
}

function Get-PortEvidence {
    param([string]$Protocol, [string]$AddressFamily)
    $tcp = New-Collection
    $udp = New-Collection
    if ($Protocol -in @('TCP', 'Both')) {
        try { $tcp = New-Collection -Items @(Get-NetTCPConnection -ErrorAction Stop | Select-Object LocalPort, LocalAddress, State, OwningProcess) }
        catch { $tcp = New-Collection -Status (Get-ErrorCategory $_) -ErrorCode 'tcp_collection_failed' }
    }
    if ($Protocol -in @('UDP', 'Both')) {
        try { $udp = New-Collection -Items @(Get-NetUDPEndpoint -ErrorAction Stop | Select-Object LocalPort, LocalAddress, OwningProcess) }
        catch { $udp = New-Collection -Status (Get-ErrorCategory $_) -ErrorCode 'udp_collection_failed' }
    }
    try {
        $processes = New-Collection -Items @(Get-CimInstance Win32_Process -Property ProcessId, ParentProcessId, Name, CreationDate -OperationTimeoutSec 5 -ErrorAction Stop |
            Select-Object ProcessId, ParentProcessId, Name, CreationDate)
    } catch { $processes = New-Collection -Status (Get-ErrorCategory $_) -ErrorCode 'process_collection_failed' }
    try {
        $services = New-Collection -Items @(Get-CimInstance Win32_Service -Filter "Name='hns' OR Name='WinNat' OR Name='WslService' OR Name='LxssManager' OR Name='com.docker.service'" -Property Name, State -OperationTimeoutSec 5 -ErrorAction Stop |
            Select-Object Name, State)
    } catch { $services = New-Collection -Status (Get-ErrorCategory $_) -ErrorCode 'service_collection_failed' }
    $families = @('IPv4', 'IPv6')
    if ($AddressFamily -ne 'Both') { $families = @($AddressFamily) }
    $protocols = @('TCP', 'UDP')
    if ($Protocol -ne 'Both') { $protocols = @($Protocol) }
    $ranges = @()
    foreach ($family in $families) { foreach ($transport in $protocols) {
        $excludedRaw = Invoke-PortNetsh -Family $family -Protocol $transport -Kind excluded
        $dynamicRaw = Invoke-PortNetsh -Family $family -Protocol $transport -Kind dynamic
        $excluded = ConvertFrom-ExcludedPortRanges -Text $excludedRaw.Text -ExitCode $excludedRaw.ExitCode
        $dynamic = ConvertFrom-DynamicPortRange -Text $dynamicRaw.Text -ExitCode $dynamicRaw.ExitCode
        if ($excludedRaw.Status -ne 'ok') { $excluded.Status = $excludedRaw.Status; $excluded.ErrorCode = $excludedRaw.ErrorCode }
        if ($dynamicRaw.Status -ne 'ok') { $dynamic.Status = $dynamicRaw.Status; $dynamic.ErrorCode = $dynamicRaw.ErrorCode }
        $ranges += [pscustomobject]@{ Family = $family; Protocol = $transport; Excluded = $excluded; Dynamic = $dynamic }
    } }
    $key = $null
    $registry = [pscustomobject]@{ Status = 'ok'; Value = $null; Kind = 'missing'; ErrorCode = $null }
    try {
        $key = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey('SYSTEM\CurrentControlSet\Services\Tcpip\Parameters', $false)
        if ($null -eq $key) { $registry.Status = 'unavailable'; $registry.ErrorCode = 'registry_key_unavailable' }
        elseif ($key.GetValueNames() -contains 'MaxUserPort') {
            $kind = [string]$key.GetValueKind('MaxUserPort')
            if ($kind -eq 'DWord') { $registry.Value = [long]$key.GetValue('MaxUserPort'); $registry.Kind = 'DWord' }
            else { $registry.Status = 'error'; $registry.Kind = 'unsupported'; $registry.ErrorCode = 'unexpected_registry_type' }
        }
    } catch { $registry.Status = Get-ErrorCategory $_; $registry.ErrorCode = 'registry_read_failed' }
    finally { if ($null -ne $key) { $key.Dispose() } }
    [pscustomobject]@{ DataKind = 'live'; Tcp = $tcp; Udp = $udp; Processes = $processes; Services = $services; Ranges = @($ranges); Registry = $registry }
}

function ConvertTo-PortDiagnostic {
    [CmdletBinding()]
    param([ValidateRange(1, 65535)][int]$Port, $Evidence, [string]$Protocol = 'Both', [string]$AddressFamily = 'Both')
    $sources = New-Object 'Collections.Generic.List[object]'
    $endpoints = New-Object 'Collections.Generic.List[object]'
    $findings = New-Object 'Collections.Generic.List[object]'
    $rangeReports = New-Object 'Collections.Generic.List[object]'
    $labels = @{}
    $addressCounts = @{ IPv4 = 0; IPv6 = 0 }
    $processSource = Get-Field $Evidence 'Processes'
    $processes = @(Get-Field $processSource 'Items' @())
    foreach ($sourceName in @('Processes', 'Services', 'Registry')) {
        $source = Get-Field $Evidence $sourceName
        $sources.Add([pscustomobject]@{ id = $sourceName.ToLowerInvariant(); status = (Get-Field $source 'Status' 'unavailable'); error_code = (Get-Field $source 'ErrorCode') })
    }
    foreach ($transport in @('TCP', 'UDP')) {
        if ($Protocol -ne 'Both' -and $transport -ne $Protocol) { continue }
        $source = Get-Field $Evidence $(if ($transport -eq 'TCP') { 'Tcp' } else { 'Udp' })
        $sources.Add([pscustomobject]@{ id = ($transport.ToLowerInvariant() + '_endpoints'); status = (Get-Field $source 'Status' 'unavailable'); error_code = (Get-Field $source 'ErrorCode') })
        foreach ($item in @(Get-Field $source 'Items' @())) {
            if ((Get-Field $item 'LocalPort' -1) -ne $Port) { continue }
            $ip = $null
            if (-not [Net.IPAddress]::TryParse([string](Get-Field $item 'LocalAddress'), [ref]$ip)) { continue }
            $family = if ($ip.AddressFamily -eq [Net.Sockets.AddressFamily]::InterNetwork) { 'IPv4' } else { 'IPv6' }
            if ($AddressFamily -ne 'Both' -and $family -ne $AddressFamily) { continue }
            $canonical = $ip.ToString()
            $kind = 'interface'
            if ([Net.IPAddress]::IsLoopback($ip)) { $kind = 'loopback'; $display = $canonical }
            elseif ($canonical -in @('0.0.0.0', '::')) { $kind = 'wildcard'; $display = $canonical }
            else {
                if (-not $labels.ContainsKey($canonical)) { $addressCounts[$family]++; $labels[$canonical] = $family + '-' + $addressCounts[$family] }
                $display = $labels[$canonical]
            }
            $ownerId = [int](Get-Field $item 'OwningProcess' 0)
            $chain = @(Resolve-PortProcessChain -ProcessId $ownerId -Processes $processes)
            $processName = if ($chain.Count -gt 0) { $chain[0].Name } else { $null }
            $state = if ($transport -eq 'TCP') { [string](Get-Field $item 'State' 'Unknown') } else { 'Endpoint' }
            $publicChain = @($chain | ForEach-Object { [pscustomobject]@{ process_id = $_.ProcessId; name = $_.Name; verified = $_.Verified; reason = $_.Reason } })
            $endpoints.Add([pscustomobject]@{ protocol = $transport; address_family = $family; address = $display; address_kind = $kind; state = $state; process_id = $ownerId; process_name = $processName; process_chain = @($publicChain) })
            $code = if ($transport -eq 'UDP') { 'UDP_ENDPOINT' } elseif ($state -eq 'Listen') { 'TCP_LISTENER' } else { 'TCP_ENDPOINT' }
            $findings.Add([pscustomobject]@{ code = $code; severity = 'info'; message = ($transport + ' ' + $state + ' observed on ' + $display + ':' + $Port + ' (PID ' + $ownerId + ').') })
        }
    }
    $matchingExcluded = 0
    $expectedGroups = @()
    foreach ($family in @('IPv4', 'IPv6')) { foreach ($transport in @('TCP', 'UDP')) {
        if ($Protocol -ne 'Both' -and $transport -ne $Protocol) { continue }
        if ($AddressFamily -ne 'Both' -and $family -ne $AddressFamily) { continue }
        $observedGroups = @(Get-Field $Evidence 'Ranges' @() | Where-Object { $_.Family -eq $family -and $_.Protocol -eq $transport })
        if ($observedGroups.Count -eq 1) { $expectedGroups += $observedGroups[0] }
        else {
            $expectedGroups += [pscustomobject]@{
                Family = $family; Protocol = $transport
                Excluded = [pscustomobject]@{ Status = 'unavailable'; Ranges = @(); ErrorCode = 'range_evidence_missing_or_ambiguous' }
                Dynamic = [pscustomobject]@{ Status = 'unavailable'; ErrorCode = 'range_evidence_missing_or_ambiguous' }
            }
        }
    } }
    foreach ($group in $expectedGroups) {
        $prefix = $group.Family.ToLowerInvariant() + '_' + $group.Protocol.ToLowerInvariant()
        foreach ($kind in @('Excluded', 'Dynamic')) {
            $source = $group.$kind
            $sources.Add([pscustomobject]@{ id = ($prefix + '_' + $kind.ToLowerInvariant()); status = $source.Status; error_code = $source.ErrorCode })
        }
        $matches = @()
        if ($group.Excluded.Status -eq 'ok') {
            foreach ($range in @($group.Excluded.Ranges)) { if ($Port -ge $range.Start -and $Port -le $range.End) {
                $matches += [pscustomobject]@{ start = $range.Start; end = $range.End; administered = [bool]$range.Administered }
                $matchingExcluded++
                $findings.Add([pscustomobject]@{ code = 'EXCLUDED_RANGE'; severity = 'notice'; message = ('Port appears in an excluded ' + $group.Family + ' ' + $group.Protocol + ' range ' + $range.Start + '-' + $range.End + '. Ownership and bind availability are not established.') })
            } }
        }
        $dynamic = $null
        if ($group.Dynamic.Status -eq 'ok') {
            $inside = $Port -ge $group.Dynamic.Start -and $Port -le $group.Dynamic.End
            $dynamic = [pscustomobject]@{ start = $group.Dynamic.Start; count = $group.Dynamic.Count; end = $group.Dynamic.End; contains_port = [bool]$inside }
            if ($inside) { $findings.Add([pscustomobject]@{ code = 'DYNAMIC_RANGE_MEMBER'; severity = 'info'; message = ('Port is in the ' + $group.Family + ' ' + $group.Protocol + ' dynamic range. This is informational, not a bind prohibition.') }) }
        }
        $rangeReports.Add([pscustomobject]@{ address_family = $group.Family; protocol = $group.Protocol; excluded_status = $group.Excluded.Status; observed_excluded_range_count = @($group.Excluded.Ranges).Count; matching_excluded_ranges = @($matches); dynamic_status = $group.Dynamic.Status; dynamic = $dynamic })
    }
    $wsl = @(); $docker = @()
    foreach ($process in $processes) {
        $name = [string](Get-Field $process 'Name')
        if ($name -match '^(wsl|wslhost|wslservice|vmmemWSL|vmmem)\.exe$') { $wsl += [pscustomobject]@{ kind = 'process'; name = $name } }
        if ($name -match '^(Docker Desktop|com\.docker\.backend)\.exe$') { $docker += [pscustomobject]@{ kind = 'process'; name = $name } }
    }
    foreach ($service in @(Get-Field (Get-Field $Evidence 'Services') 'Items' @())) {
        $name = [string](Get-Field $service 'Name')
        if ($name -in @('hns', 'WinNat', 'WslService', 'LxssManager')) { $wsl += [pscustomobject]@{ kind = 'service'; name = $name; state = [string](Get-Field $service 'State' 'Unknown') } }
        if ($name -eq 'com.docker.service') { $docker += [pscustomobject]@{ kind = 'service'; name = $name; state = [string](Get-Field $service 'State' 'Unknown') } }
    }
    if ($wsl.Count -gt 0) { $findings.Add([pscustomobject]@{ code = 'WSL_OBSERVED'; severity = 'info'; message = 'WSL/virtual networking components were observed; this does not prove that a distribution is running or that WSL owns an exclusion.' }) }
    if ($docker.Count -gt 0) { $findings.Add([pscustomobject]@{ code = 'DOCKER_OBSERVED'; severity = 'info'; message = 'Docker components were observed; their presence does not establish the cause of a bind failure.' }) }
    $partial = @($sources.ToArray() | Where-Object { $_.status -ne 'ok' }).Count -gt 0
    if ($partial) { $findings.Add([pscustomobject]@{ code = 'PARTIAL_EVIDENCE'; severity = 'notice'; message = 'Some requested evidence is unavailable. Missing data must not be interpreted as an empty result.' }) }
    if ($endpoints.Count -eq 0 -and $matchingExcluded -eq 0) { $findings.Add([pscustomobject]@{ code = 'NO_MATCHING_ENDPOINT_OR_EXCLUSION'; severity = 'info'; message = 'No matching endpoint or excluded range was found in the collected data. Bind availability was not tested; the cause remains undetermined.' }) }
    $registry = Get-Field $Evidence 'Registry'
    [pscustomobject][ordered]@{
        schema_version = 1
        tool = [pscustomobject]@{ name = 'Windows Port Doctor'; version = $script:ToolVersion }
        generated_at_utc = [datetime]::UtcNow.ToString('o')
        data_kind = [string](Get-Field $Evidence 'DataKind' 'synthetic')
        request = [pscustomobject]@{ port = $Port; protocol = $Protocol; address_family = $AddressFamily }
        completeness = $(if ($partial) { 'partial' } else { 'complete' })
        sources = @($sources.ToArray())
        endpoints = @($endpoints.ToArray())
        ranges = @($rangeReports.ToArray())
        registry = [pscustomobject]@{ status = (Get-Field $registry 'Status' 'unavailable'); max_user_port = (Get-Field $registry 'Value'); kind = (Get-Field $registry 'Kind' 'unknown') }
        context = [pscustomobject]@{ wsl_evidence = @($wsl); docker_evidence = @($docker) }
        findings = @($findings.ToArray())
    }
}

function Get-PortDiagnostic {
    [CmdletBinding()]
    param([ValidateRange(1, 65535)][int]$Port, [ValidateSet('TCP', 'UDP', 'Both')][string]$Protocol = 'Both', [ValidateSet('IPv4', 'IPv6', 'Both')][string]$AddressFamily = 'Both')
    if ($env:OS -ne 'Windows_NT') { throw 'Windows Port Doctor requires Windows.' }
    $evidence = Get-PortEvidence -Protocol $Protocol -AddressFamily $AddressFamily
    ConvertTo-PortDiagnostic -Port $Port -Evidence $evidence -Protocol $Protocol -AddressFamily $AddressFamily
}

Export-ModuleMember -Function Get-PortDiagnostic, ConvertTo-PortDiagnostic, Resolve-PortProcessChain
