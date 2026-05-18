# Disconnect first to clear any stale tokens
Disconnect-MgGraph -ErrorAction SilentlyContinue

# Connect with the required scopes for Intune Devices and LAPS Credential Retrieval
Connect-MgGraph -Scopes "DeviceManagementManagedDevices.Read.All", "DeviceLocalCredential.Read.All", "Device.Read.All"

# --- 1. Get ALL Intune-Managed Devices (Source of Truth) ---
Write-Host "1. Retrieving all Intune-managed devices..."
$AllIntuneDevices = Get-MgDeviceManagementManagedDevice -All | 
    Select-Object DeviceName, AzureADDeviceId, ManagedDeviceOwnerType, LastSyncDateTime

# --- 2. Get ALL Device IDs That HAVE a LAPS Record Stored (v1.0 FIX) ---
# Endpoint: GET https://graph.microsoft.com/v1.0/directory/deviceLocalCredentials
Write-Host "2. Retrieving LAPS credential records from the official v1.0 Graph API..."

# Define the V1.0 URL for LAPS listings
$Uri = "https://graph.microsoft.com/v1.0/directory/deviceLocalCredentials"
$LapsEnabledDeviceIds = @()

# Handle Paging to retrieve ALL records
do {
    # Invoke the raw request
    $Response = Invoke-MgGraphRequest -Uri $Uri -Method Get -OutputType PSObject -ErrorAction Stop
    
    # Process the current page of results
    if ($Response.value) {
        # The result returns a collection of deviceLocalCredentialInfo objects. 
        # We extract the 'id' (which is the Entra ID Device ID)
        $LapsEnabledDeviceIds += $Response.value.id
    }
    
    # Check if there is a next page
    $Uri = $Response.'@odata.nextLink'
    
} while ($Uri)

Write-Host "   Found $($LapsEnabledDeviceIds.Count) devices with active LAPS passwords in Entra ID." -ForegroundColor Cyan


# --- 3. Compare the Lists ---
Write-Host "3. Comparing Intune Fleet vs. LAPS Records..."

# Find Intune devices where the AzureADDeviceId is NOT in the LapsEnabledDeviceIds list
$DevicesMissingLAPS = $AllIntuneDevices | Where-Object { 
    # Use -notcontains for comparison
    $LapsEnabledDeviceIds -notcontains $_.AzureADDeviceId 
} | Select-Object DeviceName, AzureADDeviceId, ManagedDeviceOwnerType, LastSyncDateTime

# --- 4. Final Report ---
Write-Host "`n=================================================================="
if ($DevicesMissingLAPS.Count -gt 0) {
    Write-Host "⚠️  DEVICES MISSING LAPS PASSWORDS ($($DevicesMissingLAPS.Count))" -ForegroundColor Red
    Write-Host "=================================================================="
    $DevicesMissingLAPS | Format-Table -AutoSize
} else {
    Write-Host "✅  SUCCESS: All Intune-managed devices successfully have a LAPS password stored." -ForegroundColor Green
    Write-Host "=================================================================="
}