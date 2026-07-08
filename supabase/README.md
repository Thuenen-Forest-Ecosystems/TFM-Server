# For both schemas (lookup + inventory_archive):

- remote-sync_inventory.sh - Dumps inventory_archive (schema + data) from local database and uploads to remote server at 134.110.100.75:3389
  For lookup schema only:

- remote-reset_lookup.sh - Dumps lookup (schema + data) from local database and uploads to remote server at 134.110.100.75:3389

Both scripts:

1. Dump from local Supabase container to tmp files
2. Drop existing tables on remote server
3. Upload schema structure
4. Upload data
