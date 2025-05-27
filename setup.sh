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

# Create main Python files
print_status "Creating Python modules..."

# config.py
cat > config.py << 'EOF'
#!/usr/bin/env python3
"""
Nautalis Web Crawler - Configuration Module
"""

import yaml
import argparse
from dataclasses import dataclass
from typing import List, Optional
import os

@dataclass
class CrawlerConfig:
    """Configuration container for the crawler"""
    max_depth: int = 3
    max_pages: int = 1000
    max_workers: int = 10
    stay_in_domain: bool = True
    delay: float = 0.5
    timeout: int = 30
    database_type: str = "sqlite"
    database_url: str = "nautalis.db"
    max_retries: int = 3
    retry_delay: float = 1.0
    user_agent: str = "NautalisBot/1.0 (+https://nautalis.search)"
    log_level: str = "INFO"
    log_file: Optional[str] = None

def load_config_from_yaml(config_path: str) -> CrawlerConfig:
    """Load configuration from YAML file"""
    try:
        with open(config_path, 'r') as f:
            config_data = yaml.safe_load(f)
        
        return CrawlerConfig(
            max_depth=config_data.get('max_depth', 3),
            max_pages=config_data.get('max_pages', 1000),
            max_workers=config_data.get('max_workers', 10),
            stay_in_domain=config_data.get('stay_in_domain', True),
            delay=config_data.get('delay', 0.5),
            timeout=config_data.get('timeout', 30),
            database_type=config_data.get('database_type', 'sqlite'),
            database_url=config_data.get('database_url', 'nautalis.db'),
            max_retries=config_data.get('max_retries', 3),
            retry_delay=config_data.get('retry_delay', 1.0),
            user_agent=config_data.get('user_agent', 'NautalisBot/1.0 (+https://nautalis.search)'),
            log_level=config_data.get('log_level', 'INFO'),
            log_file=config_data.get('log_file')
        )
    except FileNotFoundError:
        print(f"Config file {config_path} not found, using defaults")
        return CrawlerConfig()
    except yaml.YAMLError as e:
        print(f"Error parsing config file: {e}")
        return CrawlerConfig()

def parse_arguments() -> tuple[CrawlerConfig, List[str]]:
    """Parse command line arguments and return config + seed URLs"""
    parser = argparse.ArgumentParser(
        description="Nautalis Web Crawler - High Performance Search Engine Crawler",
        formatter_class=argparse.RawDescriptionHelpFormatter
    )
    
    parser.add_argument('--seeds', nargs='+', help='Seed URLs to start crawling from', default=[])
    parser.add_argument('--config', type=str, help='Path to YAML configuration file', default='config.yaml')
    parser.add_argument('--depth', type=int, help='Maximum crawl depth', default=None)
    parser.add_argument('--max-pages', type=int, help='Maximum number of pages to crawl', default=None)
    parser.add_argument('--workers', type=int, help='Number of concurrent workers', default=None)
    parser.add_argument('--delay', type=float, help='Delay between requests in seconds', default=None)
    parser.add_argument('--timeout', type=int, help='Request timeout in seconds', default=None)
    parser.add_argument('--db', type=str, help='Database URL', default=None)
    parser.add_argument('--db-type', choices=['sqlite', 'postgresql'], help='Database type', default=None)
    parser.add_argument('--allow-external', action='store_true', help='Allow crawling external domains', default=False)
    parser.add_argument('--log-level', choices=['DEBUG', 'INFO', 'WARNING', 'ERROR'], help='Logging level', default=None)
    parser.add_argument('--log-file', type=str, help='Path to log file', default=None)
    
    args = parser.parse_args()
    
    # Load base configuration
    if os.path.exists(args.config):
        config = load_config_from_yaml(args.config)
    else:
        config = CrawlerConfig()
    
    # Override with CLI arguments
    if args.depth is not None:
        config.max_depth = args.depth
    if args.max_pages is not None:
        config.max_pages = args.max_pages
    if args.workers is not None:
        config.max_workers = args.workers
    if args.delay is not None:
        config.delay = args.delay
    if args.timeout is not None:
        config.timeout = args.timeout
    if args.db is not None:
        config.database_url = args.db
        if args.db.startswith('postgresql://'):
            config.database_type = 'postgresql'
    if args.db_type is not None:
        config.database_type = args.db_type
    if args.allow_external:
        config.stay_in_domain = False
    if args.log_level is not None:
        config.log_level = args.log_level
    if args.log_file is not None:
        config.log_file = args.log_file
    
    return config, args.seeds
EOF

