<#
.SYNOPSIS
    Bootstraps the Firefox Maintenance environment. 
    Run as SYSTEM via Intune Platform Scripts.
    Creates folders and permissions. DOES NOT create scheduled tasks.
#>

$ErrorActionPreference = 'Stop'
$ScriptName = "Firefox_Bootstrap"
$ScriptVersion = "3.0.2"
$EnableSlackAlerts = $true
$DebugSlackNoOp = $false
$slackWebhookURL = "https://hooks.slack.com/services/YOUR_WORKSPACE/YOUR_CHANNEL/YOUR_TOKEN" # REPLACE WITH ACTUAL WEBHOOK

$global:log = @()
$CurrentStage = "Initialization"

function Write-Log($Msg, $Level = "INFO") {
    $Timestamp = Get-Date -f "yyyy-MM-dd HH:mm:ss"
    $FormattedMsg = "[$Timestamp] [$Level] $Msg"
    $global:log += $FormattedMsg
    Write-Host $FormattedMsg
    
    $LogDir = "C:\ProgramData\WorkstationManagement\Firefox\logs"
    if (Test-Path $LogDir) {
        $FormattedMsg | Out-File "$LogDir\Bootstrap-$(Get-Date -f yyyyMMdd).log" -Append
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

try {
    Write-Log "Starting $ScriptName v$ScriptVersion"

    $CurrentStage = "Folder Creation"
    $BaseDir = "C:\ProgramData\WorkstationManagement\Firefox"
    $Paths = @(
        "$BaseDir",
        "$BaseDir\locks",
        "$BaseDir\logs",
        "$BaseDir\state",
        "$BaseDir\scripts",
        "$BaseDir\scripts\user"
    )

    foreach ($Path in $Paths) {
        if (-not (Test-Path -LiteralPath $Path)) {
            New-Item -ItemType Directory -Path $Path -Force | Out-Null
            Write-Log "Created folder: $Path"
        }
    }

    $CurrentStage = "ACL Application"
    $Acl = Get-Acl -Path $BaseDir
    $Acl.SetAccessRuleProtection($true, $false)
    $Rules = @(
        [System.Security.AccessControl.FileSystemAccessRule]::new("SYSTEM", "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow"),
        [System.Security.AccessControl.FileSystemAccessRule]::new("Administrators", "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow"),
        [System.Security.AccessControl.FileSystemAccessRule]::new("Users", "ReadAndExecute", "ContainerInherit,ObjectInherit", "None", "Allow")
    )
    foreach($Rule in $Rules) { $Acl.SetAccessRule($Rule) }
    Set-Acl -Path $BaseDir -AclObject $Acl

    $ModifyRule = [System.Security.AccessControl.FileSystemAccessRule]::new("Users", "Modify", "ContainerInherit,ObjectInherit", "None", "Allow")
    foreach($Sub in @("locks", "logs", "scripts\user")) {
        $SubAcl = Get-Acl -Path "$BaseDir\$Sub"
        $SubAcl.AddAccessRule($ModifyRule)
        Set-Acl -Path "$BaseDir\$Sub" -AclObject $SubAcl
    }
    Write-Log "ACLs applied."

         = "Cleanup Legacy Artifacts"
     = @("AITS_Firefox_UserMaintenance", "AITS_FirefoxUpdateUser")
    foreach ( in ) {
        if (Get-ScheduledTask -TaskName  -ErrorAction SilentlyContinue) {
            Unregister-ScheduledTask -TaskName  -Confirm:False -ErrorAction SilentlyContinue
            Write-Log "Removed legacy scheduled task: "
        }
    }

     = @(
        "$BaseDir\scripts\FirefoxUpdateUser.ps1",
        "$BaseDir\scripts\user\FirefoxUpdateUser.ps1"
    )
    foreach ( in ) {
        if (Test-Path -LiteralPath ) {
            Remove-Item -LiteralPath  -Force -ErrorAction SilentlyContinue
            Write-Log "Removed legacy script: "
        }
    }

     = "Final Verification"
    $Marker = @{
        BootstrapVersion = $ScriptVersion
        CreatedUtc = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd HH:mm:ssZ")
    }
    $Marker | ConvertTo-Json | Out-File "$BaseDir\state\bootstrap-complete.json" -Encoding utf8
    
    Write-Log "Bootstrap validation successful."
    Send-ToSlack "#008000" "Bootstrap Success"

} catch {
    $ErrorMsg = "ERROR in $ScriptName at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)`n`nStack Trace:`n$($_.ScriptStackTrace)"
    Write-Log $ErrorMsg "ERROR"
    Send-ToSlack "#ff0000" "Bootstrap Failure"
} finally {
    Write-Log "Bootstrap routine finished."
}

