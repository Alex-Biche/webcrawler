#!/usr/bin/env python3
"""
Nautalis Web Crawler - Database Module
Handles SQLite and PostgreSQL storage with async support
"""

import asyncio
import aiosqlite
import asyncpg
import logging
from typing import Optional, Dict, Any
from datetime import datetime

class DatabaseManager:
    """Manages database operations for both SQLite and PostgreSQL"""
    
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
        await self.connection.execute("PRAGMA cache_size=10000")
        await self.connection.execute("PRAGMA temp_store=MEMORY")
        
        # Create tables
        await self.connection.execute("""
            CREATE TABLE IF NOT EXISTS crawled_pages (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                url TEXT UNIQUE NOT NULL,
                status_code INTEGER NOT NULL,
                title TEXT,
                content_length INTEGER DEFAULT 0,
                crawled_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                error_message TEXT,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        """)
        
        await self.connection.execute("""
            CREATE INDEX IF NOT EXISTS idx_url ON crawled_pages(url)
        """)
        
        await self.connection.execute("""
            CREATE INDEX IF NOT EXISTS idx_status ON crawled_pages(status_code)
        """)
        
        await self.connection.execute("""
            CREATE INDEX IF NOT EXISTS idx_crawled_at ON crawled_pages(crawled_at)
        """)
        
        await self.connection.commit()
        self.logger.info("SQLite database initialized")
    
    async def _init_postgresql(self):
        """Initialize PostgreSQL database"""
        try:
            self.connection = await asyncpg.connect(self.database_url)
            
            # Create tables
            await self.connection.execute("""
                CREATE TABLE IF NOT EXISTS crawled_pages (
                    id SERIAL PRIMARY KEY,
                    url TEXT UNIQUE NOT NULL,
                    status_code INTEGER NOT NULL,
                    title TEXT,
                    content_length INTEGER DEFAULT 0,
                    crawled_at TIMESTAMP DEFAULT NOW(),
                    error_message TEXT,
                    created_at TIMESTAMP DEFAULT NOW()
                )
            """)
            
            # Create indexes
            await self.connection.execute("""
                CREATE INDEX IF NOT EXISTS idx_url ON crawled_pages(url)
            """)
            
            await self.connection.execute("""
                CREATE INDEX IF NOT EXISTS idx_status ON crawled_pages(status_code)
            """)
            
            await self.connection.execute("""
                CREATE INDEX IF NOT EXISTS idx_crawled_at ON crawled_pages(crawled_at)
            """)
            
            self.logger.info("PostgreSQL database initialized")
            
        except Exception as e:
            self.logger.error(f"Failed to initialize PostgreSQL: {e}")
            raise
    
    async def store_page(self, url: str, status_code: int, title: str, 
                        content_length: int, timestamp: float, error: Optional[str] = None):
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
            
            else:  # PostgreSQL
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
                        AVG(content_length) as avg_content_length,
                        MIN(crawled_at) as first_crawl,
                        MAX(crawled_at) as last_crawl
                    FROM crawled_pages
                """)
                row = await cursor.fetchone()
                
                return {
                    'total_pages': row[0],
                    'successful_pages': row[1],
                    'failed_pages': row[2],
                    'avg_content_length': row[3],
                    'first_crawl': row[4],
                    'last_crawl': row[5]
                }
            
            else:  # PostgreSQL
                row = await self.connection.fetchrow("""
                    SELECT 
                        COUNT(*) as total_pages,
                        COUNT(CASE WHEN status_code = 200 THEN 1 END) as successful_pages,
                        COUNT(CASE WHEN status_code != 200 THEN 1 END) as failed_pages,
                        AVG(content_length) as avg_content_length,
                        MIN(crawled_at) as first_crawl,
                        MAX(crawled_at) as last_crawl
                    FROM crawled_pages
                """)
                
                return dict(row)
        
        except Exception as e:
            self.logger.error(f"Error getting stats: {e}")
            return {}
    
    async def get_pages_by_status(self, status_code: int, limit: int = 100):
        """Get pages by status code"""
        try:
            if self.db_type == "sqlite":
                cursor = await self.connection.execute("""
                    SELECT url, title, content_length, crawled_at, error_message
                    FROM crawled_pages 
                    WHERE status_code = ?
                    ORDER BY crawled_at DESC
                    LIMIT ?
                """, (status_code, limit))
                return await cursor.fetchall()
            
            else:  # PostgreSQL
                rows = await self.connection.fetch("""
                    SELECT url, title, content_length, crawled_at, error_message
                    FROM crawled_pages 
                    WHERE status_code = $1
                    ORDER BY crawled_at DESC
                    LIMIT $2
                """, status_code, limit)
                return [dict(row) for row in rows]
        
        except Exception as e:
            self.logger.error(f"Error getting pages by status: {e}")
            return []
    
    async def search_pages(self, query: str, limit: int = 50):
        """Search pages by title or URL"""
        try:
            search_pattern = f"%{query}%"
            
            if self.db_type == "sqlite":
                cursor = await self.connection.execute("""
                    SELECT url, title, status_code, content_length, crawled_at
                    FROM crawled_pages 
                    WHERE title LIKE ? OR url LIKE ?
                    ORDER BY crawled_at DESC
                    LIMIT ?
                """, (search_pattern, search_pattern, limit))
                return await cursor.fetchall()
            
            else:  # PostgreSQL
                rows = await self.connection.fetch("""
                    SELECT url, title, status_code, content_length, crawled_at
                    FROM crawled_pages 
                    WHERE title ILIKE $1 OR url ILIKE $1
                    ORDER BY crawled_at DESC
                    LIMIT $2
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
                    cursor = await self.connection.execute("""
                        SELECT url FROM crawled_pages WHERE status_code = ?
                    """, (status_code,))
                    rows = await cursor.fetchall()
                    urls = [row[0] for row in rows]
                else:
                    rows = await self.connection.fetch("""
                        SELECT url FROM crawled_pages WHERE status_code = $1
                    """, status_code)
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
            
            self.logger.info(f"Exported {len(urls)} URLs to {filename}")
            return len(urls)
        
        except Exception as e:
            self.logger.error(f"Error exporting URLs: {e}")
            return 0
    
    async def close(self):
        """Close database connection"""
        if self.connection:
            await self.connection.close()
            self.logger.info("Database connection closed")
