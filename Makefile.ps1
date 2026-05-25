# =============================================================================
# Diploma Marketplace - Windows PowerShell launcher
# =============================================================================
# Usage:
#   .\Makefile.ps1 help           Show all commands
#   .\Makefile.ps1 up             Start infrastructure (databases, redis, kafka, etc.)
#   .\Makefile.ps1 down           Stop infrastructure
#   .\Makefile.ps1 start          Start infrastructure + run all microservices
#   .\Makefile.ps1 start-one api-gateway   Run a single microservice
#   .\Makefile.ps1 build          Build all Docker images
#   .\Makefile.ps1 migrate        Run DB migrations
#   .\Makefile.ps1 keys-generate  Generate RSA JWT keys
#   .\Makefile.ps1 reset          Full teardown (destroys volumes)
# =============================================================================

param(
    [Parameter(Position = 0)]
    [ValidateSet("help", "up", "down", "start", "start-one", "down-services", "build", "migrate", "keys-generate", "reset")]
    [string]$Command = "help",

    [Parameter(Position = 1)]
    [string]$ServiceName
)

$KEY_DIR = Join-Path $PSScriptRoot "keys"

$ALL_SERVICES = @(
    "api-gateway", "auth-service", "user-service", "order-service",
    "offer-service", "chat-service", "file-service", "notification-service", "mail-service"
)

$MIGRATE_SERVICES = @(
    "auth-service", "user-service", "order-service", "offer-service",
    "chat-service", "file-service", "notification-service"
)

# Map service name -> container name, database name
$MIGRATE_MAP = @{
    "auth-service"         = @{ Container = "postgres-auth";          Db = "auth_db" }
    "user-service"         = @{ Container = "postgres-user";          Db = "user_db" }
    "order-service"        = @{ Container = "postgres-order";         Db = "order_db" }
    "offer-service"        = @{ Container = "postgres-offer";         Db = "offer_db" }
    "chat-service"         = @{ Container = "postgres-chat";          Db = "chat_db" }
    "file-service"         = @{ Container = "postgres-file";          Db = "file_db" }
    "notification-service" = @{ Container = "postgres-notification";  Db = "notification_db" }
}

# Services that have a cmd/api/main.go entry point (not mail-service)
$API_SERVICES = @(
    "api-gateway", "auth-service", "user-service", "order-service",
    "offer-service", "chat-service", "file-service", "notification-service"
)

# =============================================================================
# Helpers
# =============================================================================

function Resolve-Path2 {
    param([string]$A, [string]$B)
    return Join-Path $A $B
}

function Resolve-Path3 {
    param([string]$A, [string]$B, [string]$C)
    return Join-Path (Join-Path $A $B) $C
}

# =============================================================================
# Help
# =============================================================================

function Show-Help {
    Write-Host ""
    Write-Host "Diploma Marketplace - Commands" -ForegroundColor Cyan
    Write-Host "================================`n"
    Write-Host "  .\Makefile.ps1 up                   Start all infrastructure services"
    Write-Host "  .\Makefile.ps1 down                 Stop all infrastructure services"
    Write-Host "  .\Makefile.ps1 start                Start infra + run all microservices"
    Write-Host "  .\Makefile.ps1 start-one <name>     Run a single microservice"
    Write-Host "  .\Makefile.ps1 build                Build all service Docker images"
    Write-Host "  .\Makefile.ps1 migrate              Run all database migrations"
    Write-Host "  .\Makefile.ps1 keys-generate        Generate RSA key pair for JWT"
    Write-Host "  .\Makefile.ps1 reset                Full teardown (destroys all data)"
    Write-Host ""
    Write-Host "Available services for start-one:" -ForegroundColor DarkGray
    foreach ($s in $API_SERVICES) {
        Write-Host "    $s" -ForegroundColor DarkGray
    }
    Write-Host ""
}

# =============================================================================
# Start infrastructure
# =============================================================================

function Start-Infra {
    Write-Host "Starting all infrastructure services..." -ForegroundColor Green
    docker compose up -d
}

# =============================================================================
# Stop infrastructure
# =============================================================================

function Stop-Infra {
    Write-Host "Stopping all infrastructure services..." -ForegroundColor Yellow
    docker compose down
}

# =============================================================================
# Run a single microservice
# =============================================================================

function Start-OneService {
    param([string]$Svc)

    $svcPath = Resolve-Path2 $PSScriptRoot $Svc
    $mainFile = Resolve-Path3 $PSScriptRoot $Svc "cmd/api/main.go"

    if (-not (Test-Path $mainFile)) {
        Write-Host "Error: $mainFile not found" -ForegroundColor Red
        return
    }

    Write-Host "Starting $Svc..." -ForegroundColor Cyan
    Push-Location $svcPath
    try {
        go run ./cmd/api/main.go
    } catch {
        Write-Host "Service $Svc failed: $_" -ForegroundColor Red
    }
    Pop-Location
}

# =============================================================================
# Run all microservices
# =============================================================================

function Start-AllServices {
    Write-Host "Starting infrastructure..." -ForegroundColor Green
    docker compose up -d

    Write-Host ""
    Write-Host "Starting all microservices..." -ForegroundColor Green
    Write-Host "Press Ctrl+C to stop all.`n"

    $jobs = @()
    foreach ($svc in $API_SERVICES) {
        $svcPath = Resolve-Path2 $PSScriptRoot $svc
        $jobs += Start-Job -Name $svc -ArgumentList $svcPath {
            param($path)
            Set-Location $path
            go run ./cmd/api/main.go 2>&1 | Write-Host -ForegroundColor DarkGray
        }
        Write-Host "  Started $svc (background job $($jobs[-1].Id))" -ForegroundColor Cyan
    }

    Write-Host ""
    Write-Host "All services running. Use 'Get-Job' to check status." -ForegroundColor Yellow
    Write-Host "To stop: .\Makefile.ps1 down-services" -ForegroundColor Yellow
    Write-Host ""
}

