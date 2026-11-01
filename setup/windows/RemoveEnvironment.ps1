#requires -version 5.1
[CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact='High')]
param([string]$ConfigPath)
. "$PSScriptRoot/Common.ps1"

function Remove-WorkshopEnvironment {
    [CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact='High')]
    param([Parameter(Mandatory=$true)][string]$ConfigPath)
    $config = Read-Environment $ConfigPath
    $directory = Split-Path -Parent ([IO.Path]::GetFullPath($ConfigPath))
    $installed = Join-Path $config.installLocation 'environment.json'
    $pending = Get-PendingConfigPath $config.installLocation
    $legacy = Join-Path $env:LOCALAPPDATA "OpenCAE\environments\$($config.distroName)\environment.json"
    $allowed = @($installed,$pending,$legacy) | ForEach-Object { [IO.Path]::GetFullPath($_) }
    if ([IO.Path]::GetFullPath($ConfigPath) -notin $allowed) { throw 'Use the environment.json in the WSL installation directory or its recovery record.' }
    foreach ($item in @($directory,(Join-Path $directory 'launchers'),$ConfigPath)) {
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
        if ((Test-Path -LiteralPath $pending) -and (Read-Environment $pending).environmentId -ne $config.environmentId) { throw 'Recovery record belongs to another environment.' }
        Save-Environment $pending $config
        Assert-WslResult (Invoke-Wsl -Arguments @('--unregister',$config.distroName)) 'WSL removal'
        if (Get-WslRegistration $config.distroName) { throw 'WSL registration still exists. Metadata was kept.' }
    }
    # 移行元の旧記録が、削除後の再セットアップで復活しないようにする。
    foreach ($oldPath in (Get-LegacyConfigPaths $config.distroName | Select-Object -Unique)) {
        if (!(Test-Path -LiteralPath $oldPath -PathType Leaf)) { continue }
        $old = Read-Environment $oldPath
        if ($old.environmentId -eq $config.environmentId -and $old.registrationId -eq $config.registrationId) {
            $old.phase='Removed'; Save-Environment $oldPath $old
        }
    }
    # unregister が保存先を削除する場合にも対応し、既知のファイルだけを整理する。
    foreach ($base in @($directory,$config.installLocation,(Join-Path $directory 'launchers'))) {
        foreach ($file in (Get-InstalledLauncherFiles)) {
            $path = Join-Path $base $file
            if (Test-Path -LiteralPath $path -PathType Leaf) { Remove-Item -LiteralPath $path -Force }
        }
    }
    foreach ($path in @($ConfigPath,$installed,$pending) | Select-Object -Unique) {
        if (Test-Path -LiteralPath $path -PathType Leaf) { Remove-Item -LiteralPath $path }
    }
    foreach ($path in @((Join-Path $directory 'launchers'),(Split-Path -Parent $pending))) {
        if ((Test-Path -LiteralPath $path) -and @(Get-ChildItem -LiteralPath $path -Force).Count -eq 0) { Remove-Item -LiteralPath $path }
    }
    Write-Host 'Environment removed. The Windows checkout and other WSL environments were kept.'
}

if ($MyInvocation.InvocationName -ne '.') {
    try {
        if (!$ConfigPath) { $ConfigPath = Join-Path $PSScriptRoot 'environment.json' }
        $PSBoundParameters['ConfigPath'] = $ConfigPath
        Remove-WorkshopEnvironment @PSBoundParameters
    }
    catch { Write-Host $_.Exception.Message -ForegroundColor Red; exit 1 }
}
