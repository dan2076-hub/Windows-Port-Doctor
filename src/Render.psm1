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
    $lines.Add(''); $lines.Add('Bind availability was not tested. No application or service was stopped and no system setting was changed.')
    $lines -join [Environment]::NewLine
}

function ConvertTo-PortDoctorJson {
    [CmdletBinding()]
    param($Report)
    ConvertTo-Json -InputObject $Report -Depth 20
}

Export-ModuleMember -Function ConvertTo-PortDoctorText, ConvertTo-PortDoctorJson
