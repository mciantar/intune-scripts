function Get-FolderSizes {
    param (
        [string]$Path
    )

    $padLength = 500  # Adjust based on the maximum expected path length or console width
    $displayPath = if ($Path.Length -le $padLength) { $Path } else { "..." + $Path.Substring($Path.Length - $padLength + 3) }
    $message = "Processing: $displayPath"
    $messagePadded = $message + " " * ($padLength - $message.Length)
    
    Write-Host "`r$messagePadded" -NoNewline
    
    $ownSize = 0
    $totalSize = 0

    $files = Get-ChildItem -Path $Path -File -Force -ErrorAction SilentlyContinue
    foreach ($file in $files) {
        $ownSize += $file.Length
    }

    $totalSize += $ownSize

    $subFolders = Get-ChildItem -Path $Path -Directory -Force -ErrorAction SilentlyContinue | Sort-Object FullName
    foreach ($subFolder in $subFolders) {
        $subFolderSizes = Get-FolderSizes -Path $subFolder.FullName
        $totalSize += $subFolderSizes.TotalSize
    }

    $csvLine = "`"$Path`",$ownSize,$totalSize"
    Add-Content -Path $global:reportFilePath -Value $csvLine

    return @{
        OwnSize = $ownSize
        TotalSize = $totalSize
    }
}

$rootPath = "C:\"
$global:reportFilePath = "C:\Windows\Temp\folderSizesReport.csv"
"Path,Folder Size,Total Size (Including Children)" | Out-File -FilePath $global:reportFilePath
Get-FolderSizes -Path $rootPath
Write-Host "`nReport generation complete."
