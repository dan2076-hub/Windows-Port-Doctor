Set-StrictMode -Version 2

function ConvertTo-PortDoctorText {
    [CmdletBinding()]
    param($Report)
    $lines = New-Object 'Collections.Generic.List[string]'
    $lines.Add('Windows Port Doctor ' + $Report.tool.version)
    $lines.Add('Port: ' + $Report.request.port + ' | Protocol: ' + $Report.request.protocol + ' | Address family: ' + $Report.request.address_family)
    $lines.Add('Collection: ' + $Report.completeness + ' | Data: ' + $Report.data_kind)
    $lines.Add('')
    foreach ($finding in @($Report.findings)) { $lines.Add('[' + $finding.code + '] ' + $finding.message) }
    if (@($Report.endpoints).Count -gt 0) {
        $lines.Add(''); $lines.Add('Processes (observed snapshot):')
        foreach ($endpoint in @($Report.endpoints)) {
            $parts = @($endpoint.process_chain | ForEach-Object {
                if ($_.verified) { [string]$_.name + ' (' + $_.process_id + ')' }
                else { 'unknown (' + $_.process_id + '; ' + $_.reason + ')' }
            })
            $lines.Add('  ' + $endpoint.protocol + ' ' + $endpoint.address_family + ' ' + $endpoint.address + ' ' + $endpoint.state + ': ' + ($parts -join ' <- '))
        }
    }
    $lines.Add(''); $lines.Add('Port ranges:')
    foreach ($range in @($Report.ranges)) {
        $description = '  ' + $range.address_family + ' ' + $range.protocol + ': excluded=' + $range.excluded_status
        if ($null -ne $range.dynamic) { $description += '; dynamic=' + $range.dynamic.start + '-' + $range.dynamic.end }
        else { $description += '; dynamic=' + $range.dynamic_status }
        $lines.Add($description)
    }
    $registryValue = if ($null -eq $Report.registry.max_user_port) { 'not observed' } else { [string]$Report.registry.max_user_port }
    $lines.Add('MaxUserPort: ' + $registryValue + ' (registry context; active dynamic ranges are listed above)')
    $lines.Add(''); $lines.Add('Evidence sources:')
    foreach ($source in @($Report.sources)) { $lines.Add('  ' + $source.id + ': ' + $source.status) }
    if ($null -ne $Report.PSObject.Properties['explanations']) {
        foreach ($item in @($Report.explanations)) {
            $lines.Add(''); $lines.Add('Explanation: ' + $item.code)
            $lines.Add($item.meaning); $lines.Add('Next: ' + $item.next_steps)
            $lines.Add('Reference: ' + $item.documentation_url)
        }
    }
    $lines.Add(''); $lines.Add('Bind availability was not tested. No application or service was stopped and no system setting was changed.')
    $lines -join [Environment]::NewLine
}

function ConvertTo-PortDoctorJson {
    [CmdletBinding()]
    param($Report)
    ConvertTo-Json -InputObject $Report -Depth 20
}

function Add-PortDoctorExplanation {
    [CmdletBinding()]
    param($Report)
    $network = 'https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/netsh-interface'
    $tcp = 'https://learn.microsoft.com/en-us/powershell/module/nettcpip/get-nettcpconnection'
    $sockets = 'https://learn.microsoft.com/en-us/windows/win32/winsock/windows-sockets-error-codes-2'
    $guidance = @{
        TCP_LISTENER = @('A TCP listener was observed at collection time. Wildcard and dual-stack behavior depends on socket options.', 'Identify the displayed process and check the exact address requested by your application.', $tcp)
        TCP_ENDPOINT = @('A non-listening TCP endpoint still carries state; absence of Listen does not prove the port is available.', 'Compare the endpoint state and owning PID with the application socket error.', $tcp)
        UDP_ENDPOINT = @('A UDP endpoint was observed. TCP and UDP use separate transport namespaces.', 'Check the UDP bind address and sharing options used by the application.', 'https://learn.microsoft.com/en-us/powershell/module/nettcpip/get-netudpendpoint')
        EXCLUDED_RANGE = @('Windows reports an excluded range containing this port. Its administrator marker does not identify an owner.', 'Compare IPv4/IPv6 and TCP/UDP exclusions. Do not delete exclusions without understanding their consumers.', $network)
        DYNAMIC_RANGE_MEMBER = @('Membership in the dynamic client-port allocation range is not a prohibition on binding a server socket.', 'Use endpoint and exclusion findings together with the exact bind error; do not change the dynamic range based on membership alone.', $network)
        WSL_OBSERVED = @('Visible WSL or virtual-network services are context, not evidence that they created an exclusion.', 'Check whether a relevant workload actually needs the port before changing any service.', $network)
        DOCKER_OBSERVED = @('Visible Docker components do not establish that Docker caused the failure.', 'Compare the application error with any known published container port; the tool does not start Docker.', $network)
        PARTIAL_EVIDENCE = @('At least one requested source could not be collected or parsed. A missing result is not an empty result.', 'Inspect source statuses. If authorized, compare a read-only run from an elevated shell.', $tcp)
        NO_MATCHING_ENDPOINT_OR_EXCLUSION = @('The collected data did not explain a bind failure. The cause remains undetermined, even after complete collection.', 'Obtain the exact socket error and requested bind address. Permissions, timing and socket options can also matter.', $sockets)
    }
    $items = @()
    foreach ($code in @($Report.findings.code | Select-Object -Unique)) {
        $value = $guidance[$code]
        if ($null -eq $value) { $value = @('This finding has no built-in explanation; its cause remains undetermined.', 'Review the observed finding and application socket error.', $sockets) }
        $items += [pscustomobject]@{ code = $code; meaning = $value[0]; next_steps = $value[1]; documentation_url = $value[2] }
    }
    $copy = $Report.PSObject.Copy()
    $copy | Add-Member -MemberType NoteProperty -Name explanations -Value @($items) -Force
    $copy
}

