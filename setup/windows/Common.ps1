Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-Names {
    param([string]$DistroName, [string]$UserName)
    if ($DistroName -cnotmatch '^[A-Za-z][A-Za-z0-9_-]{0,63}$') { throw 'Invalid WSL name (letters, digits, _ and - only).' }
    if ($UserName -cnotmatch '^[a-z][a-z0-9_-]{0,30}$' -or $UserName -eq 'root') { throw 'Invalid Linux user name.' }
}

function ConvertTo-NativeArgument {
    param([AllowEmptyString()][string]$Value)
    # WSL のオプション・空白のない値には不要な引用符を付けない。
    if ($Value.Length -gt 0 -and $Value -notmatch '[\s"]') { return $Value }
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
        $p = Get-ItemProperty $item.PSPath
        if ($p.DistributionName -ieq $DistroName) {
            return [pscustomobject]@{ Id=$item.PSChildName; BasePath=$p.BasePath; Version=$p.Version }
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

function Invoke-CrewAction {
    param([ValidateSet('Login','Start','Stop')][string]$Action, [string]$ConfigPath)
    $config = Read-Environment $ConfigPath
    if ($config.phase -ne 'Ready') { throw 'Setup is incomplete. Re-run Setup.ps1.' }
    Assert-Registration $config
    # Check the root-owned environment marker before running project code.
    $marker = Invoke-Wsl -Capture -Arguments @('-d',$config.distroName,'-u','root','--exec','cat','/etc/opencae-environment-id')
    Assert-WslResult $marker 'Environment identity check'
    if ($marker.Output.Trim() -ne $config.environmentId) { throw 'Environment identity mismatch.' }
    switch ($Action) {
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
            Start-Process -FilePath $url
            Write-Host 'Kiro Crew is running. Browser opened.'
        }
        Stop {
            $result = Invoke-Wsl -Arguments (Get-UserArguments $config 'crew-stop.sh')
            Assert-WslResult $result 'Crew stop'
        }
    }
}

function New-CrewShortcuts {
    param([string]$LauncherDirectory,[string]$ConfigPath,[string]$DistroName)
    $desktop = [Environment]::GetFolderPath('DesktopDirectory')
    $shell = New-Object -ComObject WScript.Shell
    $hostExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    foreach ($entry in @(@('Kiro CLI Login','KiroLogin.ps1'),@('Start Kiro Crew','StartCrew.ps1'),@('Stop Kiro Crew','StopCrew.ps1'))) {
        $shortcut = $shell.CreateShortcut((Join-Path $desktop "$($entry[0]) ($DistroName).lnk"))
        $shortcut.TargetPath = $hostExe
        $shortcut.Arguments = '-NoProfile -ExecutionPolicy Bypass -File ' + (ConvertTo-NativeArgument (Join-Path $LauncherDirectory $entry[1])) + ' -ConfigPath ' + (ConvertTo-NativeArgument $ConfigPath) + ' -PauseOnError'
        $shortcut.WorkingDirectory = $LauncherDirectory
        $shortcut.Save()
    }
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
