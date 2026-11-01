#requires -version 5.1
[CmdletBinding()]
param(
    [string]$DistroName = 'opencae-workshop2026',
    [string]$ConfigPath
)
try {
    . "$PSScriptRoot/Common.ps1"
    if (!$ConfigPath) {
        Assert-Names $DistroName 'workshop'
        $ConfigPath = Join-Path $env:LOCALAPPDATA "OpenCAE\environments\$DistroName\environment.json"
    }
    $config = Read-Environment $ConfigPath
    if ($config.phase -ne 'Ready') { throw 'Setup is incomplete. Finish Setup.ps1 first.' }
    $ConfigPath = (Resolve-Path -LiteralPath $ConfigPath).ProviderPath
    $launchers = Join-Path (Split-Path -Parent $ConfigPath) 'launchers'
    [void][IO.Directory]::CreateDirectory($launchers)
    foreach ($file in @('Common.ps1','KiroLogin.ps1','StartBackend.ps1','StartCrew.ps1','StopCrew.ps1')) {
        $source = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot $file)).ProviderPath
        $target = Join-Path $launchers $file
        if ([IO.Path]::GetFullPath($source) -ine [IO.Path]::GetFullPath($target)) { Copy-Item -LiteralPath $source -Destination $target -Force }
    }
    New-CrewShortcuts $launchers $ConfigPath $config.distroName
    Remove-OwnedCrewShortcuts $launchers $ConfigPath $config.distroName -LegacyOnly
    Write-Host 'Launchers and desktop shortcuts refreshed. Docker and CFD setup was not run.'
} catch {
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}
