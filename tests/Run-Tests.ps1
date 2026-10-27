param([switch]$Live)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2
$script:Passed = 0
$script:Failed = 0
$root = Split-Path $PSScriptRoot -Parent

function Assert-True {
    param([bool]$Condition, [string]$Message = 'Expected true.')
    if (-not $Condition) { throw $Message }
}
function Assert-Equal {
    param($Expected, $Actual, [string]$Message = 'Values differ.')
    if ($Expected -ne $Actual) { throw ($Message + ' Expected: ' + $Expected + '; actual: ' + $Actual) }
}
function Test-Case {
    param([string]$Name, [scriptblock]$Body)
    try { & $Body; $script:Passed++; Write-Host ('PASS ' + $Name) }
    catch { $script:Failed++; Write-Host ('FAIL ' + $Name + ': ' + $_.Exception.Message) }
}

try {
    Import-Module (Join-Path $root 'src\Netsh.psm1') -Force
    Import-Module (Join-Path $root 'src\PortDoctor.psm1') -Force
    Import-Module (Join-Path $root 'src\Render.psm1') -Force
    foreach ($file in @('Parser.Tests.ps1', 'Core.Tests.ps1', 'Render.Tests.ps1', 'Cli.Tests.ps1')) {
        . (Join-Path $PSScriptRoot $file)
    }
    if ($Live) { . (Join-Path $PSScriptRoot 'Live.Tests.ps1') }
} catch {
    $script:Failed++
    Write-Host ('FAIL test setup: ' + $_.Exception.Message)
}
Write-Host ('Tests: ' + $script:Passed + ' passed, ' + $script:Failed + ' failed.')
if ($script:Failed -gt 0) { exit 1 }
exit 0
