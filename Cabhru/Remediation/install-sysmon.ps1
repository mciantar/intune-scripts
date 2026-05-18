# Fetch the base64 encoded content from the URL
$base64ContentURL = "https://cabhrupublicstore.blob.core.windows.net/public/sysmon-configs/current.dat"
$base64Content = Invoke-RestMethod -Uri $base64ContentURL

$slackWebhookURL = "https://hooks.slack.com/services/YOUR_WORKSPACE/YOUR_CHANNEL/YOUR_TOKEN"

$appVersion = "20260203.01"
$requiredVersion = [Version]"15.15"

# Initialize the log
$log = @()
$hostName = [System.Net.Dns]::GetHostName()

# Log function
function Write-Log {
    param(
        [string]$Message
    )
    $global:log += $Message
	Write-Host $Message
}

# Slack function
function Send-ToSlack {
    param(
        [string]$Text,
        [string]$Color = "#008000" # default to no erors, "ff0000" for errors and exceptions
    )

    $headerText = ""
	
    $blocks = @(
        @{
            type = "header"
            text = @{
                type = "plain_text"
                text = "Sysmon Installer Script"
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


try {
    Write-Log "Started Sysmon Installer version $appVersion on $hostName."

    # Sysmon check
    $sysmonPath = $null
    $sysmonService = $null
	$currentVersion = $null
    if (Test-Path "C:\Windows\Sysmon64.exe") {
        $sysmonPath = "C:\Windows\Sysmon64.exe"
        $sysmonService = "Sysmon64"
		$currentVersion = (Get-Item $sysmonPath).VersionInfo.ProductVersion
        $currentVersionParsed = [Version]$currentVersion
		Write-Log "Detected Sysmon version: $currentVersionParsed"
    } elseif (Test-Path "C:\Windows\Sysmon.exe") {
        $sysmonPath = "C:\Windows\Sysmon.exe"
        $sysmonService = "Sysmon"
		$currentVersion = (Get-Item $sysmonPath).VersionInfo.ProductVersion
        $currentVersionParsed = [Version]$currentVersion
		Write-Log "Detected Sysmon version: $currentVersionParsed"
    }

	$needsInstall = $false

	if ($sysmonPath -eq $null -or -not $currentVersionParsed) {
		$needsInstall = $true
	} elseif ($currentVersionParsed -lt $requiredVersion) {
		Write-Log "Sysmon version $currentVersionParsed is older than required $requiredVersion. Uninstalling..."
		Start-Process -FilePath $sysmonPath -ArgumentList "-u", "force" -Wait
		$needsInstall = $true
	}

	if ($needsInstall) {
       
        Write-Log "Sysmon missing or outdated. Installing..."
        $sysmonURL = "https://download.sysinternals.com/files/Sysmon.zip"
        $downloadLocation = "$env:TEMP\Sysmon.zip"
        Invoke-WebRequest -Uri $sysmonURL -OutFile $downloadLocation
        $unzipLocation = "$env:TEMP\Sysmon"
        New-Item -ItemType Directory -Path $unzipLocation -Force
        Expand-Archive -Path $downloadLocation -DestinationPath $unzipLocation
        if (Test-Path "$unzipLocation\Sysmon64.exe") {
            Start-Process -FilePath "$unzipLocation\Sysmon64.exe" -ArgumentList "-accepteula", "-i" -Wait
            $sysmonPath = "C:\Windows\Sysmon64.exe"
            $sysmonService = "Sysmon64"
        } else {
            Start-Process -FilePath "$unzipLocation\Sysmon.exe" -ArgumentList "-accepteula", "-i" -Wait
            $sysmonPath = "C:\Windows\Sysmon.exe"
            $sysmonService = "Sysmon"
        }
        Remove-Item -Path $downloadLocation -Force
        Remove-Item -Path $unzipLocation -Recurse -Force
		Write-Log "Sysmon installed."
    } else {
		Write-Log "Sysmon was already installed."
	}

    # Service check
    $service = Get-Service -Name $sysmonService -ErrorAction SilentlyContinue
    if ($service.Status -ne "Running") {
        Start-Service -Name $sysmonService
		Write-Log "Service started."
    } 

    # Config application
    $decodedBytes = [System.Convert]::FromBase64String($base64Content)
    $decodedXML = [System.Text.Encoding]::UTF8.GetString($decodedBytes)
    $tempXMLFile = "$env:TEMP\tempSysmonConfig.xml"
    $decodedXML | Out-File -Encoding utf8 -FilePath $tempXMLFile
    Start-Process -FilePath $sysmonPath -ArgumentList "-c", $tempXMLFile -Wait
    Remove-Item -Path $tempXMLFile -Force

    Write-Log "Script: Completed successfully."
	
	# Send logs to Slack
	$logText = $log -join "`n"
	Send-ToSlack -Text $logText -Color "#008000"

} catch {
    Write-Log "Script: FAILED - $($_.Exception.Message)"
	$logText = $log -join "`n"
	Send-ToSlack -Text $logText -Color "#ff0000"
}