# database.py
cat > database.py << 'EOF'
#!/usr/bin/env python3
"""
Nautalis Web Crawler - Database Module
"""

import asyncio
import aiosqlite
import asyncpg
import logging
from typing import Optional, Dict, Any
from datetime import datetime

class DatabaseManager:
    def __init__(self, database_url: str, db_type: str = "sqlite"):
        self.database_url = database_url
        self.db_type = db_type.lower()
        self.connection = None
        self.logger = logging.getLogger(__name__)
        
        if self.db_type not in ["sqlite", "postgresql"]:
            raise ValueError("Database type must be 'sqlite' or 'postgresql'")
    
    async def initialize(self):
        """Initialize database connection and create tables"""
        if self.db_type == "sqlite":
            await self._init_sqlite()
        else:
            await self._init_postgresql()
    
    async def _init_sqlite(self):
        """Initialize SQLite database"""
        self.connection = await aiosqlite.connect(self.database_url)
        
        # Enable WAL mode for better concurrent access
        await self.connection.execute("PRAGMA journal_mode=WAL")
        await self.connection.execute("PRAGMA synchronous=NORMAL")
        
        # Create tables
        await self.connection.execute("""
            CREATE TABLE IF NOT EXISTS crawled_pages (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                url TEXT UNIQUE NOT NULL,
                status_code INTEGER NOT NULL,
                title TEXT,
                content_length INTEGER DEFAULT 0,
                crawled_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                error_message TEXT
            )
        """)
        
        await self.connection.execute("CREATE INDEX IF NOT EXISTS idx_url ON crawled_pages(url)")
        await self.connection.execute("CREATE INDEX IF NOT EXISTS idx_status ON crawled_pages(status_code)")
        await self.connection.commit()
        self.logger.info("SQLite database initialized")
    
    async def _init_postgresql(self):
        """Initialize PostgreSQL database"""
        self.connection = await asyncpg.connect(self.database_url)
        
        await self.connection.execute("""
            CREATE TABLE IF NOT EXISTS crawled_pages (
                id SERIAL PRIMARY KEY,
                url TEXT UNIQUE NOT NULL,
                status_code INTEGER NOT NULL,
                title TEXT,
                content_length INTEGER DEFAULT 0,
                crawled_at TIMESTAMP DEFAULT NOW(),
                error_message TEXT
            )
        """)
        
        await self.connection.execute("CREATE INDEX IF NOT EXISTS idx_url ON crawled_pages(url)")
        await self.connection.execute("CREATE INDEX IF NOT EXISTS idx_status ON crawled_pages(status_code)")
        self.logger.info("PostgreSQL database initialized")
    
    async def store_page(self, url: str, status_code: int, title: str, content_length: int, timestamp: float, error: Optional[str] = None):
        """Store crawled page data"""
        try:
            crawled_at = datetime.fromtimestamp(timestamp)
            
            if self.db_type == "sqlite":
                await self.connection.execute("""
                    INSERT OR REPLACE INTO crawled_pages 
                    (url, status_code, title, content_length, crawled_at, error_message)
                    VALUES (?, ?, ?, ?, ?, ?)
                """, (url, status_code, title, content_length, crawled_at, error))
                await self.connection.commit()
            else:
                await self.connection.execute("""
                    INSERT INTO crawled_pages 
                    (url, status_code, title, content_length, crawled_at, error_message)
                    VALUES ($1, $2, $3, $4, $5, $6)
                    ON CONFLICT (url) DO UPDATE SET
                    status_code = EXCLUDED.status_code,
                    title = EXCLUDED.title,
                    content_length = EXCLUDED.content_length,
                    crawled_at = EXCLUDED.crawled_at,
                    error_message = EXCLUDED.error_message
                """, url, status_code, title, content_length, crawled_at, error)
        except Exception as e:
            self.logger.error(f"Error storing page {url}: {e}")
    
    async def get_crawl_stats(self) -> Dict[str, Any]:
        """Get crawling statistics"""
        try:
            if self.db_type == "sqlite":
                cursor = await self.connection.execute("""
                    SELECT 
                        COUNT(*) as total_pages,
                        COUNT(CASE WHEN status_code = 200 THEN 1 END) as successful_pages,
                        COUNT(CASE WHEN status_code != 200 THEN 1 END) as failed_pages,
                        AVG(content_length) as avg_content_length
                    FROM crawled_pages
                """)
                row = await cursor.fetchone()
                return {
                    'total_pages': row[0],
                    'successful_pages': row[1],
                    'failed_pages': row[2],
                    'avg_content_length': row[3]
                }
            else:
                row = await self.connection.fetchrow("""
                    SELECT 
                        COUNT(*) as total_pages,
                        COUNT(CASE WHEN status_code = 200 THEN 1 END) as successful_pages,
                        COUNT(CASE WHEN status_code != 200 THEN 1 END) as failed_pages,
                        AVG(content_length) as avg_content_length
                    FROM crawled_pages
                """)
                return dict(row)
        except Exception as e:
            self.logger.error(f"Error getting stats: {e}")
            return {}
    
    async def search_pages(self, query: str, limit: int = 50):
        """Search pages by title or URL"""
        try:
            search_pattern = f"%{query}%"
            
            if self.db_type == "sqlite":
                cursor = await self.connection.execute("""
                    SELECT url, title, status_code, content_length, crawled_at
                    FROM crawled_pages 
                    WHERE title LIKE ? OR url LIKE ?
                    ORDER BY crawled_at DESC LIMIT ?
                """, (search_pattern, search_pattern, limit))
                return await cursor.fetchall()
            else:
                rows = await self.connection.fetch("""
                    SELECT url, title, status_code, content_length, crawled_at
                    FROM crawled_pages 
                    WHERE title ILIKE $1 OR url ILIKE $1
                    ORDER BY crawled_at DESC LIMIT $2
                """, search_pattern, limit)
                return [dict(row) for row in rows]
        except Exception as e:
            self.logger.error(f"Error searching pages: {e}")
            return []
    
    async def export_urls(self, status_code: Optional[int] = None, filename: str = "urls.txt"):
        """Export URLs to a text file"""
        try:
            if status_code:
                if self.db_type == "sqlite":
                    cursor = await self.connection.execute("SELECT url FROM crawled_pages WHERE status_code = ?", (status_code,))
                    rows = await cursor.fetchall()
                    urls = [row[0] for row in rows]
                else:
                    rows = await self.connection.fetch("SELECT url FROM crawled_pages WHERE status_code = $1", status_code)
                    urls = [row['url'] for row in rows]
            else:
                if self.db_type == "sqlite":
                    cursor = await self.connection.execute("SELECT url FROM crawled_pages")
                    rows = await cursor.fetchall()
                    urls = [row[0] for row in rows]
                else:
                    rows = await self.connection.fetch("SELECT url FROM crawled_pages")
                    urls = [row['url'] for row in rows]
            
            with open(filename, 'w') as f:
                for url in urls:
                    f.write(f"{url}\n")
            
            return len(urls)
        except Exception as e:
            self.logger.error(f"Error exporting URLs: {e}")
            return 0
    
    async def close(self):
        """Close database connection"""
        if self.connection:
            await self.connection.close()
