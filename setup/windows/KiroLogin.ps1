#requires -version 5.1
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$ConfigPath, [switch]$PauseOnError)
. "$PSScriptRoot/Common.ps1"
try {
    Invoke-CrewAction -Action 'Login' -ConfigPath $ConfigPath
} catch {
    Write-Host $_.Exception.Message -ForegroundColor Red
    if ($PauseOnError) { [void](Read-Host 'Press Enter to close') }
    exit 1
}
