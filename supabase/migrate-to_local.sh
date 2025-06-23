#!/bin/bash
# filepath: /Users/b-mini/sites/thuenen/tfm/TFM-Server/supabase/migrate-to_local.sh

set -e  # Exit on error
set -a && source ../.env && set +a

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Local database connection string
LOCAL_DB="postgres://postgres:postgres@127.0.0.1:54322/postgres"

echo -e "${BLUE}🚀 Migration Script for Local Supabase${NC}"
echo "========================================================"

# Function to check if migration file exists
check_migration_file() {
    local migration_file=$1
    if [[ ! -f "$migration_file" ]]; then
        echo -e "${RED}❌ Migration file not found: $migration_file${NC}"
        exit 1
    fi
}

# Function to create backup
create_backup() {
    echo -e "${YELLOW}📦 Creating backup...${NC}"
    local backup_file="backups/local_backup_$(date +%Y%m%d_%H%M%S).sql"
    mkdir -p backups
    
    pg_dump "$LOCAL_DB" > "$backup_file"
    
    if [[ $? -eq 0 ]]; then
        echo -e "${GREEN}✅ Backup created: $backup_file${NC}"
    else
        echo -e "${RED}❌ Backup failed!${NC}"
        exit 1
    fi
}

# Function to apply migration
apply_migration() {
    local migration_file=$1
    echo -e "${YELLOW}🔄 Applying migration: $migration_file${NC}"
    
    # Check if migration contains potentially dangerous operations
    if grep -i "DROP TABLE\|TRUNCATE\|DELETE FROM" "$migration_file" > /dev/null; then
        echo -e "${RED}⚠️  WARNING: Migration contains potentially destructive operations!${NC}"
        echo "Found: $(grep -i "DROP TABLE\|TRUNCATE\|DELETE FROM" "$migration_file")"
        read -p "Are you sure you want to continue? (yes/no): " confirm
        if [[ $confirm != "yes" ]]; then
            echo -e "${YELLOW}Migration cancelled.${NC}"
            exit 1
        fi
    fi
    
    # Apply migration to local database
    PGPASSWORD=postgres psql -h 127.0.0.1 -p 54322 -U postgres -d postgres -f "$migration_file"
    
    if [[ $? -eq 0 ]]; then
        echo -e "${GREEN}✅ Migration applied successfully!${NC}"
    else
        echo -e "${RED}❌ Migration failed!${NC}"
        echo -e "${YELLOW}💡 You can restore from backup if needed.${NC}"
        exit 1
    fi
}

# Function to test connection
test_connection() {
    echo -e "${YELLOW}🔗 Testing local database connection...${NC}"
    PGPASSWORD=postgres psql -h 127.0.0.1 -p 54322 -U postgres -d postgres -c "SELECT version();" > /dev/null 2>&1
    
    if [[ $? -eq 0 ]]; then
        echo -e "${GREEN}✅ Local database connection successful${NC}"
    else
        echo -e "${RED}❌ Cannot connect to local database. Is Supabase running?${NC}"
        echo -e "${YELLOW}💡 Try running: supabase start${NC}"
        exit 1
    fi
}

# Function to check if Supabase is running
check_supabase_status() {
    echo -e "${YELLOW}🔍 Checking Supabase status...${NC}"
    if supabase status > /dev/null 2>&1; then
        echo -e "${GREEN}✅ Supabase is running${NC}"
        supabase status
    else
        echo -e "${RED}❌ Supabase is not running${NC}"
        echo -e "${YELLOW}💡 Starting Supabase...${NC}"
        supabase start
    fi
}

# Main script logic
main() {
    # Check if migration file is provided
    if [[ $# -eq 0 ]]; then
        echo -e "${YELLOW}Usage: $0 <migration_file.sql>${NC}"
        echo -e "${YELLOW}Example: $0 migrations/20250115140818_public.sql${NC}"
        echo ""
        echo -e "${BLUE}Available migration files:${NC}"
        ls -la migrations/*.sql 2>/dev/null || echo "No migration files found"
        exit 1
    fi
    
    local migration_file=$1
    
    # Validate inputs
    check_supabase_status
    test_connection
    check_migration_file "$migration_file"
    
    # Show migration preview
    echo -e "${BLUE}📋 Migration Preview:${NC}"
    echo "File: $migration_file"
    echo "Size: $(wc -l < "$migration_file") lines"
    echo "Target: Local Supabase (127.0.0.1:54322)"
    echo ""
    
    # Confirm before proceeding
    read -p "Do you want to create a backup before applying migration? (y/n): " backup_confirm
    if [[ $backup_confirm == "y" || $backup_confirm == "Y" ]]; then
        create_backup
    fi
    
    read -p "Apply migration to local database? (y/n): " apply_confirm
    if [[ $apply_confirm == "y" || $apply_confirm == "Y" ]]; then
        apply_migration "$migration_file"
        echo -e "${GREEN}🎉 Local migration completed successfully!${NC}"
        echo -e "${BLUE}💡 You can now test your changes locally before applying to remote${NC}"
    else
        echo -e "${YELLOW}Migration cancelled.${NC}"
    fi
}

# Run main function with all arguments
main "$@"