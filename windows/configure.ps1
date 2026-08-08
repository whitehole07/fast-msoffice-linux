# Runs automatically at first logon, elevated, via autounattend.xml.
# Also safe to run by hand later:  powershell -ExecutionPolicy Bypass -File configure.ps1
#
# Everything Windows needs for this setup, in one place. Idempotent - re-running
# only re-asserts the same values.
#
# NOTE: keep this file pure ASCII. Windows PowerShell 5.1 reads BOM-less files
# as Windows-1252, so a UTF-8 dash breaks parsing with a confusing
# "string is missing the terminator" error.

$ErrorActionPreference = 'Continue'
$log = "$env:SystemDrive\m365-configure.log"
function Say($m) { Write-Host "==> $m"; Add-Content -Path $log -Value "$(Get-Date -f s) $m" }

Say "Enabling Remote Desktop"
Set-ItemProperty 'HKLM:\System\CurrentControlSet\Control\Terminal Server' `
    -Name fDenyTSConnections -Value 0 -Type DWord
Set-ItemProperty 'HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' `
    -Name UserAuthentication -Value 1 -Type DWord
Enable-NetFirewallRule -DisplayGroup 'Remote Desktop' -ErrorAction SilentlyContinue

Say "Allowing any application to be published as a RemoteApp"
# Without this, launching an app as a RemoteApp fails with
# RAIL_EXEC_E_NOT_IN_ALLOWLIST and the session is dropped immediately.
# The VM is only reachable on host loopback, so this is not network-exposed.
$ts = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Terminal Server\TSAppAllowList'
New-Item -Path $ts -Force | Out-Null
Set-ItemProperty -Path $ts -Name fDisabledAllowList -Value 1 -Type DWord

Say "Raising the RDP frame rate to ~60fps"
# Windows throttles RDP compositing to about 30fps by default; this is the
# minimum inter-frame interval in milliseconds.
$pol = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services'
New-Item -Path $pol -Force | Out-Null
Set-ItemProperty -Path $pol -Name DWMFRAMEINTERVAL -Value 15 -Type DWord
Set-ItemProperty -Path $pol -Name AVC444ModePreferred -Value 1 -Type DWord

Say "Disabling Virtualization-Based Security"
# Windows 11 enables VBS and Memory Integrity by default. Inside a VM that
# means nested virtualisation, which slows down everything. These protect
# credentials on real hardware; this is a disposable sandbox on loopback.
$dg = 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard'
New-Item -Path $dg -Force | Out-Null
Set-ItemProperty -Path $dg -Name EnableVirtualizationBasedSecurity -Value 0 -Type DWord
New-Item -Path "$dg\Scenarios\HypervisorEnforcedCodeIntegrity" -Force | Out-Null
Set-ItemProperty -Path "$dg\Scenarios\HypervisorEnforcedCodeIntegrity" -Name Enabled -Value 0 -Type DWord
bcdedit /set hypervisorlaunchtype off | Out-Null

Say "Setting the High Performance power plan and disabling hibernation"
powercfg /setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c 2>$null
powercfg /hibernate off 2>$null

Say "Trimming visual effects"
# No GPU here, so the desktop compositor renders on the CPU. Animations and
# shadows cost real frames. ClearType stays: disabling it only makes text worse.
$vfx = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects'
New-Item -Path $vfx -Force | Out-Null
Set-ItemProperty -Path $vfx -Name VisualFXSetting -Value 2 -Type DWord
Set-ItemProperty 'HKCU:\Control Panel\Desktop\WindowMetrics' -Name MinAnimate -Value 0 -Type String
Set-ItemProperty 'HKCU:\Control Panel\Desktop' -Name MenuShowDelay -Value 0 -Type String
Set-ItemProperty 'HKCU:\Control Panel\Desktop' -Name FontSmoothing -Value 2 -Type String

Say "Turning off Office hardware graphics acceleration"
# Office renders shapes through Direct3D; with no GPU that falls back to WARP,
# Microsoft's software rasteriser, which is slower than Office's plain drawing
# path. This is the main fix for laggy object dragging in PowerPoint over RDP.
# 16.0 covers every Office release from 2016 onwards, including Microsoft 365.
$gfx = 'HKCU:\Software\Microsoft\Office\16.0\Common\Graphics'
New-Item -Path $gfx -Force | Out-Null
Set-ItemProperty -Path $gfx -Name DisableHardwareAcceleration -Value 1 -Type DWord
Set-ItemProperty -Path $gfx -Name DisableAnimations -Value 1 -Type DWord

Say "Installing virtio drivers if the driver CD is present"
# Pre-installing NetKVM lets the host switch the NIC to virtio-net later
# without the VM losing its network.
$virtio = Get-Volume | Where-Object { $_.FileSystemLabel -like 'virtio-win*' } | Select-Object -First 1
if ($virtio) {
    $msi = "$($virtio.DriveLetter):\virtio-win-gt-x64.msi"
    if (Test-Path $msi) {
        Start-Process msiexec.exe -ArgumentList "/i `"$msi`" /qn /norestart" -Wait
        Say "virtio drivers installed"
    }
} else {
    Say "no virtio CD found, skipping drivers"
}

Say "Disabling the auto-logon used to run this script"
# autounattend.xml signs this account in automatically so these commands can
# run. Left enabled, Windows keeps a console session open forever, and every
# RDP connection then has to ask permission to take it over - a prompt no
# automated script can answer. Turning it off means the reboot below leaves the
# machine at a login screen with no session, so RDP connects cleanly.
$wl = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
Set-ItemProperty -Path $wl -Name 'AutoAdminLogon' -Value '0' -Type String
Remove-ItemProperty -Path $wl -Name 'DefaultPassword'  -ErrorAction SilentlyContinue
Remove-ItemProperty -Path $wl -Name 'AutoLogonCount'   -ErrorAction SilentlyContinue
Remove-ItemProperty -Path $wl -Name 'DefaultUserName'  -ErrorAction SilentlyContinue

Say "Done. A reboot applies the security and driver changes."
