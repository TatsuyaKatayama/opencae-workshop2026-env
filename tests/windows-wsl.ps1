param([string]$DistroName = 'Ubuntu-24.04')
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../setup/windows/Common.ps1')
function Run-Linux {
    param([string[]]$Command, [string]$User = 'root')
    $result = Invoke-Wsl -Capture -Arguments (@('-d',$DistroName,'-u',$User,'--exec') + $Command)
    Assert-WslResult $result 'WSL boundary test'
    return $result.Output.Trim()
}
# Fail rather than treating WSL1 or a mocked invocation as WSL2 coverage.
$kernel = Run-Linux @('uname','-r')
if ($kernel -notmatch '(?i)microsoft.*WSL2') { throw "Expected actual WSL2 kernel: $kernel" }
[void](Run-Linux @('bash','-eu','-c','source /etc/os-release; test "$ID:$VERSION_ID" = ubuntu:24.04; command -v python3'))
$literal = 'space 日本語 "quoted" $(touch /tmp/opencae-injected) trailing\'
$probe = 'import json,sys; print(json.dumps(sys.argv[1:],ensure_ascii=False)); print("stderr 日本語",file=sys.stderr); sys.exit(42)'
$result = Invoke-Wsl -Capture -Arguments @('-d',$DistroName,'-u','root','--exec','python3','-c',$probe,$literal)
if ($result.Code -ne 42 -or $result.Error.Trim() -ne 'stderr 日本語') { throw 'WSL exit status / stderr lost.' }
$actual = @(ConvertFrom-Json $result.Output)
if ($actual.Count -ne 1 -or $actual[0] -cne $literal) { throw 'WSL argument quoting or Unicode transfer failed.' }
[void](Run-Linux @('test','!','-e','/tmp/opencae-injected'))
$identity = 'e4f75ac9-6899-44bd-942e-0ced2f8301dc'
# Only the disposable CI distro is modified. No Docker/CFD install duplication.
[void](Run-Linux @('bash','-eu','-c',('id ciuser >/dev/null 2>&1 || useradd -m -s /bin/bash ciuser; printf %s ' + $identity + ' > /etc/opencae-environment-id')))
$fixture = Join-Path $env:RUNNER_TEMP 'project 日本語 with spaces'
[void][IO.Directory]::CreateDirectory($fixture)
try {
    # Exercise the same staging script with a Windows checkout (including CRLF env).
    $repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).ProviderPath
    Copy-Item -LiteralPath (Join-Path $repo 'setup') -Destination $fixture -Recurse -Force
    Copy-Item -LiteralPath (Join-Path $repo 'scripts') -Destination $fixture -Recurse -Force
    Copy-Item -LiteralPath (Join-Path $repo 'examples') -Destination $fixture -Recurse -Force
    Copy-Item -LiteralPath (Join-Path $repo 'PROJECT_SPEC.md') -Destination $fixture -Force
    $envText = [IO.File]::ReadAllText((Join-Path $repo 'versions.env')).Replace("`r`n","`n").Replace("`n","`r`n")
    [IO.File]::WriteAllText((Join-Path $fixture 'versions.env'),$envText,(New-Object Text.UTF8Encoding($false)))
    foreach ($private in @('.git','work','.aws','.codex','.agents')) {
        [void][IO.Directory]::CreateDirectory((Join-Path $fixture $private))
        [IO.File]::WriteAllText((Join-Path (Join-Path $fixture $private) 'private.txt'),'must not stage')
    }
    $linuxSource = Run-Linux @('wslpath','-a','-u',$fixture)
    $stage = "$linuxSource/setup/ubuntu2404/stage-project.sh"
    [void](Run-Linux -User ciuser -Command @('bash',$stage,$linuxSource,'/home/ciuser/opencae-workshop2026-env',$identity))
    [void](Run-Linux -User ciuser -Command @('python3','-c',@'
from pathlib import Path
import os
p = Path.home() / 'opencae-workshop2026-env'
assert (p / 'PROJECT_SPEC.md').is_file()
assert (p / 'versions.env').stat().st_uid == os.getuid()
assert b'\r' not in (p / 'versions.env').read_bytes()
assert all(not (p / x).exists() for x in ('.git','work','.aws','.codex','.agents'))
(p / 'preserved.txt').write_text('keep')
'@))
    [void](Run-Linux -User ciuser -Command @('bash',$stage,$linuxSource,'/home/ciuser/opencae-workshop2026-env',$identity))
    [void](Run-Linux -User ciuser -Command @('test','-f','/home/ciuser/opencae-workshop2026-env/preserved.txt'))
    Write-Host 'PASS: actual WSL2, Unicode/quoted arguments, stdout/stderr, exit 42, Windows project staging, LF normalization, private-file exclusion and repeat staging.'
} finally {
    if (Test-Path -LiteralPath $fixture) { Remove-Item -LiteralPath $fixture -Recurse -Force }
}