EOF

# crawler.py
cat > crawler.py << 'EOF'
#!/usr/bin/env python3
"""
Nautalis Web Crawler - Main Crawler Module
"""

import asyncio
import aiohttp
import logging
import time
import urllib.robotparser
from urllib.parse import urljoin, urlparse, urlunparse
from typing import Set, List, Optional, Dict
from dataclasses import dataclass
from bs4 import BeautifulSoup

from database import DatabaseManager
from config import CrawlerConfig

@dataclass
class CrawlResult:
    url: str
    status_code: int
    title: str
    content_length: int
    links: List[str]
    timestamp: float
    error: Optional[str] = None

class RobotsChecker:
    def __init__(self):
        self.robots_cache: Dict[str, urllib.robotparser.RobotFileParser] = {}
        self.user_agent = "NautalisBot/1.0"
    
    async def can_fetch(self, session: aiohttp.ClientSession, url: str) -> bool:
        try:
            parsed = urlparse(url)
            domain = f"{parsed.scheme}://{parsed.netloc}"
            
            if domain not in self.robots_cache:
                robots_url = urljoin(domain, '/robots.txt')
                rp = urllib.robotparser.RobotFileParser()
                
                try:
                    async with session.get(robots_url, timeout=aiohttp.ClientTimeout(total=10)) as response:
                        if response.status == 200:
                            robots_content = await response.text()
                            rp.set_url(robots_url)
                            rp.feed(robots_content)
                        else:
                            rp.set_url(robots_url)
                            rp.feed("")
                except Exception:
                    rp.set_url(robots_url)
                    rp.feed("")
                
                self.robots_cache[domain] = rp
            
            return self.robots_cache[domain].can_fetch(self.user_agent, url)
        except Exception:
            return True

