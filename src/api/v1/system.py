from fastapi import APIRouter, BackgroundTasks
import psutil
import socket
import requests
from datetime import datetime

from src.utils.system_monitor import SystemMonitor

router = APIRouter()
monitor = SystemMonitor()

@router.get("/status")
async def get_system_status():
    """Get comprehensive system status"""
    status = {
        "timestamp": datetime.utcnow().isoformat(),
        "system": monitor.get_system_info(),
        "resources": monitor.get_resource_usage(),
        "network": monitor.get_network_info(),
        "storage": monitor.get_storage_info(),
        "api": {
            "status": "operational",
            "uptime": monitor.get_uptime(),
            "requests_processed": monitor.get_request_count()
        }
    }
    
    # Add ISP/ASN info
    try:
        status["isp"] = monitor.get_isp_info()
    except:
        status["isp"] = {"error": "Could not fetch ISP info"}
    
    return status

@router.get("/metrics")
async def get_system_metrics():
    """Get real-time system metrics"""
    return {
        "cpu_percent": psutil.cpu_percent(interval=1),
        "cpu_count": psutil.cpu_count(),
        "memory_percent": psutil.virtual_memory().percent,
        "memory_used_gb": psutil.virtual_memory().used / (1024**3),
        "memory_total_gb": psutil.virtual_memory().total / (1024**3),
        "disk_percent": psutil.disk_usage('/').percent,
        "disk_used_gb": psutil.disk_usage('/').used / (1024**3),
        "disk_total_gb": psutil.disk_usage('/').total / (1024**3),
        "network_sent_mb": psutil.net_io_counters().bytes_sent / (1024**2),
        "network_recv_mb": psutil.net_io_counters().bytes_recv / (1024**2),
        "timestamp": datetime.utcnow().isoformat()
    }

@router.post("/update")
async def update_application(background_tasks: BackgroundTasks):
    """Trigger application update from GitHub"""
    background_tasks.add_task(monitor.update_application)
    return {"message": "Update process started in background"}

@router.get("/logs")
async def get_recent_logs(lines: int = 100):
    """Get recent application logs"""
    logs = monitor.get_recent_logs(lines)
    return {"logs": logs}
