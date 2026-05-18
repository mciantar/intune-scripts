# Define Slack Webhook URL
$slackWebhookURL = "https://hooks.slack.com/services/YOUR_WORKSPACE/YOUR_CHANNEL/YOUR_TOKEN"

function Send-ToSlack {
    param(
        [string]$Text,
        [string]$Color = "#008000"
    )

    $blocks = @(
        @{
            type = "header"
            text = @{
                type = "plain_text"
                text = "SSDP, UPNP and Discovery Services Disable Script"
            }
        },
        @{
            type = "divider"
        },
        @{
            type = "section"
            text = @{
                type = "mrkdwn"
                text = $Text
            }
        }
    )

    $payload = @{
        attachments = @(
            @{
                color  = $Color
                blocks = $blocks
            }
        )
    } | ConvertTo-Json -Depth 5

    try {
        Invoke-RestMethod -Uri $slackWebhookURL -Method Post -Body $payload
    } catch {
        Write-Host "Failed to send to Slack: $($_.Exception.Message)"
    }
}

# Service list with correct service names
$servicesToDisable = @("SSDPSRV", "upnphost", "FDResPub")

# Map short service names to full display names for logging
$serviceNameMapping = @{
    SSDPSRV  = "SSDP Discovery";
    upnphost = "UPnP Device Host";    
    FDResPub = "Function Discovery Resource Publication";
}

# Log variable to accumulate all log messages
$log = @()

# Error flag
$errorOccurred = $false

$hostName = [System.Net.Dns]::GetHostName()
$log += "Starting script on $hostName."

try {
    foreach ($service in $servicesToDisable) {
        if (Get-Service $service -ErrorAction SilentlyContinue) {
            Set-Service -Name $service -StartupType Disabled
            Stop-Service -Name $service -Force -ErrorAction SilentlyContinue
            $log += "Service $($serviceNameMapping[$service]) has been stopped and disabled successfully."
        }
    }
	Set-Service -Name "fdPHost" -StartupType Automatic -Status Running -PassThru	
	$log += "Service $($serviceNameMapping[$service]) has been stopped and disabled successfully."
    $log += "Script execution completed successfully."
} catch {
    $errorMessage = "Error occurred while processing the services: $($_.Exception.Message)"
    $log += $errorMessage
    $errorOccurred = $true
}

# Join all log messages and send to Slack
$logMessage = $log -join "`n"
if ($errorOccurred) {
    Send-ToSlack -Text $logMessage -Color "#ff0000"
} else {
    Send-ToSlack -Text $logMessage
}