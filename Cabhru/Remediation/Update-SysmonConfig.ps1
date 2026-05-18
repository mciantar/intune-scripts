<#----------------------------------------------------------------------------
LEGAL DISCLAIMER 
This Sample Code is provided for the purpose of illustration only and is not 
intended to be used in a production environment.  THIS SAMPLE CODE AND ANY 
RELATED INFORMATION ARE PROVIDED "AS IS" WITHOUT WARRANTY OF ANY KIND, EITHER 
EXPRESSED OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE IMPLIED WARRANTIES OF 
MERCHANTABILITY AND/OR FITNESS FOR A PARTICULAR PURPOSE.  We grant You a 
nonexclusive, royalty-free right to use and modify the Sample Code and to 
reproduce and distribute the object code form of the Sample Code, provided 
that You agree: (i) to not use Our name, logo, or trademarks to market Your 
software product in which the Sample Code is embedded; (ii) to include a valid 
copyright notice on Your software product in which the Sample Code is embedded; 
and (iii) to indemnify, hold harmless, and defend Us and Our suppliers from and 
against any claims or lawsuits, including attorneys’ fees, that arise or result 
from the use or distribution of the Sample Code. 
  
This posting is provided "AS IS" with no warranties, and confers no rights. Use 
of included script samples are subject to the terms specified 
at http://www.microsoft.com/info/cpyright.htm. 

Written by Moti Bani - mobani@microsoft.com - (http://blogs.technet.com/b/motiba/) 
#>
function Write-LogToConsole($msg, $status) {
    switch ($status) {
        'OK' {Write-Color -Text "[*] $msg ... ", $status -Color White, Green}
        'Error' {Write-Color -Text "[*] $msg ... ", $status -Color White, Red}        
    }
}
function Write-Color([String[]]$Text, [ConsoleColor[]]$Color) {
    for ($i = 0; $i -lt $Text.Length; $i++) {
        Write-Host $Text[$i] -Foreground $Color[$i] -NoNewLine
    }
    Write-Host
}
<#
   Sysinternals Sysmom Configuration Update

	.DESCRIPTION
	    Use Update-SysmonConfig to load Sysmon configuration from a XML file and publish it using Group Policy Preferneces
	    	
    .PARAMETER SysmonBinPath 
        Sysmon EXE file location
    .PARAMETER SysmonXMLPath 
        Sysmon XML file location
    .PARAMETER GPOName 
        Group Policy Name
	.EXAMPLE
		    Update-SysmonConfig -SysmonBinPath C:\Windows\Sysmon.exe -SysmonXMLPath C:\temp\Sysmon\config_v8.xml -GPOName "Domain Audit Policy"
#>
function Update-SysmonConfig {
    [CmdletBinding()]
    param (
        [string]$SysmonBinPath,
        [string]$SysmonXMLPath,
        [string]$GPOName
    )
    
    $Sysmon__Arguemnts = @("/accepteula")
    $Sysmon__Arguemnts += " -c `"$SysmonXMLPath`""    
    
    try {
        Write-LogToConsole -msg "Running command: $SysmonBinPath $Sysmon__Arguemnts" -status "ok"
        Start-Process -FilePath $SysmonPath -ArgumentList $Sysmon__Arguemnts -wait -windowStyle Hidden 
    }
    catch [System.Exception] {
        Write-Host $Exception 
    }    

    $key_path = 'HKLM:\SYSTEM\CurrentControlSet\Services\SysmonDrv\Parameters'
    Write-LogToConsole -msg "Reading Registry values from: $key_path" -status "ok"
    $Rules = (Get-ItemProperty -Path $key_path)."Rules"
    $Options = (Get-ItemProperty -Path $key_path)."Options"
    $HashingAlgorithm = (Get-ItemProperty -Path $key_path)."HashingAlgorithm"
    
    Write-LogToConsole -msg "Writing Registry values to: $GPOName" -status "ok"
    
    Remove-GPPrefRegistryValue -Name $GPOName  -Context Computer -Key "HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\SysmonDrv\Parameters" -ErrorAction SilentlyContinue
    Set-GPPrefRegistryValue -Name $GPOName -Action Replace -Key "HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\SysmonDrv\Parameters" -Context Computer -valueName Rules -Value $Rules  -order 1 -Type Binary
    Set-GPPrefRegistryValue -Name $GPOName -Action Replace -Key "HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\SysmonDrv\Parameters" -Context Computer  -valueName Options -Value $Options  -order 2 -Type DWord
    Set-GPPrefRegistryValue -Name $GPOName -Action Replace -Key "HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\SysmonDrv\Parameters" -Context Computer  -valueName HashingAlgorithm -Value $HashingAlgorithm -order 3 -Type DWord
    
}



