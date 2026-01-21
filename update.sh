#!/bin/bash
# Auto-update script for News Aggregator API

set -e

echo "Starting auto-update process..."
echo "Date: $(date)"

APP_DIR="/var/www/news-aggregator-api"
cd "$APP_DIR"

# Backup current state
echo "Backing up current state..."
if [ -f "news.db" ]; then
    cp news.db "news.db.backup.$(date +%Y%m%d_%H%M%S)"
fi

# Pull latest changes from GitHub
echo "Pulling latest changes from GitHub..."
git fetch origin
git reset --hard origin/main

# Update dependencies
echo "Updating dependencies..."
source venv/bin/activate
pip install --upgrade pip
pip install -r requirements.txt

# Run any database migrations
echo "Running database migrations..."
if [ -f "alembic.ini" ]; then
    alembic upgrade head
fi

# Clear cache
echo "Clearing cache..."
rm -rf storage/cache/*

# Restart services
echo "Restarting services..."
systemctl restart news-api
systemctl restart news-worker

echo "Update completed successfully!"
echo "Time: $(date)"
