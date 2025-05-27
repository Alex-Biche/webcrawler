#!/usr/bin/env python3
"""
Nautalis Web Crawler - High Performance Production Crawler
Main crawler module with async crawling capabilities
"""

import asyncio
import aiohttp
import logging
import time
import urllib.robotparser
from urllib.parse import urljoin, urlparse, urlunparse
from typing import Set, List, Optional, Dict, Tuple
from dataclasses import dataclass
from bs4 import BeautifulSoup
import re

from database import DatabaseManager
from config import CrawlerConfig

@dataclass
class CrawlResult:
    """Container for crawl results"""
    url: str
    status_code: int
    title: str
    content_length: int
    links: List[str]
    timestamp: float
    error: Optional[str] = None

class RobotsChecker:
    """Manages robots.txt checking for domains"""
    
    def __init__(self):
        self.robots_cache: Dict[str, urllib.robotparser.RobotFileParser] = {}
        self.user_agent = "NautalisBot/1.0"
    
    async def can_fetch(self, session: aiohttp.ClientSession, url: str) -> bool:
        """Check if URL can be fetched according to robots.txt"""
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
                            # If robots.txt doesn't exist, allow all
                            rp.set_url(robots_url)
                            rp.feed("")
                except Exception:
                    # If we can't fetch robots.txt, be conservative and allow
                    rp.set_url(robots_url)
                    rp.feed("")
                
                self.robots_cache[domain] = rp
            
            return self.robots_cache[domain].can_fetch(self.user_agent, url)
        except Exception as e:
            logging.warning(f"Error checking robots.txt for {url}: {e}")
            return True  # Default to allowing if check fails