class WebCrawler:
    def __init__(self, config: CrawlerConfig):
        self.config = config
        self.db = DatabaseManager(config.database_url, config.database_type)
        self.robots_checker = RobotsChecker()
        
        self.visited_urls: Set[str] = set()
        self.queued_urls: Set[str] = set()
        self.url_queue = asyncio.Queue()
        
        self.stats = {
            'total_crawled': 0,
            'successful': 0,
            'failed': 0,
            'robots_blocked': 0,
            'start_time': time.time()
        }
        
        self.logger = logging.getLogger(__name__)
    
    def normalize_url(self, url: str) -> str:
        parsed = urlparse(url)
        normalized = urlunparse((
            parsed.scheme.lower(),
            parsed.netloc.lower(),
            parsed.path,
            parsed.params,
            parsed.query,
            ''
        ))
        return normalized
    
    def is_valid_url(self, url: str, base_domain: str = None) -> bool:
        try:
            parsed = urlparse(url)
            
            if not parsed.scheme or not parsed.netloc:
                return False
            
            if parsed.scheme not in ['http', 'https']:
                return False
            
            if base_domain and self.config.stay_in_domain:
                if parsed.netloc.lower() != base_domain.lower():
                    return False
            
            skip_extensions = {'.jpg', '.jpeg', '.png', '.gif', '.pdf', '.doc', '.zip', '.mp3', '.mp4'}
            if any(parsed.path.lower().endswith(ext) for ext in skip_extensions):
                return False
            
            return True
        except Exception:
            return False
    
    def extract_links(self, html: str, base_url: str) -> List[str]:
        links = []
        try:
            soup = BeautifulSoup(html, 'html.parser')
            
            for link in soup.find_all('a', href=True):
                href = link['href'].strip()
                if href:
                    absolute_url = urljoin(base_url, href)
                    if self.is_valid_url(absolute_url):
                        links.append(self.normalize_url(absolute_url))
        except Exception as e:
            self.logger.warning(f"Error extracting links from {base_url}: {e}")
        
        return list(set(links))
    
    def extract_title(self, html: str) -> str:
        try:
            soup = BeautifulSoup(html, 'html.parser')
            title_tag = soup.find('title')
            if title_tag:
                return title_tag.get_text().strip()
        except Exception:
            pass
        return ""
    
    async def fetch_url(self, session: aiohttp.ClientSession, url: str, depth: int) -> Optional[CrawlResult]:
        try:
            if not await self.robots_checker.can_fetch(session, url):
                self.stats['robots_blocked'] += 1
                return None
            
            if self.config.delay > 0:
                await asyncio.sleep(self.config.delay)
            
            timeout = aiohttp.ClientTimeout(total=self.config.timeout)
            headers = {'User-Agent': self.config.user_agent}
            
            async with session.get(url, timeout=timeout, headers=headers) as response:
                content_type = response.headers.get('content-type', '').lower()
                if 'text/html' not in content_type:
                    return CrawlResult(
                        url=url, status_code=response.status, title="",
                        content_length=0, links=[], timestamp=time.time()
                    )
                
                html = await response.text()
                title = self.extract_title(html)
                links = self.extract_links(html, url)
                
                if depth < self.config.max_depth:
                    base_domain = urlparse(url).netloc if self.config.stay_in_domain else None
                    
                    for link in links:
                        if (link not in self.visited_urls and 
                            link not in self.queued_urls and
                            self.is_valid_url(link, base_domain)):
                            
                            self.queued_urls.add(link)
                            await self.url_queue.put((link, depth + 1))
                
                return CrawlResult(
                    url=url, status_code=response.status, title=title,
                    content_length=len(html), links=links, timestamp=time.time()
                )
                
        except asyncio.TimeoutError:
            return CrawlResult(
                url=url, status_code=0, title="", content_length=0,
                links=[], timestamp=time.time(), error="Timeout"
            )
        except Exception as e:
            return CrawlResult(
                url=url, status_code=0, title="", content_length=0,
                links=[], timestamp=time.time(), error=str(e)
            )
    
    async def worker(self, session: aiohttp.ClientSession, worker_id: int):
        while True:
            try:
                url, depth = await asyncio.wait_for(self.url_queue.get(), timeout=5.0)
                
                if url in self.visited_urls:
                    self.url_queue.task_done()
                    continue
                
                self.visited_urls.add(url)
                self.logger.info(f"Worker {worker_id}: Crawling {url} (depth: {depth})")
                
                result = await self.fetch_url(session, url, depth)
                
                if result:
                    await self.db.store_page(
                        result.url, result.status_code, result.title,
                        result.content_length, result.timestamp, result.error
                    )
                    
                    if result.status_code == 200:
                        self.stats['successful'] += 1
                    else:
                        self.stats['failed'] += 1
                    
                    self.stats['total_crawled'] += 1
                    
                    if (self.config.max_pages > 0 and 
                        self.stats['total_crawled'] >= self.config.max_pages):
                        break
                
                self.url_queue.task_done()
                
            except asyncio.TimeoutError:
                break
            except Exception as e:
                self.logger.error(f"Worker {worker_id} error: {e}")
                self.url_queue.task_done()
    
    async def crawl(self, seed_urls: List[str]):
        self.logger.info(f"Starting crawl with {len(seed_urls)} seed URLs")
        
        await self.db.initialize()
        
        for url in seed_urls:
            normalized_url = self.normalize_url(url)
            if self.is_valid_url(normalized_url):
                self.queued_urls.add(normalized_url)
                await self.url_queue.put((normalized_url, 0))
        
        connector = aiohttp.TCPConnector(limit=100, limit_per_host=10)
        
        async with aiohttp.ClientSession(connector=connector) as session:
            workers = [
                asyncio.create_task(self.worker(session, i))
                for i in range(self.config.max_workers)
            ]
            
            await asyncio.gather(*workers, return_exceptions=True)
        
        elapsed = time.time() - self.stats['start_time']
        self.logger.info(f"Crawl completed in {elapsed:.2f} seconds")
        self.logger.info(f"Total: {self.stats['total_crawled']}, "
                        f"Success: {self.stats['successful']}, "
                        f"Failed: {self.stats['failed']}")
        
        await self.db.close()
