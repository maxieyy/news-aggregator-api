import os
from pathlib import Path
from typing import Optional
from pydantic_settings import BaseSettings

BASE_DIR = Path(__file__).resolve().parent.parent

class Settings(BaseSettings):
    # API
    api_key: str
    api_key_name: str = "X-API-Key"
    secret_key: str
    debug: bool = False
    
    # Database
    database_url: str = f"sqlite:///{BASE_DIR}/news.db"
    
    # Redis
    redis_url: str = "redis://localhost:6379/0"
    
    # AI
    openai_api_key: Optional[str] = None
    openai_model: str = "gpt-3.5-turbo-1106"
    ai_summarize: bool = True
    
    # Storage
    media_storage_path: Path = BASE_DIR / "storage" / "media"
    cache_path: Path = BASE_DIR / "storage" / "cache"
    
    # Server
    host: str = "0.0.0.0"
    port: int = 8000
    domain: str = "https://news.devmaxwell.site"
    
    # Security
    fetch_delay: float = 1.0
    max_concurrent_fetches: int = 5
    
    class Config:
        env_file = BASE_DIR / ".env"

settings = Settings()
