#!/usr/bin/env python3
"""
Nautalis Web Crawler - Analysis and Reporting Tool
Analyze crawled data and generate reports
"""

import asyncio
import argparse
import json
from collections import Counter, defaultdict
from urllib.parse import urlparse
from database import DatabaseManager
from config import CrawlerConfig

class CrawlAnalyzer:
    """Analyze crawled data and generate reports"""
    
    def __init__(self, db_manager: DatabaseManager):
        self.db = db_manager
    
    async def generate_full_report(self):
        """Generate comprehensive crawl report"""
        print("Generating Nautalis Crawl Analysis Report...")
        print("=" * 60)
        
        # Basic statistics
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
        
        # Status code breakdown
        await self._analyze_status_codes()
        
        # Domain analysis
        await self._analyze_domains()
        
        # Common errors
        await self._analyze_errors()
        
        # Top pages by size
        await self._analyze_page_sizes()
        
        print(f"\n✅ Analysis complete!")
    
    async def _analyze_status_codes(self):
        """Analyze HTTP status code distribution"""
        print(f"\n🌐 STATUS CODE ANALYSIS")
        print("-" * 30)
        
        # Get status code counts
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
        
        status_descriptions = {
            200: "OK",
            301: "Moved Permanently", 
            302: "Found (Redirect)",
            403: "Forbidden",
            404: "Not Found",
            500: "Internal Server Error",
            503: "Service Unavailable"
        }
        
        for row in rows:
            if self.db.db_type == "sqlite":
                status_code, count = row
            else:
                status_code, count = row['status_code'], row['count']
            
            desc = status_descriptions.get(status_code, "Unknown")
            print(f"{status_code} ({desc}): {count:,} pages")
    
    async def _analyze_domains(self):
        """Analyze domain distribution"""
        print(f"\n🌍 DOMAIN ANALYSIS")
        print("-" * 30)
        
        if self.db.db_type == "sqlite":
            cursor = await self.db.connection.execute("""
                SELECT url FROM crawled_pages WHERE status_code = 200
            """)
            rows = await cursor.fetchall()
            urls = [row[0] for row in rows]
        else:
            rows = await self.db.connection.fetch("""
                SELECT url FROM crawled_pages WHERE status_code = 200
            """)
            urls = [row['url'] for row in rows]
        
        domain_counts = Counter()
        for url in urls:
            domain = urlparse(url).netloc
            domain_counts[domain] += 1
        
        print("Top domains crawled:")
        for domain, count in domain_counts.most_common(10):
            print(f"  {domain}: {count:,} pages")
    
    async def _analyze_errors(self):
        """Analyze common errors"""
        print(f"\n❌ ERROR ANALYSIS")
        print("-" * 30)
        
        if self.db.db_type == "sqlite":
            cursor = await self.db.connection.execute("""
                SELECT error_message, COUNT(*) as count
                FROM crawled_pages
                WHERE error_message IS NOT NULL
                GROUP BY error_message
                ORDER BY count DESC
                LIMIT 10
            """)
            rows = await cursor.fetchall()
        else:
            rows = await self.db.connection.fetch("""
                SELECT error_message, COUNT(*) as count
                FROM crawled_pages
                WHERE error_message IS NOT NULL
                GROUP BY error_message
                ORDER BY count DESC
                LIMIT 10
            """)
        
        if rows:
            print("Most common errors:")
            for row in rows:
                if self.db.db_type == "sqlite":
                    error_msg, count = row
                else:
                    error_msg, count = row['error_message'], row['count']
                print(f"  {error_msg[:50]}...: {count} times")
        else:
            print("No errors recorded!")
    
    async def _analyze_page_sizes(self):
        """Analyze page sizes"""
        print(f"\n📏 PAGE SIZE ANALYSIS")
        print("-" * 30)
        
        if self.db.db_type == "sqlite":
            cursor = await self.db.connection.execute("""
                SELECT url, title, content_length
                FROM crawled_pages
                WHERE status_code = 200 AND content_length > 0
                ORDER BY content_length DESC
                LIMIT 10
            """)
            rows = await cursor.fetchall()
        else:
            rows = await self.db.connection.fetch("""
                SELECT url, title, content_length
                FROM crawled_pages
                WHERE status_code = 200 AND content_length > 0
                ORDER BY content_length DESC
                LIMIT 10
            """)
        
        if rows:
            print("Largest pages:")
            for row in rows:
                if self.db.db_type == "sqlite":
                    url, title, size = row
                else:
                    url, title, size = row['url'], row['title'], row['content_length']
                
                size_kb = size / 1024
                title_short = (title[:40] + "...") if len(title) > 40 else title
                print(f"  {size_kb:6.1f} KB - {title_short}")
                print(f"             {url}")
    
    async def export_successful_urls(self, filename: str = "successful_urls.txt"):
        """Export all successful URLs"""
        count = await self.db.export_urls(status_code=200, filename=filename)
        print(f"Exported {count} successful URLs to {filename}")
    
    async def export_failed_urls(self, filename: str = "failed_urls.txt"):
        """Export all failed URLs"""
        if self.db.db_type == "sqlite":
            cursor = await self.db.connection.execute("""
                SELECT url, status_code, error_message
                FROM crawled_pages
                WHERE status_code != 200
            """)
            rows = await cursor.fetchall()
        else:
            rows = await self.db.connection.fetch("""
                SELECT url, status_code, error_message
                FROM crawled_pages
                WHERE status_code != 200
            """)
        
        with open(filename, 'w') as f:
            f.write("URL\tStatus Code\tError\n")
            for row in rows:
                if self.db.db_type == "sqlite":
                    url, status, error = row
                else:
                    url, status, error = row['url'], row['status_code'], row['error_message']
                
                error = error or ""
                f.write(f"{url}\t{status}\t{error}\n")
        
        print(f"Exported {len(rows)} failed URLs to {filename}")
    
    async def search_pages(self, query: str):
        """Search crawled pages"""
        results = await self.db.search_pages(query, limit=20)
        
        print(f"\n🔍 SEARCH RESULTS for '{query}'")
        print("-" * 50)
        
        if not results:
            print("No results found.")
            return
        
        for i, result in enumerate(results, 1):
            if self.db.db_type == "sqlite":
                url, title, status, size, crawled_at = result
            else:
                url, title, status, size, crawled_at = (
                    result['url'], result['title'], result['status_code'],
                    result['content_length'], result['crawled_at']
                )
            
            print(f"{i:2}. {title or '(No title)'}")
            print(f"    URL: {url}")
            print(f"    Status: {status}, Size: {size/1024:.1f}KB, Crawled: {crawled_at}")
            print()

