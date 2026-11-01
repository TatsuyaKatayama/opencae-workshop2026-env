Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-Sha256 {
    param([Parameter(Mandatory=$true)][string]$LiteralPath)
    # PowerShell.Utility の自動読み込みに依存せず、5.1 / 7 共通の .NET API を使う。
    $stream = [IO.File]::OpenRead($LiteralPath)
    $algorithm = $null
    try {
        $algorithm = [Security.Cryptography.SHA256]::Create()
        return ([BitConverter]::ToString($algorithm.ComputeHash($stream))).Replace('-', '').ToLowerInvariant()
    } finally {
        if ($null -ne $algorithm) { $algorithm.Dispose() }
        $stream.Dispose()
    }
}

function Assert-Names {
    param([string]$DistroName, [string]$UserName)
    if ($DistroName -cnotmatch '^[A-Za-z][A-Za-z0-9_-]{0,63}$') { throw 'Invalid WSL name (letters, digits, _ and - only).' }
    if ($UserName -cnotmatch '^[a-z][a-z0-9_-]{0,30}$' -or $UserName -eq 'root') { throw 'Invalid Linux user name.' }
}

function ConvertTo-NativeArgument {
    param([AllowEmptyString()][string]$Value, [switch]$ForceQuote)
    # WSL のオプション・空白のない値には不要な引用符を付けない。
    if (!$ForceQuote -and $Value.Length -gt 0 -and $Value -notmatch '[\s"]') { return $Value }
    # CommandLineToArgvW quoting, including backslashes before quotes/end.
    '"' + [regex]::Replace([regex]::Replace($Value, '(\\*)"', '$1$1\"'), '(\\+)$', '$1$1') + '"'
}

function Invoke-Wsl {
    param([string[]]$Arguments, [switch]$Capture)
    $info = New-Object System.Diagnostics.ProcessStartInfo
    $info.FileName = 'wsl.exe'
    $info.Arguments = ($Arguments | ForEach-Object { ConvertTo-NativeArgument $_ }) -join ' '
    $info.UseShellExecute = $false
    $info.RedirectStandardOutput = [bool]$Capture
    $info.RedirectStandardError = [bool]$Capture
    if ($Capture) {
        $info.StandardOutputEncoding = New-Object Text.UTF8Encoding($false)
        $info.StandardErrorEncoding = New-Object Text.UTF8Encoding($false)
    }
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $info
    try {
        [void]$process.Start()
        if ($Capture) {
            $stdout = $process.StandardOutput.ReadToEndAsync()
            $stderr = $process.StandardError.ReadToEndAsync()
        }
        $process.WaitForExit()
        if ($Capture) {
            return [pscustomobject]@{ Code = $process.ExitCode; Output = $stdout.Result.Replace([string][char]0, ''); Error = $stderr.Result.Replace([string][char]0, '') }
        }
        return [pscustomobject]@{ Code = $process.ExitCode; Output = ''; Error = '' }
    } finally { $process.Dispose() }
}

function Assert-WslResult {
    param($Result, [string]$Operation)
    if ($Result.Code -ne 0) { throw "$Operation failed (exit $($Result.Code)). $($Result.Error)" }
}

function Assert-WslReady {
    param($Result)
    [string[]]$details = @()
    if ($Result.Code -ne 0) {
        # wsl.exe can report failures on either stdout or stderr.
        foreach ($text in @([string]$Result.Error, [string]$Result.Output)) {
            if (![string]::IsNullOrWhiteSpace($text)) { $details += $text.Trim() }
        }
        if ($details.Count -eq 0) { $details = @('wsl.exe returned no error details.') }
        throw ("WSL is not ready (exit $($Result.Code))." + [Environment]::NewLine +
            ($details -join [Environment]::NewLine) + [Environment]::NewLine +
            'Check the details above. If WSL is not installed, run wsl --install --no-distribution, restart Windows, then retry.')
    }
}

function Save-Environment {
    param([string]$Path, $Config)
    $directory = Split-Path -Parent $Path
    [void][IO.Directory]::CreateDirectory($directory)
    $temp = Join-Path $directory ([guid]::NewGuid().ToString() + '.tmp')
    try {
        [IO.File]::WriteAllText($temp, ($Config | ConvertTo-Json -Depth 8), (New-Object Text.UTF8Encoding($false)))
        Move-Item -LiteralPath $temp -Destination $Path -Force
    } finally { if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp } }
}

