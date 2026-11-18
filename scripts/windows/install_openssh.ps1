# ==============================================================================
# LapDeck Windows OpenSSH Server Setup & Key Provisioning
# ==============================================================================
# Self-elevation check
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "[!] Not running as Administrator. Requesting elevated privileges..." -ForegroundColor Yellow
    Start-Process powershell -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    exit
}

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  LapDeck & Antigravity - Windows OpenSSH Server Installer  " -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

# 1. Install OpenSSH.Server capability if not present
Write-Host "`n[1/6] Checking Windows OpenSSH Server capability..." -ForegroundColor Yellow
$sshdBin = "$env:SystemRoot\System32\OpenSSH\sshd.exe"
$serviceObj = Get-Service -Name sshd -ErrorAction SilentlyContinue

if ((Test-Path $sshdBin) -or $serviceObj) {
    Write-Host "[✓] OpenSSH Server is already installed and present." -ForegroundColor Green
} else {
    $sshCapability = Get-WindowsCapability -Online | Where-Object Name -like 'OpenSSH.Server*'
    if ($sshCapability.State -ne 'Installed') {
        Write-Host "[+] Ensuring Windows Update service is running..." -ForegroundColor Cyan
        Start-Service wuauserv -ErrorAction SilentlyContinue
        Write-Host "[+] Installing OpenSSH.Server capability (requires Internet)..." -ForegroundColor Cyan
        Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
        Write-Host "[✓] OpenSSH Server capability installed." -ForegroundColor Green
    } else {
        Write-Host "[✓] OpenSSH Server is already installed." -ForegroundColor Green
    }
}

# 2. Configure Default Shell to PowerShell
Write-Host "`n[2/6] Setting default SSH login shell to PowerShell..." -ForegroundColor Yellow
if (-not (Test-Path "HKLM:\SOFTWARE\OpenSSH")) {
    New-Item -Path "HKLM:\SOFTWARE\OpenSSH" -Force | Out-Null
}
New-ItemProperty -Path "HKLM:\SOFTWARE\OpenSSH" -Name DefaultShell -Value "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" -PropertyType String -Force | Out-Null
Write-Host "[✓] Default shell configured: powershell.exe" -ForegroundColor Green

# 3. Configure and start sshd service
Write-Host "`n[3/6] Configuring sshd service..." -ForegroundColor Yellow
Set-Service -Name sshd -StartupType 'Automatic'
$service = Get-Service -Name sshd
if ($service.Status -ne 'Running') {
    Start-Service sshd
    Write-Host "[✓] sshd service started." -ForegroundColor Green
} else {
    Write-Host "[✓] sshd service is already running." -ForegroundColor Green
}

# Also ensure ssh-agent is enabled
Set-Service -Name "ssh-agent" -StartupType 'Automatic'
Start-Service "ssh-agent" -ErrorAction SilentlyContinue

# 4. Open Windows Firewall rule for TCP 22
Write-Host "`n[4/6] Configuring Windows Defender Firewall for TCP port 22..." -ForegroundColor Yellow
$fwRule = Get-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -ErrorAction SilentlyContinue
if (-not $fwRule) {
    New-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -DisplayName 'OpenSSH Server (sshd)' -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22 -Profile Any | Out-Null
    Write-Host "[✓] Inbound firewall rule created for TCP port 22 (All profiles)." -ForegroundColor Green
} else {
    Set-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -Enabled True -Profile Any | Out-Null
    Write-Host "[✓] Firewall rule already exists (Profile set to Any)." -ForegroundColor Green
}

# 5. Provision Ed25519 SSH Keys
Write-Host "`n[5/6] Provisioning Ed25519 authorized keys for user qwerk..." -ForegroundColor Yellow
$keys = @(
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDQ8rWJU0aRTiJuO9wv605zgsTbxZKabA0y6K1wLlsOL qwerky2003hush@gmail.com",
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICw170+V0Xk/Qq8fYMcKStpsTznV9lJDtHQIHdY31Qxp qwerk@MochironDesu"
)

# A. User profile .ssh/authorized_keys
$userSshDir = "$env:USERPROFILE\.ssh"
if (-not (Test-Path $userSshDir)) {
    New-Item -ItemType Directory -Path $userSshDir -Force | Out-Null
}
$userAuthKeys = "$userSshDir\authorized_keys"
$keys | Out-File -FilePath $userAuthKeys -Encoding ascii -Force
Write-Host "[✓] Written user keys to: $userAuthKeys" -ForegroundColor Green

# B. Administrators authorized_keys (Required when qwerk is an Administrator)
$adminSshDir = "$env:ProgramData\ssh"
if (-not (Test-Path $adminSshDir)) {
    New-Item -ItemType Directory -Path $adminSshDir -Force | Out-Null
}
$adminAuthKeys = "$adminSshDir\administrators_authorized_keys"
$keys | Out-File -FilePath $adminAuthKeys -Encoding ascii -Force
Write-Host "[✓] Written administrator keys to: $adminAuthKeys" -ForegroundColor Green

# C. Apply strict NTFS ACL permissions (crucial for sshd to accept keys)
Write-Host "[*] Applying strict NTFS ACLs on administrators_authorized_keys..." -ForegroundColor Yellow
icacls.exe $adminAuthKeys /inheritance:r /grant "SYSTEM:(F)" "BUILTIN\Administrators:(F)" | Out-Null
Write-Host "[✓] Strict ACLs applied (SYSTEM and BUILTIN\Administrators only)." -ForegroundColor Green

# 6. Restart sshd service and verify
Write-Host "`n[6/6] Restarting sshd to apply all changes..." -ForegroundColor Yellow
Restart-Service sshd
Start-Sleep -Seconds 2

$conn = Get-NetTCPConnection -LocalPort 22 -State Listen -ErrorAction SilentlyContinue
if ($conn) {
    Write-Host "[✓] VERIFIED: sshd is listening on TCP port 22!" -ForegroundColor Green
} else {
    Write-Host "[!] Warning: Port 22 not yet detected in Listen state. Check service status." -ForegroundColor Yellow
}

Write-Host "`n============================================================" -ForegroundColor Cyan
Write-Host "  Setup Complete! OpenSSH Server is active.                " -ForegroundColor Green
Write-Host "  You can now connect from LapDeck or Linux peer.           " -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "`nPress Enter to exit..."
Read-Host