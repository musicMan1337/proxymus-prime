#!/usr/bin/env python3
import requests
import time
import sys
import urllib3

# Disable SSL warnings for self-signed certificates in testing
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

def check_services():
    """Check if all services are healthy before running tests"""

    # Check NGINX proxy
    try:
        response = requests.get('https://localhost', verify=False, timeout=5)
        print(f"✅ NGINX proxy: {response.status_code}")
    except Exception as e:
        print(f"❌ NGINX proxy failed: {e}")
        return False

    # Check backend servers directly
    for port in [8081, 8082, 8083]:
        try:
            response = requests.get(f'http://localhost:{port}', timeout=5)
            print(f"✅ Backend {port}: {response.status_code}")
        except Exception as e:
            print(f"❌ Backend {port} failed: {e}")
            return False

    # Check Redis (via backend)
    try:
        response = requests.get('https://localhost/health', verify=False, timeout=5)
        print(f"✅ Health endpoint: {response.status_code}")
    except Exception as e:
        print(f"⚠️  Health endpoint: {e}")

    return True

if __name__ == "__main__":
    if not check_services():
        print("❌ Service health check failed!")
        sys.exit(1)
    print("✅ All services healthy!")