function Read-Environment {
    param([string]$Path)
    $config = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-Names $config.distroName $config.linuxUser
    if ($config.schema -ne 1 -or $config.projectPath -ne "/home/$($config.linuxUser)/opencae-workshop2026-env" -or
        $config.port -lt 1024 -or $config.port -gt 65535 -or $config.environmentId -notmatch '^[0-9a-f-]{36}$') {
        throw 'Invalid environment configuration.'
    }
    return $config
}

function Get-WslRegistration {
    param([string]$DistroName)
    $key = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss'
    if (!(Test-Path $key)) { return $null }
    foreach ($item in Get-ChildItem $key) {
        # Lxss also contains metadata keys that are not distributions.
        if ($item.PSChildName -notmatch '^\{[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\}$') { continue }
        $p = Get-ItemProperty $item.PSPath
        $name = $p.PSObject.Properties['DistributionName']
        if ($null -eq $name -or [string]::IsNullOrWhiteSpace([string]$name.Value)) { continue }
        if ($name.Value -ieq $DistroName) {
            $basePath = $p.PSObject.Properties['BasePath']
            $version = $p.PSObject.Properties['Version']
            if ($null -eq $basePath -or $null -eq $version) { throw "Incomplete WSL registration: $DistroName (BasePath or Version is missing)." }
            return [pscustomobject]@{ Id=$item.PSChildName; BasePath=$basePath.Value; Version=$version.Value }
        }
    }
    return $null
}

