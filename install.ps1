$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$Repository = 'tonykastaneda/yakkity'
$Branch = 'main'
$InstallDir = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'Programs\yakkity'
$ScriptPath = Join-Path $InstallDir 'yakk.ps1'
$LauncherPath = Join-Path $InstallDir 'yakk.cmd'
$DownloadUrl = "https://raw.githubusercontent.com/$Repository/$Branch/yakk.ps1"

if (-not [Environment]::Is64BitOperatingSystem) {
    throw 'yakkity requires 64-bit Windows.'
}

if (-not (Get-Command fzf -ErrorAction SilentlyContinue)) {
    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if (-not $winget) {
        throw 'fzf is required. Install fzf, then rerun this installer. See https://github.com/junegunn/fzf#installation'
    }
    Write-Host 'Installing fzf with Winget...'
    & $winget.Source install --id junegunn.fzf --exact --accept-package-agreements --accept-source-agreements
    if ($LASTEXITCODE -ne 0) { throw 'Winget could not install fzf.' }
}

New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
Write-Host 'Downloading yakkity...'
$client = [Net.WebClient]::new()
$client.Headers['User-Agent'] = 'yakkity-installer'
$client.DownloadFile($DownloadUrl, $ScriptPath)

$launcher = '@echo off' + "`r`n" + 'set "yakk_args=%*"' + "`r`n" + 'set "yakk_args=%yakk_args:--=-%"' + "`r`n" + 'powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0yakk.ps1" %yakk_args%' + "`r`n"
[IO.File]::WriteAllText($LauncherPath, $launcher, [Text.ASCIIEncoding]::new())

$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
$parts = @($userPath -split ';' | Where-Object { $_ })
if ($parts -notcontains $InstallDir) {
    $newPath = (($parts + $InstallDir) -join ';')
    [Environment]::SetEnvironmentVariable('Path', $newPath, 'User')
    Write-Host "Added $InstallDir to your user PATH."
}
if (($env:Path -split ';') -notcontains $InstallDir) { $env:Path += ";$InstallDir" }

& $LauncherPath --version
Write-Host "Installed: $LauncherPath"
Write-Host 'Open a new terminal, then run: yakk --help'