# =============================================================================
# Stop all background service jobs
# =============================================================================

function Stop-AllServices {
    Write-Host "Stopping all background services..." -ForegroundColor Yellow
    $jobs = Get-Job | Where-Object { $_.Name -in $API_SERVICES }
    foreach ($job in $jobs) {
        Stop-Job -Job $job
        Remove-Job -Job $job
        Write-Host "  Stopped $($job.Name)" -ForegroundColor DarkGray
    }
    Write-Host "All service jobs stopped." -ForegroundColor Yellow
}

# =============================================================================
# Build all Docker images
# =============================================================================

function Build-All {
    Write-Host "Building all services..." -ForegroundColor Green
    foreach ($svc in $ALL_SERVICES) {
        $dockerfile = Resolve-Path3 $PSScriptRoot $svc "Dockerfile"
        if (Test-Path $dockerfile) {
            Write-Host "Building $svc..." -ForegroundColor Cyan
            docker build -t "diploma/${svc}:latest" (Resolve-Path2 $PSScriptRoot $svc)
        } else {
            Write-Host "Skipping $svc (no Dockerfile)" -ForegroundColor DarkGray
        }
    }
    Write-Host "Build complete." -ForegroundColor Green
}

# =============================================================================
# Run all migrations
# =============================================================================

function Invoke-Migrate {
    Write-Host "Running migrations for all services..." -ForegroundColor Green
    foreach ($svc in $MIGRATE_SERVICES) {
        $migrationDir = Resolve-Path3 $PSScriptRoot $svc "migrations"
        if (Test-Path $migrationDir) {
            $container = $MIGRATE_MAP[$svc].Container
            $db = $MIGRATE_MAP[$svc].Db
            Write-Host "Migrating $svc ($container/$db)..." -ForegroundColor Cyan

            $sqlFiles = Get-ChildItem -Path $migrationDir -Filter "*.up.sql" | Sort-Object Name
            foreach ($sqlFile in $sqlFiles) {
                Write-Host "  Running $($sqlFile.Name)..." -ForegroundColor DarkGray
                Get-Content $sqlFile.FullName -Raw | docker exec -i $container psql -U postgres -d $db
                if ($LASTEXITCODE -ne 0) {
                    Write-Host "  Migration $($sqlFile.Name) failed for $svc" -ForegroundColor Red
                }
            }
        } else {
            Write-Host "Skipping $svc (no migrations directory)" -ForegroundColor DarkGray
        }
    }
    Write-Host "Migrations complete." -ForegroundColor Green
}

# =============================================================================
# Generate RSA keys
# =============================================================================

function New-JwtKeys {
    Write-Host "Generating RSA key pair for JWT signing..." -ForegroundColor Green

    if (-not (Test-Path $KEY_DIR)) {
        New-Item -ItemType Directory -Force -Path $KEY_DIR | Out-Null
    }

    # Try OpenSSL first
    $openssl = Get-Command openssl -ErrorAction SilentlyContinue
    if ($openssl) {
        Write-Host "Using OpenSSL..." -ForegroundColor Cyan
        & openssl genrsa -out (Resolve-Path2 $KEY_DIR "private.pem") 2048
        & openssl rsa -in (Resolve-Path2 $KEY_DIR "private.pem") -pubout -out (Resolve-Path2 $KEY_DIR "public.pem")
    } else {
        # Use .NET cryptography as fallback
        Write-Host "OpenSSL not found, using .NET cryptography..." -ForegroundColor Cyan

        $rsa = [System.Security.Cryptography.RSA]::Create(2048)

        $privateKeyBytes = $rsa.ExportPkcs8PrivateKey()
        $privatePem = "-----BEGIN PRIVATE KEY-----`r`n" +
                      [Convert]::ToBase64String($privateKeyBytes, [Base64FormattingOptions]::InsertLineBreaks) +
                      "`r`n-----END PRIVATE KEY-----"
        Set-Content -Path (Resolve-Path2 $KEY_DIR "private.pem") -Value $privatePem -NoNewline

        $publicKeyBytes = $rsa.ExportSubjectPublicKeyInfo()
        $publicPem = "-----BEGIN PUBLIC KEY-----`r`n" +
                     [Convert]::ToBase64String($publicKeyBytes, [Base64FormattingOptions]::InsertLineBreaks) +
                     "`r`n-----END PUBLIC KEY-----"
        Set-Content -Path (Resolve-Path2 $KEY_DIR "public.pem") -Value $publicPem -NoNewline

        $rsa.Dispose()
    }

    Write-Host "RSA keys generated in $KEY_DIR" -ForegroundColor Green
}

# =============================================================================
# Full reset
# =============================================================================

function Reset-All {
    Write-Host "Full teardown (including volumes)..." -ForegroundColor Red
    docker compose down -v
    Write-Host "Full reset complete. All volumes removed." -ForegroundColor Yellow
}

# =============================================================================
# Dispatch
# =============================================================================

switch ($Command) {
    "help"           { Show-Help }
    "up"             { Start-Infra }
    "down"           { Stop-Infra }
    "start"          { Start-AllServices }
    "start-one"      { Start-OneService -Svc $ServiceName }
    "down-services"  { Stop-AllServices }
    "build"          { Build-All }
    "migrate"        { Invoke-Migrate }
    "keys-generate"  { New-JwtKeys }
    "reset"          { Reset-All }
}
