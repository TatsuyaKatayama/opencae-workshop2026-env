#requires -version 5.1
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$ConfigPath, [switch]$PauseOnError)
try {
    . "$PSScriptRoot/Common.ps1"
    Invoke-CrewAction -Action 'Login' -ConfigPath $ConfigPath
} catch {
    Write-Host $_.Exception.Message -ForegroundColor Red
    if ($PauseOnError) { [void](Read-Host 'Press Enter to close') }
    exit 1
}
