# install-zig.ps1

# Create temporary directory for download
$tempDir = Join-Path $env:TEMP "zig-install"
New-Item -ItemType Directory -Force -Path $tempDir | Out-Null

# Download Zig
$zigVersion = "0.11.0"
$zigUrl = "https://ziglang.org/download/$zigVersion/zig-windows-x86_64-$zigVersion.zip"
$zipPath = Join-Path $tempDir "zig.zip"
Write-Host "Downloading Zig $zigVersion..."
Invoke-WebRequest -Uri $zigUrl -OutFile $zipPath

# Remove existing Zig if present
if (Test-Path "C:\zig") {
    Write-Host "Removing existing Zig installation..."
    Remove-Item -Path "C:\zig" -Recurse -Force
}

# Extract Zig
Write-Host "Extracting Zig..."
Expand-Archive -Path $zipPath -DestinationPath "C:\" -Force
Rename-Item -Path "C:\zig-windows-x86_64-$zigVersion" -NewName "zig"

# Add to PATH if not already present
$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
if ($userPath -notlike "*C:\zig*") {
    Write-Host "Adding Zig to PATH..."
    [Environment]::SetEnvironmentVariable(
        "Path",
        "$userPath;C:\zig",
        "User"
    )
}

# Clean up
Remove-Item -Path $tempDir -Recurse -Force

# Update current session's PATH
$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")

Write-Host "Zig installation complete! Please restart your terminal."
Write-Host "Verifying installation..."
& "C:\zig\zig.exe" version