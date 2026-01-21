#!/bin/bash

# News Aggregator API Deployment Script
set -e

echo "Starting deployment..."

# Variables
APP_NAME="news-aggregator-api"
APP_DIR="/var/www/$APP_NAME"
VENV_DIR="$APP_DIR/venv"
USER="www-data"
GITHUB_REPO="https://github.com/yourusername/news-aggregator-api.git"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1"
    exit 1
}

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    error "Please run as root"
fi

# Create directory if it doesn't exist
if [ ! -d "$APP_DIR" ]; then
    log "Creating application directory..."
    mkdir -p "$APP_DIR"
fi

cd "$APP_DIR"

# Clone or pull repository
if [ ! -d ".git" ]; then
    log "Cloning repository..."
    git clone "$GITHUB_REPO" .
else
    log "Pulling latest changes..."
    git pull origin main
fi

# Create virtual environment if it doesn't exist
if [ ! -d "$VENV_DIR" ]; then
    log "Creating virtual environment..."
    python3.11 -m venv "$VENV_DIR"
fi

# Activate virtual environment and install dependencies
log "Installing dependencies..."
source "$VENV_DIR/bin/activate"
pip install --upgrade pip
pip install -r requirements.txt

# Set permissions
log "Setting permissions..."
chown -R $USER:$USER "$APP_DIR"
chmod -R 755 "$APP_DIR"
chmod +x "$APP_DIR/deploy.sh"
chmod +x "$APP_DIR/update.sh"

# Create systemd service file
log "Creating systemd service..."
cat > /etc/systemd/system/news-api.service << EOF
[Unit]
Description=News Aggregator API
After=network.target redis.service

[Service]
Type=exec
User=$USER
Group=$USER
WorkingDirectory=$APP_DIR
Environment="PATH=$VENV_DIR/bin"
ExecStart=$VENV_DIR/bin/uvicorn src.main:app --host 0.0.0.0 --port 8000
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# Create systemd service for Celery worker
cat > /etc/systemd/system/news-worker.service << EOF
[Unit]
Description=News Aggregator Celery Worker
After=network.target redis.service

[Service]
Type=exec
User=$USER
Group=$USER
WorkingDirectory=$APP_DIR
Environment="PATH=$VENV_DIR/bin"
ExecStart=$VENV_DIR/bin/celery -A src.tasks.worker.celery_app worker --loglevel=info
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd and enable services
systemctl daemon-reload
systemctl enable news-api news-worker redis

# Start services
log "Starting services..."
systemctl restart redis
systemctl restart news-api
systemctl restart news-worker

# Configure Nginx
log "Configuring Nginx..."
if [ -f "$APP_DIR/nginx/news-api.conf" ]; then
    cp "$APP_DIR/nginx/news-api.conf" /etc/nginx/sites-available/news-api
    ln -sf /etc/nginx/sites-available/news-api /etc/nginx/sites-enabled/
    nginx -t
    systemctl restart nginx
fi

# Set up log rotation
log "Setting up log rotation..."
cat > /etc/logrotate.d/news-api << EOF
$APP_DIR/logs/*.log {
    daily
    missingok
    rotate 14
    compress
    delaycompress
    notifempty
    create 640 $USER $USER
    sharedscripts
    postrotate
        systemctl reload news-api > /dev/null 2>&1 || true
    endscript
}
EOF

# Create SSL certificate if not exists
if [ ! -f "/etc/letsencrypt/live/news.devmaxwell.site/fullchain.pem" ]; then
    log "Setting up SSL certificate..."
    certbot certonly --nginx -d news.devmaxwell.site --non-interactive --agree-tos --email admin@devmaxwell.site
fi

# Create update webhook endpoint
log "Setting up update webhook..."
cat > "$APP_DIR/update_webhook.py" << 'EOF'
from http.server import HTTPServer, BaseHTTPRequestHandler
import json
import subprocess
import hmac
import hashlib

WEBHOOK_SECRET = "your-update-secret-here"

class UpdateHandler(BaseHTTPRequestHandler):
    def do_POST(self):
        if self.path == '/webhook/update':
            content_length = int(self.headers['Content-Length'])
            post_data = self.rfile.read(content_length)
            
            # Verify signature
            signature = self.headers.get('X-Hub-Signature-256', '').replace('sha256=', '')
            expected = hmac.new(WEBHOOK_SECRET.encode(), post_data, hashlib.sha256).hexdigest()
            
            if not hmac.compare_digest(signature, expected):
                self.send_response(403)
                self.end_headers()
                return
            
            # Execute update
            try:
                result = subprocess.run(['/var/www/news-aggregator-api/update.sh'], 
                                      capture_output=True, text=True, timeout=300)
                
                self.send_response(200)
                self.send_header('Content-type', 'application/json')
                self.end_headers()
                response = {
                    'success': result.returncode == 0,
                    'output': result.stdout,
                    'error': result.stderr
                }
                self.wfile.write(json.dumps(response).encode())
            except Exception as e:
                self.send_response(500)
                self.end_headers()
                self.wfile.write(str(e).encode())
        else:
            self.send_response(404)
            self.end_headers()
    
    def log_message(self, format, *args):
        pass  # Disable default logging

if __name__ == '__main__':
    server = HTTPServer(('localhost', 9000), UpdateHandler)
    print('Update webhook server running on port 9000...')
    server.serve_forever()
EOF

# Create update script
cat > "$APP_DIR/update.sh" << 'EOF'
#!/bin/bash
# Auto-update script triggered by GitHub webhook

cd /var/www/news-aggregator-api

# Pull latest changes
git pull origin main

# Install dependencies
source venv/bin/activate
pip install -r requirements.txt

# Run database migrations if any
# alembic upgrade head

# Restart services
systemctl restart news-api
systemctl restart news-worker

echo "Update completed at $(date)"
EOF

chmod +x "$APP_DIR/update.sh"

log "Deployment completed successfully!"
log "API will be available at: https://news.devmaxwell.site"
log "API Key: MAX_Nwstdy21onetwditwdi6"
log "Use header: X-API-Key: MAX_Nwstdy21onetwditwdi6"

# Display status
echo ""
systemctl status news-api --no-pager
echo ""
systemctl status news-worker --no-pager
