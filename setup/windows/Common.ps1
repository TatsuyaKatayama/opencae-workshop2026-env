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
            Start-Process -FilePath $url
            Write-Host 'Kiro Crew is running. Browser opened.'
        }
        Stop {
            $result = Invoke-Wsl -Arguments (Get-UserArguments $config 'crew-stop.sh')
            Assert-WslResult $result 'Crew stop'
        }
    }
}

function Get-CrewShortcutArguments {
    param([string]$ScriptPath,[string]$ConfigPath)
    '-NoProfile -NoExit -ExecutionPolicy Bypass -File ' + (ConvertTo-NativeArgument $ScriptPath -ForceQuote) +
        ' -ConfigPath ' + (ConvertTo-NativeArgument $ConfigPath -ForceQuote) + ' -PauseOnError'
}

function Initialize-CrewShellLink {
    if ('OpenCAE.ShellLinks' -as [type]) { return }
    # WScript.Shell のコードページ変換を避け、Unicode の Shell API を直接使う。
    Add-Type -TypeDefinition @'
using System;
using System.Text;
using System.Runtime.InteropServices;
using System.Runtime.InteropServices.ComTypes;
namespace OpenCAE {
    [ComImport, Guid("00021401-0000-0000-C000-000000000046")]
    internal class ShellLinkClass { }
    [ComImport, Guid("000214F9-0000-0000-C000-000000000046"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IShellLinkW {
        void GetPath([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder path, int length, IntPtr data, uint flags);
        void GetIDList(out IntPtr id);
        void SetIDList(IntPtr id);
        void GetDescription([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder value, int length);
        void SetDescription([MarshalAs(UnmanagedType.LPWStr)] string value);
        void GetWorkingDirectory([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder value, int length);
        void SetWorkingDirectory([MarshalAs(UnmanagedType.LPWStr)] string value);
        void GetArguments([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder value, int length);
        void SetArguments([MarshalAs(UnmanagedType.LPWStr)] string value);
        void GetHotkey(out short value);
        void SetHotkey(short value);
        void GetShowCmd(out int value);
        void SetShowCmd(int value);
        void GetIconLocation([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder path, int length, out int index);
        void SetIconLocation([MarshalAs(UnmanagedType.LPWStr)] string path, int index);
        void SetRelativePath([MarshalAs(UnmanagedType.LPWStr)] string path, uint reserved);
        void Resolve(IntPtr window, uint flags);
        void SetPath([MarshalAs(UnmanagedType.LPWStr)] string path);
    }
    public class ShellLinkData {
        public string TargetPath;
        public string Arguments;
        public string WorkingDirectory;
        public int WindowStyle;
    }
    public static class ShellLinks {
        public static void Save(string path, string target, string arguments, string directory) {
            object instance = new ShellLinkClass();
            try {
                IShellLinkW link = (IShellLinkW)instance;
                link.SetPath(target);
                link.SetArguments(arguments);
                link.SetWorkingDirectory(directory);
                link.SetShowCmd(1);
                ((IPersistFile)instance).Save(path, true);
            } finally { Marshal.FinalReleaseComObject(instance); }
        }
        public static ShellLinkData Read(string path) {
            object instance = new ShellLinkClass();
            try {
                ((IPersistFile)instance).Load(path, 0);
                IShellLinkW link = (IShellLinkW)instance;
                StringBuilder target = new StringBuilder(32768);
                StringBuilder arguments = new StringBuilder(32768);
                StringBuilder directory = new StringBuilder(32768);
                int show;
                link.GetPath(target, target.Capacity, IntPtr.Zero, 0);
                link.GetArguments(arguments, arguments.Capacity);
                link.GetWorkingDirectory(directory, directory.Capacity);
                link.GetShowCmd(out show);
                return new ShellLinkData { TargetPath=target.ToString(), Arguments=arguments.ToString(), WorkingDirectory=directory.ToString(), WindowStyle=show };
            } finally { Marshal.FinalReleaseComObject(instance); }
        }
    }
}
'@
}

function New-CrewShortcuts {
    param([string]$LauncherDirectory,[string]$ConfigPath,[string]$DistroName,[string]$DesktopDirectory)
    $LauncherDirectory = (Resolve-Path -LiteralPath $LauncherDirectory).ProviderPath
    $ConfigPath = (Resolve-Path -LiteralPath $ConfigPath).ProviderPath
    $entries = @(@('Start Backend','StartBackend.ps1'),@('Start Kiro Crew','StartCrew.ps1'),@('Stop Kiro Crew','StopCrew.ps1'))
    foreach ($entry in $entries) {
        if (!(Test-Path -LiteralPath (Join-Path $LauncherDirectory $entry[1]) -PathType Leaf)) { throw "Launcher is missing: $($entry[1])" }
    }
    if (!$DesktopDirectory) { $DesktopDirectory = [Environment]::GetFolderPath('DesktopDirectory') }
    $desktop = (Resolve-Path -LiteralPath $DesktopDirectory).ProviderPath
    Initialize-CrewShellLink
    $hostExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    if (!(Test-Path -LiteralPath $hostExe -PathType Leaf)) { throw 'Windows PowerShell executable was not found.' }
    foreach ($entry in $entries) {
        $path = Join-Path $desktop "$($entry[0]) ($DistroName).lnk"
        $arguments = Get-CrewShortcutArguments (Join-Path $LauncherDirectory $entry[1]) $ConfigPath
        # すべて絶対パスで渡すため、作業フォルダーをリンク先の条件にしない。
        [OpenCAE.ShellLinks]::Save($path,$hostExe,$arguments,'')
        $saved = [OpenCAE.ShellLinks]::Read($path)
        if ($saved.TargetPath -ine $hostExe -or $saved.Arguments -cne $arguments -or $saved.WorkingDirectory -ne '') {
            throw "Shortcut verification failed: $path"
        }
    }
}

function Remove-OwnedCrewShortcuts {
    param([string]$LauncherDirectory,[string]$ConfigPath,[string]$DistroName,[switch]$LegacyOnly)
    $desktop = [Environment]::GetFolderPath('DesktopDirectory')
    Initialize-CrewShellLink
    $hostExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $entries = @(@('Kiro CLI Login','KiroLogin.ps1'))
    if (!$LegacyOnly) { $entries += @(@('Start Backend','StartBackend.ps1'),@('Start Kiro Crew','StartCrew.ps1'),@('Stop Kiro Crew','StopCrew.ps1')) }
    foreach ($entry in $entries) {
        $path = Join-Path $desktop "$($entry[0]) ($DistroName).lnk"
        if (!(Test-Path -LiteralPath $path)) { continue }
        $shortcut = [OpenCAE.ShellLinks]::Read($path)
        $arguments = '-NoProfile -ExecutionPolicy Bypass -File ' + (ConvertTo-NativeArgument (Join-Path $LauncherDirectory $entry[1])) + ' -ConfigPath ' + (ConvertTo-NativeArgument $ConfigPath) + ' -PauseOnError'
        $currentArguments = Get-CrewShortcutArguments (Join-Path $LauncherDirectory $entry[1]) $ConfigPath
        if ($shortcut.TargetPath -ieq $hostExe -and ($shortcut.Arguments -ceq $arguments -or $shortcut.Arguments -ceq $currentArguments)) { Remove-Item -LiteralPath $path }
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
