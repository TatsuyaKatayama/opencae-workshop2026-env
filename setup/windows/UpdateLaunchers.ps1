#requires -version 5.1
[CmdletBinding()]
param(
    [string]$DistroName = 'opencae-workshop2026',
    [string]$InstallLocation,
    [string]$ConfigPath
)
try {
    . "$PSScriptRoot/Common.ps1"
    if (!$InstallLocation -and !$ConfigPath) {
        $registration = Get-WslRegistration $DistroName
        if ($registration) { $InstallLocation = $registration.BasePath -replace '^\\\\\?\\', '' }
    }
    if (!$ConfigPath) { $ConfigPath = Find-EnvironmentConfig $DistroName $InstallLocation }
    if (!$ConfigPath) { throw 'Environment record was not found. Specify -ConfigPath.' }
    $config = Read-Environment $ConfigPath
    if ($config.phase -ne 'Ready') { throw 'Setup is incomplete. Finish Setup.ps1 first.' }
    if ($InstallLocation -and [IO.Path]::GetFullPath($InstallLocation).TrimEnd('\') -ine [IO.Path]::GetFullPath($config.installLocation).TrimEnd('\')) { throw 'Install location differs from the saved configuration.' }
    Assert-Registration $config
    $marker = Invoke-Wsl -Capture -Arguments @('-d',$config.distroName,'-u','root','--exec','cat','/etc/opencae-environment-id')
    Assert-WslResult $marker 'Environment identity check'
    if ($marker.Output.Trim() -ne $config.environmentId) { throw 'Environment identity mismatch.' }
    Sync-CrewRuntime $PSScriptRoot $config
    Install-EnvironmentLaunchers $PSScriptRoot $config
    Write-Host "Windows launchers updated: $($config.installLocation)"
    Write-Host 'Run Start Backend.cmd, then Start Kiro Crew.cmd. Old desktop shortcuts can be deleted manually.'
} catch {
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}
