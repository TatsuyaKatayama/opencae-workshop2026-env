param([string]$RepositoryRoot = (Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference = 'Stop'
. (Join-Path $RepositoryRoot 'setup/windows/Common.ps1')
$count = 0
function Check { param([bool]$Condition,[string]$Message) if (!$Condition) { throw $Message }; $script:count++ }
function Must-Fail { param([scriptblock]$Code) $failed=$false; try { & $Code } catch { $failed=$true }; Check $failed 'Expected failure' }

foreach ($file in Get-ChildItem (Join-Path $RepositoryRoot 'setup/windows') -Filter '*.ps1') {
    $bytes = [IO.File]::ReadAllBytes($file.FullName)
    Check ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) "UTF-8 BOM missing: $($file.Name)"
    $tokens=$null; $errors=$null
    [void][System.Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$errors)
    Check ($errors.Count -eq 0) "Parse failure: $($file.Name): $errors"
}
Assert-Names 'custom-env_2026' 'workshop'
foreach ($name in @('bad name','../bad','bad;echo','bad"name')) { Must-Fail { Assert-Names $name 'user' } }
foreach ($name in @('root','UPPER','bad name','x;echo')) { Must-Fail { Assert-Names 'test' $name } }
Check ((ConvertTo-NativeArgument 'a b') -eq '"a b"') 'Space quoting'
Check ((ConvertTo-NativeArgument 'a"b') -eq '"a\"b"') 'Quote escaping'
Check ((ConvertTo-NativeArgument '--status') -eq '--status') 'Do not quote WSL options'
Check ((ConvertTo-NativeArgument 'C:\plain\file.ps1' -ForceQuote) -eq '"C:\plain\file.ps1"') 'Shortcut file paths must be quoted'

Assert-WslReady ([pscustomobject]@{Code=0;Output='ready';Error=''})
$message=''
try { Assert-WslReady ([pscustomobject]@{Code=45;Output='stdout error detail';Error='stderr error detail'}) } catch { $message=$_.Exception.Message }
Check ($message -match 'exit 45') 'WSL status exit code must be visible'
Check ($message -match 'stdout error detail' -and $message -match 'stderr error detail') 'Both WSL error streams must be visible'
foreach ($empty in @('', $null)) {
    $message=''
    try { Assert-WslReady ([pscustomobject]@{Code=45;Output=$empty;Error=$empty}) } catch { $message=$_.Exception.Message }
    Check ($message -match 'exit 45' -and $message -match 'no error details') 'Empty output must not hide the WSL failure'
}

# Read-only registry mocks: metadata keys must not be treated as distributions.
& {
    function Test-Path { param($Path) return $true }
    function Get-ChildItem {
        param($Path)
        @([pscustomobject]@{PSChildName='AppxInstallerCache';PSPath='ignored'},
          [pscustomobject]@{PSChildName='{11111111-1111-1111-1111-111111111111}';PSPath='metadata'},
          [pscustomobject]@{PSChildName='{22222222-2222-2222-2222-222222222222}';PSPath='valid'})
    }
    function Get-ItemProperty {
        param($Path)
        if ($Path -eq 'ignored') { throw 'Non-distribution key must not be read' }
        if ($Path -eq 'metadata') { return [pscustomobject]@{Other=1} }
        return [pscustomobject]@{DistributionName='example';BasePath='C:\WSL\example';Version=2}
    }
    $found=Get-WslRegistration 'example'
    Check ($found.Id -eq '{22222222-2222-2222-2222-222222222222}') 'Distribution must be found after metadata keys'
    Check ($found.BasePath -eq 'C:\WSL\example' -and $found.Version -eq 2) 'WSL registration values changed'
    Check ($null -eq (Get-WslRegistration 'missing')) 'Absent distribution must return null'
    function Get-ItemProperty { param($Path) return [pscustomobject]@{DistributionName='example'} }
    $message=''
    try { Get-WslRegistration 'example' } catch { $message=$_.Exception.Message }
    Check ($message -match 'Incomplete WSL registration') 'Incomplete target must produce a clear error'
}

$temp = Join-Path ([IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString())
[void][IO.Directory]::CreateDirectory($temp)
try {
    $hashFile=Join-Path $temp 'hash [literal] 日本語.txt'
    [IO.File]::WriteAllText($hashFile,'abc',(New-Object Text.UTF8Encoding($false)))
    Check ((Get-Sha256 -LiteralPath $hashFile) -eq 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad') 'SHA256 must match the known abc vector'
    # ハンドルが解放され、直後に同じファイルを更新できる。
    [IO.File]::WriteAllBytes($hashFile,[byte[]]@())
    Check ((Get-Sha256 -LiteralPath $hashFile) -eq 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855') 'Empty file SHA256 must match'
    Must-Fail { Get-Sha256 -LiteralPath (Join-Path $temp 'missing-file') }
    $path=Join-Path $temp 'environment.json'
    $script:config = [pscustomobject]@{
        schema=1; distroName='custom-env'; linuxUser='workshop'; projectPath='/home/workshop/opencae-workshop2026-env'
        port=5476; environmentId=[guid]::NewGuid().ToString(); phase='Ready'; registrationId='test-registration'; installLocation=$temp
    }
    $config | Add-Member -NotePropertyName displayName -NotePropertyValue ([string][char]0x65e5 + [char]0x672c + [char]0x8a9e)
    Save-Environment $path $config
    $loaded=Read-Environment $path
    Check ($loaded.distroName -eq 'custom-env') 'Configuration roundtrip'
    Check ($loaded.displayName -eq $config.displayName) 'UTF-8 configuration must preserve Japanese text'
    $script:registration=[pscustomobject]@{Id='test-registration';BasePath=$temp;Version=2}
    function Get-WslRegistration { param($DistroName) return $script:registration }
    Assert-Registration $config
    $script:registration.Version=1
    Must-Fail { Assert-Registration $config }
    $script:registration.Version=2
    $script:registration.Id='other'
    Must-Fail { Assert-Registration $config }
    $script:registration.Id='test-registration'

    $script:calls=@(); $script:opened=@(); $script:auth=0; $script:failure=''; $script:url='http://localhost:5476/?token=private-test'
    function Invoke-Wsl {
        param([string[]]$Arguments,[switch]$Capture)
        $script:calls+=,@($Arguments)
        $code=0; $output=''
        if ($Arguments -contains 'cat') { $output=$script:config.environmentId }
        elseif ($Arguments -contains '--status') { $code=$script:auth }
        elseif (($Arguments -join ' ') -match 'crew-start.sh') { $output=$script:url }
        if ($script:failure -and ($Arguments -join ' ') -match $script:failure) { $code=23 }
        return [pscustomobject]@{Code=$code;Output=$output;Error=''}
    }
    $script:lifetimeCalls=@()
    function Start-Process {
        param([string]$FilePath,[string]$ArgumentList,[string]$WindowStyle)
        if ($FilePath -eq 'wsl.exe') { $script:lifetimeCalls+=,[pscustomobject]@{Arguments=$ArgumentList;Style=$WindowStyle}; return }
        $script:opened+=,$FilePath
    }
    Invoke-CrewAction Login $path
    Check ($script:calls.Count -eq 2) 'Authenticated login must not launch another login'
    $script:auth=3
    Invoke-CrewAction Login $path
    Check ($script:calls[-1] -contains '--open-browser') 'Missing browser login option'
    Check ($script:calls[-1][1] -eq 'custom-env') 'Wrong WSL environment'
    Check ($script:calls[-1][3] -eq 'workshop') 'Wrong WSL user'
    $script:auth=23
    Must-Fail { Invoke-CrewAction Login $path }
    $before=$script:calls.Count
    Invoke-CrewAction Backend $path -Backend codex
    Check ($script:calls[-1] -contains '--backend' -and $script:calls[-1] -contains 'codex') 'Codex backend was not selected'
    Check (($script:calls[-1] -join ' ') -match 'start-backend.sh') 'Wrong backend script'
    Check (@($script:calls | Select-Object -Skip $before).Count -eq 2) 'Backend must use identity check and interactive call only'
    Invoke-CrewAction Backend $path -Backend opencode -SkipAuthentication
    Check ($script:calls[-1] -contains '--skip-auth') 'OpenCode preconfigured provider option missing'
    Must-Fail { Invoke-CrewAction Backend $path -Backend codex -SkipAuthentication }
    $script:failure='start-backend.sh'
    Must-Fail { Invoke-CrewAction Backend $path -Backend kiro }
    $script:failure=''
    $script:auth=0
    Invoke-CrewAction Start $path
    Check ($script:opened.Count -eq 1) 'Start must open browser'
    Check ($script:opened[0] -eq $script:url) 'Access URL changed'
    Check ($script:lifetimeCalls.Count -eq 1) 'Start must keep WSL alive'
    Check ($script:lifetimeCalls[0].Style -eq 'Hidden') 'Lifetime process must be hidden'
    Check ($script:lifetimeCalls[0].Arguments -match 'custom-env.*workshop.*crew-keepalive.sh') 'Lifetime process must select the WSL and prevent duplicates'
    foreach ($url in @('https://evil.example/','http://localhost:9999/','http://user:pass@localhost:5476/')) {
        $script:url=$url
        Must-Fail { Invoke-CrewAction Start $path }
    }
    Check ($script:opened.Count -eq 1) 'Rejected URL was opened'
    Check ($script:lifetimeCalls.Count -eq 1) 'Rejected URL must not start a WSL lifetime process'
    $script:url='http://localhost:5476/?token=private-test'
    $script:failure='crew-keepalive.sh'
    Must-Fail { Invoke-CrewAction Start $path }
    Check ($script:lifetimeCalls.Count -eq 1) 'Missing lifetime script must fail before starting the hidden process'
    $script:failure=''

    Invoke-CrewAction Stop $path
    Check (($script:calls[-1] -join ' ') -match 'crew-stop.sh') 'Wrong stop command'
    $script:failure='crew-stop.sh'
    Must-Fail { Invoke-CrewAction Stop $path }
    $config.phase='Staged'; Save-Environment $path $config
    Must-Fail { Invoke-CrewAction Start $path }
    $config.phase='Ready'; $config.projectPath='/tmp/other'; Save-Environment $path $config
    Must-Fail { Read-Environment $path }
} finally { Remove-Item -LiteralPath $temp -Recurse -Force }
& {
    . (Join-Path $RepositoryRoot 'setup/windows/RemoveEnvironment.ps1') -ConfigPath 'unused'
    $root=Join-Path ([IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString())
    $previousLocalAppData=$env:LOCALAPPDATA
    $env:LOCALAPPDATA=$root
    $script:removalRegistration=$null; $script:removalCalls=@(); $script:removalCode=0; $script:wrongMarker=$false
    function Get-WslRegistration { param($DistroName) return $script:removalRegistration }
    function Invoke-Wsl {
        param([string[]]$Arguments,[switch]$Capture)
        $script:removalCalls+=,@($Arguments)
        if ($Arguments -contains 'cat') {
            $marker=if ($script:wrongMarker) { 'wrong-id' } else { $script:removalConfig.environmentId }
            return [pscustomobject]@{Code=0;Output=$marker;Error=''}
        }
        if ($Arguments -contains '--unregister') {
            if ($script:removalCode -eq 0) { $script:removalRegistration=$null }
            return [pscustomobject]@{Code=$script:removalCode;Output='';Error='mock removal result'}
        }
        throw 'Unexpected WSL command'
    }
    try {
        $directory=Join-Path $root 'OpenCAE/environments/remove-test'
        $file=Join-Path $directory 'environment.json'
        $launchers=Join-Path $directory 'launchers'
        [void][IO.Directory]::CreateDirectory($launchers)
        $script:removalConfig=[pscustomobject]@{
            schema=1;distroName='remove-test';linuxUser='workshop';projectPath='/home/workshop/opencae-workshop2026-env'
            port=5476;environmentId=[guid]::NewGuid().ToString();phase='Ready';registrationId='owned-id';installLocation=$root
        }
        $script:removalRegistration=[pscustomobject]@{Id='owned-id';BasePath=$root;Version=2}
        Save-Environment $file $script:removalConfig
        Remove-WorkshopEnvironment -ConfigPath $file -WhatIf
        Check (@($script:removalCalls | Where-Object { $_ -contains '--unregister' }).Count -eq 0) 'WhatIf must not unregister WSL'
        Check ((Read-Environment $file).phase -eq 'Ready') 'WhatIf must not change metadata'
        & {
            function Get-Item { param($LiteralPath,[switch]$Force) return [pscustomobject]@{Attributes=[IO.FileAttributes]::ReparsePoint} }
            Must-Fail { Remove-WorkshopEnvironment -ConfigPath $file -Confirm:$false }
        }
        $script:removalRegistration.Id='foreign-id'
        Must-Fail { Remove-WorkshopEnvironment -ConfigPath $file -Confirm:$false }
        $script:removalRegistration.Id='owned-id'
        $script:removalRegistration.BasePath=Join-Path $root 'foreign-path'
        Must-Fail { Remove-WorkshopEnvironment -ConfigPath $file -Confirm:$false }
        $script:removalRegistration.BasePath=$root
        $script:wrongMarker=$true
        Must-Fail { Remove-WorkshopEnvironment -ConfigPath $file -Confirm:$false }
        $script:wrongMarker=$false
        Check (@($script:removalCalls | Where-Object { $_ -contains '--unregister' }).Count -eq 0) 'Identity failures must never unregister WSL'
        $otherFile=Join-Path $root 'copied.json'
        Save-Environment $otherFile $script:removalConfig
        Must-Fail { Remove-WorkshopEnvironment -ConfigPath $otherFile -Confirm:$false }
        $script:removalRegistration=$null
        Must-Fail { Remove-WorkshopEnvironment -ConfigPath $file -Confirm:$false }
        $script:removalRegistration=[pscustomobject]@{Id='owned-id';BasePath=$root;Version=2}
        & {
            function Read-Host { param($Prompt) return '' }
            $text=Remove-WorkshopEnvironment -ConfigPath $file -InteractiveConfirmation -Confirm:$false 6>&1 | Out-String
            Check ($text.Contains('wsl --unregister remove-test') -and $text.Contains('元に戻せません')) 'Allclean must show the exact action and irreversible data loss warning'
            Check ((Read-Environment $file).phase -eq 'Ready') 'Cancelled Allclean must keep metadata unchanged'
        }
        Check (@($script:removalCalls | Where-Object { $_ -contains '--unregister' }).Count -eq 0) 'Cancelled Allclean must not unregister'
        $script:removalCode=23
        & {
            function Read-Host { param($Prompt) return 'DELETE' }
            Must-Fail { Remove-WorkshopEnvironment -ConfigPath $file -InteractiveConfirmation -Confirm:$false }
        }
        Check ((Read-Environment $file).phase -eq 'Removing') 'Removal failure must retain recovery metadata'
        # WSL 削除後のメタデータ処理失敗からも安全に再開できる。
        $script:removalRegistration=$null
        [IO.File]::WriteAllText((Join-Path $launchers 'StartBackend.ps1'),'managed launcher')
        $keep=Join-Path $directory 'user-file.txt'
        [IO.File]::WriteAllText($keep,'keep')
        Remove-WorkshopEnvironment -ConfigPath $file -Confirm:$false
        Check (!(Test-Path -LiteralPath $file)) 'Successful removal must remove environment.json'
        Check (Test-Path -LiteralPath $keep) 'Unknown metadata files must be kept'
        Check (!(Test-Path -LiteralPath (Join-Path $launchers 'StartBackend.ps1'))) 'Managed launcher not removed'
        Check (Test-Path -LiteralPath $root) 'Installation path must not be recursively removed'
        # 正常な unregister も、指定した環境以外へは発行しない。
        [void][IO.Directory]::CreateDirectory($launchers)
        $script:removalConfig.phase='Ready'; Save-Environment $file $script:removalConfig
        $script:removalRegistration=[pscustomobject]@{Id='owned-id';BasePath=$root;Version=2}
        $script:removalCode=0
        Remove-WorkshopEnvironment -ConfigPath $file -Confirm:$false
        Check (($script:removalCalls[-1] -join ' ') -eq '--unregister remove-test') 'Only the owned WSL may be unregistered'
        Check (!(Test-Path -LiteralPath $file)) 'Successful unregister must clean metadata'
    } finally {
        $env:LOCALAPPDATA=$previousLocalAppData
        Remove-Item -LiteralPath $root -Recurse -Force
    }
}

& {
    $tempRoot=Join-Path ([IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString())
    $previousLocalAppData=$env:LOCALAPPDATA
    $env:LOCALAPPDATA=Join-Path $tempRoot 'AppData'
    $install=Join-Path $tempRoot 'disk'
    [void][IO.Directory]::CreateDirectory($install)
    try {
        $record=[pscustomobject]@{
            schema=1;distroName='migration-test';linuxUser='workshop';projectPath='/home/workshop/opencae-workshop2026-env'
            port=5476;environmentId=[guid]::NewGuid().ToString();phase='Ready';registrationId='migration-id';installLocation=$install
        }
        Check ($null -eq (Find-EnvironmentConfig 'migration-test' $install)) 'Absent configuration must not be invented'
        $legacy=Join-Path $env:LOCALAPPDATA 'Packages/Test.App/LocalCache/Local/OpenCAE/environments/migration-test/environment.json'
        Save-Environment $legacy $record
        Check ((Find-EnvironmentConfig 'migration-test' $install) -eq $legacy) 'Redirected old configuration must be discoverable'
        $installed=Join-Path $install 'environment.json'
        Save-Environment $installed $record
        Check ((Find-EnvironmentConfig 'migration-test' $install) -eq $installed) 'Installation directory configuration must take priority'
        Remove-Item -LiteralPath $installed
        $other=Join-Path $env:LOCALAPPDATA 'Packages/Other.App/LocalCache/Local/OpenCAE/environments/migration-test/environment.json'
        $record.environmentId=[guid]::NewGuid().ToString(); Save-Environment $other $record
        Must-Fail { Find-EnvironmentConfig 'migration-test' $install }
        Remove-Item -LiteralPath $legacy; Remove-Item -LiteralPath $other
        $pending=Get-PendingConfigPath $install
        $record.phase='Importing'; $record.registrationId=''; Save-Environment $pending $record
        Check ((Find-EnvironmentConfig 'migration-test' $install) -eq $pending) 'Interrupted import record must be discoverable'
        Remove-Item -LiteralPath $pending
        $record.phase='Removed'; Save-Environment $legacy $record
        Check ($null -eq (Find-EnvironmentConfig 'migration-test' $install)) 'Removed legacy records must not block a fresh installation'
        Check (!(Test-Path -LiteralPath (Join-Path $install 'environment.json'))) 'Pending record must stay outside the import directory'
    } finally {
        $env:LOCALAPPDATA=$previousLocalAppData
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}

& {
    $runtimeTemp=Join-Path ([IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString())
    $source=Join-Path $runtimeTemp 'windows'
    $runtime=Join-Path $runtimeTemp 'ubuntu2404'
    [void][IO.Directory]::CreateDirectory($source); [void][IO.Directory]::CreateDirectory($runtime)
    foreach ($name in @('crew-start.sh','crew-keepalive.sh')) { [IO.File]::WriteAllText((Join-Path $runtime $name),"#!/bin/sh`nexit 0`n") }
    $script:runtimeCalls=@(); $script:runtimeFailure=$false
    function Invoke-Wsl {
        param([string[]]$Arguments,[switch]$Capture)
        $script:runtimeCalls+=,@($Arguments)
        $output=''; $code=0
        if ($Arguments -contains 'wslpath') { $output='/mnt/source with spaces/' + [IO.Path]::GetFileName($Arguments[-1]) }
        if ($script:runtimeFailure -and $Arguments -contains 'cmp') { $code=74 }
        return [pscustomobject]@{Code=$code;Output=$output;Error=''}
    }
    try {
        $runtimeConfig=[pscustomobject]@{distroName='runtime-test';linuxUser='workshop';projectPath='/home/workshop/opencae-workshop2026-env'}
        Sync-CrewRuntime $source $runtimeConfig
        $copies=@($script:runtimeCalls | Where-Object { $_ -contains 'install' })
        Check ($copies.Count -eq 2) 'Updater must deploy startup and lifetime scripts'
        Check ($copies[0][-1] -eq '/home/workshop/opencae-workshop2026-env/setup/ubuntu2404/crew-start.sh') 'Startup update must select the project script'
        Check ($copies[1][-1] -eq '/home/workshop/opencae-workshop2026-env/setup/ubuntu2404/crew-keepalive.sh') 'Lifetime update must select the project script'
        Check (@($script:runtimeCalls | Where-Object { $_ -contains 'cmp' }).Count -eq 2) 'Both runtime copies must be verified'
        $script:runtimeFailure=$true
        Must-Fail { Sync-CrewRuntime $source $runtimeConfig }
    } finally { Remove-Item -LiteralPath $runtimeTemp -Recurse -Force }
}

if ($env:OS -eq 'Windows_NT') {
    # 一時インストール先へ実際の CMD を配置し、空白・日本語パスで起動する。
    $launcherTemp=Join-Path ([IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString() + ' 日本語 test')
    $launcherSource=Join-Path $launcherTemp 'source'
    $launcherInstall=Join-Path $launcherTemp 'installed'
    [void][IO.Directory]::CreateDirectory($launcherSource)
    [void][IO.Directory]::CreateDirectory($launcherInstall)
    try {
        $launcherConfig=[pscustomobject]@{
            schema=1;distroName='launcher-test';linuxUser='workshop';projectPath='/home/workshop/opencae-workshop2026-env'
            port=5476;environmentId=[guid]::NewGuid().ToString();phase='Ready';registrationId='launcher-id';installLocation=$launcherInstall
        }
        $runtimeSource=Join-Path $launcherTemp 'ubuntu2404'
        [void][IO.Directory]::CreateDirectory($runtimeSource)
        foreach ($name in @('crew-start.sh','crew-keepalive.sh')) { [IO.File]::WriteAllText((Join-Path $runtimeSource $name),"#!/bin/sh`nexit 0`n") }
        $dummy=@'
param([string]$ConfigPath,[switch]$InteractiveConfirmation)
[IO.File]::WriteAllText(($PSCommandPath + '.ran'),$ConfigPath)
if ((Split-Path -Leaf $PSCommandPath) -eq 'RemoveEnvironment.ps1') {
    if (!$InteractiveConfirmation) { exit 91 }
    # Allclean の CMD 自体が消えても、親 CMD が正常に終了することを確認。
    Remove-Item -LiteralPath (Join-Path (Split-Path -Parent $PSScriptRoot) '9_Allclean.cmd')
}
exit 0
'@
        foreach ($name in (Get-WindowsScriptFiles)) {
            [IO.File]::WriteAllText((Join-Path $launcherSource $name),$dummy,(New-Object Text.UTF8Encoding($true)))
        }
        [IO.File]::WriteAllText((Join-Path $launcherInstall 'Common.ps1'),'old layout')
        [IO.File]::WriteAllText((Join-Path $launcherInstall 'Start Backend.cmd'),'old layout')
        [IO.File]::WriteAllText((Join-Path $launcherInstall 'user-data.txt'),'keep')
        Install-EnvironmentLaunchers $launcherSource $launcherConfig
        Check (!(Test-Path -LiteralPath (Join-Path $launcherInstall 'Common.ps1'))) 'Old root PS1 must be removed after migration'
        Check (!(Test-Path -LiteralPath (Join-Path $launcherInstall 'Start Backend.cmd'))) 'Old CMD name must be removed after migration'
        Check (Test-Path -LiteralPath (Join-Path $launcherInstall 'user-data.txt')) 'Unrelated files must survive layout migration'
        Check (Test-Path -LiteralPath (Join-Path $launcherInstall 'scripts/RemoveEnvironment.ps1')) 'Removal script must be in the script directory'

        $record=Join-Path $launcherInstall 'environment.json'
        Check (Test-Path -LiteralPath (Join-Path $launcherInstall 'scripts/runtime/crew-keepalive.sh')) 'Runtime update payload must be staged'
        Check ((Read-Environment $record).environmentId -eq $launcherConfig.environmentId) 'Installed record identity changed'
        $commands=@(Get-ChildItem -LiteralPath $launcherInstall -Filter '*.cmd')
        Check ($commands.Count -eq 4) 'Four numbered CMD launchers must be installed'
        $cases=@($commands) + @($commands | Where-Object { $_.Name -eq '1_StartBackend.cmd' })
        $caseIndex=0
        foreach ($command in $cases) {
            $expectedExit=0
            if ($caseIndex -eq 4) {
                $expectedExit=23
                [IO.File]::WriteAllText((Join-Path $launcherInstall 'scripts/StartBackend.ps1'),"exit 23`n")
            }
            $caseIndex++
            $bytes=[IO.File]::ReadAllBytes($command.FullName)
            Check ([Text.Encoding]::ASCII.GetString($bytes).Contains('environment.json') -and [Text.Encoding]::ASCII.GetString($bytes).Contains('scripts\')) 'CMD must bind its adjacent environment record'
            $info=New-Object Diagnostics.ProcessStartInfo
            $info.FileName=Join-Path $env:SystemRoot 'System32\cmd.exe'
            $info.Arguments='/d /c ""' + $command.FullName + '""'
            $info.WorkingDirectory=$launcherSource; $info.UseShellExecute=$false; $info.CreateNoWindow=$true
            $info.RedirectStandardInput=$true; $info.RedirectStandardOutput=$true; $info.RedirectStandardError=$true
            $process=New-Object Diagnostics.Process
            $process.StartInfo=$info
            try {
                [void]$process.Start()
                $stdout=$process.StandardOutput.ReadToEndAsync(); $stderr=$process.StandardError.ReadToEndAsync()
                # StreamWriter の BOM が対話コマンドとして解釈されないよう生の改行を送る。
                $process.StandardInput.BaseStream.WriteByte(13)
                $process.StandardInput.BaseStream.WriteByte(10)
                $process.StandardInput.BaseStream.Flush()
                $process.StandardInput.Close()
                if (!$process.WaitForExit(60000)) {
                    & (Join-Path $env:SystemRoot 'System32/taskkill.exe') /PID $process.Id /T /F | Out-Null
                    [void]$process.WaitForExit(10000)
                    throw ('CMD launcher timed out: ' + $command.Name)
                }
                Check ($process.ExitCode -eq $expectedExit) ('CMD exit code was not preserved: ' + $stderr.Result)
            } finally { $process.Dispose() }
        }
        foreach ($name in @('StartBackend.ps1','StartCrew.ps1','StopCrew.ps1')) {
            Check ([IO.File]::ReadAllText((Join-Path $launcherInstall ('scripts/'+$name+'.ran'))) -eq $record) 'CMD must preserve the adjacent configuration path'
        }
        $foreign=$launcherConfig | Select-Object *
        $foreign.environmentId=[guid]::NewGuid().ToString()
        Must-Fail { Install-EnvironmentLaunchers $launcherSource $foreign }
    } finally { Remove-Item -LiteralPath $launcherTemp -Recurse -Force }
    if ($env:TEST_EXPECTED_ARCH) { Check ((Get-WindowsCpu) -eq $env:TEST_EXPECTED_ARCH) 'Wrong native Windows CPU' }
    . (Join-Path $RepositoryRoot 'setup/windows/Setup.ps1')
    $temp = Join-Path ([IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString())
    $previousLocalAppData=$env:LOCALAPPDATA
    $env:LOCALAPPDATA=$temp
    $script:setupRegistration=$null; $script:setupCalls=@(); $script:setupFailure=$true; $script:setupRefreshFailure=$false
    function Get-SetupArchitecture { return 'amd64' }
    function Get-WorkshopUserRoot { return Join-Path $env:LOCALAPPDATA 'OpenCAE' }
    function Get-WslRegistration { param($DistroName) return $script:setupRegistration }
    function Invoke-WebRequest { param($Uri,$OutFile,[switch]$UseBasicParsing,$Proxy) [IO.File]::WriteAllText($OutFile,'fake-rootfs') }
    function Get-Sha256 { param($LiteralPath) return '8251e27ffff381a4af5f41dcb94d867de3e0d9774a9241908ab34555d99315ea' }
    function Invoke-Wsl {
        param([string[]]$Arguments,[switch]$Capture)
        $script:setupCalls+=,@($Arguments)
        $code=0; $output=''
        if ($Arguments -contains '--import') {
            Check (Test-Path -LiteralPath $Arguments[2] -PathType Container) 'Import directory must exist before wsl --import'
            Check (@(Get-ChildItem -LiteralPath $Arguments[2] -Force).Count -eq 0) 'Import directory must remain empty until import succeeds'
            $script:setupRegistration=[pscustomobject]@{Id='created-id';BasePath=$Arguments[2];Version=2}
        } elseif ($script:setupRefreshFailure -and $Arguments -contains 'cmp') { $code=72 }
        elseif ($Arguments -contains 'wslpath') { $output='/mnt/source with spaces' }
        elseif ($Arguments -contains 'cat') {
            $c=Get-Content $script:setupConfigPath -Raw | ConvertFrom-Json
            $output=$c.environmentId
        } elseif ($script:setupFailure -and ($Arguments -join ' ') -match '/setup.sh') { $code=23 }
        return [pscustomobject]@{Code=$code;Output=$output;Error=''}
    }
    try {
        $options=@{DistroName='test-new';UserName='workshop';InstallLocation=(Join-Path $temp 'disk with spaces');Port=5480}
        $script:setupConfigPath=Join-Path $options.InstallLocation 'environment.json'
        Must-Fail { Invoke-WorkshopSetup @options }
        $file=$script:setupConfigPath
        $c=Read-Environment $file
        Check ($c.phase -eq 'Staged') 'Failed setup must retain the staged phase'
        $script:setupFailure=$false
        Invoke-WorkshopSetup @options
        $c=Read-Environment $file
        Check ($c.phase -eq 'Ready') 'Resumed setup did not complete'
        Check (@($script:setupCalls | Where-Object { $_ -contains '--import' }).Count -eq 1) 'Resume must not reimport'
        Check (@($script:setupCalls | Where-Object { ($_ -join ' ') -match 'stage-project.sh' }).Count -eq 1) 'Resume must not restage'
        Check (Test-Path -LiteralPath (Join-Path $options.InstallLocation '1_StartBackend.cmd')) 'CMD launcher not installed'
        Check (@($script:setupCalls | Where-Object { $_ -contains 'normalize' }).Count -eq 2) 'Initial setup and resume must both normalize shared configuration'
        Check (@($script:setupCalls | Where-Object { $_ -contains 'compare' }).Count -eq 2) 'Version comparison must ignore line ending differences'
        $refreshes=@($script:setupCalls | Where-Object { $_ -contains 'install' -and $_[-1] -match '/scripts/smoke-test.sh$' })
        Check ($refreshes.Count -eq 2) 'Initial setup and resume must both refresh the validation script'
        Check ($refreshes[0][-2] -eq '/mnt/source with spaces/scripts/smoke-test.sh') 'Refresh must use the current Windows checkout'
        Check (@($script:setupCalls | Where-Object { $_ -contains 'cmp' -and $_[-1] -match '/scripts/smoke-test.sh$' }).Count -eq 2) 'Copied validation script must be verified'
        Check (Test-Path (Join-Path $options.InstallLocation 'scripts/StartBackend.ps1')) 'Launchers were not copied'
        $bad=@{}; foreach ($k in $options.Keys) { $bad[$k]=$options[$k] }; $bad.Port=5481
        Must-Fail { Invoke-WorkshopSetup @bad }
        # 別の設定記録がない登録済み環境を流用しない。
        $bad.DistroName='unrelated'
        Must-Fail { Invoke-WorkshopSetup @bad }
        $script:pathPrompt=''
        function Read-Host { param($Prompt) $script:pathPrompt=$Prompt; return '' }
        Invoke-WorkshopSetup -DistroName test-new -UserName workshop -Port 5480
        Check ($script:pathPrompt.Contains($options.InstallLocation)) 'Resume prompt must suggest the saved location'
        Check ((Read-Environment $file).installLocation -eq $options.InstallLocation) 'Enter must preserve the saved location'
        $script:pathPrompt=''
        Invoke-WorkshopSetup @options
        Check ($script:pathPrompt -eq '') 'Explicit InstallLocation must not prompt'
        $script:setupRefreshFailure=$true
        $before=$script:setupCalls.Count
        Must-Fail { Invoke-WorkshopSetup @options }
        $newCalls=@($script:setupCalls | Select-Object -Skip $before)
        Check (@($newCalls | Where-Object { ($_ -join ' ') -match '/setup.sh' }).Count -eq 0) 'Copy verification failure must block the core setup'
    } finally {
        $env:LOCALAPPDATA=$previousLocalAppData
        Remove-Item -LiteralPath $temp -Recurse -Force
    }
}
Write-Host "$count Windows control checks passed. No real WSL environment or browser was launched."
