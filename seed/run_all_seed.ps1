# ============================================================================
# Seed all Diploma Marketplace databases (PowerShell).
# Usage: .\seed\run_all_seed.ps1
# ============================================================================

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

Write-Host "Seeding auth_db..."
Get-Content "$ScriptDir\001_auth_seed.sql" | docker exec -i postgres-auth psql -U postgres -d auth_db
Write-Host "  auth_db seeded."

Write-Host "Seeding user_db..."
Get-Content "$ScriptDir\002_user_seed.sql" | docker exec -i postgres-user psql -U postgres -d user_db
Write-Host "  user_db seeded."

Write-Host "Seeding order_db..."
Get-Content "$ScriptDir\003_order_seed.sql" | docker exec -i postgres-order psql -U postgres -d order_db
Write-Host "  order_db seeded."

Write-Host ""
Write-Host "All databases seeded successfully!"
