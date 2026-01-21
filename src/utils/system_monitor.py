import psutil
import socket
import requests
import subprocess
import logging
from datetime import datetime
from typing import Dict, Any

logger = logging.getLogger(__name__)

class SystemMonitor:
    def __init__(self):
        self.start_time = datetime.now()
    
    def get_system_info(self) -> Dict[str, Any]:
        """Get basic system information"""
        return {
            "hostname": socket.gethostname(),
            "os": f"{psutil.sys.platform}",
            "python_version": "3.11",
            "processor": psutil.cpu_freq().current if psutil.cpu_freq() else "Unknown",
            "boot_time": datetime.fromtimestamp(psutil.boot_time()).isoformat()
        }
    
    def get_resource_usage(self) -> Dict[str, Any]:
        """Get current resource usage"""
        memory = psutil.virtual_memory()
        swap = psutil.swap_memory()
        
        return {
            "cpu": {
                "percent": psutil.cpu_percent(interval=1),
                "count": psutil.cpu_count(logical=False),
                "count_logical": psutil.cpu_count(logical=True)
            },
            "memory": {
                "total_gb": round(memory.total / (1024**3), 2),
                "available_gb": round(memory.available / (1024**3), 2),
                "used_gb": round(memory.used / (1024**3), 2),
                "percent": memory.percent
            },
            "swap": {
                "total_gb": round(swap.total / (1024**3), 2),
                "used_gb": round(swap.used / (1024**3), 2),
                "percent": swap.percent
            }
        }
    
    def get_network_info(self) -> Dict[str, Any]:
        """Get network information including public IP"""
        try:
            # Get public IP
            response = requests.get('https://api.ipify.org?format=json', timeout=5)
            public_ip = response.json()['ip']
            
            # Get ISP/ASN info
            ip_info = requests.get(f'https://ipapi.co/{public_ip}/json/', timeout=5).json()
            
            return {
                "public_ip": public_ip,
                "isp": ip_info.get('org', 'Unknown'),
                "asn": ip_info.get('asn', 'Unknown'),
                "city": ip_info.get('city', 'Unknown'),
                "country": ip_info.get('country_name', 'Unknown'),
                "hostname": socket.gethostname(),
                "local_ip": socket.gethostbyname(socket.gethostname())
            }
        except Exception as e:
            logger.error(f"Failed to get network info: {e}")
            return {"error": str(e)}
    
    def get_storage_info(self) -> Dict[str, Any]:
        """Get storage information"""
        storage = []
        for partition in psutil.disk_partitions():
            try:
                usage = psutil.disk_usage(partition.mountpoint)
                storage.append({
                    "device": partition.device,
                    "mountpoint": partition.mountpoint,
                    "fstype": partition.fstype,
                    "total_gb": round(usage.total / (1024**3), 2),
                    "used_gb": round(usage.used / (1024**3), 2),
                    "free_gb": round(usage.free / (1024**3), 2),
                    "percent": usage.percent
                })
            except:
                continue
        
        return {"partitions": storage}
    
    def get_uptime(self) -> str:
        """Get system and application uptime"""
        system_uptime = datetime.now() - datetime.fromtimestamp(psutil.boot_time())
        app_uptime = datetime.now() - self.start_time
        
        return {
            "system": str(system_uptime).split('.')[0],
            "application": str(app_uptime).split('.')[0]
        }
    
    def get_request_count(self) -> int:
        """Get total requests processed (placeholder)"""
        # Implement your request counter logic here
        return 0
    
    def get_isp_info(self) -> Dict[str, Any]:
        """Get detailed ISP/ASN information"""
        try:
            response = requests.get('https://api.ipify.org?format=json', timeout=5)
            public_ip = response.json()['ip']
            
            # Use ipapi.co for detailed info
            details = requests.get(f'https://ipapi.co/{public_ip}/json/', timeout=10).json()
            
            return {
                "ip": public_ip,
                "isp": details.get('org', 'Unknown'),
                "asn": details.get('asn', 'Unknown'),
                "asn_name": details.get('asn', 'Unknown').split()[0] if details.get('asn') else 'Unknown',
                "city": details.get('city', 'Unknown'),
                "region": details.get('region', 'Unknown'),
                "country": details.get('country_name', 'Unknown'),
                "latitude": details.get('latitude'),
                "longitude": details.get('longitude'),
                "timezone": details.get('timezone', 'Unknown')
            }
        except Exception as e:
            return {"error": str(e)}
    
    def update_application(self):
        """Update application from GitHub"""
        try:
            # Pull latest changes
            subprocess.run(['git', 'pull', 'origin', 'main'], check=True)
            
            # Install dependencies
            subprocess.run(['pip', 'install', '-r', 'requirements.txt'], check=True)
            
            # Restart application
            subprocess.run(['systemctl', 'restart', 'news-api'], check=True)
            
            logger.info("Application updated successfully")
            return True
        except subprocess.CalledProcessError as e:
            logger.error(f"Update failed: {e}")
            return False
    
    def get_recent_logs(self, lines: int = 100) -> list:
        """Get recent application logs"""
        try:
            # Assuming logs are in /var/log/news-api.log
            with open('/var/log/news-api.log', 'r') as f:
                log_lines = f.readlines()[-lines:]
            return log_lines
        except:
            return ["Log file not available"]
