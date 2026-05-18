# Paths for the export and modified security configurations
$exportPath = Join-Path $env:TEMP "currentSecPolicy.inf"
$modifiedPath = Join-Path $env:TEMP "modifiedSecPolicy.inf"

# Backup directory
$backupDir = "$env:PROGRAMDATA\CIS Compliance Scripts\SDB Backups"

# Ensure backup directory exists
if (-not (Test-Path $backupDir)) {
    New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
}

# Define Backup file name with timestamp
$backupFile = Join-Path $backupDir ("local.sdb." + (Get-Date -Format "yyyyMMddHHmmss"))

# Initialize log array and compliance results
$global:logMessages = @()
$global:complianceResults = @()

function Log-Message {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Message
    )
    Write-Output $Message
    $global:logMessages += $Message
}

function Export-SecurityPolicy {
    try {
        secedit /export /cfg $exportPath
        if (-not (Test-Path $exportPath)) {
            throw "Failed to export local security policy."
        }
        
        # Create a backup        
        Copy-Item -Path $exportPath -Destination $backupFile -Force
        Log-Message "Security policy exported successfully and a backup was saved to $backupFile."
    } catch {
        Log-Message "ERROR: $_"
        exit 1
    }
}

function Import-ModifiedPolicy {
    try {
        secedit /configure /db C:\windows\security\local.sdb /cfg $modifiedPath
        Log-Message "Modified security policy imported successfully."

        # Cleanup - remove temporary files
        Remove-Item $exportPath, $modifiedPath -ErrorAction SilentlyContinue
    } catch {
        Log-Message "ERROR: $_"
    }
}

function Verify-Setting {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Path,
        [Parameter(Mandatory=$true)]
        [string]$Pattern,
        [Parameter(Mandatory=$true)]
        [string]$ExpectedValue
    )

    $content = Get-Content $Path
    if ($content -match $Pattern) {
        return $matches[2] -eq $ExpectedValue
    }
    return $false
}

function Set-SecurityPolicy {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Pattern,
        [Parameter(Mandatory=$true)]
        [string]$Replacement,
        [Parameter(Mandatory=$true)]
        [string]$CISCheck
    )

    $content = Get-Content $exportPath    

    # Get initial value    
    $initialValue = $content -match $Pattern
    
    # Replace and set the value
    (Get-Content $exportPath) | ForEach-Object {
        $_ -replace $Pattern, $Replacement
    } | Set-Content -Encoding Unicode $modifiedPath

    # Verify the change    
    $expectedValue = if ($Replacement -match $Pattern) { $matches[2] } else { 'Not Found' }
    $replacedValue = if (Verify-Setting -Path $modifiedPath -Pattern $Pattern -ExpectedValue $expectedValue) { $expectedValue } else { 'FAILED' }

    if ( $replacedValue -eq 'FAILED' ) {
        Add-Content $modifiedPath $Replacement
        $replacedValue = if (Verify-Setting -Path $modifiedPath -Pattern $Pattern -ExpectedValue $expectedValue) { $expectedValue } else { 'FAILED' }
    }

    Copy-Item -Path $modifiedPath -Destination $exportPath -Force

    # Log the result
    $global:complianceResults += [PSCustomObject]@{'CIS Check'=$CISCheck; 'Initial Value'=$initialValue; 'Replaced Value'=$replacedValue}
}

function Set-RegistryValue {
    param (
        [string]$Path,
        [string]$Key,
        [string]$Value,
        [string]$CISCheck
    )
    
    $initialValue = ""

    try {
        # Get the current value for logging
        $initialValue = Get-ItemPropertyValue -Path $Path -Name $Key -ErrorAction SilentlyContinue
    } catch {
        $logMessage = "CIS Check $CISCheck : Error encountered: $_"
    }

    # Try to set the new value
    try {
        Set-ItemProperty -Path $Path -Name $Key -Value $Value

        $postValue = Get-ItemPropertyValue -Path $Path -Name $Key -ErrorAction SilentlyContinue
        
        # Check if the value was actually changed
        if ($initialValue -ne $postValue) {
            $logMessage = "CIS Check $CISCheck : Value changed from $initialValue to $postValue."
        } else {
            $logMessage = "CIS Check $CISCheck : Failed to change value. Initial value: $initialValue."
        }
    } catch {
        $logMessage = "CIS Check $CISCheck : Error encountered: $_"
    }
    
    Log-Message -Message $logMessage
}

