#!/usr/bin/env python3
"""
Nautalis Web Crawler - Configuration Module
Handles configuration loading from YAML and CLI arguments
"""

import yaml
import argparse
from dataclasses import dataclass
from typing import List, Optional
import os

@dataclass
class CrawlerConfig:
    """Configuration container for the crawler"""
    # Crawling behavior
    max_depth: int = 3
    max_pages: int = 1000
    max_workers: int = 10
    stay_in_domain: bool = True
    delay: float = 0.5  # Seconds between requests
    timeout: int = 30   # Request timeout in seconds
    
    # Database settings
    database_type: str = "sqlite"  # sqlite or postgresql
    database_url: str = "nautalis.db"
    
    # Retry settings
    max_retries: int = 3
    retry_delay: float = 1.0
    
    # User agent
    user_agent: str = "NautalisBot/1.0 (+https://nautalis.search)"
    
    # Logging
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
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Basic crawl with seed URLs
  python main.py --seeds https://example.com https://test.com
  
  # Deep crawl with custom settings
  python main.py --seeds https://example.com --depth 5 --max-pages 5000 --workers 20
  
  # Use PostgreSQL database
  python main.py --seeds https://example.com --db postgresql://user:pass@localhost/nautalis
  
  # Load from config file
  python main.py --config config.yaml
        """
    )
    
    # Seed URLs
    parser.add_argument(
        '--seeds',
        nargs='+',
        help='Seed URLs to start crawling from',
        default=[]
    )
    
    # Configuration file
    parser.add_argument(
        '--config',
        type=str,
        help='Path to YAML configuration file',
        default='config.yaml'
    )
    
    # Crawling parameters
    parser.add_argument(
        '--depth',
        type=int,
        help='Maximum crawl depth (default: 3)',
        default=None
    )
    
    parser.add_argument(
        '--max-pages',
        type=int,
        help='Maximum number of pages to crawl (default: 1000)',
        default=None
    )
    
    parser.add_argument(
        '--workers',
        type=int,
        help='Number of concurrent workers (default: 10)',
        default=None
    )
    
    parser.add_argument(
        '--delay',
        type=float,
        help='Delay between requests in seconds (default: 0.5)',
        default=None
    )
    
    parser.add_argument(
        '--timeout',
        type=int,
        help='Request timeout in seconds (default: 30)',
        default=None
    )
    
    # Database settings
    parser.add_argument(
        '--db',
        type=str,
        help='Database URL (SQLite file or PostgreSQL connection string)',
        default=None
    )
    
    parser.add_argument(
        '--db-type',
        choices=['sqlite', 'postgresql'],
        help='Database type (default: sqlite)',
        default=None
    )
    
    # Behavior flags
    parser.add_argument(
        '--allow-external',
        action='store_true',
        help='Allow crawling external domains (default: stay in same domain)',
        default=False
    )
    
    # Logging
    parser.add_argument(
        '--log-level',
        choices=['DEBUG', 'INFO', 'WARNING', 'ERROR'],
        help='Logging level (default: INFO)',
        default=None
    )
    
    parser.add_argument(
        '--log-file',
        type=str,
        help='Path to log file (default: log to console)',
        default=None
    )
    
    args = parser.parse_args()
    
    # Load base configuration from file if it exists
    if os.path.exists(args.config):
        config = load_config_from_yaml(args.config)
    else:
        config = CrawlerConfig()
    
    # Override with command line arguments
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
        # Auto-detect database type from URL
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

def create_default_config():
    """Create a default config.yaml file"""
    default_config = {
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
        'log_file': None
    }
    
    with open('config.yaml', 'w') as f:
        yaml.dump(default_config, f, default_flow_style=False, indent=2)
    
    print("Created default config.yaml file")

if __name__ == "__main__":
    create_default_config()
