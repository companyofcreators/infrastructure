#!/bin/bash
# ============================================================================
# Seed all Diploma Marketplace databases.
# Usage: bash seed/run_all_seed.sh
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Seeding auth_db..."
docker exec -i postgres-auth psql -U postgres -d auth_db < "${SCRIPT_DIR}/001_auth_seed.sql"
echo "  auth_db seeded."

echo "Seeding user_db..."
docker exec -i postgres-user psql -U postgres -d user_db < "${SCRIPT_DIR}/002_user_seed.sql"
echo "  user_db seeded."

echo "Seeding order_db..."
docker exec -i postgres-order psql -U postgres -d order_db < "${SCRIPT_DIR}/003_order_seed.sql"
echo "  order_db seeded."

echo ""
echo "All databases seeded successfully!"
