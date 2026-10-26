#requires -version 5.1
[CmdletBinding()]
param(
    [string]$DistroName = 'opencae-workshop2026',
    [string]$UserName,
    [string]$InstallLocation,
    [ValidateRange(1024,65535)][int]$Port = 5476,
    [switch]$EnableProxyPreview,
    [string]$ProxyConfig
)
. "$PSScriptRoot/Common.ps1"

function Invoke-WorkshopSetup {
param(
    [string]$DistroName = 'opencae-workshop2026',
    [string]$UserName,
    [string]$InstallLocation,
    [ValidateRange(1024,65535)][int]$Port = 5476,
    [switch]$EnableProxyPreview,
    [string]$ProxyConfig
)
    $arch = Get-SetupArchitecture
    if (!$UserName) { $UserName = Read-Host 'Linux user name (lowercase)' }
    Assert-Names $DistroName $UserName
    $homeDirectory = Join-Path $env:LOCALAPPDATA "OpenCAE\environments\$DistroName"
    $configPath = Join-Path $homeDirectory 'environment.json'
    if (!$InstallLocation) { $InstallLocation = Join-Path $env:LOCALAPPDATA "OpenCAE\WSL\$DistroName" }
    $InstallLocation = [IO.Path]::GetFullPath($InstallLocation)
    if ($InstallLocation -notmatch '^[A-Za-z]:\\' -or $InstallLocation -match '[\r\n]') { throw 'Use an absolute path on a local Windows drive.' }
    if ($EnableProxyPreview -ne [bool]$ProxyConfig) { throw 'Specify both -EnableProxyPreview and -ProxyConfig.' }
    $proxyEnvironment = @()
    $webProxy = $null
    if ($EnableProxyPreview) {
        $proxy = Get-Content -LiteralPath $ProxyConfig -Raw | ConvertFrom-Json
        foreach ($name in @('httpProxy','httpsProxy')) {
            $value = [string]$proxy.$name
            if ($value) {
                $uri = [Uri]$value
                if ($uri.Scheme -notin @('http','https') -or !$uri.Host -or $uri.UserInfo -or $value -match '[\r\n]') { throw 'Proxy preview supports unauthenticated HTTP(S) proxies only.' }
            }
        }
        $noProxy = 'localhost,127.0.0.1,::1,' + [string]$proxy.noProxy
        if ($noProxy -match '[\r\n]') { throw 'Invalid noProxy.' }
        foreach ($pair in @(@('http_proxy',$proxy.httpProxy),@('https_proxy',$proxy.httpsProxy),@('no_proxy',$noProxy))) {
            $proxyEnvironment += "$($pair[0])=$($pair[1])"
        }
        $webProxy = if ($proxy.httpsProxy) { $proxy.httpsProxy } else { $proxy.httpProxy }
        Write-Warning 'Proxy preview: no proxy authentication or custom CA support.'
    }
    $repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
    $registration = Get-WslRegistration $DistroName
    if (Test-Path -LiteralPath $configPath) {
        $config = Read-Environment $configPath
        if ($config.linuxUser -ne $UserName -or $config.installLocation -ine $InstallLocation -or $config.port -ne $Port) { throw 'Existing setup options differ. Use the original options.' }
        if ($registration) {
            if (!$config.registrationId -and $config.phase -eq 'Importing') {
                $base = $registration.BasePath -replace '^\\\\\?\\', ''
                if ([IO.Path]::GetFullPath($base).TrimEnd('\') -ine $InstallLocation.TrimEnd('\')) { throw 'Import registration path mismatch.' }
                $config.registrationId = $registration.Id
                Save-Environment $configPath $config
            }
            Assert-Registration $config
        } elseif ($config.phase -ne 'Importing') { throw 'Previously created WSL environment is missing.' }
    } else {
        if ($registration) { throw 'WSL name already exists. Choose a new name.' }
        if ((Test-Path -LiteralPath $InstallLocation) -and @(Get-ChildItem -LiteralPath $InstallLocation -Force).Count) { throw 'Install location is not empty.' }
        $config = [pscustomobject]@{
            schema=1; distroName=$DistroName; linuxUser=$UserName; installLocation=$InstallLocation
            projectPath="/home/$UserName/opencae-workshop2026-env"; port=$Port
            environmentId=[guid]::NewGuid().ToString(); registrationId=''; phase='Importing'
        }
        Save-Environment $configPath $config
    }
    if (!$registration) {
        if ((Test-Path -LiteralPath $InstallLocation) -and @(Get-ChildItem -LiteralPath $InstallLocation -Force).Count) { throw 'Install location contains data. Inspect the interrupted import manually.' }
        $images = Get-Content -LiteralPath (Join-Path $repo 'setup/config/wsl.json') -Raw | ConvertFrom-Json
        $image = $images.$arch
        $cache = Join-Path $env:LOCALAPPDATA 'OpenCAE\downloads'
        [void][IO.Directory]::CreateDirectory($cache)
        $archive = Join-Path $cache $image.file
        if (!(Test-Path -LiteralPath $archive) -or (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash -ine $image.sha256) {
            $download = @{ Uri=($images.baseUrl+$image.file); OutFile=($archive+'.part'); UseBasicParsing=$true }
            if ($webProxy) { $download.Proxy=$webProxy }
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            Invoke-WebRequest @download
            if ((Get-FileHash -LiteralPath ($archive+'.part') -Algorithm SHA256).Hash -ine $image.sha256) { throw 'Ubuntu rootfs SHA256 mismatch.' }
            Move-Item -LiteralPath ($archive+'.part') -Destination $archive -Force
        }
        $result = Invoke-Wsl -Arguments @('--import',$DistroName,$InstallLocation,$archive,'--version','2')
        Assert-WslResult $result 'Ubuntu import'
        $registration = Get-WslRegistration $DistroName
        if (!$registration) { throw 'Imported WSL registration was not found.' }
        $config.registrationId = $registration.Id
        Save-Environment $configPath $config
        Assert-Registration $config
    }
    $result = Invoke-Wsl -Capture -Arguments @('-d',$DistroName,'-u','root','--exec','wslpath','-a','-u',$repo)
    Assert-WslResult $result 'Project path conversion'
    $linuxSource = $result.Output.Trim()
    if ($config.phase -eq 'Importing') {
        $bootstrapArguments = @('-d',$DistroName,'-u','root','--exec','env') + $proxyEnvironment + @('bash',"$linuxSource/setup/ubuntu2404/bootstrap-wsl.sh",$UserName,$config.environmentId)
        Assert-WslResult (Invoke-Wsl -Arguments $bootstrapArguments) 'Linux user initialization'
        Assert-WslResult (Invoke-Wsl -Arguments @('--terminate',$DistroName)) 'WSL restart'
        $config.phase='Initialized'; Save-Environment $configPath $config
    }
    $identity = Invoke-Wsl -Capture -Arguments @('-d',$DistroName,'-u','root','--exec','cat','/etc/opencae-environment-id')
    Assert-WslResult $identity 'Environment identity check'
    if ($identity.Output.Trim() -ne $config.environmentId) { throw 'Environment identity mismatch.' }
    if ($config.phase -eq 'Initialized') {
        Assert-WslResult (Invoke-Wsl -Arguments @('-d',$DistroName,'-u',$UserName,'--exec','bash',"$linuxSource/setup/ubuntu2404/stage-project.sh",$linuxSource,$config.projectPath,$config.environmentId)) 'Project staging'
        $config.phase='Staged'; Save-Environment $configPath $config
    }
    $coreArgs = Get-UserArguments $config 'setup.sh'
    if ($EnableProxyPreview) {
        $winProxy = (Resolve-Path -LiteralPath $ProxyConfig).Path
        $r = Invoke-Wsl -Capture -Arguments @('-d',$DistroName,'-u',$UserName,'--exec','wslpath','-a','-u',$winProxy)
        Assert-WslResult $r 'Proxy path conversion'
        $privateProxy = "/home/$UserName/.opencae-proxy.json"
        Assert-WslResult (Invoke-Wsl -Arguments @('-d',$DistroName,'-u',$UserName,'--exec','install','-m','600',$r.Output.Trim(),$privateProxy)) 'Proxy configuration copy'
        $coreArgs += @('--enable-proxy-preview','--proxy-config',$privateProxy)
    }
    $coreArgs += @('--port',[string]$Port)
    Assert-WslResult (Invoke-Wsl -Arguments $coreArgs) 'Ubuntu tool setup and CFD validation'
    $launchers = Join-Path $homeDirectory 'launchers'
    [void][IO.Directory]::CreateDirectory($launchers)
    foreach ($file in @('Common.ps1','KiroLogin.ps1','StartCrew.ps1','StopCrew.ps1')) {
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot $file) -Destination (Join-Path $launchers $file) -Force
    }
    New-CrewShortcuts $launchers $configPath $DistroName
    $config.phase='Ready'; Save-Environment $configPath $config
    Write-Host 'Setup complete. On the workshop day: Kiro CLI Login, then Start Kiro Crew.'
}

if ($MyInvocation.InvocationName -ne '.') {
    try {
        Invoke-WorkshopSetup @PSBoundParameters
    } catch {
        Write-Host $_.Exception.Message -ForegroundColor Red
        Write-Host 'Setup stopped. Correct the error and rerun with the same options. Existing environments are not deleted.'
        exit 1
    }
}
