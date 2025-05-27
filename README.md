# 🌊 Nautalis Web Crawler

A high-performance, production-ready web crawler built for search engine indexing with async Python and modern best practices.

## ⚡ Features

- **High Performance**: Async/await with aiohttp for concurrent crawling
- **Respectful**: Honors robots.txt and implements proper delays
- **Configurable**: YAML config + CLI arguments for flexibility  
- **Database Support**: Both SQLite and PostgreSQL backends
- **Smart Crawling**: Depth control, domain restrictions, deduplication
- **Production Ready**: Logging, error handling, statistics, and monitoring
- **Analysis Tools**: Built-in data analysis and reporting capabilities

## 🚀 Quick Setup on Ubuntu 22.04

### 1. Clone and Setup

```bash
# Download the setup script
wget https://raw.githubusercontent.com/your-repo/nautalis-crawler/main/setup.sh
chmod +x setup.sh

# Run the automated setup
./setup.sh
```

### 2. Manual Setup (Alternative)

```bash
# Update system
sudo apt update && sudo apt upgrade -y

# Install dependencies
sudo apt install -y python3 python3-pip python3-venv python3-dev \
    build-essential libssl-dev libffi-dev git sqlite3

# Create project directory
mkdir ~/nautalis-crawler && cd ~/nautalis-crawler

# Clone repository (replace with actual repo URL)
git clone https://github.com/your-repo/nautalis-crawler.git .

# Create virtual environment
python3 -m venv venv
source venv/bin/activate

# Install Python packages
pip install -r requirements.txt
```

## 🏃‍♂️ Quick Start

### Basic Crawling

```bash
# Activate virtual environment
cd ~/nautalis-crawler
source venv/bin/activate

# Crawl a single site (staying in domain)
python3 main.py --seeds https://example.com

# Crawl multiple sites with custom settings
python3 main.py --seeds https://example.com https://test.com \
    --depth 3 --max-pages 1000 --workers 5 --delay 1.0

# Allow external domains
python3 main.py --seeds https://example.com --allow-external

# Use PostgreSQL database
python3 main.py --seeds https://example.com \
    --db postgresql://user:pass@localhost/nautalis
```

### Using Configuration File

```bash
# Edit config.yaml with your settings
nano config.yaml

# Run with config file
python3 main.py --config config.yaml
```

### Analysis and Reporting

```bash
# Generate comprehensive report
python3 analyze.py --report

# Search crawled pages
python3 analyze.py --search "python"

# Export successful URLs
python3 analyze.py --export-success urls.txt

# Export failed URLs with errors
python3 analyze.py --export-failed errors.txt
```

## ⚙️ Configuration

### config.yaml Example

```yaml
# Crawling Behavior
max_depth: 3                    # Maximum link depth to follow
max_pages: 1000                 # Maximum pages to crawl
max_workers: 10                 # Concurrent worker threads
stay_in_domain: true            # Restrict to seed domains
delay: 0.5                      # Delay between requests (seconds)
timeout: 30                     # Request timeout (seconds)

# Database Configuration
database_type: sqlite           # 'sqlite' or 'postgresql'
database_url: nautalis.db       # Database file or connection string

# Retry and Error Handling
max_retries: 3                  # Maximum retry attempts
retry_delay: 1.0               # Delay between retries

# User Agent
user_agent: "NautalisBot/1.0 (+https://nautalis.search)"

# Logging
log_level: INFO                 # DEBUG, INFO, WARNING, ERROR
log_file: logs/nautalis.log     # Log file path
```

### Command Line Options

```bash
python3 main.py --help
```

**Key Options:**
- `--seeds URL [URL ...]`: Seed URLs to start crawling
- `--depth N`: Maximum crawl depth (default: 3)
- `--max-pages N`: Maximum pages to crawl (default: 1000)
- `--workers N`: Number of concurrent workers (default: 10)
- `--delay SECONDS`: Delay between requests (default: 0.5)
- `--db URL`: Database file or connection string
- `--allow-external`: Allow crawling external domains
- `--log-level LEVEL`: Logging level (DEBUG/INFO/WARNING/ERROR)

## 🗄️ Database Setup

### SQLite (Default)
```bash
# Automatically creates nautalis.db
python3 main.py --seeds https://example.com
```

### PostgreSQL (Recommended for Production)
```bash
# Install PostgreSQL
sudo apt install postgresql postgresql-contrib

# Create database and user
sudo -u postgres psql
CREATE DATABASE nautalis_db;
CREATE USER nautalis WITH PASSWORD 'your-password';
GRANT ALL PRIVILEGES ON DATABASE nautalis_db TO nautalis;
\q

# Use PostgreSQL
python3 main.py --seeds https://example.com \
    --db postgresql://nautalis:your-password@localhost/nautalis_db
```

