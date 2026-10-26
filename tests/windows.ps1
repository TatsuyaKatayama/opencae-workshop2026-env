param([string]$RepositoryRoot = (Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference = 'Stop'
. (Join-Path $RepositoryRoot 'setup/windows/Common.ps1')
$count = 0
function Check { param([bool]$Condition,[string]$Message) if (!$Condition) { throw $Message }; $script:count++ }
function Must-Fail { param([scriptblock]$Code) $failed=$false; try { & $Code } catch { $failed=$true }; Check $failed 'Expected failure' }

foreach ($file in Get-ChildItem (Join-Path $RepositoryRoot 'setup/windows') -Filter '*.ps1') {
    $tokens=$null; $errors=$null
    [void][System.Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$errors)
    Check ($errors.Count -eq 0) "Parse failure: $($file.Name): $errors"
}
Assert-Names 'custom-env_2026' 'workshop'
foreach ($name in @('bad name','../bad','bad;echo','bad"name')) { Must-Fail { Assert-Names $name 'user' } }
foreach ($name in @('root','UPPER','bad name','x;echo')) { Must-Fail { Assert-Names 'test' $name } }
Check ((ConvertTo-NativeArgument 'a b') -eq '"a b"') 'Space quoting'
Check ((ConvertTo-NativeArgument 'a"b') -eq '"a\"b"') 'Quote escaping'
Check ((ConvertTo-NativeArgument 'C:\path\') -eq '"C:\path\\"') 'Trailing backslash escaping'

$temp = Join-Path ([IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString())
[void][IO.Directory]::CreateDirectory($temp)
try {
    $path=Join-Path $temp 'environment.json'
    $script:config = [pscustomobject]@{
        schema=1; distroName='custom-env'; linuxUser='workshop'; projectPath='/home/workshop/opencae-workshop2026-env'
        port=5476; environmentId=[guid]::NewGuid().ToString(); phase='Ready'; registrationId='test-registration'; installLocation=$temp
    }
    Save-Environment $path $config
    $loaded=Read-Environment $path
    Check ($loaded.distroName -eq 'custom-env') 'Configuration roundtrip'
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
if ($env:OS -eq 'Windows_NT') {
    if ($env:TEST_EXPECTED_ARCH) { Check ((Get-WindowsCpu) -eq $env:TEST_EXPECTED_ARCH) 'Wrong native Windows CPU' }
    . (Join-Path $RepositoryRoot 'setup/windows/Setup.ps1')
    $temp = Join-Path ([IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString())
    $previousLocalAppData=$env:LOCALAPPDATA
    $env:LOCALAPPDATA=$temp
    $script:setupRegistration=$null; $script:setupCalls=@(); $script:setupFailure=$true; $script:shortcuts=0
    function Get-SetupArchitecture { return 'amd64' }
    function Get-WslRegistration { param($DistroName) return $script:setupRegistration }
    function New-CrewShortcuts { param($LauncherDirectory,$ConfigPath,$DistroName) $script:shortcuts++ }
    function Invoke-WebRequest { param($Uri,$OutFile,[switch]$UseBasicParsing,$Proxy) [IO.File]::WriteAllText($OutFile,'fake-rootfs') }
    function Get-FileHash { param($LiteralPath,$Algorithm) return [pscustomobject]@{Hash='8251e27ffff381a4af5f41dcb94d867de3e0d9774a9241908ab34555d99315ea'} }
    function Invoke-Wsl {
        param([string[]]$Arguments,[switch]$Capture)
        $script:setupCalls+=,@($Arguments)
        $code=0; $output=''
        if ($Arguments -contains '--import') {
            $script:setupRegistration=[pscustomobject]@{Id='created-id';BasePath=$Arguments[2];Version=2}
        } elseif ($Arguments -contains 'wslpath') { $output='/mnt/source with spaces' }
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
        Check (Test-Path (Join-Path $temp 'OpenCAE/environments/test-new/launchers/KiroLogin.ps1')) 'Launchers were not copied'
        $bad=@{}; foreach ($k in $options.Keys) { $bad[$k]=$options[$k] }; $bad.Port=5481
        Must-Fail { Invoke-WorkshopSetup @bad }
        # 別の設定記録がない登録済み環境を流用しない。
        $bad.DistroName='unrelated'
        Must-Fail { Invoke-WorkshopSetup @bad }
    } finally {
        $env:LOCALAPPDATA=$previousLocalAppData
        Remove-Item -LiteralPath $temp -Recurse -Force
    }
}
Write-Host "$count Windows control checks passed. No real WSL environment or browser was launched."
