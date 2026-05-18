$registry_script_b64 = "V2luZG93cyBSZWdpc3RyeSBFZGl0b3IgVmVyc2lvbiA1LjAwCgpbSEtFWV9MT0NBTF9NQUNISU5FXFNZU1RFTVxDdXJyZW50Q29udHJvbFNldFxTZXJ2aWNlc1xtcnhzbWIxMF0KIlN0YXJ0Ij1kd29yZDowMDAwMDAwNAo="
$registry_script = [System.Text.Encoding]::ASCII.GetString([System.Convert]::FromBase64String($registry_script_b64))
$registry_script_file = New-TemporaryFile
$registry_script | Out-File $registry_script_file.FullName
Start-Process -FilePath "c:\Windows\system32\reg.exe" -ArgumentList "import",$registry_script_file.FullName -Wait -WindowStyle Hidden -Verb RunAs -Verbose
Remove-Item $registry_script_file.FullName 