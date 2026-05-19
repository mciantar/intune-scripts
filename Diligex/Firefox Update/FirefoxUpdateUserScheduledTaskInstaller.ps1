<#
.SYNOPSIS
    Intune Platform Script (USER Context).
    Waits for Bootstrap, dumps FirefoxUpdateUser.ps1, and creates the Scheduled Task.
#>

$ErrorActionPreference = 'Stop'
$ScriptName = "FirefoxUpdateUser_Installer"
$EnableSlackAlerts = $true
$slackWebhookURL = "https://hooks.slack.com/services/YOUR_WORKSPACE/YOUR_CHANNEL/YOUR_TOKEN" # REPLACE WITH ACTUAL WEBHOOK

$BaseDir = "C:\ProgramData\WorkstationManagement\Firefox"
$BootstrapMarker = "$BaseDir\state\bootstrap-complete.json"
$ScriptDest = "$BaseDir\scripts\user\FirefoxUpdateUser.ps1"
$TaskName = "AITS_FirefoxUpdateUser"

# BASE64_PLACEHOLDER_USER
$Base64Script = "BASE64_PLACEHOLDER_USER"

function Send-ToSlack($Color, $Title, $Text) {
    if (-not $EnableSlackAlerts -or $slackWebhookURL -like "*XXXXX*") { return }
    $Payload = @{ attachments = @(@{ title = "$Title ($env:COMPUTERNAME)"; text = $Text; color = $Color }) }
    try { Invoke-RestMethod -Method Post -Uri $slackWebhookURL -Body (ConvertTo-Json $Payload -Depth 4) -ContentType "application/json" } catch {}
}

try {
    $WaitTime = 0
    while (-not (Test-Path $BootstrapMarker)) {
        if ($WaitTime -ge 1200) { throw "Timeout waiting for Bootstrap (20 mins)." }
        Start-Sleep -Seconds 60
        $WaitTime += 60
    }

    if ($Base64Script -eq "BASE64_PLACEHOLDER_USER") {
        throw "Base64 script content is missing. Please run Build.ps1."
    }

    $Bytes = [System.Convert]::FromBase64String($Base64Script)
    [System.IO.File]::WriteAllBytes($ScriptDest, $Bytes)

    $Action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-ExecutionPolicy Bypass -WindowStyle Hidden -NoProfile -File `"$ScriptDest`""
    $Trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Hours 4)
    $Principal = New-ScheduledTaskPrincipal -GroupId "BUILTIN\Users" -RunLevel Limited
    $Settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -MultipleInstances Parallel

    Register-ScheduledTask -TaskName $TaskName -Action $Action -Trigger $Trigger -Principal $Principal -Settings $Settings -Force | Out-Null

    Send-ToSlack "#008000" "User Task Installer Success" "Successfully dumped script and registered USER scheduled task for $env:USERNAME."
} catch {
    Send-ToSlack "#ff0000" "User Task Installer Failed" "Error: $($_.Exception.Message)"
    exit 1
}


