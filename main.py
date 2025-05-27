#!/usr/bin/env python3
"""
Nautalis Web Crawler - Main Entry Point
High-performance web crawler for search engine indexing
"""

import asyncio
import logging
import sys
from typing import List

from config import parse_arguments, create_default_config
from crawler import WebCrawler
from database import DatabaseManager

def setup_logging(log_level: str, log_file: str = None):
    """Setup logging configuration"""
    level = getattr(logging, log_level.upper())
    
    if log_file:
        logging.basicConfig(
            level=level,
            format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
            handlers=[
                logging.FileHandler(log_file),
                logging.StreamHandler()
            ]
        )
    else:
        logging.basicConfig(
            level=level,
            format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
        )

async def main():
    """Main entry point"""
    try:
        # Parse configuration and seed URLs
        config, seed_urls = parse_arguments()
        
        # Setup logging
        setup_logging(config.log_level, config.log_file)
        logger = logging.getLogger(__name__)
        
        # Validate seed URLs
        if not seed_urls:
            logger.error("No seed URLs provided. Use --seeds to specify URLs to crawl.")
            print("\nExample usage:")
            print("  python main.py --seeds https://example.com https://test.com")
            print("  python main.py --config config.yaml")
            print("\nRun with --help for more options.")
            sys.exit(1)
        
        logger.info(f"Starting Nautalis Web Crawler")
        logger.info(f"Configuration: {config}")
        logger.info(f"Seed URLs: {seed_urls}")
        
        # Initialize and run crawler
        crawler = WebCrawler(config)
        await crawler.crawl(seed_urls)
        
        logger.info("Crawl completed successfully!")
        
    except KeyboardInterrupt:
        logger.info("Crawl interrupted by user")
        sys.exit(0)
    except Exception as e:
        logger.error(f"Fatal error: {e}")
        sys.exit(1)

def print_banner():
    """Print ASCII banner"""
    banner = """
    ╔═══════════════════════════════════════════════════════╗
    ║                                                       ║
    ║    ███╗   ██╗ █████╗ ██╗   ██╗████████╗ █████╗ ██╗   ║
    ║    ████╗  ██║██╔══██╗██║   ██║╚══██╔══╝██╔══██╗██║   ║
    ║    ██╔██╗ ██║███████║██║   ██║   ██║   ███████║██║   ║
    ║    ██║╚██╗██║██╔══██║██║   ██║   ██║   ██╔══██║██║   ║
    ║    ██║ ╚████║██║  ██║╚██████╔╝   ██║   ██║  ██║██║   ║
    ║    ╚═╝  ╚═══╝╚═╝  ╚═╝ ╚═════╝    ╚═╝   ╚═╝  ╚═╝╚═╝   ║
    ║                                                       ║
    ║           High-Performance Web Crawler v1.0          ║
    ║              Built for Search Engines                ║
    ║                                                       ║
    ╚═══════════════════════════════════════════════════════╝
    """
    print(banner)

if __name__ == "__main__":
    print_banner()
    
    # Handle special commands
    if len(sys.argv) > 1:
        if sys.argv[1] == "create-config":
            create_default_config()
            sys.exit(0)
        elif sys.argv[1] == "stats":
            # Show database statistics
            asyncio.run(show_stats())
            sys.exit(0)
    
    # Run main crawler
    asyncio.run(main())

async def show_stats():
    """Show crawling statistics"""
    try:
        # Try to load config to get database settings
        from config import CrawlerConfig
        config = CrawlerConfig()
        
        db = DatabaseManager(config.database_url, config.database_type)
        await db.initialize()
        
        stats = await db.get_crawl_stats()
        
        print("\n" + "="*50)
        print("           NAUTALIS CRAWL STATISTICS")
        print("="*50)
        
        if stats:
            print(f"Total Pages Crawled: {stats.get('total_pages', 0):,}")
            print(f"Successful (200 OK): {stats.get('successful_pages', 0):,}")
            print(f"Failed/Errors:       {stats.get('failed_pages', 0):,}")
            
            if stats.get('avg_content_length'):
                avg_size = stats['avg_content_length'] / 1024  # Convert to KB
                print(f"Average Page Size:   {avg_size:.1f} KB")
            
            if stats.get('first_crawl'):
                print(f"First Crawl:         {stats['first_crawl']}")
            if stats.get('last_crawl'):
                print(f"Last Crawl:          {stats['last_crawl']}")
        else:
            print("No crawl data found in database.")
        
        print("="*50)
        
        await db.close()
        
    except Exception as e:
        print(f"Error reading database: {e}")
        print("Make sure you have crawled some pages first!")