function Assert-Registration {
    param($Config)
    $registration = Get-WslRegistration $Config.distroName
    if (!$registration -or $registration.Id -ne $Config.registrationId -or $registration.Version -ne 2) {
        throw 'WSL registration does not match setup. Run Setup.ps1 with the original options.'
    }
    $actual = $registration.BasePath -replace '^\\\\\?\\', ''
    if ([IO.Path]::GetFullPath($actual).TrimEnd('\') -ine [IO.Path]::GetFullPath($Config.installLocation).TrimEnd('\')) {
        throw 'WSL installation path does not match setup.'
    }
}

function Get-UserArguments {
    param($Config, [string]$Script)
    @('--distribution', $Config.distroName, '--user', $Config.linuxUser, '--exec', 'bash', "$($Config.projectPath)/setup/ubuntu2404/$Script")
}

function Start-CrewWslLifetime {
    param($Config)
    Assert-WslResult (Invoke-Wsl -Capture -Arguments @('-d',$Config.distroName,'-u',$Config.linuxUser,'--exec','test','-r',"$($Config.projectPath)/setup/ubuntu2404/crew-keepalive.sh")) 'WSL lifetime script check (run UpdateLaunchers.ps1 if missing)'
    # 通常の wsl.exe 呼び出しを残し、WSL のアイドル終了を防ぐ。
    $arguments = Get-UserArguments $Config 'crew-keepalive.sh'
    $commandLine = ($arguments | ForEach-Object { ConvertTo-NativeArgument $_ }) -join ' '
    Start-Process -FilePath 'wsl.exe' -ArgumentList $commandLine -WindowStyle Hidden
}

function Invoke-CrewAction {
    param([ValidateSet('Login','Backend','Start','Stop')][string]$Action, [string]$ConfigPath,
          [ValidateSet('kiro','codex','opencode')][string]$Backend = 'kiro', [switch]$SkipAuthentication)
    $config = Read-Environment $ConfigPath
    if ($config.phase -ne 'Ready') { throw 'Setup is incomplete. Re-run Setup.ps1.' }
    Assert-Registration $config
    # Check the root-owned environment marker before running project code.
    $marker = Invoke-Wsl -Capture -Arguments @('-d',$config.distroName,'-u','root','--exec','cat','/etc/opencae-environment-id')
    Assert-WslResult $marker 'Environment identity check'
    if ($marker.Output.Trim() -ne $config.environmentId) { throw 'Environment identity mismatch.' }
    switch ($Action) {
        Backend {
            $arguments = (Get-UserArguments $config 'start-backend.sh') + @('--backend',$Backend,'--open-browser')
            if ($SkipAuthentication) {
                if ($Backend -ne 'opencode') { throw '-SkipAuthentication is only available for OpenCode local or preconfigured providers.' }
                $arguments += '--skip-auth'
            }
            Assert-WslResult (Invoke-Wsl -Arguments $arguments) 'Backend setup'
        }
        Login {
            $status = Invoke-Wsl -Capture -Arguments ((Get-UserArguments $config 'kiro-login.sh') + @('--status'))
            if ($status.Code -eq 0) { Write-Host 'Kiro CLI is already signed in.'; return }
            if ($status.Code -ne 3) { Assert-WslResult $status 'Authentication status check' }
            $result = Invoke-Wsl -Arguments ((Get-UserArguments $config 'kiro-login.sh') + @('--open-browser'))
            Assert-WslResult $result 'Kiro CLI login'
        }
        Start {
            $result = Invoke-Wsl -Capture -Arguments (Get-UserArguments $config 'crew-start.sh')
            Assert-WslResult $result 'Crew start'
            $url = $result.Output.Trim()
            $uri = $null
            if (![Uri]::TryCreate($url,[UriKind]::Absolute,[ref]$uri) -or $uri.Scheme -ne 'http' -or
                $uri.Host -notin @('localhost','127.0.0.1','[::1]') -or $uri.Port -ne $config.port -or $uri.UserInfo) {
                throw 'Crew did not return a valid local access URL.'
            }
            Start-CrewWslLifetime $config
            Start-Process -FilePath $url
            Write-Host 'Kiro Crew is running. Browser opened.'
        }
        Stop {
            $result = Invoke-Wsl -Arguments (Get-UserArguments $config 'crew-stop.sh')
            Assert-WslResult $result 'Crew stop'
        }
    }
}

function Get-WorkshopUserRoot {
    Join-Path ([Environment]::GetFolderPath('UserProfile')) 'OpenCAE'
}

function Get-PendingConfigPath {
    param([string]$InstallLocation)
    Join-Path ($InstallLocation.TrimEnd('\') + '.opencae-state') 'environment.json'
}

function Get-LegacyConfigPaths {
    param([string]$DistroName)
    $paths = @()
    $legacy = "OpenCAE\environments\$DistroName\environment.json"
    $paths += (Join-Path $env:LOCALAPPDATA $legacy)
    # パッケージ化された端末から旧 Setup を実行した場合の物理保存先。
    $packages = Join-Path $env:LOCALAPPDATA 'Packages'
    if (Test-Path -LiteralPath $packages -PathType Container) {
        foreach ($package in Get-ChildItem -LiteralPath $packages -Directory) {
            $paths += (Join-Path $package.FullName "LocalCache\Local\$legacy")
        }
    }
    return $paths
}

function Find-EnvironmentConfig {
    param([string]$DistroName,[string]$InstallLocation)
    Assert-Names $DistroName 'workshop'
    $paths = @()
    if ($InstallLocation) {
        $paths += (Join-Path $InstallLocation 'environment.json')
        $paths += (Get-PendingConfigPath $InstallLocation)
    }
    $paths += @(Get-LegacyConfigPaths $DistroName)
    $found = @()
    foreach ($path in ($paths | Select-Object -Unique)) {
        if (!(Test-Path -LiteralPath $path -PathType Leaf)) { continue }
        $config = Read-Environment $path
        if ($config.distroName -ine $DistroName -or $config.phase -eq 'Removed') { continue }
        if ($InstallLocation -and [IO.Path]::GetFullPath($config.installLocation).TrimEnd('\') -ine [IO.Path]::GetFullPath($InstallLocation).TrimEnd('\')) { continue }
        # インストール先の記録を最優先とする。
        if ($InstallLocation -and [IO.Path]::GetFullPath($path) -ieq [IO.Path]::GetFullPath((Join-Path $InstallLocation 'environment.json'))) { return $path }
        $found += [pscustomobject]@{Path=$path;Config=$config}
    }
    if ($found.Count -eq 0) { return $null }
    $first = $found[0].Config
    foreach ($item in $found) {
        if ($item.Config.environmentId -ne $first.environmentId -or $item.Config.registrationId -ne $first.registrationId) {
            throw 'Multiple different environment records found. Specify -ConfigPath explicitly in UpdateLaunchers.ps1.'
        }
    }
    return $found[0].Path
}

function Get-WindowsScriptFiles {
    @('Common.ps1','KiroLogin.ps1','StartBackend.ps1','StartCrew.ps1','StopCrew.ps1','RemoveEnvironment.ps1','UpdateLaunchers.ps1')
}

function Get-LegacyLauncherFiles {
    @(Get-WindowsScriptFiles) + @('Start Backend.cmd','Start Kiro Crew.cmd','Stop Kiro Crew.cmd','runtime/crew-start.sh','runtime/crew-keepalive.sh')
}

function Get-InstalledLauncherFiles {
    @((Get-WindowsScriptFiles | ForEach-Object { 'scripts/' + $_ })) +
        @('1_StartBackend.cmd','2_StartCrew.cmd','3_StopCrew.cmd','9_Allclean.cmd',
          'scripts/runtime/crew-start.sh','scripts/runtime/crew-keepalive.sh')
}

function Get-CrewRuntimeSource {
    param([string]$SourceDirectory)
    foreach ($candidate in @((Join-Path $SourceDirectory '../ubuntu2404'),(Join-Path $SourceDirectory 'runtime'))) {
        if ((Test-Path -LiteralPath (Join-Path $candidate 'crew-start.sh') -PathType Leaf) -and
            (Test-Path -LiteralPath (Join-Path $candidate 'crew-keepalive.sh') -PathType Leaf)) {
            return (Resolve-Path -LiteralPath $candidate).ProviderPath
        }
    }
    throw 'Crew runtime scripts were not found. Run UpdateLaunchers.ps1 from the updated repository.'
}

function Sync-CrewRuntime {
    param([string]$SourceDirectory,$Config)
    $source = Get-CrewRuntimeSource $SourceDirectory
    foreach ($name in @('crew-start.sh','crew-keepalive.sh')) {
        $path = Join-Path $source $name
        $converted = Invoke-Wsl -Capture -Arguments @('-d',$Config.distroName,'-u',$Config.linuxUser,'--exec','wslpath','-a','-u',$path)
        Assert-WslResult $converted 'Runtime path conversion'
        $linuxSource = $converted.Output.Trim()
        if (!$linuxSource.StartsWith('/') -or $linuxSource -match '[\r\n]') { throw 'Invalid runtime source path.' }
        Assert-WslResult (Invoke-Wsl -Arguments @('-d',$Config.distroName,'-u',$Config.linuxUser,'--exec','bash','-n',$linuxSource)) 'Runtime syntax check'
        $target = "$($Config.projectPath)/setup/ubuntu2404/$name"
        Assert-WslResult (Invoke-Wsl -Arguments @('-d',$Config.distroName,'-u',$Config.linuxUser,'--exec','install','-m','0755',$linuxSource,$target)) 'Runtime update'
        Assert-WslResult (Invoke-Wsl -Arguments @('-d',$Config.distroName,'-u',$Config.linuxUser,'--exec','cmp','--silent','--',$linuxSource,$target)) 'Runtime update verification'
    }
}

function Install-EnvironmentLaunchers {
    param([string]$SourceDirectory,$Config)
    $directory = [IO.Path]::GetFullPath($Config.installLocation)
    if (!(Test-Path -LiteralPath $directory -PathType Container)) { throw 'WSL installation directory is missing.' }
    $configPath = Join-Path $directory 'environment.json'
    if (Test-Path -LiteralPath $configPath) {
        $previous = Read-Environment $configPath
        if ($previous.environmentId -ne $Config.environmentId) { throw 'Installation directory belongs to another environment.' }
    }
    $files = @(Get-WindowsScriptFiles)
    foreach ($file in $files) {
        if (!(Test-Path -LiteralPath (Join-Path $SourceDirectory $file) -PathType Leaf)) { throw "Source script is missing: $file" }
    }
    $runtimeSource = Get-CrewRuntimeSource $SourceDirectory
    Save-Environment $configPath $Config
    $scriptTarget = Join-Path $directory 'scripts'
    if ((Test-Path -LiteralPath $scriptTarget) -and ((Get-Item -LiteralPath $scriptTarget -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Script directory must not be a link or junction.' }
    foreach ($path in @((Join-Path $scriptTarget 'runtime'),(Join-Path $directory 'runtime'))) {
        if ((Test-Path -LiteralPath $path) -and ((Get-Item -LiteralPath $path -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Runtime directory must not be a link or junction.' }
    }
    [void][IO.Directory]::CreateDirectory($scriptTarget)
    foreach ($file in $files) {
        $source = (Resolve-Path -LiteralPath (Join-Path $SourceDirectory $file)).ProviderPath
        $target = Join-Path $scriptTarget $file
        if ([IO.Path]::GetFullPath($source) -ine [IO.Path]::GetFullPath($target)) { Copy-Item -LiteralPath $source -Destination $target -Force }
    }
    $runtimeTarget = Join-Path $scriptTarget 'runtime'
    [void][IO.Directory]::CreateDirectory($runtimeTarget)
    foreach ($name in @('crew-start.sh','crew-keepalive.sh')) {
        $source = Join-Path $runtimeSource $name
        $target = Join-Path $runtimeTarget $name
        if ([IO.Path]::GetFullPath($source) -ine [IO.Path]::GetFullPath($target)) { Copy-Item -LiteralPath $source -Destination $target -Force }
    }
    foreach ($entry in @(@('1_StartBackend.cmd','StartBackend.ps1'),@('2_StartCrew.cmd','StartCrew.ps1'),@('3_StopCrew.cmd','StopCrew.ps1'),@('9_Allclean.cmd','RemoveEnvironment.ps1'))) {
        $invocation = '"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\' + $entry[1] + '" -ConfigPath "%~dp0environment.json"'
        if ($entry[0] -eq '9_Allclean.cmd') {
            # 自分の CMD が削除されても後続行を読み直さない。PS は結果表示のため残す。
            $invocation = $invocation.Replace('-NoProfile ', '-NoProfile -NoExit ').Replace('%~dp0', '%opencae_install_dir%') + ' -InteractiveConfirmation'
            $lines = @('@echo off','setlocal DisableDelayedExpansion','set "opencae_install_dir=%~dp0"','cd /d "%SystemRoot%"',('(' + $invocation + ') & exit /b'))
        } else {
            $lines = @('@echo off','setlocal DisableDelayedExpansion',$invocation,
                'set "opencae_launcher_status=%errorlevel%"','echo.','pause','exit /b %opencae_launcher_status%')
        }
        [IO.File]::WriteAllText((Join-Path $directory $entry[0]),(($lines -join "`r`n")+"`r`n"),[Text.Encoding]::ASCII)
    }
    # 新しい配置を作成した後に、旧レイアウトの既知ファイルだけを整理する。
    foreach ($file in (Get-LegacyLauncherFiles)) {
        $path = Join-Path $directory $file
        if (Test-Path -LiteralPath $path -PathType Leaf) { Remove-Item -LiteralPath $path -Force }
    }
    $oldRuntime = Join-Path $directory 'runtime'
    if ((Test-Path -LiteralPath $oldRuntime) -and @(Get-ChildItem -LiteralPath $oldRuntime -Force).Count -eq 0) { Remove-Item -LiteralPath $oldRuntime }

}

function Get-WindowsCpu {
    # Machine registry reports ARM64 even when PowerShell runs under x64 emulation.
    $nativeArch = [Microsoft.Win32.Registry]::GetValue('HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Session Manager\Environment', 'PROCESSOR_ARCHITECTURE', $null)
    if (!$nativeArch) { $nativeArch = if ($env:PROCESSOR_ARCHITEW6432) { $env:PROCESSOR_ARCHITEW6432 } else { $env:PROCESSOR_ARCHITECTURE } }
    switch ($nativeArch) { 'ARM64' { return 'arm64' }; 'AMD64' { return 'amd64' }; default { throw 'Unsupported Windows CPU.' } }
}

function Get-SetupArchitecture {
    if ($env:OS -ne 'Windows_NT') { throw 'Run Setup.ps1 on Windows 11.' }
    if (![Environment]::Is64BitProcess) { throw 'Use 64-bit PowerShell.' }
    if ([Environment]::OSVersion.Version.Build -lt 22000) { throw 'Windows 11 is required.' }
    if (!(Get-Command wsl.exe -ErrorAction SilentlyContinue)) { throw 'Install WSL first: wsl --install --no-distribution. Restart Windows, then retry.' }
    $result = Invoke-Wsl -Capture -Arguments @('--status')
    Assert-WslReady $result
    return Get-WindowsCpu
}
