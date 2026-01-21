#!/bin/bash

# News Aggregator API - Production Deployment Script
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
    clear
    echo -e "${MAGENTA}╔══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${MAGENTA}║${NC} ${BOLD}NEWS AGGREGATOR API - PRODUCTION DEPLOYMENT${NC} ${MAGENTA}               ║${NC}"
    echo -e "${MAGENTA}╚══════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

log() {
    echo -e "${GREEN}[✓]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[!]${NC} $1"
}

error() {
    echo -e "${RED}[✗] ERROR:${NC} $1"
    exit 1
}

info() {
    echo -e "${BLUE}[i]${NC} $1"
}

prompt() {
    echo -e "${CYAN}[?]${NC} $1"
}

success() {
    echo -e "${GREEN}[✓] SUCCESS:${NC} ${BOLD}$1${NC}"
}

step() {
    echo ""
    echo -e "${YELLOW}▸${NC} ${BOLD}$1${NC}"
}

# Check if running as root
check_root() {
    if [ "$EUID" -ne 0 ]; then 
        error "Please run as root: ${BOLD}sudo ./deploy.sh${NC}"
    fi
}

# Detect system information
detect_system() {
    info "Detecting system information..."
    
    # Get VPS IP
    VPS_PUBLIC_IP=$(curl -s --max-time 5 https://api.ipify.org 2>/dev/null || echo "156.251.65.243")
    VPS_PRIVATE_IP=$(hostname -I | awk '{print $1}')
    
    # Get OS info
    OS_NAME=$(lsb_release -si 2>/dev/null || echo "Debian")
    OS_VERSION=$(lsb_release -sr 2>/dev/null || echo "12")
    
    echo -e "${CYAN}System Information:${NC}"
    echo -e "  ${BOLD}OS:${NC}          $OS_NAME $OS_VERSION"
    echo -e "  ${BOLD}Public IP:${NC}   $VPS_PUBLIC_IP"
    echo -e "  ${BOLD}Private IP:${NC}  $VPS_PRIVATE_IP"
    echo -e "  ${BOLD}Hostname:${NC}    $(hostname)"
    echo ""
}

# Check for existing services
check_existing_services() {
    info "Checking for existing services..."
    
    local conflicts=()
    
    # Check for existing web servers
    if systemctl is-active --quiet apache2; then
        conflicts+=("Apache2")
    fi
    
    if systemctl is-active --quiet nginx; then
        conflicts+=("Nginx")
    fi
    
    # Check port conflicts
    if netstat -tulpn | grep -q ":80 "; then
        conflicts+=("Port 80 (HTTP) in use")
    fi
    
    if netstat -tulpn | grep -q ":443 "; then
        conflicts+=("Port 443 (HTTPS) in use")
    fi
    
    if netstat -tulpn | grep -q ":8000 "; then
        conflicts+=("Port 8000 (API) in use")
    fi
    
    if [ ${#conflicts[@]} -gt 0 ]; then
        warn "Potential conflicts detected:"
        for conflict in "${conflicts[@]}"; do
            echo -e "  ${YELLOW}•${NC} $conflict"
        done
        echo ""
        prompt "Do you want to continue anyway? (y/N): "
        read -r continue_anyway
        if [[ ! "$continue_anyway" =~ ^[Yy]$ ]]; then
            error "Deployment cancelled due to conflicts"
        fi
    fi
}

# Get user configuration
get_configuration() {
    echo -e "${CYAN}════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}Configuration Setup${NC}"
    echo -e "${CYAN}════════════════════════════════════════════════════════════${NC}"
    echo ""
    
    # Domain configuration
    while true; do
        prompt "Enter your domain name (e.g., news.devmaxwell.site): "
        read -r DOMAIN
        
        if [[ -z "$DOMAIN" ]]; then
            warn "Domain name cannot be empty"
            continue
        fi
        
        if [[ "$DOMAIN" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            warn "IP address detected. For SSL certificates, you need a domain name."
            prompt "Continue with IP address? (y/N): "
            read -r use_ip
            if [[ "$use_ip" =~ ^[Yy]$ ]]; then
                NO_SSL=true
                break
            fi
            continue
        fi
        
        # Validate domain format
        if [[ "$DOMAIN" =~ ^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z]{2,})+$ ]]; then
            break
        else
            warn "Invalid domain format. Please enter a valid domain name."
        fi
    done
    
    echo ""
    
    # SSL configuration
    if [ "$NO_SSL" != true ]; then
        info "SSL Certificate Setup"
        echo -e "  You need a domain name pointing to: ${BOLD}$VPS_PUBLIC_IP${NC}"
        echo ""
        warn "Before proceeding, ensure:"
        echo -e "  1. DNS record for ${BOLD}$DOMAIN${NC} points to ${BOLD}$VPS_PUBLIC_IP${NC}"
        echo -e "  2. Ports 80 and 443 are open in firewall"
        echo ""
        
        prompt "Do you want to setup SSL certificate now? (Y/n): "
        read -r setup_ssl
        setup_ssl=${setup_ssl:-Y}
        
        if [[ "$setup_ssl" =~ ^[Yy]$ ]]; then
            SETUP_SSL=true
            
            # Get email for SSL
            while true; do
                prompt "Enter email for SSL certificate (required by Let's Encrypt): "
                read -r SSL_EMAIL
                
                if [[ -z "$SSL_EMAIL" ]]; then
                    warn "Email is required for SSL certificate"
                    continue
                fi
                
                if [[ "$SSL_EMAIL" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
                    break
                else
                    warn "Invalid email format"
                fi
            done
        else
            warn "SSL setup skipped. API will run on HTTP only."
            NO_SSL=true
        fi
    fi
    
    # API Key
    echo ""
    info "API Security Configuration"
    API_KEY="MAX_Nwstdy21onetwditwdi6"
    echo -e "  ${BOLD}Default API Key:${NC} $API_KEY"
    
    prompt "Do you want to generate a new API key? (y/N): "
    read -r new_key
    if [[ "$new_key" =~ ^[Yy]$ ]]; then
        API_KEY=$(openssl rand -hex 24)
        echo -e "  ${BOLD}New API Key:${NC} $API_KEY"
    fi
    
    # OpenAI API Key
    echo ""
    prompt "Do you have an OpenAI API key for AI summarization? (y/N): "
    read -r has_openai
    if [[ "$has_openai" =~ ^[Yy]$ ]]; then
        prompt "Enter your OpenAI API key: "
        read -r OPENAI_API_KEY
    else
        OPENAI_API_KEY="your-openai-api-key-here"
        warn "AI summarization will be disabled until you add an OpenAI API key"
    fi
    
    # Confirm configuration
    echo ""
    echo -e "${CYAN}════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}Configuration Summary${NC}"
    echo -e "${CYAN}════════════════════════════════════════════════════════════${NC}"
    echo -e "  ${BOLD}Domain:${NC}        $DOMAIN"
    echo -e "  ${BOLD}SSL:${NC}           $(if [ "$NO_SSL" = true ]; then echo "Disabled (HTTP)"; else echo "Enabled (HTTPS)"; fi)"
    if [ "$SETUP_SSL" = true ]; then
        echo -e "  ${BOLD}SSL Email:${NC}     $SSL_EMAIL"
    fi
    echo -e "  ${BOLD}API Key:${NC}       $API_KEY"
    echo -e "  ${BOLD}OpenAI Key:${NC}    $(if [ "$OPENAI_API_KEY" = "your-openai-api-key-here" ]; then echo "Not configured"; else echo "Configured"; fi)"
    echo ""
    
    prompt "Continue with this configuration? (Y/n): "
    read -r confirm
    confirm=${confirm:-Y}
    
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        error "Deployment cancelled by user"
    fi
}

# Install system dependencies
install_dependencies() {
    step "Installing System Dependencies"
    
    info "Updating package lists..."
    apt-get update -q 2>/dev/null
    
    info "Installing core dependencies..."
    apt-get install -y -q \
        software-properties-common \
        curl \
        wget \
        gnupg \
        ca-certificates \
        lsb-release \
        apt-transport-https 2>/dev/null
    
    # Add Python repository for Python 3.11
    if ! apt-cache policy python3.11 | grep -q "Installed"; then
        info "Adding Python 3.11 repository..."
        add-apt-repository -y ppa:deadsnakes/ppa 2>/dev/null
        apt-get update -q 2>/dev/null
    fi
    
    info "Installing Python and tools..."
    apt-get install -y -q \
        python3.11 \
        python3.11-venv \
        python3.11-dev \
        python3-pip \
        python3.11-distutils 2>/dev/null
    
    info "Installing web server and database..."
    apt-get install -y -q \
        nginx \
        redis-server \
        sqlite3 \
        supervisor 2>/dev/null
    
    info "Installing development libraries..."
    apt-get install -y -q \
        build-essential \
        libssl-dev \
        libffi-dev \
        libxml2-dev \
        libxslt1-dev \
        libjpeg-dev \
        libpng-dev \
        zlib1g-dev 2>/dev/null
    
    info "Installing Git..."
    apt-get install -y -q git 2>/dev/null
    
    log "System dependencies installed successfully"
}

# Setup SSL certificate
setup_ssl() {
    if [ "$SETUP_SSL" != true ]; then
        return
    fi
    
    step "Setting up SSL Certificate"
    
    info "Installing Certbot..."
    apt-get install -y -q certbot python3-certbot-nginx 2>/dev/null
    
    info "Checking DNS resolution..."
    local dns_check=$(dig +short "$DOMAIN" | head -1)
    if [[ -z "$dns_check" ]]; then
        warn "DNS resolution failed for $DOMAIN"
        warn "Please ensure DNS is properly configured before continuing"
        prompt "Continue anyway? (y/N): "
        read -r continue_ssl
        if [[ ! "$continue_ssl" =~ ^[Yy]$ ]]; then
            NO_SSL=true
            return
        fi
    else
        log "DNS resolved to: $dns_check"
    fi
    
    info "Stopping Nginx for certificate verification..."
    systemctl stop nginx 2>/dev/null || true
    
    info "Obtaining SSL certificate..."
    echo ""
    echo -e "${YELLOW}Certbot will now obtain your SSL certificate...${NC}"
    echo ""
    
    if certbot certonly --standalone \
        -d "$DOMAIN" \
        --non-interactive \
        --agree-tos \
        --email "$SSL_EMAIL" \
        --preferred-challenges http \
        --http-01-port 8080; then
        success "SSL certificate obtained successfully"
        SSL_CERT_PATH="/etc/letsencrypt/live/$DOMAIN"
    else
        warn "Failed to obtain SSL certificate automatically"
        echo ""
        info "You can try manually:"
        echo -e "  ${BOLD}1.${NC} Ensure DNS points to: ${BOLD}$VPS_PUBLIC_IP${NC}"
        echo -e "  ${BOLD}2.${NC} Run: ${BOLD}certbot --nginx -d $DOMAIN${NC}"
        echo ""
        prompt "Continue without SSL? (Y/n): "
        read -r continue_without_ssl
        continue_without_ssl=${continue_without_ssl:-Y}
        if [[ "$continue_without_ssl" =~ ^[Yy]$ ]]; then
            NO_SSL=true
        else
            error "SSL setup failed. Please check DNS and try again."
        fi
    fi
    
    info "Starting Nginx..."
    systemctl start nginx 2>/dev/null || true
}

# Setup application
setup_application() {
    step "Setting up Application"
    
    # Variables
    APP_NAME="news-aggregator-api"
    APP_DIR="/var/www/$APP_NAME"
    VENV_DIR="$APP_DIR/venv"
    USER="www-data"
    GITHUB_REPO="https://github.com/maxieyy/news-aggregator-api.git"
    
    # Create application directory
    info "Creating application directory..."
    mkdir -p "$APP_DIR"
    cd "$APP_DIR"
    
    # Clone repository
    if [ ! -d ".git" ]; then
        info "Cloning repository..."
        git clone "$GITHUB_REPO" . 2>&1 | grep -E "(Cloning|Receiving|Resolving)" || true
        log "Repository cloned"
    else
        info "Updating repository..."
        git pull origin main 2>&1 | grep -E "(Already|Updating|Fast-forward)" || true
        log "Repository updated"
    fi
    
    # Create Python virtual environment
    info "Setting up Python virtual environment..."
    if [ ! -d "$VENV_DIR" ]; then
        python3.11 -m venv "$VENV_DIR"
        log "Virtual environment created"
    fi
    
    # Activate and install dependencies
    info "Installing Python dependencies..."
    source "$VENV_DIR/bin/activate"
    
    # Upgrade pip first
    pip install --upgrade pip 2>&1 | grep -v "already satisfied" || true
    
    # Install dependencies
    if [ -f "requirements.txt" ]; then
        pip install -r requirements.txt 2>&1 | grep -E "(Collecting|Installing|Successfully)" || true
        log "Python dependencies installed"
    else
        warn "requirements.txt not found, installing basic dependencies..."
        pip install fastapi uvicorn sqlalchemy redis celery feedparser requests 2>&1 | grep -E "(Collecting|Installing|Successfully)" || true
    fi
    
    # Create necessary directories
    info "Creating directories..."
    mkdir -p "$APP_DIR/storage/media/images"
    mkdir -p "$APP_DIR/storage/media/videos"
    mkdir -p "$APP_DIR/storage/cache"
    mkdir -p "$APP_DIR/logs"
    mkdir -p "$APP_DIR/static"
    
    # Create environment file
    info "Creating environment configuration..."
    cat > "$APP_DIR/.env" << EOF
# API Configuration
API_KEY=$API_KEY
API_KEY_NAME=X-API-Key
SECRET_KEY=$(openssl rand -hex 32)
DEBUG=False

# Database
DATABASE_URL=sqlite:///$APP_DIR/news.db

# Redis
REDIS_URL=redis://localhost:6379/0

# AI Configuration
OPENAI_API_KEY=$OPENAI_API_KEY
OPENAI_MODEL=gpt-3.5-turbo-1106
AI_SUMMARIZE=True

# Storage Paths
MEDIA_STORAGE_PATH=$APP_DIR/storage/media
CACHE_PATH=$APP_DIR/storage/cache

# Server
HOST=0.0.0.0
PORT=8000
DOMAIN=$(if [ "$NO_SSL" = true ]; then echo "http://$DOMAIN"; else echo "https://$DOMAIN"; fi)

# Settings
FETCH_DELAY=1.0
MAX_CONCURRENT_FETCHES=5
EOF
    
    # Set permissions
    chown -R $USER:$USER "$APP_DIR"
    chmod 755 "$APP_DIR"
    chmod 600 "$APP_DIR/.env"
    
    log "Application setup completed"
}

# Configure services
configure_services() {
    step "Configuring Services"
    
    APP_DIR="/var/www/news-aggregator-api"
    VENV_DIR="$APP_DIR/venv"
    USER="www-data"
    
    # Configure Redis
    info "Configuring Redis..."
    sed -i 's/^supervised no/supervised systemd/' /etc/redis/redis.conf 2>/dev/null || true
    systemctl enable redis-server
    systemctl restart redis-server
    log "Redis configured"
    
    # Create systemd service for API
    info "Creating API service..."
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
EnvironmentFile=$APP_DIR/.env
ExecStart=$VENV_DIR/bin/uvicorn src.main:app --host 0.0.0.0 --port 8000
Restart=always
RestartSec=10
StandardOutput=append:$APP_DIR/logs/api.log
StandardError=append:$APP_DIR/logs/api-error.log

[Install]
WantedBy=multi-user.target
EOF
    
    # Create systemd service for worker
    info "Creating worker service..."
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
EnvironmentFile=$APP_DIR/.env
ExecStart=$VENV_DIR/bin/celery -A src.tasks.worker.celery_app worker --loglevel=info
Restart=always
RestartSec=10
StandardOutput=append:$APP_DIR/logs/worker.log
StandardError=append:$APP_DIR/logs/worker-error.log

[Install]
WantedBy=multi-user.target
EOF
    
    # Create systemd service for scheduler
    info "Creating scheduler service..."
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
EnvironmentFile=$APP_DIR/.env
ExecStart=$VENV_DIR/bin/python -m src.core.scheduler
Restart=always
RestartSec=10
StandardOutput=append:$APP_DIR/logs/scheduler.log
StandardError=append:$APP_DIR/logs/scheduler-error.log

[Install]
WantedBy=multi-user.target
EOF
    
    # Reload systemd
    systemctl daemon-reload
    
    log "Services configured"
}

# Configure Nginx
configure_nginx() {
    step "Configuring Nginx"
    
    APP_DIR="/var/www/news-aggregator-api"
    
    # Remove default site
    rm -f /etc/nginx/sites-enabled/default 2>/dev/null || true
    
    # Create nginx configuration
    info "Creating Nginx configuration..."
    
    if [ "$NO_SSL" = true ]; then
        # HTTP configuration
        cat > /etc/nginx/sites-available/news-api << EOF
server {
    listen 80;
    server_name $DOMAIN;
    client_max_body_size 100M;
    
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
        
        proxy_connect_timeout 300s;
        proxy_send_timeout 300s;
        proxy_read_timeout 300s;
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
    
    # Root redirect
    location / {
        return 302 /api/v1/;
    }
}
EOF
        log "HTTP configuration created"
    else
        # HTTPS configuration
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
    client_max_body_size 100M;
    
    # SSL certificates
    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;
    
    # SSL configuration
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384;
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
        
        proxy_connect_timeout 300s;
        proxy_send_timeout 300s;
        proxy_read_timeout 300s;
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
    
    # Root redirect
    location / {
        return 302 /api/v1/;
    }
}
EOF
        log "HTTPS configuration created"
    fi
    
    # Enable site
    ln -sf /etc/nginx/sites-available/news-api /etc/nginx/sites-enabled/
    
    # Test Nginx configuration
    info "Testing Nginx configuration..."
    if nginx -t 2>/dev/null; then
        log "Nginx configuration test passed"
    else
        warn "Nginx configuration test failed, checking error..."
        nginx -t
        error "Fix Nginx configuration before continuing"
    fi
    
    # Enable and start Nginx
    systemctl enable nginx
    systemctl restart nginx
    log "Nginx configured and started"
}

# Setup firewall
setup_firewall() {
    step "Configuring Firewall"
    
    # Check if ufw is available
    if command -v ufw > /dev/null 2>&1; then
        info "Configuring UFW firewall..."
        
        # Allow SSH
        ufw allow 22/tcp
        
        # Allow HTTP/HTTPS
        ufw allow 80/tcp
        ufw allow 443/tcp
        
        # Allow API port
        ufw allow 8000/tcp
        
        # Enable firewall
        echo "y" | ufw enable
        
        log "Firewall configured"
    else
        warn "UFW not installed, skipping firewall configuration"
    fi
}

# Setup log rotation
setup_log_rotation() {
    step "Setting up Log Rotation"
    
    APP_DIR="/var/www/news-aggregator-api"
    USER="www-data"
    
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
    step "Creating Update Script"
    
    APP_DIR="/var/www/news-aggregator-api"
    VENV_DIR="$APP_DIR/venv"
    
    cat > "$APP_DIR/update.sh" << 'EOF'
#!/bin/bash

# News Aggregator API Update Script

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo ""
echo -e "${BLUE}╔══════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║${NC}      News Aggregator API - Update           ${BLUE}║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════╝${NC}"
echo ""

APP_DIR="/var/www/news-aggregator-api"
VENV_DIR="$APP_DIR/venv"

cd "$APP_DIR"

echo -e "${YELLOW}[1/4]${NC} Pulling latest changes from GitHub..."
if git pull origin main; then
    echo -e "${GREEN}✓ Repository updated${NC}"
else
    echo -e "${RED}✗ Failed to pull changes${NC}"
    exit 1
fi

echo ""
echo -e "${YELLOW}[2/4]${NC} Updating Python dependencies..."
source $VENV_DIR/bin/activate
if pip install -r requirements.txt; then
    echo -e "${GREEN}✓ Dependencies updated${NC}"
else
    echo -e "${RED}✗ Failed to install dependencies${NC}"
    exit 1
fi

echo ""
echo -e "${YELLOW}[3/4]${NC} Restarting services..."
systemctl restart news-api
systemctl restart news-worker
systemctl restart news-scheduler

echo ""
echo -e "${YELLOW}[4/4]${NC} Checking service status..."
for service in news-api news-worker news-scheduler; do
    if systemctl is-active --quiet "$service"; then
        echo -e "${GREEN}✓ $service is running${NC}"
    else
        echo -e "${RED}✗ $service is not running${NC}"
    fi
done

echo ""
echo -e "${GREEN}✅ Update completed successfully!${NC}"
echo -e "   Time: $(date)"
echo ""
EOF
    
    chmod +x "$APP_DIR/update.sh"
    log "Update script created: $APP_DIR/update.sh"
}

# Start services
start_services() {
    step "Starting Services"
    
    info "Starting Redis..."
    systemctl restart redis-server
    sleep 2
    
    info "Starting API..."
    systemctl restart news-api
    sleep 2
    
    info "Starting worker..."
    systemctl restart news-worker
    sleep 2
    
    info "Starting scheduler..."
    systemctl restart news-scheduler
    sleep 2
    
    # Enable services to start on boot
    systemctl enable redis-server news-api news-worker news-scheduler
    
    log "All services started"
}

# Verify installation
verify_installation() {
    step "Verifying Installation"
    
    info "Checking service status..."
    local all_running=true
    
    for service in redis-server news-api news-worker news-scheduler nginx; do
        if systemctl is-active --quiet "$service"; then
            echo -e "  ${GREEN}✓${NC} $service is running"
        else
            echo -e "  ${RED}✗${NC} $service is not running"
            all_running=false
        fi
    done
    
    if [ "$all_running" = true ]; then
        log "All services are running"
    else
        warn "Some services are not running. Check logs with: journalctl -u service-name"
    fi
    
    # Test API endpoint
    info "Testing API endpoint..."
    sleep 5  # Give services time to fully start
    
    if [ "$NO_SSL" = true ]; then
        local test_url="http://$DOMAIN/health"
    else
        local test_url="https://$DOMAIN/health"
    fi
    
    if curl -s --max-time 10 "$test_url" | grep -q "healthy"; then
        log "API health check passed"
    else
        warn "API health check failed. API might need more time to start."
    fi
}

# Display completion message
display_completion() {
    echo ""
    success "DEPLOYMENT COMPLETED SUCCESSFULLY!"
    echo ""
    echo -e "${CYAN}════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}📡 ACCESS INFORMATION${NC}"
    echo -e "${CYAN}════════════════════════════════════════════════════════════${NC}"
    
    if [ "$NO_SSL" = true ]; then
        echo -e "  ${BOLD}API URL:${NC}      http://$DOMAIN/api/v1/"
        echo -e "  ${BOLD}Health Check:${NC}  http://$DOMAIN/health"
    else
        echo -e "  ${BOLD}API URL:${NC}      https://$DOMAIN/api/v1/"
        echo -e "  ${BOLD}Health Check:${NC}  https://$DOMAIN/health"
    fi
    
    echo ""
    echo -e "${CYAN}════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}🔑 SECURITY INFORMATION${NC}"
    echo -e "${CYAN}════════════════════════════════════════════════════════════${NC}"
    echo -e "  ${BOLD}API Key:${NC}        $API_KEY"
    echo -e "  ${BOLD}Header:${NC}         X-API-Key: $API_KEY"
    
    if [ "$OPENAI_API_KEY" = "your-openai-api-key-here" ]; then
        echo -e "  ${BOLD}OpenAI Key:${NC}    ${YELLOW}Not configured - AI summarization disabled${NC}"
        echo -e "  ${BOLD}To enable AI:${NC}  Edit /var/www/news-aggregator-api/.env"
    else
        echo -e "  ${BOLD}OpenAI Key:${NC}    ${GREEN}Configured - AI summarization enabled${NC}"
    fi
    
    echo ""
    echo -e "${CYAN}════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}🛠️  MANAGEMENT COMMANDS${NC}"
    echo -e "${CYAN}════════════════════════════════════════════════════════════${NC}"
    echo -e "  ${BOLD}Check logs:${NC}       journalctl -u news-api -f"
    echo -e "  ${BOLD}Update API:${NC}       /var/www/news-aggregator-api/update.sh"
    echo -e "  ${BOLD}Restart all:${NC}      systemctl restart news-api news-worker news-scheduler"
    echo -e "  ${BOLD}View status:${NC}      systemctl status news-api"
    
    echo ""
    echo -e "${CYAN}════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}📁 IMPORTANT PATHS${NC}"
    echo -e "${CYAN}════════════════════════════════════════════════════════════${NC}"
    echo -e "  ${BOLD}App Directory:${NC}    /var/www/news-aggregator-api"
    echo -e "  ${BOLD}Logs:${NC}             /var/www/news-aggregator-api/logs/"
    echo -e "  ${BOLD}Database:${NC}         /var/www/news-aggregator-api/news.db"
    echo -e "  ${BOLD}Config:${NC}           /var/www/news-aggregator-api/.env"
    echo -e "  ${BOLD}Media Storage:${NC}    /var/www/news-aggregator-api/storage/media/"
    
    echo ""
    echo -e "${CYAN}════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}🚀 QUICK TEST${NC}"
    echo -e "${CYAN}════════════════════════════════════════════════════════════${NC}"
    
    if [ "$NO_SSL" = true ]; then
        echo -e "  ${BOLD}Test API:${NC} curl -H 'X-API-Key: $API_KEY' http://$DOMAIN/api/v1/system/status"
    else
        echo -e "  ${BOLD}Test API:${NC} curl -H 'X-API-Key: $API_KEY' https://$DOMAIN/api/v1/system/status"
    fi
    
    echo ""
    echo -e "${GREEN}✅ Your News Aggregator API is now live and ready to use!${NC}"
    echo ""
    
    if [ "$NO_SSL" = true ] && [ "$SETUP_SSL" != true ]; then
        echo -e "${YELLOW}⚠  REMINDER: SSL is not configured. To add SSL later:${NC}"
        echo -e "  1. Ensure DNS points to: ${BOLD}$VPS_PUBLIC_IP${NC}"
        echo -e "  2. Run: ${BOLD}certbot --nginx -d $DOMAIN${NC}"
        echo ""
    fi
}

# Main execution
main() {
    header
    
    # Check root
    check_root
    
    # Detect system
    detect_system
    
    # Check for conflicts
    check_existing_services
    
    # Get configuration
    get_configuration
    
    echo ""
    echo -e "${GREEN}Starting deployment process...${NC}"
    echo ""
    
    # Installation steps
    install_dependencies
    setup_ssl
    setup_application
    configure_services
    configure_nginx
    setup_firewall
    setup_log_rotation
    create_update_script
    start_services
    verify_installation
    display_completion
}

# Run main function
main