## 📊 Performance Tuning

### High-Performance Settings

```yaml
# config.yaml for high-performance crawling
max_workers: 50                 # More concurrent workers
delay: 0.1                      # Faster crawling (be respectful!)
max_pages: 10000               # Larger crawls
timeout: 15                     # Shorter timeouts
```

### Resource Monitoring

```bash
# Monitor system resources
htop

# Monitor crawler logs
tail -f logs/nautalis.log

# Check database size
du -h nautalis.db

# PostgreSQL monitoring
sudo -u postgres psql nautalis_db -c "SELECT COUNT(*) FROM crawled_pages;"
```

## 🔍 Data Analysis Examples

### View Crawl Statistics
```bash
python3 main.py stats
```

### Generate Full Report
```bash
python3 analyze.py --report
```

### Search and Export
```bash
# Search for specific content
python3 analyze.py --search "python programming"

# Export all successful URLs
python3 analyze.py --export-success successful_urls.txt

# Export failed URLs with error details
python3 analyze.py --export-failed failed_urls.txt
```

### Database Queries (Advanced)

```sql
-- Connect to SQLite
sqlite3 nautalis.db

-- View recent crawls
SELECT url, title, status_code, crawled_at 
FROM crawled_pages 
ORDER BY crawled_at DESC 
LIMIT 10;

-- Count by status code
SELECT status_code, COUNT(*) 
FROM crawled_pages 
GROUP BY status_code;

-- Find largest pages
SELECT url, title, content_length 
FROM crawled_pages 
WHERE status_code = 200 
ORDER BY content_length DESC 
LIMIT 10;
```

## 🛠️ Utility Scripts

The setup creates several utility scripts in your project directory:

```bash
# Quick start crawler
./start_crawler.sh --seeds https://example.com

# Generate analysis report
./analyze_data.sh

# Show quick statistics
./quick_stats.sh
```

## 🔧 Production Deployment

### Systemd Service

```bash
# Install as system service (created during setup)
sudo systemctl enable nautalis-crawler
sudo systemctl start nautalis-crawler

# Check status
sudo systemctl status nautalis-crawler

# View logs
sudo journalctl -u nautalis-crawler -f
```

### Log Rotation

Log rotation is automatically configured during setup:

```bash
# Manual log rotation
sudo logrotate -f /etc/logrotate.d/nautalis

# Check log rotation status
sudo logrotate -d /etc/logrotate.d/nautalis
```

### Monitoring and Alerts

```bash
# Monitor crawler with cron job
# Add to crontab: */5 * * * * /path/to/check_crawler.sh

# Example monitoring script
#!/bin/bash
if ! pgrep -f "python3 main.py" > /dev/null; then
    echo "Nautalis crawler not running!" | mail -s "Crawler Alert" admin@example.com
fi
```

## 🏆 Recommended Settings

### Small Scale (Personal/Testing)
```yaml
max_depth: 2
max_pages: 100
max_workers: 5
delay: 1.0
```

### Medium Scale (Business)
```yaml
max_depth: 3
max_pages: 5000
max_workers: 20
delay: 0.5
database_type: postgresql
```

### Large Scale (Enterprise)
```yaml
max_depth: 4
max_pages: 50000
max_workers: 50
delay: 0.2
database_type: postgresql
# Use dedicated PostgreSQL server
```

## 🚨 Troubleshooting

### Common Issues

1. **Permission Denied**
   ```bash
   chmod +x setup.sh
   sudo chown -R $USER:$USER ~/nautalis-crawler
   ```

2. **Database Connection Errors**
   ```bash
   # Check PostgreSQL status
   sudo systemctl status postgresql
   
   # Test connection
   psql -h localhost -U nautalis -d nautalis_db
   ```

3. **Memory Issues**
   ```bash
   # Reduce workers and max_pages
   python3 main.py --seeds https://example.com --workers 5 --max-pages 500
   ```

4. **Rate Limiting**
   ```bash
   # Increase delay between requests
   python3 main.py --seeds https://example.com --delay 2.0
   ```

### Debug Mode

```bash
# Enable debug logging
python3 main.py --seeds https://example.com --log-level DEBUG

# Check crawler internals
python3 -c "
from crawler import WebCrawler
from config import CrawlerConfig
config = CrawlerConfig()
print(f'Config: {config}')
"
```

## 📝 License

This project is licensed under the MIT License - see the LICENSE file for details.

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests if applicable
5. Submit a pull request

## 📞 Support

- **Issues**: GitHub Issues
- **Documentation**: This README
- **Email**: support@nautalis.search

---

**Happy Crawling! 🌊**
