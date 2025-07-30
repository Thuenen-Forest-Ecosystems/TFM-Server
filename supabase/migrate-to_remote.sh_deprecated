#!/bin/bash
# filepath: /Users/b-mini/sites/thuenen/tfm/TFM-Server/supabase/migrate-to_remote.sh

set -e  # Exit on error
set -a && source ../.env && set +a

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Remote database connection string
REMOTE_DB="postgres://postgres:$POSTGRES_PASSWORD@134.110.100.75:3389/$POSTGRES_DB"

echo -e "${BLUE}🚀 Migration Script for Remote Self-hosted Supabase${NC}"
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
    local backup_file="backups/backup_$(date +%Y%m%d_%H%M%S).sql"
    mkdir -p backups
    
    pg_dump "$REMOTE_DB" > "$backup_file"
    
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
    
    # Apply migration
    psql "$REMOTE_DB" -f "$migration_file"
    
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
    echo -e "${YELLOW}🔗 Testing database connection...${NC}"
    psql "$REMOTE_DB" -c "SELECT version();" > /dev/null 2>&1
    
    if [[ $? -eq 0 ]]; then
        echo -e "${GREEN}✅ Database connection successful${NC}"
    else
        echo -e "${RED}❌ Cannot connect to database${NC}"
        exit 1
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
    test_connection
    check_migration_file "$migration_file"
    
    # Show migration preview
    echo -e "${BLUE}📋 Migration Preview:${NC}"
    echo "File: $migration_file"
    echo "Size: $(wc -l < "$migration_file") lines"
    echo ""
    
    # Confirm before proceeding
    read -p "Do you want to create a backup before applying migration? (y/n): " backup_confirm
    if [[ $backup_confirm == "y" || $backup_confirm == "Y" ]]; then
        create_backup
    fi
    
    read -p "Apply migration to remote database? (y/n): " apply_confirm
    if [[ $apply_confirm == "y" || $apply_confirm == "Y" ]]; then
        apply_migration "$migration_file"
        echo -e "${GREEN}🎉 Migration completed successfully!${NC}"
    else
        echo -e "${YELLOW}Migration cancelled.${NC}"
    fi
}

# Run main function with all arguments
main "$@"