# Run the modules
Export-SecurityPolicy

# CIS 1.1.1: Ensure 'Enforce password history' is set to '24 or more password(s)'
Set-SecurityPolicy -Pattern '^(PasswordHistorySize)\s*=\s*(\d+)' -Replacement 'PasswordHistorySize = 24' -CISCheck '1.1.1'

# CIS 1.1.3: Ensure 'Minimum password age' is set to '1 or more day(s)'
Set-SecurityPolicy -Pattern '^(MinimumPasswordAge)\s*=\s*(\d+)' -Replacement 'MinimumPasswordAge = 1' -CISCheck '1.1.3'

# CIS 1.1.4: Ensure 'Minimum password length' is set to '14 or more character(s)'
Set-SecurityPolicy -Pattern '^(MinimumPasswordLength)\s*=\s*(\d+)' -Replacement 'MinimumPasswordLength = 14' -CISCheck '1.1.4'

# CIS 1.1.6: Call the function to set the 'Relax minimum password length limits' policy
Set-RegistryValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa' -Key 'NoLMHash' -Value '0' -CISCheck '1.1.6'

# CIS 1.2.2: Ensure 'Account lockout threshold' is set to '5 or fewer invalid logon attempt(s), but not 0'
Set-SecurityPolicy -Pattern '^(LockoutBadCount)\s*=\s*(\d+)' -Replacement 'LockoutBadCount = 5' -CISCheck '1.2.2'

# CIS 2.3.1.5: Configure 'Accounts: Rename administrator account'
$newName = "`"Ares`"" # A recommended alternative to "Administrator" but can be changed to any desired name other than 'root'
Set-SecurityPolicy -Pattern '^(NewAdministratorName)\s*=\s*(.*)' -Replacement "NewAdministratorName = $newName" -CISCheck '2.3.1.5'

# CIS 2.3.1.6: Configure 'Accounts: Rename guest account'
$newName = "`"Visitor`"" # A recommended alternative to "Guest"
Set-SecurityPolicy -Pattern '^(NewGuestName)\s*=\s*(.*)' -Replacement "NewGuestName = $newName" -CISCheck '2.3.1.6'

# CIS 2.3.4.1: Call the function to set the 'Devices: Allowed to format and eject removable media' policy
Set-RegistryValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' -Key 'AllocateDASD' -Value '2' -CISCheck '2.3.4.1'

# CIS 2.3.7.4 Ensure 'Interactive logon: Do not require CTRL+ALT+DEL' is set to 'Disabled'
Set-SecurityPolicy -Pattern '^(DisableCAD)\s*=\s*(\d+)' -Replacement 'DisableCAD = 0' -CISCheck '2.3.7.4'

# CIS 2.3.7.5 Ensure 'Interactive logon: Message text for users attempting to log on' 
$GDPRMessage = "By logging on to this system, you acknowledge that you are authorized to access this private system owned by Cabhrú Housing Association. Unauthorized access, use, or modification of this system or its data is strictly prohibited and may be subject to legal penalties under EU GDPR and Irish laws. By continuing, you indicate your awareness of and consent to these terms and conditions of use. LOG OFF IMMEDIATELY if you do not agree to the conditions stated in this warning."
Set-SecurityPolicy -Pattern '^(LegalNoticeText)\s*=\s*(.*)' -Replacement "LegalNoticeText = $GDPRMessage" -CISCheck '2.3.7.5'

# CIS 2.3.7.6 Ensure 'Interactive logon: Message title for users attempting to log on'
Set-SecurityPolicy -Pattern '^(LegalNoticeCaption)\s*=\s*(.*)' -Replacement 'LegalNoticeCaption = "Warning: Authorized Access Only!"' -CISCheck '2.3.7.6'

