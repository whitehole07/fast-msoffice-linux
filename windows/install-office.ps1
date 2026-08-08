# Installs Microsoft 365 apps. Runs elevated at first logon via autounattend.xml,
# and is also safe to run by hand:
#   powershell -ExecutionPolicy Bypass -File install-office.ps1
#
# Best effort by design: if the download or install fails, setup carries on and
# you can install Office manually from https://office.com. That is preferable
# to leaving a half-configured machine because a CDN was unreachable.
#
# This installs the software only. Activation is separate: sign in inside Excel
# or PowerPoint with your Microsoft 365 account the first time you open one.
#
# Keep this file pure ASCII (Windows PowerShell 5.1 reads BOM-less files as
# Windows-1252).

$ErrorActionPreference = 'Continue'
$log = "$env:SystemDrive\m365-office-install.log"
function Say($m) { Write-Host "==> $m"; Add-Content -Path $log -Value "$(Get-Date -f s) $m" }

if (Test-Path "$env:ProgramFiles\Microsoft Office\root\Office16\POWERPNT.EXE") {
    Say "Office is already installed, nothing to do"
    exit 0
}

# The Click-to-Run bootstrapper: a small stub that streams the current build
# from Microsoft's CDN. No product key needed here - the subscription is what
# licenses it, and that is checked when you sign in.
$url = 'https://c2rsetup.officeapps.live.com/c2r/download.aspx?ProductreleaseID=O365ProPlusRetail&platform=x64&language=en-us&version=O16GA'
$exe = "$env:TEMP\OfficeSetup.exe"

Say "Downloading the Office installer"
try {
    # Progress rendering makes Invoke-WebRequest dramatically slower on large
    # files, and nobody is watching this run anyway.
    $ProgressPreference = 'SilentlyContinue'
    Invoke-WebRequest -Uri $url -OutFile $exe -UseBasicParsing -TimeoutSec 600
} catch {
    Say "Download failed: $($_.Exception.Message)"
    Say "Install Office manually from https://office.com when convenient"
    exit 0
}

if (-not (Test-Path $exe)) { Say "Installer missing after download"; exit 0 }

Say "Installing Office - this takes a while and needs no input"
try {
    Start-Process -FilePath $exe -Wait
} catch {
    Say "Installer returned an error: $($_.Exception.Message)"
}

if (Test-Path "$env:ProgramFiles\Microsoft Office\root\Office16\POWERPNT.EXE") {
    Say "Office installed"
} else {
    Say "Office does not appear to be installed; do it manually from https://office.com"
}
Remove-Item $exe -ErrorAction SilentlyContinue
