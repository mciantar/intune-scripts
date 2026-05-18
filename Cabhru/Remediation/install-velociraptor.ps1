# Slack URI
$slackWebhookURL = "https://hooks.slack.com/services/YOUR_WORKSPACE/YOUR_CHANNEL/YOUR_TOKEN"

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
                text = "Velociraptor Installer Script"
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
    Write-Log "Started Velociraptor Install on $hostName."

	# Define the URIs at the top
	$exeUri = "https://github.com/Velocidex/velociraptor/releases/download/v0.75/velociraptor-v0.75.3-windows-amd64.exe"               
	$configUri = "https://cabhrupublicstore.blob.core.windows.net/public/velociraptor/client.config.yaml"

	$serviceName = "velociraptor"
	$service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue

	# Check if the service 'velociraptor' exists
	if ($service) {		
		# Get the path to the executable from the service configuration
		$servicePath = (Get-WmiObject Win32_Service -Filter "Name='$serviceName'").PathName

		# Split on the second '"' and take the first part, then trim the surrounding quotes
		$executablePath = ($servicePath -split '"', 3)[1].Trim('"')

		if (Test-Path $executablePath) {
			$fileInfo = Get-Item $executablePath
			$lastModifiedDate = $fileInfo.LastWriteTime

			# Define the cutoff date
			$cutoffDate = Get-Date "2025-09-01"

			if ($lastModifiedDate -lt $cutoffDate) {
				Write-Output "The executable was last modified $lastModifiedDate. We need to Remove and Upgrade..."
				Stop-Service $serviceName -ErrorAction SilentlyContinue				
				sc.exe delete $serviceName
			} else {
				Write-Log "Velociraptor service already exists at the correct version. Exiting..."
				exit
			}
		} else {
			Write-Output "Executable path not found: $executablePath"
		}		    
	}

	# Create a temporary directory and navigate to it
	$tempDir = New-Item -ItemType Directory -Path "$env:TEMP\tempDir_$(Get-Random)"
	Set-Location $tempDir.FullName

	# Download the .exe file to the temporary directory and rename it
	Invoke-WebRequest -Uri $exeUri -OutFile "velociraptor.exe"

	# Download the .yaml file to the temporary directory
	Invoke-WebRequest -Uri $configUri -OutFile "client.config.yaml"

	# Run the command to install the service
	Start-Process -FilePath ".\velociraptor.exe" -ArgumentList "--config .\client.config.yaml service install" -Wait

    # Add a delay of 30 seconds before trying to remove the directory
    Start-Sleep -Seconds 30
	
	# Remove the temporary directory
	Remove-Item $tempDir -Force -Recurse -ErrorAction SilentlyContinue

	# Ensure that the 'velociraptor' service startup type is set to automatic
	Set-Service -Name "velociraptor" -StartupType Automatic

	# Start the service if it's not already running
	if ((Get-Service "velociraptor").Status -ne "Running") {
		Start-Service "velociraptor"
		Write-Log "Velociraptor service installed and running."		
	}

    Write-Log "Script: Completed successfully."
	
	# Send logs to Slack
	$logText = $log -join "`n"
	Send-ToSlack -Text $logText -Color "#008000"

} catch {
    Write-Log "Script: FAILED - $($_.Exception.Message)"
	$logText = $log -join "`n"
	Send-ToSlack -Text $logText -Color "#ff0000"
}