# Create deploy.sh on your server
#!/bin/bash
cd volumes/functions
git pull origin main
docker compose restart functions
echo "Deployment completed at $(date)"