async def main():
    """Main analysis function"""
    parser = argparse.ArgumentParser(description="Nautalis Crawl Data Analyzer")
    parser.add_argument("--db", default="nautalis.db", help="Database file/URL")
    parser.add_argument("--db-type", choices=["sqlite", "postgresql"], default="sqlite")
    parser.add_argument("--report", action="store_true", help="Generate full report")
    parser.add_argument("--export-success", help="Export successful URLs to file")
    parser.add_argument("--export-failed", help="Export failed URLs to file")
    parser.add_argument("--search", help="Search pages by title/URL")
    
    args = parser.parse_args()
    
    # Initialize database
    db = DatabaseManager(args.db, args.db_type)
    await db.initialize()
    
    analyzer = CrawlAnalyzer(db)
    
    try:
        if args.report:
            await analyzer.generate_full_report()
        
        if args.export_success:
            await analyzer.export_successful_urls(args.export_success)
        
        if args.export_failed:
            await analyzer.export_failed_urls(args.export_failed)
        
        if args.search:
            await analyzer.search_pages(args.search)
        
        if not any([args.report, args.export_success, args.export_failed, args.search]):
            # Default: show basic stats
            stats = await db.get_crawl_stats()
            if stats:
                print(f"Database contains {stats.get('total_pages', 0):,} crawled pages")
                print("Use --report for detailed analysis")
            else:
                print("No crawl data found in database")
    
    finally:
        await db.close()

if __name__ == "__main__":
    asyncio.run(main())
