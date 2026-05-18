$ErrorActionPreference = 'Stop'

$slackWebhookURL = "https://hooks.slack.com/services/YOUR_WORKSPACE/YOUR_CHANNEL/YOUR_TOKEN"

# Define the array of AdminUsers (these AzureAD accounts will be kept/ensured)
$AdminUsers = @(
    "AzureAD\matthew.ciantar@cabhru.ie"
)

$log = @()
$hostName = [System.Net.Dns]::GetHostName()
$ServiceGroup = "Administrators"

function Write-Log {
    param([string]$Message)
    $global:log += $Message
    Write-Host $Message
}

function Send-ToSlack {
    param(
        [string]$Text,
        [string]$Color = "#008000"
    )

    # Do not let Slack failures break Intune runs
    try {
        try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}

        $blocks = @(
            @{
                type = "header"
                text = @{
                    type = "plain_text"
                    text = "Admin Removal Script"
                }
            },
            @{ type = "divider" },
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
        } | ConvertTo-Json -Depth 6

        Invoke-RestMethod -Uri $slackWebhookURL -Method Post -Body $payload -ErrorAction Stop | Out-Null
    } catch {
        Write-Host "Slack post failed (non-fatal): $($_.Exception.Message)"
    }
}

$matchedUsers = @()

try {
    Write-Log "Started Admin Removal Script on $hostName."

    # net.exe output includes headers/footers; filter them out
    $members = net localgroup $ServiceGroup |
        Where-Object {
            $_ -and
            $_ -notmatch '^-+$' -and
            $_ -notmatch 'The command completed successfully' -and
            $_ -notmatch 'Command completed successfully'
        }

    Write-Log "Successfully retrieved members of the $ServiceGroup group."

    # Azure AD members only
    $azureADMembers = $members | Where-Object { $_ -like "AzureAD\*" }
    Write-Log "Successfully filtered Azure AD members from the list."

    foreach ($user in $azureADMembers) {
        if ($AdminUsers -icontains $user) {
            $log += "$user is in the AdminUsers allow-list. Skipping removal."
            $matchedUsers += $user
        } else {
            try {
                net localgroup $ServiceGroup $user /DELETE | Out-Null
                $log += "Successfully removed $user from the $ServiceGroup group."
            } catch {
                $log += "Error removing $user from the $ServiceGroup group: $($_.Exception.Message)"
            }
        }
    }

    # Ensure allow-listed AdminUsers are present
    $usersToAdd = $AdminUsers | Where-Object { $_ -notin $matchedUsers }
    foreach ($userToAdd in $usersToAdd) {
        try {
            net localgroup $ServiceGroup $userToAdd /ADD | Out-Null
            $log += "Successfully added $userToAdd to the $ServiceGroup group."
        } catch {
            $log += "Error adding $userToAdd to the $ServiceGroup group: $($_.Exception.Message)"
        }
    }

    Write-Log "Script: Completed successfully."
    Send-ToSlack -Text ($log -join "`n") -Color "#008000"

    exit 0
}
catch {
    Write-Log "Script: FAILED - $($_.Exception.Message)"
    Send-ToSlack -Text ($log -join "`n") -Color "#ff0000"
    exit 1
}
