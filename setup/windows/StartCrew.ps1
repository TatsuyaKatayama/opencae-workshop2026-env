#requires -version 5.1
[CmdletBinding()]
param([string]$ConfigPath, [switch]$PauseOnError)
try {
    . "$PSScriptRoot/Common.ps1"
    if (!$ConfigPath) { $ConfigPath = Join-Path $PSScriptRoot '../environment.json' }
    Invoke-CrewAction -Action 'Start' -ConfigPath $ConfigPath
} catch {
    Write-Host $_.Exception.Message -ForegroundColor Red
    if ($PauseOnError) { [void](Read-Host 'Press Enter to close') }
    exit 1
}
