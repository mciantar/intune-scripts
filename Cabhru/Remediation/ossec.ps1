# Wazuh Agent install/repair for Intune (SYSTEM-safe, logs to ProgramData)
# Version pinned to 4.11.0-1
# Writes:
#   C:\ProgramData\Wazuh\deploy.log
#   C:\ProgramData\Wazuh\wazuh-agent-install-4.11.0-1.log

$ErrorActionPreference = 'Stop'

# ---- Config ----
$BaseDir = Join-Path $env:ProgramData "Wazuh"
New-Item -Path $BaseDir -ItemType Directory -Force | Out-Null

$WazuhVersion = "4.11.0-1"
$WazuhUri     = "https://packages.wazuh.com/4.x/windows/wazuh-agent-$WazuhVersion.msi"
$MsiPath      = Join-Path $BaseDir "wazuh-agent-$WazuhVersion.msi"
$LogPath      = Join-Path $BaseDir "wazuh-agent-install-$WazuhVersion.log"

$Manager      = "wazuh.cabhru.ie"
$RegServer    = "wazuh.cabhru.ie"
$ServiceName  = "WazuhSvc"

# ---- Helpers ----
function Write-Log {
    param([Parameter(Mandatory)][string]$Message)
    $ts = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $line = "[{0}] {1}" -f $ts, $Message
    Write-Output $line
    Add-Content -Path (Join-Path $BaseDir "deploy.log") -Value $line
}

function Wait-ServiceState {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][ValidateSet('Running','Stopped')][string]$Desired,
        [int]$TimeoutSeconds = 120
    )
    $sw = [Diagnostics.Stopwatch]::StartNew()
    while ($sw.Elapsed.TotalSeconds -lt $TimeoutSeconds) {
        $svc = Get-Service -Name $Name -ErrorAction SilentlyContinue
        if ($null -ne $svc -and $svc.Status.ToString() -eq $Desired) { return $true }
        Start-Sleep -Seconds 2
    }
    return $false
}

function Invoke-MsiExec {
    param([Parameter(Mandatory)][string]$Arguments)

    Write-Log ("Running: msiexec.exe {0}" -f $Arguments)
    $p = Start-Process -FilePath "msiexec.exe" -ArgumentList $Arguments -Wait -PassThru
    Write-Log ("msiexec exit code: {0}" -f $p.ExitCode)
    return $p.ExitCode
}

function Download-WithRetry {
    param(
        [Parameter(Mandatory)][string]$Uri,
        [Parameter(Mandatory)][string]$OutFile,
        [int]$Attempts = 3
    )

    # Ensure TLS 1.2 (helps on older clients / hardened environments)
    try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}

    for ($i = 1; $i -le $Attempts; $i++) {
        try {
            # Use -f formatting to avoid PowerShell variable interpolation edge cases
            Write-Log ("Download attempt {0}/{1}: {2}" -f $i, $Attempts, $Uri)

            Invoke-WebRequest -Uri $Uri -OutFile $OutFile -UseBasicParsing

            if (Test-Path $OutFile) {
                $len = (Get-Item $OutFile).Length
                Write-Log ("Downloaded to {0} ({1} bytes)" -f $OutFile, $len)
                if ($len -gt 1024) { return } # basic sanity check
            }

            throw "Downloaded file missing or too small."
        }
        catch {
            Write-Log ("Download failed: {0}" -f $_.Exception.Message)
            if ($i -lt $Attempts) {
                Start-Sleep -Seconds (5 * $i)
            } else {
                throw
            }
        }
    }
}

function Remove-WazuhServiceIfStuck {
    Write-Log ("Attempting to remove service '{0}' if present/stuck..." -f $ServiceName)
    $null = & sc.exe stop   $ServiceName 2>$null
    Start-Sleep -Seconds 2
    $null = & sc.exe delete $ServiceName 2>$null
    Start-Sleep -Seconds 2
}

function Is-MsiBusyExitCode {
    param([Parameter(Mandatory)][int]$Code)
    # 1618 = another installation in progress
    return ($Code -eq 1618)
}

# ---- Begin ----
try {
    Write-Log ("Starting Wazuh deployment. Running as: {0}" -f (whoami))
    Write-Log ("Target MSI: {0}" -f $WazuhUri)

    # Download
    Download-WithRetry -Uri $WazuhUri -OutFile $MsiPath -Attempts 3

    # Stop existing service if present (non-fatal)
    $svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if ($null -ne $svc) {
        Write-Log ("Service exists (Status: {0}). Stopping..." -f $svc.Status)
        try { Stop-Service -Name $ServiceName -Force -ErrorAction SilentlyContinue } catch {}
        [void](Wait-ServiceState -Name $ServiceName -Desired Stopped -TimeoutSeconds 60)
    }

    # Install with retry/backoff if Windows Installer is busy
    $msiArgs = "/i `"$MsiPath`" /qn /norestart WAZUH_MANAGER=`"$Manager`" WAZUH_REGISTRATION_SERVER=`"$RegServer`" /l*v `"$LogPath`""

    $maxInstallAttempts = 3
    $installed = $false

    for ($a = 1; $a -le $maxInstallAttempts; $a++) {
        $exit = Invoke-MsiExec -Arguments $msiArgs

        if ($exit -eq 0 -or $exit -eq 3010) {
            $installed = $true
            break
        }

        if (Is-MsiBusyExitCode -Code $exit -and $a -lt $maxInstallAttempts) {
            Write-Log "Windows Installer busy (1618). Backing off and retrying..."
            Start-Sleep -Seconds (30 * $a)
            continue
        }

        Write-Log ("Install attempt {0} failed with exit code {1}." -f $a, $exit)

        if ($a -eq 1) {
            # One recovery cycle matching your manual approach
            Write-Log "Performing recovery: delete service and retry install."
            Remove-WazuhServiceIfStuck
        } elseif ($a -lt $maxInstallAttempts) {
            Start-Sleep -Seconds (10 * $a)
        }
    }

    if (-not $installed) {
        throw ("Wazuh install failed after {0} attempts. MSI log: {1}" -f $maxInstallAttempts, $LogPath)
    }

    # Ensure service exists and start it
    $svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if ($null -eq $svc) {
        Write-Log "Service not found immediately after install; waiting for registration..."
        $found = $false
        for ($j = 1; $j -le 30; $j++) {
            Start-Sleep -Seconds 2
            $svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
            if ($null -ne $svc) { $found = $true; break }
        }
        if (-not $found) {
            throw ("Service '{0}' not present after install. MSI log: {1}" -f $ServiceName, $LogPath)
        }
    }

    Write-Log ("Starting service '{0}'..." -f $ServiceName)
    try {
        Start-Service -Name $ServiceName -ErrorAction Stop
    }
    catch {
        Write-Log ("Start-Service failed: {0}. Falling back to sc.exe start..." -f $_.Exception.Message)
        $null = & sc.exe start $ServiceName 2>$null
    }

    if (-not (Wait-ServiceState -Name $ServiceName -Desired Running -TimeoutSeconds 120)) {
        throw ("Service '{0}' did not reach Running state. MSI log: {1}" -f $ServiceName, $LogPath)
    }

    Write-Log ("Completed successfully. Service '{0}' is Running. MSI log: {1}" -f $ServiceName, $LogPath)
    exit 0
}
catch {
    # Ensure Intune gets a clear failure signal and you get a clear message in deploy.log
    Write-Log ("FAILED: {0}" -f $_.Exception.Message)
    Write-Log ("MSI log (if created): {0}" -f $LogPath)
    exit 1
}