class WebCrawler:
    """High-performance async web crawler"""
    
    def __init__(self, config: CrawlerConfig):
        self.config = config
        self.db = DatabaseManager(config.database_url, config.database_type)
        self.robots_checker = RobotsChecker()
        
        # URL tracking
        self.visited_urls: Set[str] = set()
        self.queued_urls: Set[str] = set()
        self.url_queue = asyncio.Queue()
        
        # Statistics
        self.stats = {
            'total_crawled': 0,
            'successful': 0,
            'failed': 0,
            'robots_blocked': 0,
            'start_time': time.time()
        }
        
        # Setup logging
        logging.basicConfig(
            level=logging.INFO,
            format='%(asctime)s - %(levelname)s - %(message)s'
        )
        self.logger = logging.getLogger(__name__)
    
    def normalize_url(self, url: str) -> str:
        """Normalize URL for deduplication"""
        parsed = urlparse(url)
        # Remove fragment and normalize
        normalized = urlunparse((
            parsed.scheme.lower(),
            parsed.netloc.lower(),
            parsed.path,
            parsed.params,
            parsed.query,
            ''  # Remove fragment
        ))
        return normalized
    
    def is_valid_url(self, url: str, base_domain: str = None) -> bool:
        """Check if URL is valid for crawling"""
        try:
            parsed = urlparse(url)
            
            # Must have scheme and netloc
            if not parsed.scheme or not parsed.netloc:
                return False
            
            # Only HTTP/HTTPS
            if parsed.scheme not in ['http', 'https']:
                return False
            
            # Domain restriction check
            if base_domain and self.config.stay_in_domain:
                if parsed.netloc.lower() != base_domain.lower():
                    return False
            
            # Skip common non-content files
            skip_extensions = {
                '.jpg', '.jpeg', '.png', '.gif', '.bmp', '.ico',
                '.pdf', '.doc', '.docx', '.xls', '.xlsx', '.zip',
                '.tar', '.gz', '.mp3', '.mp4', '.avi', '.mov'
            }
            
            path_lower = parsed.path.lower()
            if any(path_lower.endswith(ext) for ext in skip_extensions):
                return False
            
            return True
            
        except Exception:
            return False
    
    def extract_links(self, html: str, base_url: str) -> List[str]:
        """Extract all links from HTML content"""
        links = []
        try:
            soup = BeautifulSoup(html, 'html.parser')
            
            # Extract from <a> tags
            for link in soup.find_all('a', href=True):
                href = link['href'].strip()
                if href:
                    absolute_url = urljoin(base_url, href)
                    if self.is_valid_url(absolute_url):
                        links.append(self.normalize_url(absolute_url))
            
            # Extract from <link> tags (for resources)
            for link in soup.find_all('link', href=True):
                href = link['href'].strip()
                if href:
                    absolute_url = urljoin(base_url, href)
                    if self.is_valid_url(absolute_url):
                        links.append(self.normalize_url(absolute_url))
        
        except Exception as e:
            self.logger.warning(f"Error extracting links from {base_url}: {e}")
        
        return list(set(links))  # Deduplicate
    
    def extract_title(self, html: str) -> str:
        """Extract page title from HTML"""
        try:
            soup = BeautifulSoup(html, 'html.parser')
            title_tag = soup.find('title')
            if title_tag:
                return title_tag.get_text().strip()
        except Exception:
            pass
        return ""
    
    async def fetch_url(self, session: aiohttp.ClientSession, url: str, depth: int) -> Optional[CrawlResult]:
        """Fetch a single URL and extract data"""
        try:
            # Check robots.txt
            if not await self.robots_checker.can_fetch(session, url):
                self.stats['robots_blocked'] += 1
                self.logger.info(f"Blocked by robots.txt: {url}")
                return None
            
            # Apply delay
            if self.config.delay > 0:
                await asyncio.sleep(self.config.delay)
            
            timeout = aiohttp.ClientTimeout(total=self.config.timeout)
            headers = {
                'User-Agent': 'NautalisBot/1.0 (+https://nautalis.search)'
            }
            
            async with session.get(url, timeout=timeout, headers=headers) as response:
                # Only process HTML content
                content_type = response.headers.get('content-type', '').lower()
                if 'text/html' not in content_type:
                    return CrawlResult(
                        url=url,
                        status_code=response.status,
                        title="",
                        content_length=0,
                        links=[],
                        timestamp=time.time()
                    )
                
                html = await response.text()
                title = self.extract_title(html)
                links = self.extract_links(html, url)
                
                # Add new links to queue if within depth limit
                if depth < self.config.max_depth:
                    base_domain = urlparse(url).netloc if self.config.stay_in_domain else None
                    
                    for link in links:
                        if (link not in self.visited_urls and 
                            link not in self.queued_urls and
                            self.is_valid_url(link, base_domain)):
                            
                            self.queued_urls.add(link)
                            await self.url_queue.put((link, depth + 1))
                
                return CrawlResult(
                    url=url,
                    status_code=response.status,
                    title=title,
                    content_length=len(html),
                    links=links,
                    timestamp=time.time()
                )
                
        except asyncio.TimeoutError:
            self.logger.warning(f"Timeout fetching {url}")
            return CrawlResult(
                url=url, status_code=0, title="", content_length=0,
                links=[], timestamp=time.time(), error="Timeout"
            )
        except Exception as e:
            self.logger.warning(f"Error fetching {url}: {e}")
            return CrawlResult(
                url=url, status_code=0, title="", content_length=0,
                links=[], timestamp=time.time(), error=str(e)
            )
    
    async def worker(self, session: aiohttp.ClientSession, worker_id: int):
        """Worker coroutine to process URLs from queue"""
        while True:
            try:
                # Get URL from queue with timeout
                url, depth = await asyncio.wait_for(
                    self.url_queue.get(), timeout=5.0
                )
                
                if url in self.visited_urls:
                    self.url_queue.task_done()
                    continue
                
                self.visited_urls.add(url)
                self.logger.info(f"Worker {worker_id}: Crawling {url} (depth: {depth})")
                
                result = await self.fetch_url(session, url, depth)
                
                if result:
                    # Store in database
                    await self.db.store_page(
                        result.url,
                        result.status_code,
                        result.title,
                        result.content_length,
                        result.timestamp,
                        result.error
                    )
                    
                    if result.status_code == 200:
                        self.stats['successful'] += 1
                    else:
                        self.stats['failed'] += 1
                    
                    self.stats['total_crawled'] += 1
                    
                    # Check if we've hit the max pages limit
                    if (self.config.max_pages > 0 and 
                        self.stats['total_crawled'] >= self.config.max_pages):
                        break
                
                self.url_queue.task_done()
                
            except asyncio.TimeoutError:
                # No more URLs in queue, worker can exit
                break
            except Exception as e:
                self.logger.error(f"Worker {worker_id} error: {e}")
                self.url_queue.task_done()
    
    async def crawl(self, seed_urls: List[str]):
        """Main crawl method"""
        self.logger.info(f"Starting crawl with {len(seed_urls)} seed URLs")
        self.logger.info(f"Config: max_depth={self.config.max_depth}, "
                        f"max_pages={self.config.max_pages}, "
                        f"workers={self.config.max_workers}")
        
        # Initialize database
        await self.db.initialize()
        
        # Add seed URLs to queue
        for url in seed_urls:
            normalized_url = self.normalize_url(url)
            if self.is_valid_url(normalized_url):
                self.queued_urls.add(normalized_url)
                await self.url_queue.put((normalized_url, 0))
        
        # Create HTTP session with connection pooling
        connector = aiohttp.TCPConnector(
            limit=100,
            limit_per_host=10,
            ttl_dns_cache=300,
            use_dns_cache=True
        )
        
        async with aiohttp.ClientSession(connector=connector) as session:
            # Start worker tasks
            workers = [
                asyncio.create_task(self.worker(session, i))
                for i in range(self.config.max_workers)
            ]
            
            # Wait for all workers to complete
            await asyncio.gather(*workers, return_exceptions=True)
        
        # Print final statistics
        elapsed = time.time() - self.stats['start_time']
        self.logger.info(f"Crawl completed in {elapsed:.2f} seconds")
        self.logger.info(f"Total crawled: {self.stats['total_crawled']}")
        self.logger.info(f"Successful: {self.stats['successful']}")
        self.logger.info(f"Failed: {self.stats['failed']}")
        self.logger.info(f"Robots blocked: {self.stats['robots_blocked']}")
        self.logger.info(f"Pages per second: {self.stats['total_crawled']/elapsed:.2f}")
        
        await self.db.close()

if __name__ == "__main__":
    # This will be handled by main.py
    pass
