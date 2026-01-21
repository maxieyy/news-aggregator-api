from fastapi import APIRouter, HTTPException, BackgroundTasks
from typing import List, Optional
import yaml
from pathlib import Path

from src.models.source import Source, SourceCreate, SourceUpdate, SourceResponse
from src.core.fetcher import SourceManager
from src.db import crud
from config.settings import settings

router = APIRouter()
source_manager = SourceManager()

@router.get("/", response_model=List[SourceResponse])
async def get_sources(active_only: bool = True):
    """Get all configured sources"""
    sources = source_manager.get_sources(active_only)
    return sources

@router.get("/{source_id}", response_model=SourceResponse)
async def get_source(source_id: str):
    """Get specific source details"""
    source = source_manager.get_source(source_id)
    if not source:
        raise HTTPException(status_code=404, detail="Source not found")
    return source

@router.post("/", response_model=SourceResponse)
async def add_source(source: SourceCreate, background_tasks: BackgroundTasks):
    """Add a new source"""
    # Check if source already exists
    existing = source_manager.get_source(source.id)
    if existing:
        raise HTTPException(status_code=400, detail="Source already exists")
    
    # Add to YAML config
    sources_file = Path(__file__).parent.parent.parent / "config" / "sources.yaml"
    with open(sources_file, 'r') as f:
        sources_data = yaml.safe_load(f) or {}
    
    sources_data[source.id] = source.dict()
    
    with open(sources_file, 'w') as f:
        yaml.dump(sources_data, f, default_flow_style=False)
    
    # Trigger immediate fetch
    background_tasks.add_task(source_manager.fetch_source, source.id)
    
    return source

@router.put("/{source_id}", response_model=SourceResponse)
async def update_source(source_id: str, source_update: SourceUpdate):
    """Update source configuration"""
    updated_source = source_manager.update_source(source_id, source_update.dict(exclude_unset=True))
    if not updated_source:
        raise HTTPException(status_code=404, detail="Source not found")
    return updated_source

@router.delete("/{source_id}")
async def delete_source(source_id: str):
    """Delete a source"""
    success = source_manager.delete_source(source_id)
    if not success:
        raise HTTPException(status_code=404, detail="Source not found")
    return {"message": f"Source {source_id} deleted successfully"}

@router.post("/{source_id}/fetch")
async def fetch_source_now(source_id: str):
    """Manually trigger fetch for a source"""
    result = source_manager.fetch_source(source_id)
    if not result:
        raise HTTPException(status_code=404, detail="Source not found or fetch failed")
    return {"message": f"Fetch triggered for {source_id}", "articles_found": len(result)}