function ConvertTo-MarkdownCell {
    param($Value)
    if ($null -eq $Value) { return 'unknown' }
    $text = [string]$Value
    $text = $text.Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;')
    $text = $text.Replace('|', '&#124;').Replace('`', '&#96;').Replace('\', '&#92;')
    $text = $text.Replace('*', '&#42;').Replace('_', '&#95;').Replace('[', '&#91;').Replace(']', '&#93;')
    $text -replace '\r\n|\r|\n', '<br>'
}

function ConvertTo-PortDoctorMarkdown {
    [CmdletBinding()]
    param($Report)
    $lines = New-Object 'Collections.Generic.List[string]'
    $lines.Add('# Windows Port Doctor')
    $lines.Add('')
    $lines.Add('Port **' + $Report.request.port + '** | ' + $Report.request.protocol + ' | ' + $Report.request.address_family)
    $lines.Add('')
    $lines.Add('Collection: **' + $Report.completeness + '**. Data: ' + $Report.data_kind + '. Snapshot: ' + $Report.generated_at_utc + '.')
    $lines.Add(''); $lines.Add('## Findings'); $lines.Add('')
    foreach ($finding in @($Report.findings)) { $lines.Add('- **' + (ConvertTo-MarkdownCell $finding.code) + '**: ' + (ConvertTo-MarkdownCell $finding.message)) }
    $lines.Add(''); $lines.Add('## Endpoints'); $lines.Add('')
    if (@($Report.endpoints).Count -eq 0) { $lines.Add('No matching endpoints in the collected data; this is not a bind guarantee.') }
    else {
        $lines.Add('| Protocol | Family | Address | State | Process chain (child to parent) |')
        $lines.Add('| --- | --- | --- | --- | --- |')
        foreach ($endpoint in @($Report.endpoints)) {
            $chain = @($endpoint.process_chain | ForEach-Object {
                if ($_.verified) { [string]$_.name + ' (' + $_.process_id + ')' }
                else { 'unknown (' + $_.process_id + '; ' + $_.reason + ')' }
            }) -join ' <- '
            $cells = @($endpoint.protocol, $endpoint.address_family, $endpoint.address, $endpoint.state, $chain) | ForEach-Object { ConvertTo-MarkdownCell $_ }
            $lines.Add('| ' + ($cells -join ' | ') + ' |')
        }
    }
    $lines.Add(''); $lines.Add('## Ranges and registry context'); $lines.Add('')
    $lines.Add('| Family | Protocol | Exclusion collection | Matching exclusions | Dynamic range |')
    $lines.Add('| --- | --- | --- | --- | --- |')
    foreach ($range in @($Report.ranges)) {
        $excluded = @($range.matching_excluded_ranges | ForEach-Object { [string]$_.start + '-' + $_.end + $(if ($_.administered) { ' (administered)' } else { '' }) }) -join ', '
        if ($excluded -eq '') { $excluded = 'None observed' }
        $dynamic = if ($null -eq $range.dynamic) { $range.dynamic_status } else { [string]$range.dynamic.start + '-' + $range.dynamic.end }
        $cells = @($range.address_family, $range.protocol, $range.excluded_status, $excluded, $dynamic) | ForEach-Object { ConvertTo-MarkdownCell $_ }
        $lines.Add('| ' + ($cells -join ' | ') + ' |')
    }
    $lines.Add('')
    $lines.Add('MaxUserPort: ' + (ConvertTo-MarkdownCell $Report.registry.max_user_port) + ' (registry context, not a replacement for the active dynamic range).')
    $lines.Add(''); $lines.Add('## Evidence sources'); $lines.Add('')
    $lines.Add('| Source | Status | Error category |'); $lines.Add('| --- | --- | --- |')
    foreach ($source in @($Report.sources)) {
        $cells = @($source.id, $source.status, $source.error_code) | ForEach-Object { ConvertTo-MarkdownCell $_ }
        $lines.Add('| ' + ($cells -join ' | ') + ' |')
    }
    if ($null -ne $Report.PSObject.Properties['explanations']) {
        $lines.Add(''); $lines.Add('## Explanations'); $lines.Add('')
        foreach ($item in @($Report.explanations)) {
            $lines.Add('### ' + (ConvertTo-MarkdownCell $item.code)); $lines.Add('')
            $lines.Add((ConvertTo-MarkdownCell $item.meaning)); $lines.Add('')
            $lines.Add('Next: ' + (ConvertTo-MarkdownCell $item.next_steps)); $lines.Add('')
            $lines.Add('Reference: ' + (ConvertTo-MarkdownCell $item.documentation_url)); $lines.Add('')
        }
    }
    $lines.Add('')
    $lines.Add('Bind availability was not tested. No application or service was stopped and no system setting was changed.')
    $lines -join [Environment]::NewLine
}

Export-ModuleMember -Function ConvertTo-PortDoctorText, ConvertTo-PortDoctorJson, Add-PortDoctorExplanation, ConvertTo-PortDoctorMarkdown
