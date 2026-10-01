"""
metrics.py — collects raw system/infrastructure facts.
No web-framework code lives here on purpose.
"""
import socket     # gives us access to hostname info
import platform   # gives us access to OS name/version info
import psutil     # third-party library for CPU/memory stats

def get_hostname() -> str:
    """Return this machine's hostname (e.g. "app-server")."""
    # socket module has a build-in function for exactly this
    return socket.gethostname()

def get_os_info() -> str:
    """Return a human-readable OS description, e.g. "Linux 5.15.0-generic."""
    # platform.system() returns the OS name (e.g. "Linux"), and platform.release() returns the kernel version (e.g. "5.15.0-generic")
    # combine both into one readbale string
    return f"{platform.system()} {platform.release()}"

def get_cpu_info() -> dict:
    """Return CPU detials: how many cores, and how busy it is right now."""
    return {
        "cores_count": psutil.cpu_count(logical=True),  # logical=True counts hyperthreaded cores too
        "usage_percent": psutil.cpu_percent(interval=1)  # measure CPU usage over a 1-second interval
    }

def get_memory_info() -> dict:
    """Return memory detials: total, used, and percent used in MB."""
    # psutil gives memory in raw bytes, so we grab it once and convert below
    mem =  psutil.virtual_memory()
    return {
        # bytes -> MB: divide by 1024*1024, roun to 2 decimals for readability
        "total_mb": round(mem.total / (1024 * 1024), 2),
        "used_mb": round(mem.used / (1024 * 1024), 2),
        "percent_used": mem.percent # psutil already gives us a percentage, so no conversion needed
    }

def collect_all() -> dict: 
    """
    Bundle everything into one dict, this is the only function
    main.py will ever call. Everything above is a private helper.
    """
    return {
        "hostname": get_hostname(),
        "os": get_os_info(),
        "cpu": get_cpu_info(),
        "memory": get_memory_info()
    }

