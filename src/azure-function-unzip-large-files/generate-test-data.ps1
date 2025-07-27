Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Generating Test Data for Azure Function" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# Configuration
$NumFiles = 10
$FileSizeMB = 1
$ZipPassword = "password"
$OutputDir = "test-data"
$ZipFile = "test-data-1gb.zip"

# Create output directory
Write-Host "Creating test data directory..." -ForegroundColor Green
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

# Check if 7-Zip is installed
$7zipPath = @(
    "$env:ProgramFiles\7-Zip\7z.exe",
    "$env:ProgramFiles(x86)\7-Zip\7z.exe",
    "C:\Program Files\7-Zip\7z.exe",
    "C:\Program Files (x86)\7-Zip\7z.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1

if (-not $7zipPath) {
    Write-Host "Error: 7-Zip not found. Please install 7-Zip from https://www.7-zip.org/" -ForegroundColor Red
    Write-Host "Or install via winget: winget install 7zip.7zip" -ForegroundColor Yellow
    exit 1
}

# Generate files
Write-Host "Generating $NumFiles files of ${FileSizeMB}MB each..." -ForegroundColor Green
for ($i = 1; $i -le $NumFiles; $i++) {
    $FileName = "$OutputDir\test-file-$('{0:D2}' -f $i).txt"
    Write-Host "Creating $FileName (${FileSizeMB}MB)..." -ForegroundColor White
    
    # Create file with random text-like content
    $FileSizeBytes = $FileSizeMB * 1024 * 1024
    $StringBuilder = New-Object System.Text.StringBuilder
    
    # Generate random text in chunks to avoid memory issues
    $ChunkSize = 1024 * 1024  # 1MB chunks
    $ChunksNeeded = $FileSizeMB
    
    for ($chunk = 0; $chunk -lt $ChunksNeeded; $chunk++) {
        # Generate random bytes and convert to Base64 for text-like content
        $RandomBytes = New-Object byte[] $ChunkSize
        $Random = New-Object System.Random
        $Random.NextBytes($RandomBytes)
        $Base64Text = [Convert]::ToBase64String($RandomBytes)
        $StringBuilder.Append($Base64Text) | Out-Null
    }
    
    # Write to file and ensure exact size
    $Content = $StringBuilder.ToString()
    [System.IO.File]::WriteAllText($FileName, $Content.Substring(0, $FileSizeBytes))
    
    Write-Host "✓ Created $FileName" -ForegroundColor Green
}

# Create password-protected ZIP file using 7-Zip
Write-Host ""
Write-Host "Creating password-protected ZIP file..." -ForegroundColor Green
$FilesToZip = Join-Path $OutputDir "*.txt"
& $7zipPath a -tzip -p"$ZipPassword" -mx=3 "$ZipFile" "$FilesToZip" | Out-Null

# Calculate sizes
$TotalSizeMB = $NumFiles * $FileSizeMB
$ZipInfo = Get-Item $ZipFile
$ZipSizeMB = [math]::Round($ZipInfo.Length / 1MB, 2)

# Clean up temporary files
Write-Host "Cleaning up temporary files..." -ForegroundColor Green
Remove-Item -Path $OutputDir -Recurse -Force

# Summary
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Test Data Generation Complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Generated: $ZipFile" -ForegroundColor Yellow
Write-Host "Password: $ZipPassword" -ForegroundColor Yellow
Write-Host "Contents: $NumFiles files × ${FileSizeMB}MB = ${TotalSizeMB}MB uncompressed" -ForegroundColor White
Write-Host "ZIP Size: ${ZipSizeMB}MB" -ForegroundColor White
Write-Host ""
Write-Host "To upload to Azure Storage:" -ForegroundColor Cyan
Write-Host "az storage blob upload \`" -ForegroundColor White
Write-Host "  --account-name YOUR_STORAGE_ACCOUNT_NAME \`" -ForegroundColor White
Write-Host "  --container-name zipped \`" -ForegroundColor White
Write-Host "  --name $ZipFile \`" -ForegroundColor White
Write-Host "  --file $ZipFile" -ForegroundColor White
Write-Host ""
Write-Host "Or use Azure Storage Explorer for a GUI upload experience." -ForegroundColor Yellow