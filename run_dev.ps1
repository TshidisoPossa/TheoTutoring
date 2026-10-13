# Starts the whole project for local development:
#   1. loads theo_tutoring_backend/.env
#   2. starts the Dart Frog backend in its own window (http://localhost:8080)
#   3. runs the Flutter app once the backend is listening
#
# Usage:  powershell -ExecutionPolicy Bypass -File .\run_dev.ps1 [-Device chrome|edge|windows]
# The Windows desktop build needs ~15 GB free disk space (Firebase C++ SDK), so Chrome is the default.
param([string]$Device = 'chrome')

$ErrorActionPreference = 'Stop'
$backend = Join-Path $PSScriptRoot 'theo_tutoring_backend'
$app = Join-Path $PSScriptRoot 'theo_tutoring_app'

# The backend reads its settings from environment variables, so copy .env into this session.
$envFile = Join-Path $backend '.env'
if (-not (Test-Path $envFile)) { throw "Missing $envFile" }
Get-Content $envFile | ForEach-Object {
    if ($_ -match '^\s*([^#=]+?)\s*=\s*(.*)$') {
        Set-Item "env:$($matches[1])" $matches[2].Trim().Trim('"')
    }
}
if (-not $env:DB_PASSWORD) {
    Write-Warning 'DB_PASSWORD is empty in .env - MySQL will refuse the connection.'
}

if (Get-NetTCPConnection -LocalPort 8080 -State Listen -ErrorAction SilentlyContinue) {
    Write-Host 'Backend already running on port 8080 - reusing it.'
} else {
    # The new window inherits the variables loaded above.
    Start-Process powershell -ArgumentList '-NoExit', '-Command', "Set-Location '$backend'; dart_frog dev"
}

Write-Host 'Waiting for the backend on port 8080...'
$deadline = (Get-Date).AddSeconds(90)
while (-not (Get-NetTCPConnection -LocalPort 8080 -State Listen -ErrorAction SilentlyContinue)) {
    if ((Get-Date) -gt $deadline) { throw 'Backend did not start - check the Dart Frog window.' }
    Start-Sleep -Seconds 1
}
Write-Host 'Backend is up. Starting the Flutter app...'

Set-Location $app
flutter run -d $Device
