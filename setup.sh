#!/bin/bash
# Nautalis Web Crawler - Ubuntu 22.04 Setup Script
# This script sets up the complete environment for the Nautalis web crawler

set -e  # Exit on any error

echo "🚀 Setting up Nautalis Web Crawler on Ubuntu 22.04"
echo "=================================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
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
   print_warning "Please run as a regular user with sudo privileges"
   exit 1
fi

# Update system packages
print_step "Updating system packages..."
sudo apt update && sudo apt upgrade -y
print_success "System packages updated"

# Install required system packages
print_step "Installing system dependencies..."
sudo apt install -y \
    python3 \
    python3-pip \
    python3-venv \
    python3-dev \
    build-essential \
    libssl-dev \
    libffi-dev \
    git \
    curl \
    wget \
    sqlite3 \
    postgresql-client \
    htop \
    nano \
    vim

print_success "System dependencies installed"

# Install PostgreSQL (optional but recommended for production)
read -p "Do you want to install PostgreSQL for production use? (y/N): " install_postgres
if [[ $install_postgres =~ ^[Yy]$ ]]; then
    print_step "Installing PostgreSQL..."
    sudo apt install -y postgresql postgresql-contrib
    
    # Start and enable PostgreSQL
    sudo systemctl start postgresql
    sudo systemctl enable postgresql
    
    print_step "Setting up PostgreSQL database..."
    sudo -u postgres psql -c "CREATE DATABASE nautalis_db;"
    sudo -u postgres psql -c "CREATE USER nautalis WITH PASSWORD 'nautalis_password';"
    sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE nautalis_db TO nautalis;"
    
    print_success "PostgreSQL installed and configured"
    print_warning "Database: nautalis_db, User: nautalis, Password: nautalis_password"
    print_warning "Please change the default password in production!"
fi

# Create project directory
PROJECT_DIR="$HOME/nautalis-crawler"
print_step "Setting up project directory at $PROJECT_DIR..."

if [ -d "$PROJECT_DIR" ]; then
    print_warning "Directory $PROJECT_DIR already exists"
    read -p "Do you want to remove it and start fresh? (y/N): " remove_dir
    if [[ $remove_dir =~ ^[Yy]$ ]]; then
        rm -rf "$PROJECT_DIR"
        print_success "Removed existing directory"
    else
        print_warning "Using existing directory"
    fi
fi

mkdir -p "$PROJECT_DIR"
cd "$PROJECT_DIR"

# Clone repository (if using Git) or create directory structure
read -p "Do you have a Git repository URL for Nautalis? (y/N): " has_repo
if [[ $has_repo =~ ^[Yy]$ ]]; then
    read -p "Enter the Git repository URL: " repo_url
    print_step "Cloning repository..."
    git clone "$repo_url" .
    print_success "Repository cloned"
else
    print_step "Creating directory structure for manual file placement..."
    mkdir -p logs data exports
    print_success "Directory structure created"
    print_warning "Please place your Python files in $PROJECT_DIR"
fi

# Create Python virtual environment
print_step "Creating Python virtual environment..."
python3 -m venv venv
source venv/bin/activate
print_success "Virtual environment created and activated"

# Upgrade pip
print_step "Upgrading pip..."
pip install --upgrade pip
print_success "Pip upgraded"

# Install Python dependencies
print_step "Installing Python dependencies..."
if [ -f "requirements.txt" ]; then
    pip install -r requirements.txt
else
    print_warning "requirements.txt not found, installing common dependencies..."
    pip install \
        aiohttp>=3.9.0 \
        aiosqlite>=0.19.0 \
        asyncpg>=0.29.0 \
        beautifulsoup4>=4.12.0 \
        lxml>=4.9.0 \
        PyYAML>=6.0 \
        uvloop>=0.19.0
fi
print_success "Python dependencies installed"

# Create default configuration if it doesn't exist
if [ ! -f "config.yaml" ]; then
    print_step "Creating default configuration..."
    python3 -c "
