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
Check ((ConvertTo-NativeArgument 'ubuntu_of_kiro') -eq 'ubuntu_of_kiro') 'Do not quote a simple WSL name'
Check ((ConvertTo-NativeArgument '') -eq '""') 'Empty argument must stay empty'
Check ((ConvertTo-NativeArgument 'C:\path\') -eq 'C:\path\') 'Do not quote a path without spaces'
Check ((ConvertTo-NativeArgument 'C:\path with spaces\') -eq '"C:\path with spaces\\"') 'Quoted trailing backslash escaping'
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
    function Start-Process { param([string]$FilePath) $script:opened+=,$FilePath }
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
    foreach ($url in @('https://evil.example/','http://localhost:9999/','http://user:pass@localhost:5476/')) {
        $script:url=$url
        Must-Fail { Invoke-CrewAction Start $path }
    }
    Check ($script:opened.Count -eq 1) 'Rejected URL was opened'
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
    $script:removedShortcuts=0
    function Get-WslRegistration { param($DistroName) return $script:removalRegistration }
    function Remove-OwnedCrewShortcuts { param($LauncherDirectory,$ConfigPath,$DistroName) $script:removedShortcuts++ }
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
        $script:removalCode=23
        Must-Fail { Remove-WorkshopEnvironment -ConfigPath $file -Confirm:$false }
        Check ((Read-Environment $file).phase -eq 'Removing') 'Removal failure must retain recovery metadata'
        Check ($script:removedShortcuts -eq 0) 'Failed removal must keep shortcuts'
        # WSL 削除後のメタデータ処理失敗からも安全に再開できる。
        $script:removalRegistration=$null
        [IO.File]::WriteAllText((Join-Path $launchers 'StartBackend.ps1'),'managed launcher')
        $keep=Join-Path $directory 'user-file.txt'
        [IO.File]::WriteAllText($keep,'keep')
        Remove-WorkshopEnvironment -ConfigPath $file -Confirm:$false
        Check (!(Test-Path -LiteralPath $file)) 'Successful removal must remove environment.json'
        Check (Test-Path -LiteralPath $keep) 'Unknown metadata files must be kept'
        Check ($script:removedShortcuts -eq 1) 'Successful removal must clean owned shortcuts'
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

if ($env:OS -eq 'Windows_NT') {
    if ($env:TEST_EXPECTED_ARCH) { Check ((Get-WindowsCpu) -eq $env:TEST_EXPECTED_ARCH) 'Wrong native Windows CPU' }
    . (Join-Path $RepositoryRoot 'setup/windows/Setup.ps1')
    $temp = Join-Path ([IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString())
    $previousLocalAppData=$env:LOCALAPPDATA
    $env:LOCALAPPDATA=$temp
    $script:setupRegistration=$null; $script:setupCalls=@(); $script:setupFailure=$true; $script:setupRefreshFailure=$false; $script:shortcuts=0
    function Get-SetupArchitecture { return 'amd64' }
    function Get-WslRegistration { param($DistroName) return $script:setupRegistration }
    function New-CrewShortcuts { param($LauncherDirectory,$ConfigPath,$DistroName) $script:shortcuts++ }
    function Remove-OwnedCrewShortcuts { param($LauncherDirectory,$ConfigPath,$DistroName,[switch]$LegacyOnly) }
    function Invoke-WebRequest { param($Uri,$OutFile,[switch]$UseBasicParsing,$Proxy) [IO.File]::WriteAllText($OutFile,'fake-rootfs') }
    function Get-Sha256 { param($LiteralPath) return '8251e27ffff381a4af5f41dcb94d867de3e0d9774a9241908ab34555d99315ea' }
    function Invoke-Wsl {
        param([string[]]$Arguments,[switch]$Capture)
        $script:setupCalls+=,@($Arguments)
        $code=0; $output=''
        if ($Arguments -contains '--import') {
            Check (Test-Path -LiteralPath $Arguments[2] -PathType Container) 'Import directory must exist before wsl --import'
            $script:setupRegistration=[pscustomobject]@{Id='created-id';BasePath=$Arguments[2];Version=2}
        } elseif ($script:setupRefreshFailure -and $Arguments -contains 'cmp') { $code=72 }
        elseif ($Arguments -contains 'wslpath') { $output='/mnt/source with spaces' }
        elseif ($Arguments -contains 'cat') {
            $c=Get-Content (Join-Path $env:LOCALAPPDATA 'OpenCAE/environments/test-new/environment.json') -Raw | ConvertFrom-Json
            $output=$c.environmentId
        } elseif ($script:setupFailure -and ($Arguments -join ' ') -match '/setup.sh') { $code=23 }
        return [pscustomobject]@{Code=$code;Output=$output;Error=''}
    }
    try {
        $options=@{DistroName='test-new';UserName='workshop';InstallLocation=(Join-Path $temp 'disk with spaces');Port=5480}
        Must-Fail { Invoke-WorkshopSetup @options }
        $file=Join-Path $temp 'OpenCAE/environments/test-new/environment.json'
        $c=Read-Environment $file
        Check ($c.phase -eq 'Staged') 'Failed setup must retain the staged phase'
        $script:setupFailure=$false
        Invoke-WorkshopSetup @options
        $c=Read-Environment $file
        Check ($c.phase -eq 'Ready') 'Resumed setup did not complete'
        Check (@($script:setupCalls | Where-Object { $_ -contains '--import' }).Count -eq 1) 'Resume must not reimport'
        Check (@($script:setupCalls | Where-Object { ($_ -join ' ') -match 'stage-project.sh' }).Count -eq 1) 'Resume must not restage'
        Check ($script:shortcuts -eq 1) 'Shortcuts not created'
        $refreshes=@($script:setupCalls | Where-Object { $_ -contains 'install' -and $_[-1] -match '/scripts/smoke-test.sh$' })
        Check ($refreshes.Count -eq 2) 'Initial setup and resume must both refresh the validation script'
        Check ($refreshes[0][-2] -eq '/mnt/source with spaces/scripts/smoke-test.sh') 'Refresh must use the current Windows checkout'
        Check (@($script:setupCalls | Where-Object { $_ -contains 'cmp' -and $_[-1] -match '/scripts/smoke-test.sh$' }).Count -eq 2) 'Copied validation script must be verified'
        Check (Test-Path (Join-Path $temp 'OpenCAE/environments/test-new/launchers/StartBackend.ps1')) 'Launchers were not copied'
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
