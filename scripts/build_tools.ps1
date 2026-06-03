param (
    [switch]$Force,
    [switch]$NoUpdate
)

# Check if tools/.current exists
if (-not $Force -and (Test-Path "tools\.current") -And !(Compare-Object (Get-Content "tools\.current") (Get-Content "tools\.expected") -SyncWindow 0)) {
    Write-Host "Files are identical. No build needed."
    exit 0
}

if (-not $NoUpdate) {
    Write-Host "Updating submodules"
    git submodule update --init --recursive
    if ( -not $? ) {
        exit 1
    }
}

Write-Host "Building Odin Toolchain"
Push-Location "tools\Odin"
.\build.bat release
if ( -not $? ) {
    exit 1
}
Pop-Location

Copy-Item -Force "tools\.expected" "tools\.current"
Write-Host "Build complete and .current updated."