EOF

# analyze.py
cat > analyze.py << 'EOF'
#!/usr/bin/env python3
"""
Nautalis Web Crawler - Analysis Tool
"""

import asyncio
import argparse
from collections import Counter
from urllib.parse import urlparse
from database import DatabaseManager

class CrawlAnalyzer:
    def __init__(self, db_manager: DatabaseManager):
        self.db = db_manager
    
    async def generate_full_report(self):
        print("Generating Nautalis Crawl Analysis Report...")
        print("=" * 60)
        
        stats = await self.db.get_crawl_stats()
        if not stats:
            print("No crawl data found!")
            return
        
        print(f"\n📊 CRAWL STATISTICS")
        print("-" * 30)
        print(f"Total Pages:        {stats.get('total_pages', 0):,}")
        print(f"Successful (200):   {stats.get('successful_pages', 0):,}")
        print(f"Failed/Errors:      {stats.get('failed_pages', 0):,}")
        
        if stats.get('successful_pages', 0) > 0:
            success_rate = (stats['successful_pages'] / stats['total_pages']) * 100
            print(f"Success Rate:       {success_rate:.1f}%")
        
        if stats.get('avg_content_length'):
            avg_size = stats['avg_content_length'] / 1024
            print(f"Avg Page Size:      {avg_size:.1f} KB")
        
        await self._analyze_status_codes()
        await self._analyze_domains()
        
        print(f"\n✅ Analysis complete!")
    
    async def _analyze_status_codes(self):
        print(f"\n🌐 STATUS CODE ANALYSIS")
        print("-" * 30)
        
        if self.db.db_type == "sqlite":
            cursor = await self.db.connection.execute("""
                SELECT status_code, COUNT(*) as count
                FROM crawled_pages
                GROUP BY status_code
                ORDER BY count DESC
            """)
            rows = await cursor.fetchall()
        else:
            rows = await self.db.connection.fetch("""
                SELECT status_code, COUNT(*) as count
                FROM crawled_pages
                GROUP BY status_code
                ORDER BY count DESC
            """)
        
        status_descriptions = {200: "OK", 404: "Not Found", 403: "Forbidden", 500: "Server Error"}
        
        for row in rows:
            if self.db.db_type == "sqlite":
                status_code, count = row
            else:
                status_code, count = row['status_code'], row['count']
            
            desc = status_descriptions.get(status_code, "Unknown")
            print(f"{status_code} ({desc}): {count:,} pages")
    
    async def _analyze_domains(self):
        print(f"\n🌍 DOMAIN ANALYSIS")
        print("-" * 30)
        
        if self.db.db_type == "sqlite":
            cursor = await self.db.connection.execute("SELECT url FROM crawled_pages WHERE status_code = 200")
            rows = await cursor.fetchall()
            urls = [row[0] for row in rows]
        else:
            rows = await self.db.connection.fetch("SELECT url FROM crawled_pages WHERE status_code = 200")
            urls = [row['url'] for row in rows]
        
        domain_counts = Counter()
        for url in urls:
            domain = urlparse(url
