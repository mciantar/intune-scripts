<#
.SYNOPSIS
    Helper script to inject the real Slack webhook, encode the maintenance scripts into Base64, 
    and output the final ready-to-deploy scripts into the 'output' folder.
#>

$ErrorActionPreference = 'Stop'

$OutputDir = "output"
$WebhookFile = "$OutputDir/webhook.txt"

if (-not (Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir | Out-Null
}

if (-not (Test-Path $WebhookFile)) {
    Write-Host "Please create $WebhookFile and paste your real Slack Webhook URL into it." -ForegroundColor Yellow
    exit 1
}

$RealWebhook = (Get-Content $WebhookFile -Raw).Trim()
if ($RealWebhook -notmatch "^https://hooks\.slack\.com/services/") {
    Write-Host "Invalid webhook URL in $WebhookFile" -ForegroundColor Red
    exit 1
}

$ScriptsToProcess = @(
    "Bootstrap.ps1",
    "FirefoxUpdateSystem.ps1",
    "FirefoxUpdateUser.ps1",
    "FirefoxUpdateSystemScheduledTaskInstaller.ps1",
    "FirefoxUpdateUserScheduledTaskInstaller.ps1"
)

Write-Host "Injecting webhooks and copying to output folder..."
foreach ($Script in $ScriptsToProcess) {
    if (Test-Path $Script) {
        $Content = Get-Content $Script -Raw
        $Content = $Content -replace 'https://hooks\.slack\.com/services/YOUR_WORKSPACE/YOUR_CHANNEL/YOUR_TOKEN', $RealWebhook
        Set-Content -Path "$OutputDir/$Script" -Value $Content
    }
}

Write-Host "Building Installers..."

# System Installer
$SystemScriptOut = "$OutputDir/FirefoxUpdateSystem.ps1"
$SystemInstallerOut = "$OutputDir/FirefoxUpdateSystemScheduledTaskInstaller.ps1"
if ((Test-Path $SystemScriptOut) -and (Test-Path $SystemInstallerOut)) {
    $Bytes = [System.IO.File]::ReadAllBytes((Resolve-Path $SystemScriptOut).Path)
    $Base64 = [System.Convert]::ToBase64String($Bytes)
    $Content = Get-Content $SystemInstallerOut -Raw
    $Content = $Content -replace '(?m)^\$Base64Script = ".*"$', "`$Base64Script = `"$Base64`""
    Set-Content -Path $SystemInstallerOut -Value $Content
    Write-Host "Injected Base64 into $SystemInstallerOut"
}

# User Installer
$UserScriptOut = "$OutputDir/FirefoxUpdateUser.ps1"
$UserInstallerOut = "$OutputDir/FirefoxUpdateUserScheduledTaskInstaller.ps1"
if ((Test-Path $UserScriptOut) -and (Test-Path $UserInstallerOut)) {
    $Bytes = [System.IO.File]::ReadAllBytes((Resolve-Path $UserScriptOut).Path)
    $Base64 = [System.Convert]::ToBase64String($Bytes)
    $Content = Get-Content $UserInstallerOut -Raw
    $Content = $Content -replace '(?m)^\$Base64Script = ".*"$', "`$Base64Script = `"$Base64`""
    Set-Content -Path $UserInstallerOut -Value $Content
    Write-Host "Injected Base64 into $UserInstallerOut"
}

Write-Host "Build complete! Deploy the scripts from the '$OutputDir' folder." -ForegroundColor Green
