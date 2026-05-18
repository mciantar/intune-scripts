<#
.SYNOPSIS
    Manages machine-wide Firefox updates.
    Runs as SYSTEM every 4 hours.
#>

$ErrorActionPreference = 'Stop'
$ScriptName = "FirefoxUpdateSystem"
$ScriptVersion = "3.0.1"
$EnableSlackAlerts = $true
$DebugSlackNoOp = $false
$slackWebhookURL = "https://hooks.slack.com/services/YOUR_WORKSPACE/YOUR_CHANNEL/YOUR_TOKEN" # REPLACE WITH ACTUAL WEBHOOK

$global:log = @()
$CurrentStage = "Initialization"
$BaseDir = "C:\ProgramData\WorkstationManagement\Firefox"
$LogFile = "$BaseDir\logs\FirefoxUpdateSystem-$(Get-Date -f yyyyMMdd).log"

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
            text  = "Stage: $CurrentStage`nUser: $env:USERNAME`n`n" + ($global:log -join "`n")
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

$MachineLock = $null
$RuntimeLock = $null

try {
    $CurrentStage = "Validation"
    if (-not (Test-Path "$BaseDir\state\bootstrap-complete.json")) { exit 0 }
    
    $ActionTaken = $false

    $CurrentStage = "Machine Update Detection"
    $ExePath = "C:\Program Files\Mozilla Firefox\firefox.exe"
    
    if (-not (Test-Path $ExePath)) {
        Write-Log "System Firefox not found at $ExePath. Exiting."
        if ($DebugSlackNoOp) { Send-ToSlack "#808080" "System Update No-Op (Not Installed)" }
        exit 0
    }

    $CurrentVersion = [version](Get-Item $ExePath).VersionInfo.FileVersion

    $CurrentStage = "Fetching Latest Version"
    $ApiUrl = "https://product-details.mozilla.org/1.0/firefox_versions.json"
    $Versions = Invoke-RestMethod -Uri $ApiUrl -UseBasicParsing
    $LatestVersionStr = $Versions.LATEST_FIREFOX_VERSION
    $LatestVersion = [version]$LatestVersionStr

    if ($LatestVersion -gt $CurrentVersion) {
        Write-Log "System Firefox ($CurrentVersion) is outdated. Latest is $LatestVersion."
        
        $MachineLock = Get-Lock "$BaseDir\locks\machine.lock"
        if ($null -ne $MachineLock) {
            $RuntimeLock = Get-Lock "$BaseDir\locks\runtime.lock"
            if ($null -ne $RuntimeLock) {
                $CurrentStage = "Downloading Installer"
                $DownloadUrl = "https://download.mozilla.org/?product=firefox-latest-ssl&os=win64&lang=en-US"
                $InstallerPath = "$env:TEMP\FirefoxSetupSystem.exe"
                Invoke-WebRequest -Uri $DownloadUrl -OutFile $InstallerPath -UseBasicParsing
                
                $CurrentStage = "Machine Update Execution"
                $Sig = Get-AuthenticodeSignature -LiteralPath $InstallerPath
                if ($Sig.Status -eq 'Valid' -and $Sig.SignerCertificate.Subject -like "*Mozilla Corporation*") {
                    
                    $ActiveSessions = (quser) -match '^\s*>?[a-zA-Z0-9]'
                    if ($ActiveSessions) {
                        Write-Log "Broadcasting 5-minute warning to active sessions..."
                        msg.exe * "IT Notice: System Firefox will be updated in 5 minutes. Please save your work. Firefox will close automatically." 2>$null
                        Start-Sleep -Seconds 300
                    }

                    Write-Log "Scoped kill of machine-wide Firefox..."
                    Get-Process firefox -ErrorAction SilentlyContinue | Where-Object { $_.Path -like "C:\Program Files*" } | Stop-Process -Force -ErrorAction SilentlyContinue
                    
                    Write-Log "Updating System Firefox..."
                    Start-Process -FilePath $InstallerPath -ArgumentList "-ms" -Wait
                    Write-Log "Update complete."
                    
                    if ($ActiveSessions) {
                        msg.exe * "IT Notice: System Firefox update is complete. You may reopen Firefox." 2>$null
                    }

                    $ActionTaken = $true
                    Send-ToSlack "#008000" "System Update Successful"
                } else {
                    Write-Log "ERROR: Installer signature invalid or untrusted." "ERROR"
                    Send-ToSlack "#ff0000" "System Update Failed (Signature Invalid)"
                }
                if (Test-Path $InstallerPath) { Remove-Item $InstallerPath -Force -ErrorAction SilentlyContinue }
            } else {
                Write-Log "Runtime lock active. Deferring machine update."
            }
        } else {
            Write-Log "Machine lock active. Deferring machine update."
        }
    }

    if (-not $ActionTaken -and $DebugSlackNoOp) {
        Send-ToSlack "#808080" "System Update No-Op"
    }

} catch {
    $ErrorMsg = "ERROR in $ScriptName at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)`n`nStack Trace:`n$($_.ScriptStackTrace)"
    Write-Log $ErrorMsg "ERROR"
    Send-ToSlack "#ff0000" "System Update Failure"
} finally {
    if ($null -ne $RuntimeLock) { $RuntimeLock.Close(); $RuntimeLock.Dispose() }
    if ($null -ne $MachineLock) { $MachineLock.Close(); $MachineLock.Dispose() }
    Write-Log "System Update finished."
}
