#requires -version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$ConfigPath,
    [ValidateSet('kiro','codex','opencode')][string]$Backend,
    [switch]$SkipAuthentication,
    [switch]$PauseOnError
)
. "$PSScriptRoot/Common.ps1"
try {
    if (!$Backend) {
        Write-Host 'Select backend: 1 = Kiro CLI, 2 = Codex, 3 = OpenCode'
        switch (Read-Host 'Backend [1-3]') {
            '1' { $Backend='kiro' }
            '2' { $Backend='codex' }
            '3' { $Backend='opencode' }
            default { throw 'Select 1, 2 or 3.' }
        }
    }
    if ($Backend -eq 'opencode' -and !$SkipAuthentication) {
        $answer = Read-Host 'Run OpenCode provider login? [Y/n] (n: local or preconfigured provider)'
        if ($answer -ieq 'n') { $SkipAuthentication=$true }
        elseif ($answer -ne '' -and $answer -ine 'y') { throw 'Select y or n.' }
    }
    Invoke-CrewAction -Action Backend -ConfigPath $ConfigPath -Backend $Backend -SkipAuthentication:$SkipAuthentication
} catch {
    Write-Host $_.Exception.Message -ForegroundColor Red
    if ($PauseOnError) { [void](Read-Host 'Press Enter to close') }
    exit 1
}
