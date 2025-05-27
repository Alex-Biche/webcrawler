#!/bin/bash
# Nautalis Web Crawler - Ubuntu 22.04 Setup Script
# Complete setup for production deployment on Linode VPS

set -e  # Exit on any error

echo "🚀 Setting up Nautalis Web Crawler on Ubuntu 22.04"
echo "=================================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root
if [[ $EUID -eq 0 ]]; then
   print_error "This script should not be run as root for security reasons"
   print_status "Please run as a regular user with sudo privileges"
   exit 1
fi

print_status "Updating system packages..."
sudo apt update && sudo apt upgrade -y

print_status "Installing system dependencies..."
sudo apt install -y \
    python3 \
    python3-pip \
    python3-venv \
    python3-dev \
    build-essential \
    libssl-dev \
    libffi-dev \
    liblxml2-dev \
    libxslt1-dev \
    libxml2-dev \
    zlib1g-dev \
    git \
    curl \
    wget \
    htop \
    screen \
    postgresql-client \
    sqlite3

# Optional: Install PostgreSQL server if requested
read -p "Do you want to install PostgreSQL server locally? [y/N]: " install_postgres
if [[ $install_postgres =~ ^[Yy]$ ]]; then
    print_status "Installing PostgreSQL server..."
    sudo apt install -y postgresql postgresql-contrib
    
    print_status "Starting PostgreSQL service..."
    sudo systemctl start postgresql
    sudo systemctl enable postgresql
    
    print_status "Creating nautalis database and user..."
    sudo -u postgres createuser --interactive --pwprompt nautalis || true
    sudo -u postgres createdb nautalis_db -O nautalis || true
    
    print_status "PostgreSQL setup complete!"
    print_warning "Remember to configure pg_hba.conf if needed for remote connections"
fi

# Create project directory
PROJECT_DIR="$HOME/nautalis-crawler"
print_status "Creating project directory: $PROJECT_DIR"
mkdir -p "$PROJECT_DIR"
cd "$PROJECT_DIR"

# Create Python virtual environment
print_status "Creating Python virtual environment..."
python3 -m venv venv
source venv/bin/activate

print_status "Upgrading pip..."
pip install --upgrade pip setuptools wheel

# Install Python dependencies
print_status "Installing Python dependencies..."
cat > requirements.txt << 'EOF'
# Nautalis Web Crawler Dependencies
aiohttp>=3.9.0
aiosqlite>=0.19.0
asyncpg>=0.29.0
beautifulsoup4>=4.12.0
lxml>=4.9.0
PyYAML>=6.0
uvloop>=0.19.0; sys_platform != "win32"
cchardet>=2.1.7
EOF

pip install -r requirements.txt

print_status "Creating default configuration..."
cat > config.yaml << 'EOF'
# Nautalis Web Crawler Configuration
max_depth: 3
max_pages: 1000
max_workers: 10
stay_in_domain: true
delay: 0.5
timeout: 30
database_type: sqlite
database_url: nautalis.db
max_retries: 3
retry_delay: 1.0
user_agent: "NautalisBot/1.0 (+https://nautalis.search)"
log_level: INFO
log_file: null
EOF

# Create systemd service file
print_status "Creating systemd service file..."
sudo tee /etc/systemd/system/nautalis-crawler.service > /dev/null << EOF
[Unit]
Description=Nautalis Web Crawler
After=network.target

[Service]
Type=simple
User=$USER
WorkingDirectory=$PROJECT_DIR
Environment=PATH=$PROJECT_DIR/venv/bin
ExecStart=$PROJECT_DIR/venv/bin/python main.py --config config.yaml
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# Create log rotation configuration
print_status "Setting up log rotation..."
sudo tee /etc/logrotate.d/nautalis-crawler > /dev/null << EOF
$PROJECT_DIR/logs/*.log {
    daily
    missingok
    rotate 7
    compress
    delaycompress
    notifempty
    create 644 $USER $USER
}
EOF

# Create logs directory
mkdir -p logs

# Create startup script
print_status "Creating startup script..."
cat > start_crawler.sh << 'EOF'
#!/bin/bash
# Nautalis Crawler Startup Script

cd "$(dirname "$0")"
source venv/bin/activate

echo "🚀 Starting Nautalis Web Crawler"
echo "Configuration file: config.yaml"
echo "Logs will be written to: logs/"
echo ""

# Example seed URLs - replace with your targets
SEED_URLS=(
    "https://example.com"
    "https://httpbin.org"
    "https://jsonplaceholder.typicode.com"
)

# Start crawler with seed URLs
python main.py --seeds "${SEED_URLS[@]}" \
               --config config.yaml \
               --log-file logs/crawler.log \
               --workers 15 \
               --max-pages 5000 \
               --delay 0.3

echo "✅ Crawling completed!"
echo "📊 View results with: python analyze.py --report"
EOF

chmod +x start_crawler.sh

# Create analysis script
print_status "Creating analysis script..."
cat > analyze_results.sh << 'EOF'
#!/bin/bash
# Nautalis Results Analysis Script

cd "$(dirname "$0")"
source venv/bin/activate

echo "📊 Nautalis Crawl Analysis"
echo "=========================="

python analyze.py --report
echo ""
echo "💾 Exporting successful URLs to successful_urls.txt..."
python analyze.py --export-success successful_urls.txt

echo ""
echo "❌ Exporting failed URLs to failed_urls.txt..."
python analyze.py --export-failed failed_urls.txt

echo "✅ Analysis complete!"
EOF

chmod +x analyze_results.sh

# Create monitoring script
print_status "Creating monitoring script..."
cat > monitor.sh << 'EOF'
#!/bin/bash
# Nautalis Monitoring Script

cd "$(dirname "$0")"
source venv/bin/activate

echo "🔍 
