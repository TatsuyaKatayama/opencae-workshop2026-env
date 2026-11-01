#requires -version 5.1
[CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact='High')]
param([Parameter(Mandatory=$true)][string]$ConfigPath)
. "$PSScriptRoot/Common.ps1"

function Remove-WorkshopEnvironment {
    [CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact='High')]
    param([Parameter(Mandatory=$true)][string]$ConfigPath)
    $config = Read-Environment $ConfigPath
    $directory = Join-Path $env:LOCALAPPDATA "OpenCAE\environments\$($config.distroName)"
    $expected = Join-Path $directory 'environment.json'
    if ([IO.Path]::GetFullPath($ConfigPath) -ine [IO.Path]::GetFullPath($expected)) { throw 'Use the environment.json saved by Setup.ps1 under LOCALAPPDATA.' }
    # メタデータ削除時にジャンクションやシンボリックリンクをたどらない。
    foreach ($item in @((Join-Path $env:LOCALAPPDATA 'OpenCAE'),(Join-Path $env:LOCALAPPDATA 'OpenCAE/environments'),$directory,(Join-Path $directory 'launchers'),$ConfigPath)) {
        if ((Test-Path -LiteralPath $item) -and ((Get-Item -LiteralPath $item -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            throw 'Environment metadata must not be a link or junction.'
        }
    }
    $registration = Get-WslRegistration $config.distroName
    if ($registration) {
        Assert-Registration $config
        $marker = Invoke-Wsl -Capture -Arguments @('-d',$config.distroName,'-u','root','--exec','cat','/etc/opencae-environment-id')
        Assert-WslResult $marker 'Environment identity check'
        if ($marker.Output.Trim() -ne $config.environmentId) { throw 'Environment identity mismatch. Nothing was deleted.' }
    } elseif ($config.phase -ne 'Removing') { throw 'WSL registration is missing. Inspect the environment manually.' }
    $description = "Permanently delete WSL '$($config.distroName)' at '$($config.installLocation)', including all Linux files, credentials, CFD images and results, then remove its launcher metadata"
    if (!$PSCmdlet.ShouldProcess($config.distroName,$description)) { return }
    if ($registration) {
        # 確認ダイアログの待機中に登録先が変わっていないことを再確認する。
        Assert-Registration $config
        $marker = Invoke-Wsl -Capture -Arguments @('-d',$config.distroName,'-u','root','--exec','cat','/etc/opencae-environment-id')
        Assert-WslResult $marker 'Environment identity recheck'
        if ($marker.Output.Trim() -ne $config.environmentId) { throw 'Environment identity changed. Nothing was deleted.' }
        $config.phase='Removing'
        Save-Environment $ConfigPath $config
        Assert-WslResult (Invoke-Wsl -Arguments @('--unregister',$config.distroName)) 'WSL removal'
        if (Get-WslRegistration $config.distroName) { throw 'WSL registration still exists. Metadata was kept.' }
    }
    $launchers = Join-Path $directory 'launchers'
    Remove-OwnedCrewShortcuts $launchers $ConfigPath $config.distroName
    # 保存先の再帰削除は行わない。メタデータも既知のファイルのみを削除する。
    foreach ($file in @('Common.ps1','KiroLogin.ps1','StartBackend.ps1','StartCrew.ps1','StopCrew.ps1')) {
        $path = Join-Path $launchers $file
        if (Test-Path -LiteralPath $path -PathType Leaf) { Remove-Item -LiteralPath $path -Force }
    }
    Remove-Item -LiteralPath $ConfigPath
    foreach ($path in @($launchers,$directory)) {
        if ((Test-Path -LiteralPath $path) -and @(Get-ChildItem -LiteralPath $path -Force).Count -eq 0) { Remove-Item -LiteralPath $path }
    }
    Write-Host 'Environment removed. The Windows checkout and other WSL environments were kept.'
}

if ($MyInvocation.InvocationName -ne '.') {
    try { Remove-WorkshopEnvironment @PSBoundParameters }
    catch { Write-Host $_.Exception.Message -ForegroundColor Red; exit 1 }
}
