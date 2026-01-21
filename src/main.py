from fastapi import FastAPI, Depends, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from contextlib import asynccontextmanager
import os

from src.api.dependencies import verify_api_key
from src.api.v1 import articles, sources, system, media
from src.db.database import engine, Base
from src.core.scheduler import start_scheduler, stop_scheduler
from config.settings import settings

@asynccontextmanager
async def lifespan(app: FastAPI):
    # Startup
    print("Starting News Aggregator API...")
    
    # Create database tables
    Base.metadata.create_all(bind=engine)
    
    # Create storage directories
    os.makedirs(settings.media_storage_path / "images", exist_ok=True)
    os.makedirs(settings.media_storage_path / "videos", exist_ok=True)
    os.makedirs(settings.cache_path, exist_ok=True)
    
    # Start scheduler
    start_scheduler()
    
    yield
    
    # Shutdown
    print("Shutting down News Aggregator API...")
    stop_scheduler()

app = FastAPI(
    title="News Aggregator API",
    description="API for fetching, summarizing, and organizing news articles",
    version="1.0.0",
    lifespan=lifespan,
    docs_url="/docs" if settings.debug else None,
    redoc_url="/redoc" if settings.debug else None
)

# CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Mount static files
app.mount("/static", StaticFiles(directory="static"), name="static")

# Health check endpoint (no auth required)
@app.get("/health")
async def health_check():
    return {"status": "healthy", "service": "news-aggregator-api"}

# API endpoints with authentication
app.include_router(
    articles.router,
    prefix="/api/v1/articles",
    tags=["articles"],
    dependencies=[Depends(verify_api_key)]
)

app.include_router(
    sources.router,
    prefix="/api/v1/sources",
    tags=["sources"],
    dependencies=[Depends(verify_api_key)]
)

app.include_router(
    system.router,
    prefix="/api/v1/system",
    tags=["system"],
    dependencies=[Depends(verify_api_key)]
)

app.include_router(
    media.router,
    prefix="/api/v1/media",
    tags=["media"],
    dependencies=[Depends(verify_api_key)]
)

@app.get("/")
async def root():
    return {
        "message": "News Aggregator API",
        "docs": "/docs" if settings.debug else "Disabled in production",
        "version": "1.0.0"
    }
