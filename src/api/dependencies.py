from fastapi import Header, HTTPException, Security
from fastapi.security import APIKeyHeader
from config.settings import settings

api_key_header = APIKeyHeader(name=settings.api_key_name, auto_error=False)

async def verify_api_key(api_key: str = Security(api_key_header)):
    if api_key != settings.api_key:
        raise HTTPException(
            status_code=403,
            detail="Invalid or missing API key"
        )
    return api_key