# CIS 2.3.7.7 Ensure 'Interactive logon: Number of previous logons to cache (in case domain controller is not available)'
Set-SecurityPolicy -Pattern '^(CachedLogonsCount)\s*=\s*(\d+)' -Replacement 'CachedLogonsCount = 4' -CISCheck '2.3.7.7'

# CIS 2.3.8.1 Ensure 'Microsoft network client: Digitally sign communications (always)' is set to 'Enabled'.
Set-SecurityPolicy -Pattern '^(RequireSecuritySignature)\s*=\s*(\d+)' -Replacement 'RequireSecuritySignature = 1' -CISCheck '2.3.8.1'

# CIS 2.3.9.2 Ensure 'Microsoft network server: Digitally sign communications (always)' is set to 'Enabled'.
Set-SecurityPolicy -Pattern '^(ServerRequireSecuritySignature)\s*=\s*(\d+)' -Replacement 'ServerRequireSecuritySignature = 1' -CISCheck '2.3.9.2'

# CIS 2.3.9.3 Ensure 'Microsoft network server: Digitally sign communications (if client agrees)' is set to 'Enabled'.
Set-SecurityPolicy -Pattern '^(ServerSignClientRequested)\s*=\s*(\d+)' -Replacement 'ServerSignClientRequested = 1' -CISCheck '2.3.9.3'

# CIS 2.3.9.5 Ensure 'Microsoft network server: Server SPN target name validation level' is set to 'Accept if provided by client' or higher.
# For this setting, it might be required to set a registry key. But let's first attempt with the secedit approach:
Set-SecurityPolicy -Pattern '^(ServerSpnTargetNameValidationLevel)\s*=\s*(\d+)' -Replacement 'ServerSpnTargetNameValidationLevel = 1' -CISCheck '2.3.9.5'

# CIS 2.3.11.1 Ensure 'Network security: Allow Local System to use computer identity for NTLM' is set to 'Enabled'.
Set-SecurityPolicy -Pattern '^(UseMachineID)\s*=\s*(\d+)' -Replacement 'UseMachineID = 1' -CISCheck '2.3.11.1'

# CIS 2.3.11.4 Ensure 'Network security: Configure encryption types allowed for Kerberos' is set to 'AES128_HMAC_SHA1, AES256_HMAC_SHA1, Future encryption types'.
# This setting is usually achieved via a registry key, but let's first attempt with the secedit approach:
Set-SecurityPolicy -Pattern '^(KerberosEncryptionTypes)\s*=\s*(.*)' -Replacement 'KerberosEncryptionTypes = AES128_HMAC_SHA1, AES256_HMAC_SHA1, Future encryption types' -CISCheck '2.3.11.4'

# CIS 2.3.11.7 Ensure 'Network security: LAN Manager authentication level' is set to 'Send NTLMv2 response only. Refuse LM & NTLM'.
Set-SecurityPolicy -Pattern '^(LmCompatibilityLevel)\s*=\s*(\d+)' -Replacement 'LmCompatibilityLevel = 5' -CISCheck '2.3.11.7'

# CIS 2.3.11.9 Ensure 'Network security: Minimum session security for NTLM SSP based (including secure RPC) clients' is set to 'Require NTLMv2 session security, Require 128-bit encryption'.
Set-SecurityPolicy -Pattern '^(NTLMMinClientSec)\s*=\s*(\d+)' -Replacement 'NTLMMinClientSec = 537395200' -CISCheck '2.3.11.9'

# CIS 2.3.11.10 Ensure 'Network security: Minimum session security for NTLM SSP based (including secure RPC) servers' is set to 'Require NTLMv2 session security, Require 128-bit encryption'.
Set-SecurityPolicy -Pattern '^(NTLMMinServerSec)\s*=\s*(\d+)' -Replacement 'NTLMMinServerSec = 537395200' -CISCheck '2.3.11.10'


#Import-ModifiedPolicy

# Display the log and compliance results
# $logMessages | ForEach-Object { Write-Output $_ }
$global:complianceResults | Format-Table -AutoSize