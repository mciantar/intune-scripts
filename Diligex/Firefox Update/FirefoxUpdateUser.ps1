<#
.SYNOPSIS
    Manages per-user Firefox updates.
    Runs in User Context every 4 hours.
#>

$ErrorActionPreference = 'Stop'
$ScriptName = "FirefoxUpdateUser"
$ScriptVersion = "3.0.1"
$EnableSlackAlerts = $true
$DebugSlackNoOp = $false
$slackWebhookURL = "https://hooks.slack.com/services/YOUR_WORKSPACE/YOUR_CHANNEL/YOUR_TOKEN" # REPLACE WITH ACTUAL WEBHOOK

$global:log = @()
$CurrentStage = "Initialization"
$BaseDir = "C:\ProgramData\WorkstationManagement\Firefox"
$UserSID = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$SessionId = [System.Diagnostics.Process]::GetCurrentProcess().SessionId
$LogFile = "$BaseDir\logs\FirefoxUpdateUser-$UserSID-$(Get-Date -f yyyyMMdd).log"

function Write-Log($Msg, $Level = "INFO") {
    $Timestamp = Get-Date -f "yyyy-MM-dd HH:mm:ss"
    $FormattedMsg = "[$Timestamp] [$Level] $Msg"
    $global:log += $FormattedMsg
    Write-Host $FormattedMsg
    if (Test-Path "$BaseDir\logs") {
        $FormattedMsg | Out-File $LogFile -Append
    }
}

function Send-ToSlack($Color, $Title) {
    if (-not $EnableSlackAlerts -or $slackWebhookURL -like "*XXXXX*") { return }
    $Payload = @{
        attachments = @(@{
            title = "$Title ($env:COMPUTERNAME)"
            text  = "Stage: $CurrentStage`nUser: $env:USERNAME`nSID: $UserSID`nSession: $SessionId`n`n" + ($global:log -join "`n")
            color = $Color
            footer = "$ScriptName v$ScriptVersion"
            ts = [int64](Get-Date -UFormat %s)
        })
    }
    try {
        Invoke-RestMethod -Method Post -Uri $slackWebhookURL -Body (ConvertTo-Json $Payload -Depth 4) -ContentType "application/json"
    } catch {
        Write-Log "Failed to send Slack alert: $($_.Exception.Message)" "WARNING"
    }
}

function Get-Lock {
    param($Path)
    try {
        return [System.IO.File]::Open($Path, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
    } catch [System.IO.IOException] {
        try {
            $f = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
            $f.Close(); $f.Dispose()
            Remove-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
            return [System.IO.File]::Open($Path, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
        } catch { return $null }
    }
}

$UserLock = $null
$RuntimeLock = $null

try {
    $CurrentStage = "Validation"
    if (-not (Test-Path "$BaseDir\state\bootstrap-complete.json")) { exit 0 }
    
    $ActionTaken = $false
    
    $CurrentStage = "Detection"
    $AppData = [System.Environment]::GetFolderPath('LocalApplicationData')
    $ExePath = "$AppData\Mozilla Firefox\firefox.exe"
    
    if (-not (Test-Path $ExePath)) {
        Write-Log "User Firefox not found at $ExePath. Exiting."
        if ($DebugSlackNoOp) { Send-ToSlack "#808080" "User Update No-Op (Not Installed)" }
        exit 0
    }

    $CurrentVersion = [version](Get-Item $ExePath).VersionInfo.FileVersion

    $CurrentStage = "Fetching Latest Version"
    $ApiUrl = "https://product-details.mozilla.org/1.0/firefox_versions.json"
    $Versions = Invoke-RestMethod -Uri $ApiUrl -UseBasicParsing
    $LatestVersionStr = $Versions.LATEST_FIREFOX_VERSION
    $LatestVersion = [version]$LatestVersionStr

    if ($LatestVersion -gt $CurrentVersion) {
        Write-Log "User Firefox ($CurrentVersion) is outdated. Latest is $LatestVersion."

        $UserLock = Get-Lock "$BaseDir\locks\user-$UserSID.lock"
        if ($null -ne $UserLock) {
            $RuntimeLock = Get-Lock "$BaseDir\locks\runtime.lock"
            if ($null -ne $RuntimeLock) {
                
                $CurrentStage = "Downloading Installer"
                $DownloadUrl = "https://download.mozilla.org/?product=firefox-latest-ssl&os=win64&lang=en-US"
                $InstallerPath = "$env:TEMP\FirefoxSetupUser.exe"
                Invoke-WebRequest -Uri $DownloadUrl -OutFile $InstallerPath -UseBasicParsing

                $Sig = Get-AuthenticodeSignature -LiteralPath $InstallerPath
                if ($Sig.Status -eq 'Valid' -and $Sig.SignerCertificate.Subject -like "*Mozilla Corporation*") {
                    
                    $CurrentStage = "User Prompting"
                    Write-Log "Prompting user..."
                    $Msg = "IT Notice: Your personal Firefox installation needs to update. Please save your work. Firefox will close automatically in 5 minutes."
                    Start-Process -FilePath "powershell.exe" -ArgumentList "-WindowStyle Hidden -Command ""Add-Type -AssemblyName System.Windows.Forms; [System.Windows.Forms.MessageBox]::Show('$Msg', 'Firefox Update', 'OK', 'Information')"""
                    
                    Start-Sleep -Seconds 300

                    $CurrentStage = "Disruption"
                    $Procs = Get-Process firefox -ErrorAction SilentlyContinue | Where-Object { $_.SessionId -eq $SessionId -and $_.Path -like "$AppData*" }
                    Write-Log "Closing session Firefox processes..."
                    foreach ($P in $Procs) { $P.CloseMainWindow() | Out-Null }
                    Start-Sleep -Seconds 10
                    $Procs | Stop-Process -Force -ErrorAction SilentlyContinue

                    $CurrentStage = "Installation"
                    Write-Log "Updating User Firefox..."
                    Start-Process -FilePath $InstallerPath -ArgumentList "-ms" -Wait
                    Write-Log "Update complete."

                    $MsgDone = "IT Notice: Firefox update is complete. You may reopen Firefox."
                    Start-Process -FilePath "powershell.exe" -ArgumentList "-WindowStyle Hidden -Command ""Add-Type -AssemblyName System.Windows.Forms; [System.Windows.Forms.MessageBox]::Show('$MsgDone', 'Firefox Update', 'OK', 'Information')"""

                    $ActionTaken = $true
                    Send-ToSlack "#008000" "User Update Success"
                } else {
                    Write-Log "ERROR: Installer signature invalid or untrusted." "ERROR"
                    Send-ToSlack "#ff0000" "User Update Failed (Signature Invalid)"
                }
                if (Test-Path $InstallerPath) { Remove-Item $InstallerPath -Force -ErrorAction SilentlyContinue }
            } else {
                Write-Log "Runtime lock active. Deferring user action."
            }
        } else {
            Write-Log "User lock active. Deferring user action."
        }
    }

    if (-not $ActionTaken -and $DebugSlackNoOp) {
        Send-ToSlack "#808080" "User Update No-Op"
    }

} catch {
    $ErrorMsg = "ERROR in $ScriptName at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)`n`nStack Trace:`n$($_.ScriptStackTrace)"
    Write-Log $ErrorMsg "ERROR"
    Send-ToSlack "#ff0000" "User Update Failure"
} finally {
    if ($null -ne $RuntimeLock) { $RuntimeLock.Close(); $RuntimeLock.Dispose() }
    if ($null -ne $UserLock) { $UserLock.Close(); $UserLock.Dispose() }
    Write-Log "User Update finished."
}
