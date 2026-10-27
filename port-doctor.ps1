param(
    [string]$Port,
    [string]$Protocol = 'Both',
    [string]$AddressFamily = 'Both',
    [string]$Format = 'Text',
    [switch]$Help,
    [switch]$Explain
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2
if ($Help) {
    Write-Output 'Windows Port Doctor'
    Write-Output 'Usage: port-doctor.ps1 -Port <1-65535> [-Protocol TCP|UDP|Both] [-AddressFamily IPv4|IPv6|Both] [-Format Text|Json|Markdown] [-Explain]'
    exit 0
}
[int]$targetPort = 0
$protocols = @{ tcp = 'TCP'; udp = 'UDP'; both = 'Both' }
$families = @{ ipv4 = 'IPv4'; ipv6 = 'IPv6'; both = 'Both' }
$formats = @{ text = 'Text'; json = 'Json'; markdown = 'Markdown' }
if ([string]::IsNullOrWhiteSpace($Port) -or -not [int]::TryParse($Port, [ref]$targetPort) -or
    $targetPort -lt 1 -or $targetPort -gt 65535 -or
    [string]::IsNullOrWhiteSpace($Protocol) -or -not $protocols.ContainsKey($Protocol.ToLowerInvariant()) -or
    [string]::IsNullOrWhiteSpace($AddressFamily) -or -not $families.ContainsKey($AddressFamily.ToLowerInvariant()) -or
    [string]::IsNullOrWhiteSpace($Format) -or -not $formats.ContainsKey($Format.ToLowerInvariant())) {
    [Console]::Error.WriteLine('Invalid arguments. Use -Help for usage. Port must be an integer from 1 to 65535.')
    exit 2
}
try {
    Import-Module (Join-Path $PSScriptRoot 'src\PortDoctor.psm1') -Force
    Import-Module (Join-Path $PSScriptRoot 'src\Render.psm1') -Force
    $report = Get-PortDiagnostic -Port $targetPort -Protocol $protocols[$Protocol.ToLowerInvariant()] -AddressFamily $families[$AddressFamily.ToLowerInvariant()]
    if ($Explain) { $report = Add-PortDoctorExplanation -Report $report }
    if ($formats[$Format.ToLowerInvariant()] -eq 'Json') { Write-Output (ConvertTo-PortDoctorJson -Report $report) }
    elseif ($formats[$Format.ToLowerInvariant()] -eq 'Markdown') { Write-Output (ConvertTo-PortDoctorMarkdown -Report $report) }
    else { Write-Output (ConvertTo-PortDoctorText -Report $report) }
    if ($report.completeness -eq 'partial') { exit 1 }
    exit 0
} catch {
    [Console]::Error.WriteLine('Unable to build the diagnostic report. No application or service was stopped and no system setting was changed.')
    exit 1
}
