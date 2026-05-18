# Set username and password
$Username = "analise-admin"
$Password = ""

# Create the new user
$SecurePassword = ConvertTo-SecureString -String $Password -AsPlainText -Force
$LocalUser = New-LocalUser -Name $Username -Password $SecurePassword -UserMayNotChangePassword -PasswordNeverExpires

# Add the user to the local administrators group
$LocalAdminsGroup = Get-LocalGroup -Name "Administrators"
$LocalAdminsGroup | Add-LocalGroupMember -Member $Username