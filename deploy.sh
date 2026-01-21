#!/bin/bash

# News Aggregator API - Interactive Deployment Script
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color
BOLD='\033[1m'
UNDERLINE='\033[4m'

# Text formatting functions
header() {
    echo -e "${MAGENTA}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${MAGENTA}║${NC} ${BOLD}News Aggregator API - Deployment Script${NC} ${MAGENTA}║${NC}"
    echo -e "${MAGENTA}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

log() {
    echo -e "${GREEN}✓${NC} ${GREEN}[$(date +'%H:%M:%S')]${NC} $1"
}

warn() {
    echo -e "${YELLOW}⚠${NC} ${YELLOW}[$(date +'%H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}✗${NC} ${RED}[$(date +'%H:%M:%S')] ERROR:${NC} $1"
    exit 1
}

info() {
    echo -e "${BLUE}ℹ${NC} ${BLUE}[$(date +'%H:%M:%S')]${NC} $1"
}

prompt() {
    echo -e "${CYAN}?${NC} ${CYAN}[$(date +'%H:%M:%S')]${NC} $1"
}

success() {
    echo -e "${GREEN}🎉${NC} ${GREEN}[$(date +'%H:%M:%S')]${NC} ${BOLD}$1${NC}"
}

# Check if running as root
check_root() {
    if [ "$EUID" -ne 0 ]; then 
        error "Please run as root: ${BOLD}sudo ./deploy.sh${NC}"
    fi
}

# Detect VPS IP address
detect_ip() {
    info "Detecting VPS IP address..."
    local public_ip=$(curl -s --max-time 5 https://api.ipify.org 2>/dev/null || echo "156.251.65.243")
    local private_ip=$(hostname -I | awk '{print $1}')
    
    echo -e "${CYAN}Detected IP Addresses:${NC}"
    echo -e "  ${BOLD}Public IP:${NC}  $public_ip"
    echo -e "  ${BOLD}Private IP:${NC} $private_ip"
    echo ""
    
    VPS_PUBLIC_IP="$public_ip"
    VPS_PRIVATE_IP="$private_ip"
}

# Check for existing SSL certificates
check_ssl() {
    info "Checking for existing SSL certificates..."
    
    local cert_paths=(
        "/etc/letsencrypt/live/"
        "/etc/ssl/certs/"
        "/etc/nginx/ssl/"
    )
    
    local domains=()
    
    for path in "${cert_paths[@]}"; do
        if [ -d "$path" ]; then
            for dir in "$path"*/; do
                if [ -f "${dir}fullchain.pem" ] && [ -f "${dir}privkey.pem" ]; then
                    local domain=$(basename "$dir")
                    domains+=("$domain")
                    log "Found SSL certificate for: ${BOLD}$domain${NC}"
                fi
            done
        fi
    done
    
    if [ ${#domains[@]} -eq 0 ]; then
        warn "No SSL certificates found"
        return 1
    fi
    
    echo ""
    echo -e "${CYAN}Available SSL Certificates:${NC}"
    for i in "${!domains[@]}"; do
        echo -e "  ${BOLD}$((i+1)).${NC} ${domains[$i]}"
    done
    
    echo ""
    prompt "Select a certificate number or press Enter to use your own domain: "
    read -r selection
    
    if [[ -n "$selection" && "$selection" =~ ^[0-9]+$ ]] && [ "$selection" -le ${#domains[@]} ]; then
        SELECTED_DOMAIN="${domains[$((selection-1))]}"
        log "Selected domain: ${BOLD}$SELECTED_DOMAIN${NC}"
        return 0
    fi
    
    return 1
}

# Prompt for domain name
get_domain() {
    echo ""
    echo -e "${YELLOW}────────────────────────────────────────────────────────────${NC}"
    echo -e "${CYAN}Domain Configuration${NC}"
    echo -e "${YELLOW}────────────────────────────────────────────────────────────${NC}"
    
    if [ -n "$SELECTED_DOMAIN" ]; then
        DOMAIN="$SELECTED_DOMAIN"
        info "Using existing SSL certificate for: ${BOLD}$DOMAIN${NC}"
        return
    fi
    
    echo ""
    echo -e "Your VPS IP address is: ${BOLD}$VPS_PUBLIC_IP${NC}"
    echo ""
    warn "For SSL certificates, you need a domain name pointing to this IP."
    echo ""
    info "Options:"
    echo -e "  1. ${BOLD}Use IP address${NC} (no SSL, HTTP only)"
    echo -e "  2. ${BOLD}Enter domain name${NC} (with SSL setup)"
    echo -e "  3. ${BOLD}Skip SSL for now${NC} (setup later)"
    echo ""
    
    while true; do
        prompt "Enter your choice (1-3): "
        read -r choice
        
        case $choice in
            1)
                DOMAIN="$VPS_PUBLIC_IP"
                warn "Using IP address: ${BOLD}$DOMAIN${NC} (No SSL)"
                echo -e "  API will be available at: ${YELLOW}http://$DOMAIN${NC}"
                NO_SSL=true
                break
                ;;
            2)
                prompt "Enter your domain name (e.g., news.devmaxwell.site): "
                read -r DOMAIN
                
                if [[ -z "$DOMAIN" ]]; then
                    warn "Domain cannot be empty"
                    continue
                fi
                
                log "Using domain: ${BOLD}$DOMAIN${NC}"
                
                # Ask about SSL setup
                echo ""
                prompt "Do you want to setup SSL certificate now? (y/N): "
                read -r setup_ssl
                
                if [[ "$setup_ssl" =~ ^[Yy]$ ]]; then
                    SETUP_SSL=true
                else
                    warn "SSL setup skipped. You can setup SSL later with:"
                    echo -e "  ${BOLD}certbot --nginx -d $DOMAIN${NC}"
                fi
                break
                ;;
            3)
                DOMAIN="$VPS_PUBLIC_IP"
                warn "SSL setup skipped. Using IP: ${BOLD}$DOMAIN${NC}"
                echo -e "  You can setup SSL later with certbot"
                NO_SSL=true
                break
                ;;
            *)
                warn "Invalid choice. Please enter 1, 2, or 3"
                ;;
        esac
    done
}

# Install system dependencies
install_dependencies() {
    info "Installing system dependencies..."
    
    apt update 2>/dev/null | grep -v "Reading package lists"
    apt install -y \
        python3.11 \
        python3.11-venv \
        python3.11-dev \
        python3-pip \
        git \
        nginx \
        redis-server \
        sqlite3 \
        libssl-dev \
        libffi-dev \
        libxml2-dev \
        libxslt1-dev \
        libjpeg-dev \
        libpng-dev \
        zlib1g-dev 2>/dev/null | grep -v "Reading package lists"
    
    log "System dependencies installed"
}

# Setup SSL certificate
setup_ssl_certificate() {
    if [ "$NO_SSL" = true ] || [ "$SETUP_SSL" != true ]; then
        return
    fi
    
    info "Setting up SSL certificate for: ${BOLD}$DOMAIN${NC}"
    
    # Check if certbot is installed
    if ! command -v certbot &> /dev/null; then
        log "Installing certbot..."
        apt install -y certbot python3-certbot-nginx 2>/dev/null | grep -v "Reading package lists"
    fi
    
    # Stop nginx temporarily for standalone verification
    systemctl stop nginx
    
    echo ""
    prompt "Enter email for SSL certificate notifications: "
    read -r ssl_email
    
    if [[ -z "$ssl_email" ]]; then
        ssl_email="admin@$DOMAIN"
        warn "Using default email: ${BOLD}$ssl_email${NC}"
    fi
    
    log "Obtaining SSL certificate..."
    
    if certbot certonly --standalone -d "$DOMAIN" \
        --non-interactive \
        --agree-tos \
        --email "$ssl_email" \
        --preferred-challenges http \
        --http-01-port 8080; then
        log "SSL certificate obtained successfully"
        SSL_CERT_PATH="/etc/letsencrypt/live/$DOMAIN"
    else
        warn "Failed to obtain SSL certificate automatically"
        echo ""
        info "You can manually setup SSL later with:"
        echo -e "  ${BOLD}1.${NC} Make sure DNS points to: ${BOLD}$VPS_PUBLIC_IP${NC}"
        echo -e "  ${BOLD}2.${NC} Run: ${BOLD}certbot --nginx -d $DOMAIN${NC}"
        echo -e "  ${BOLD}3.${NC} Or: ${BOLD}certbot certonly --standalone -d $DOMAIN${NC}"
        NO_SSL=true
    fi
    
    # Restart nginx
    systemctl start nginx
}

# Clone or update repository
setup_repository() {
    info "Setting up application repository..."
    
    if [ ! -d "$APP_DIR" ]; then
        log "Creating application directory..."
        mkdir -p "$APP_DIR"
    fi
    
    cd "$APP_DIR"
    
    if [ ! -d ".git" ]; then
        log "Cloning repository from GitHub..."
        git clone "$GITHUB_REPO" . 2>&1 | while read line; do
            echo -ne "${BLUE}${line}${NC}\r"
        done
        echo ""
    else
        log "Pulling latest changes..."
        git pull origin main 2>&1 | while read line; do
            echo -ne "${BLUE}${line}${NC}\r"
        done
        echo ""
    fi
}

# Setup Python virtual environment
setup_python_env() {
    info "Setting up Python environment..."
    
    if [ ! -d "$VENV_DIR" ]; then
        log "Creating Python virtual environment..."
        python3.11 -m venv "$VENV_DIR"
    fi
    
    log "Activating virtual environment..."
    source "$VENV_DIR/bin/activate"
    
    log "Upgrading pip..."
    pip install --upgrade pip | grep -v "Requirement already satisfied"
    
    log "Installing Python dependencies..."
    if [ -f "requirements.txt" ]; then
        pip install -r requirements.txt | grep -v "Requirement already satisfied"
        log "Python dependencies installed"
    else
        warn "requirements.txt not found"
        info "Installing basic dependencies..."
        pip install fastapi uvicorn sqlalchemy redis celery feedparser requests | grep -v "Requirement already satisfied"
    fi
}

# Setup application directories
setup_directories() {
    info "Setting up application directories..."
    
    # Create necessary directories
    mkdir -p "$APP_DIR/storage/media/images"
    mkdir -p "$APP_DIR/storage/media/videos"
    mkdir -p "$APP_DIR/storage/cache"
    mkdir -p "$APP_DIR/logs"
    mkdir -p "$APP_DIR/static"
    
    # Set permissions
    chown -R $USER:$USER "$APP_DIR"
    chmod -R 755 "$APP_DIR"
    chmod +x "$APP_DIR/deploy.sh" 2>/dev/null || true
    
    log "Directories created and permissions set"
}

# Create systemd service files
create_systemd_services() {
    info "Creating systemd services..."
    
    # Redis service (if not exists)
    if [ ! -f "/etc/systemd/system/redis-server.service" ]; then
        log "Creating Redis service..."
        cat > /etc/systemd/system/redis-server.service << EOF
[Unit]
Description=Redis In-Memory Data Store
After=network.target

[Service]
Type=exec
User=redis
Group=redis
ExecStart=/usr/bin/redis-server /etc/redis/redis.conf
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
    fi
    
    # News API service
    log "Creating News API service..."
    cat > /etc/systemd/system/news-api.service << EOF
[Unit]
Description=News Aggregator API
After=network.target redis-server.service
Requires=redis-server.service

[Service]
Type=simple
User=$USER
Group=$USER
WorkingDirectory=$APP_DIR
Environment="PATH=$VENV_DIR/bin"
ExecStart=$VENV_DIR/bin/uvicorn src.main:app --host 0.0.0.0 --port 8000 --workers 2
Restart=always
RestartSec=10
StandardOutput=append:$APP_DIR/logs/api.log
StandardError=append:$APP_DIR/logs/api-error.log

[Install]
WantedBy=multi-user.target
EOF
    
    # Celery worker service
    log "Creating Celery worker service..."
    cat > /etc/systemd/system/news-worker.service << EOF
[Unit]
Description=News Aggregator Celery Worker
After=network.target redis-server.service
Requires=redis-server.service

[Service]
Type=simple
User=$USER
Group=$USER
WorkingDirectory=$APP_DIR
Environment="PATH=$VENV_DIR/bin"
ExecStart=$VENV_DIR/bin/celery -A src.tasks.worker.celery_app worker --loglevel=info --concurrency=2
Restart=always
RestartSec=10
StandardOutput=append:$APP_DIR/logs/worker.log
StandardError=append:$APP_DIR/logs/worker-error.log

[Install]
WantedBy=multi-user.target
EOF
    
    # Scheduler service
    log "Creating scheduler service..."
    cat > /etc/systemd/system/news-scheduler.service << EOF
[Unit]
Description=News Aggregator Scheduler
After=network.target redis-server.service
Requires=redis-server.service

[Service]
Type=simple
User=$USER
Group=$USER
WorkingDirectory=$APP_DIR
Environment="PATH=$VENV_DIR/bin"
ExecStart=$VENV_DIR/bin/python -m src.core.scheduler
Restart=always
RestartSec=10
StandardOutput=append:$APP_DIR/logs/scheduler.log
StandardError=append:$APP_DIR/logs/scheduler-error.log

[Install]
WantedBy=multi-user.target
EOF
}

# Configure Nginx
configure_nginx() {
    info "Configuring Nginx..."
    
    # Create nginx config directory if not exists
    mkdir -p /etc/nginx/sites-available
    mkdir -p /etc/nginx/sites-enabled
    
    if [ "$NO_SSL" = true ]; then
        # HTTP only configuration
        log "Creating HTTP-only Nginx configuration..."
        cat > /etc/nginx/sites-available/news-api << EOF
server {
    listen 80;
    server_name $DOMAIN;
    
    # Security headers
    add_header X-Frame-Options DENY;
    add_header X-Content-Type-Options nosniff;
    add_header X-XSS-Protection "1; mode=block";
    
    # API proxy
    location /api/ {
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }
    
    # Static files
    location /static/ {
        alias $APP_DIR/static/;
        expires 30d;
        add_header Cache-Control "public, immutable";
    }
    
    # Media files
    location /media/ {
        alias $APP_DIR/storage/media/;
        expires 7d;
        add_header Cache-Control "public";
    }
    
    # Health check
    location /health {
        proxy_pass http://127.0.0.1:8000/health;
        access_log off;
    }
    
    # Root redirect to API docs
    location / {
        return 302 /api/v1/;
    }
}
EOF
    else
        # HTTPS configuration
        log "Creating HTTPS Nginx configuration..."
        
        if [ -d "/etc/letsencrypt/live/$DOMAIN" ]; then
            SSL_CERT_PATH="/etc/letsencrypt/live/$DOMAIN"
        else
            SSL_CERT_PATH="/etc/ssl/certs"
        fi
        
        cat > /etc/nginx/sites-available/news-api << EOF
# HTTP redirect to HTTPS
server {
    listen 80;
    server_name $DOMAIN;
    return 301 https://\$server_name\$request_uri;
}

# HTTPS server
server {
    listen 443 ssl http2;
    server_name $DOMAIN;

    ssl_certificate $SSL_CERT_PATH/fullchain.pem;
    ssl_certificate_key $SSL_CERT_PATH/privkey.pem;
    
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-RSA-AES256-GCM-SHA512:DHE-RSA-AES256-GCM-SHA512;
    ssl_prefer_server_ciphers off;

    # Security headers
    add_header X-Frame-Options DENY;
    add_header X-Content-Type-Options nosniff;
    add_header X-XSS-Protection "1; mode=block";
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;

    # API proxy
    location /api/ {
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }

    # Static files
    location /static/ {
        alias $APP_DIR/static/;
        expires 30d;
        add_header Cache-Control "public, immutable";
    }

    # Media files
    location /media/ {
        alias $APP_DIR/storage/media/;
        expires 7d;
        add_header Cache-Control "public";
    }

    # Health check
    location /health {
        proxy_pass http://127.0.0.1:8000/health;
        access_log off;
    }
    
    # Root redirect to API docs
    location / {
        return 302 /api/v1/;
    }
}
EOF
    fi
    
    # Enable site
    ln -sf /etc/nginx/sites-available/news-api /etc/nginx/sites-enabled/
    
    # Remove default nginx site
    rm -f /etc/nginx/sites-enabled/default 2>/dev/null || true
    
    # Test nginx configuration
    log "Testing Nginx configuration..."
    if nginx -t; then
        log "Nginx configuration test passed"
    else
        error "Nginx configuration test failed"
    fi
}

# Setup log rotation
setup_log_rotation() {
    info "Setting up log rotation..."
    
    cat > /etc/logrotate.d/news-api << EOF
$APP_DIR/logs/*.log {
    daily
    missingok
    rotate 30
    compress
    delaycompress
    notifempty
    create 640 $USER $USER
    sharedscripts
    postrotate
        systemctl reload news-api > /dev/null 2>&1 || true
        systemctl reload news-worker > /dev/null 2>&1 || true
    endscript
}
EOF
    
    log "Log rotation configured"
}

# Create update script
create_update_script() {
    info "Creating update script..."
    
    cat > "$APP_DIR/update.sh" << EOF
#!/bin/bash

# News Aggregator API Update Script

set -e

echo ""
echo "╔══════════════════════════════════════════════╗"
echo "║      News Aggregator API - Update           ║"
echo "╚══════════════════════════════════════════════╝"
echo ""

cd $APP_DIR

echo "📥 Pulling latest changes from GitHub..."
if git pull origin main; then
    echo "✓ Repository updated"
else
    echo "✗ Failed to pull changes"
    exit 1
fi

echo ""
echo "🐍 Updating Python dependencies..."
source $VENV_DIR/bin/activate
if pip install -r requirements.txt; then
    echo "✓ Dependencies updated"
else
    echo "✗ Failed to install dependencies"
    exit 1
fi

echo ""
echo "🔄 Restarting services..."
systemctl restart news-api
systemctl restart news-worker
systemctl restart news-scheduler

echo ""
echo "✅ Update completed successfully!"
echo "   Time: \$(date)"
echo ""
EOF
    
    chmod +x "$APP_DIR/update.sh"
    log "Update script created: $APP_DIR/update.sh"
}

# Create environment file
create_env_file() {
    info "Creating environment configuration..."
    
    local api_key="MAX_Nwstdy21onetwditwdi6"
    
    cat > "$APP_DIR/.env" << EOF
# API Configuration
API_KEY=$api_key
API_KEY_NAME=X-API-Key
SECRET_KEY=$(openssl rand -hex 32)
DEBUG=False

# Database
DATABASE_URL=sqlite:///$APP_DIR/news.db

# Redis
REDIS_URL=redis://localhost:6379/0

# AI Configuration
OPENAI_API_KEY=your-openai-api-key-here
OPENAI_MODEL=gpt-3.5-turbo-1106
AI_SUMMARIZE=True

# Storage Paths
MEDIA_STORAGE_PATH=$APP_DIR/storage/media
CACHE_PATH=$APP_DIR/storage/cache

# Server
HOST=0.0.0.0
PORT=8000
DOMAIN=https://$DOMAIN

# Settings
FETCH_DELAY=1.0
MAX_CONCURRENT_FETCHES=5
EOF
    
    chown $USER:$USER "$APP_DIR/.env"
    chmod 600 "$APP_DIR/.env"
    
    log "Environment file created"
}

# Start and enable services
start_services() {
    info "Starting and enabling services..."
    
    systemctl daemon-reload
    
    # Enable services to start on boot
    systemctl enable redis-server
    systemctl enable news-api
    systemctl enable news-worker
    systemctl enable news-scheduler
    
    # Start services
    log "Starting Redis..."
    systemctl restart redis-server
    
    log "Starting News API..."
    systemctl restart news-api
    
    log "Starting Celery worker..."
    systemctl restart news-worker
    
    log "Starting scheduler..."
    systemctl restart news-scheduler
    
    log "Starting Nginx..."
    systemctl restart nginx
    
    # Wait a moment for services to start
    sleep 3
}

# Display final information
display_final_info() {
    echo ""
    success "Deployment completed successfully!"
    echo ""
    echo -e "${YELLOW}════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}📡 API Endpoints:${NC}"
    echo -e "${YELLOW}════════════════════════════════════════════════════════════${NC}"
    
    if [ "$NO_SSL" = true ]; then
        echo -e "  ${BOLD}API URL:${NC}      http://$DOMAIN/api/v1/"
        echo -e "  ${BOLD}Health Check:${NC}  http://$DOMAIN/health"
    else
        echo -e "  ${BOLD}API URL:${NC}      https://$DOMAIN/api/v1/"
        echo -e "  ${BOLD}Health Check:${NC}  https://$DOMAIN/health"
    fi
    
    echo ""
    echo -e "${YELLOW}🔑 Authentication:${NC}"
    echo -e "${YELLOW}════════════════════════════════════════════════════════════${NC}"
    echo -e "  ${BOLD}API Key:${NC}        $API_KEY"
    echo -e "  ${BOLD}Header:${NC}         X-API-Key: $API_KEY"
    echo ""
    
    echo -e "${YELLOW}📊 Services Status:${NC}"
    echo -e "${YELLOW}════════════════════════════════════════════════════════════${NC}"
    
    for service in redis-server news-api news-worker news-scheduler nginx; do
        if systemctl is-active --quiet "$service"; then
            echo -e "  ${GREEN}✓${NC} $service is ${GREEN}running${NC}"
        else
            echo -e "  ${RED}✗${NC} $service is ${RED}not running${NC}"
        fi
    done
    
    echo ""
    echo -e "${YELLOW}🛠️  Management Commands:${NC}"
    echo -e "${YELLOW}════════════════════════════════════════════════════════════${NC}"
    echo -e "  ${BOLD}Check logs:${NC}       journalctl -u news-api -f"
    echo -e "  ${BOLD}Update API:${NC}       $APP_DIR/update.sh"
    echo -e "  ${BOLD}Restart all:${NC}      systemctl restart news-api news-worker news-scheduler"
    echo -e "  ${BOLD}View status:${NC}      systemctl status news-api"
    
    echo ""
    echo -e "${YELLOW}📁 Important Paths:${NC}"
    echo -e "${YELLOW}════════════════════════════════════════════════════════════${NC}"
    echo -e "  ${BOLD}App Directory:${NC}    $APP_DIR"
    echo -e "  ${BOLD}Logs:${NC}             $APP_DIR/logs/"
    echo -e "  ${BOLD}Database:${NC}         $APP_DIR/news.db"
    echo -e "  ${BOLD}Media Storage:${NC}    $APP_DIR/storage/media/"
    
    echo ""
    echo -e "${YELLOW}🚀 Quick Test:${NC}"
    echo -e "${YELLOW}════════════════════════════════════════════════════════════${NC}"
    
    if [ "$NO_SSL" = true ]; then
        echo -e "  ${BOLD}Test API:${NC} curl -H 'X-API-Key: $API_KEY' http://$DOMAIN/api/v1/system/status"
    else
        echo -e "  ${BOLD}Test API:${NC} curl -H 'X-API-Key: $API_KEY' https://$DOMAIN/api/v1/system/status"
    fi
    
    echo ""
    echo -e "${GREEN}✅ Setup complete! Your News Aggregator API is ready to use.${NC}"
    echo ""
}

# Main deployment function
main() {
    clear
    header
    
    # Variables
    APP_NAME="news-aggregator-api"
    APP_DIR="/var/www/$APP_NAME"
    VENV_DIR="$APP_DIR/venv"
    USER="www-data"
    GITHUB_REPO="https://github.com/maxieyy/news-aggregator-api.git"
    API_KEY="MAX_Nwstdy21onetwditwdi6"
    
    # Initialize variables
    VPS_PUBLIC_IP=""
    VPS_PRIVATE_IP=""
    SELECTED_DOMAIN=""
    DOMAIN=""
    NO_SSL=false
    SETUP_SSL=false
    SSL_CERT_PATH=""
    
    # Check root privileges
    check_root
    
    # Detect IP addresses
    detect_ip
    
    # Check for existing SSL certificates
    check_ssl
    
    # Get domain configuration
    get_domain
    
    # Installation steps
    echo ""
    info "Starting installation process..."
    echo ""
    
    # Step 1: Install dependencies
    echo -e "${CYAN}[1/9]${NC} Installing system dependencies..."
    install_dependencies
    
    # Step 2: Setup SSL
    echo -e "${CYAN}[2/9]${NC} Configuring SSL..."
    setup_ssl_certificate
    
    # Step 3: Clone repository
    echo -e "${CYAN}[3/9]${NC} Setting up repository..."
    setup_repository
    
    # Step 4: Setup Python environment
    echo -e "${CYAN}[4/9]${NC} Setting up Python environment..."
    setup_python_env
    
    # Step 5: Create directories
    echo -e "${CYAN}[5/9]${NC} Creating directories..."
    setup_directories
    
    # Step 6: Create environment file
    echo -e "${CYAN}[6/9]${NC} Creating configuration..."
    create_env_file
    
    # Step 7: Create systemd services
    echo -e "${CYAN}[7/9]${NC} Creating services..."
    create_systemd_services
    
    # Step 8: Configure Nginx
    echo -e "${CYAN}[8/9]${NC} Configuring Nginx..."
    configure_nginx
    
    # Step 9: Setup log rotation
    echo -e "${CYAN}[9/9]${NC} Finalizing setup..."
    setup_log_rotation
    
    # Create update script
    create_update_script
    
    # Start services
    start_services
    
    # Display final information
    display_final_info
}

# Run main function
main