import yaml
config = {
    'max_depth': 3,
    'max_pages': 1000,
    'max_workers': 10,
    'stay_in_domain': True,
    'delay': 0.5,
    'timeout': 30,
    'database_type': 'sqlite',
    'database_url': 'nautalis.db',
    'max_retries': 3,
    'retry_delay': 1.0,
    'user_agent': 'NautalisBot/1.0 (+https://nautalis.search)',
    'log_level': 'INFO',
    'log_file': 'logs/nautalis.log'
}
with open('config.yaml', 'w') as f:
    yaml.dump(config, f, default_flow_style=False, indent=2)
print('Default config.yaml created')
"
    print_success "Default configuration created"
fi

# Create systemd service file (optional)
read -p "Do you want to create a systemd service for Nautalis? (y/N): " create_service
if [[ $create_service =~ ^[Yy]$ ]]; then
    print_step "Creating systemd service..."
    
    cat > nautalis-crawler.service << EOF
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

    sudo mv nautalis-crawler.service /etc/systemd/system/
    sudo systemctl daemon-reload
    print_success "Systemd service created"
    print_warning "Use 'sudo systemctl start nautalis-crawler' to start the service"
fi

# Create useful scripts
print_step "Creating utility scripts..."

# Start script
cat > start_crawler.sh << 'EOF'
#!/bin/bash
cd "$(dirname "$0")"
source venv/bin/activate

echo "Starting Nautalis Web Crawler..."
echo "Press Ctrl+C to stop"

python3 main.py "$@"
EOF

# Analysis script
cat > analyze_data.sh << 'EOF'
#!/bin/bash
cd "$(dirname "$0")"
source venv/bin/activate

echo "Analyzing crawled data..."
python3 analyze.py --report
EOF

# Quick stats script
cat > quick_stats.sh << 'EOF'
#!/bin/bash
cd "$(dirname "$0")"
source venv/bin/activate

python3 main.py stats
EOF

chmod +x start_crawler.sh analyze_data.sh quick_stats.sh

print_success "Utility scripts created"

# Create example seed URLs file
cat > example_seeds.txt << 'EOF'
# Example seed URLs for Nautalis crawler
# Add one URL per line, comments start with #

https://example.com
https://httpbin.org
https://quotes.toscrape.com
https://books.toscrape.com
EOF

print_success "Example seed URLs file created"

# Set up log rotation
print_step "Setting up log rotation..."
sudo tee /etc/logrotate.d/nautalis << EOF
$PROJECT_DIR/logs/*.log {
    daily
    missingok
    rotate 30
    compress
    delaycompress
    notifempty
    copytruncate
}
EOF

print_success "Log rotation configured"

# Create firewall rules (if UFW is available)
if command -v ufw &> /dev/null; then
    print_step "Configuring firewall (UFW)..."
    sudo ufw allow ssh
    # Add other ports if needed for your application
    print_success "Firewall configured"
fi

# Final instructions
echo ""
echo "🎉 Nautalis Web Crawler Setup Complete!"
echo "======================================"
echo ""
echo -e "${GREEN}Project Directory:${NC} $PROJECT_DIR"
echo -e "${GREEN}Virtual Environment:${NC} $PROJECT_DIR/venv"
echo -e "${GREEN}Configuration:${NC} $PROJECT_DIR/config.yaml"
echo -e "${GREEN}Logs Directory:${NC} $PROJECT_DIR/logs"
echo ""
echo -e "${BLUE}Quick Start Commands:${NC}"
echo "  cd $PROJECT_DIR"
echo "  source venv/bin/activate"
echo "  ./start_crawler.sh --seeds https://example.com"
echo "  ./analyze_data.sh"
echo "  ./quick_stats.sh"
echo ""
echo -e "${BLUE}Manual Commands:${NC}"
echo "  python3 main.py --seeds https://example.com --depth 2 --max-pages 500"
echo "  python3 analyze.py --report"
echo "  python3 analyze.py --search 'keyword'"
echo ""
echo -e "${YELLOW}Next Steps:${NC}"
echo "1. Edit config.yaml with your preferred settings"
echo "2. Add your seed URLs to example_seeds.txt or use --seeds"
echo "3. Test the crawler with a small crawl first"
echo "4. Monitor logs in logs/nautalis.log"
echo ""
echo -e "${GREEN}Setup completed successfully!${NC}"
EOF
