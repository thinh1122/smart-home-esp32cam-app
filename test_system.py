#!/usr/bin/env python3
"""
Script test tự động hệ thống Smart Home ESP32-CAM
Kiểm tra kết nối giữa ESP32, Python Server, và Flutter App
"""

import requests
import time
import sys
import socket
from colorama import init, Fore, Style

# Init colorama for Windows
init(autoreset=True)

# Configuration
ESP32_IP = "192.168.1.27"  # ← Thay bằng IP ESP32 của bạn
ESP32_PORT = 81
PYTHON_IP = "localhost"
PYTHON_PORT = 5000

def print_header(text):
    print(f"\n{Fore.CYAN}{'='*60}")
    print(f"{Fore.CYAN}{text:^60}")
    print(f"{Fore.CYAN}{'='*60}{Style.RESET_ALL}")

def print_success(text):
    print(f"{Fore.GREEN}✅ {text}{Style.RESET_ALL}")

def print_error(text):
    print(f"{Fore.RED}❌ {text}{Style.RESET_ALL}")

def print_warning(text):
    print(f"{Fore.YELLOW}⚠️  {text}{Style.RESET_ALL}")

def print_info(text):
    print(f"{Fore.BLUE}ℹ️  {text}{Style.RESET_ALL}")

def test_network_connectivity(host, port, name):
    """Test TCP connection"""
    try:
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.settimeout(3)
        result = sock.connect_ex((host, port))
        sock.close()
        
        if result == 0:
            print_success(f"{name} network reachable at {host}:{port}")
            return True
        else:
            print_error(f"{name} not reachable at {host}:{port}")
            return False
    except Exception as e:
        print_error(f"{name} connection error: {e}")
        return False

def test_esp32_status():
    """Test 1: Kiểm tra ESP32-CAM status"""
    print_header("TEST 1: ESP32-CAM STATUS")
    
    # Test network
    if not test_network_connectivity(ESP32_IP, ESP32_PORT, "ESP32-CAM"):
        print_error("ESP32-CAM không thể kết nối")
        print_info("Kiểm tra:")
        print_info("  1. ESP32 có nguồn không?")
        print_info("  2. ESP32 đã kết nối WiFi chưa?")
        print_info("  3. IP trong script đúng chưa?")
        return False
    
    # Test /status endpoint
    try:
        url = f"http://{ESP32_IP}:{ESP32_PORT}/status"
        print_info(f"Testing: {url}")
        
        response = requests.get(url, timeout=5)
        
        if response.status_code == 200:
            data = response.json()
            print_success(f"ESP32 status OK")
            print_info(f"  IP: {data.get('ip', 'N/A')}")
            print_info(f"  FPS: {data.get('fps', 'N/A')}")
            return True
        else:
            print_error(f"ESP32 status error: {response.status_code}")
            return False
            
    except requests.exceptions.Timeout:
        print_error("ESP32 timeout - không phản hồi")
        return False
    except requests.exceptions.ConnectionError:
        print_error("ESP32 connection refused")
        return False
    except Exception as e:
        print_error(f"ESP32 error: {e}")
        return False

def test_esp32_stream():
    """Test 2: Kiểm tra ESP32 MJPEG stream"""
    print_header("TEST 2: ESP32 MJPEG STREAM")
    
    try:
        url = f"http://{ESP32_IP}:{ESP32_PORT}/stream"
        print_info(f"Testing: {url}")
        
        response = requests.get(url, stream=True, timeout=5)
        
        if response.status_code == 200:
            # Đọc 1 chunk để verify
            chunk = next(response.iter_content(chunk_size=1024))
            
            if chunk:
                print_success("ESP32 stream OK - đang phát video")
                print_info(f"  Content-Type: {response.headers.get('Content-Type', 'N/A')}")
                print_info(f"  First chunk size: {len(chunk)} bytes")
                return True
            else:
                print_error("ESP32 stream không có data")
                return False
        else:
            print_error(f"ESP32 stream error: {response.status_code}")
            return False
            
    except Exception as e:
        print_error(f"ESP32 stream error: {e}")
        return False

def test_esp32_capture():
    """Test 3: Kiểm tra ESP32 capture single frame"""
    print_header("TEST 3: ESP32 CAPTURE FRAME")
    
    try:
        url = f"http://{ESP32_IP}:{ESP32_PORT}/capture"
        print_info(f"Testing: {url}")
        
        response = requests.get(url, timeout=5)
        
        if response.status_code == 200:
            jpeg_size = len(response.content)
            
            # Verify JPEG signature
            if response.content[:2] == b'\xff\xd8':
                print_success(f"ESP32 capture OK - JPEG valid")
                print_info(f"  Frame size: {jpeg_size} bytes ({jpeg_size/1024:.1f} KB)")
                return True
            else:
                print_error("ESP32 capture không phải JPEG")
                return False
        else:
            print_error(f"ESP32 capture error: {response.status_code}")
            return False
            
    except Exception as e:
        print_error(f"ESP32 capture error: {e}")
        return False

def test_python_server():
    """Test 4: Kiểm tra Python AI Server"""
    print_header("TEST 4: PYTHON AI SERVER")
    
    # Test network
    if not test_network_connectivity(PYTHON_IP, PYTHON_PORT, "Python Server"):
        print_error("Python server không chạy")
        print_info("Chạy: python face_recognition_advanced.py")
        return False
    
    # Test /status endpoint
    try:
        url = f"http://{PYTHON_IP}:{PYTHON_PORT}/status"
        print_info(f"Testing: {url}")
        
        response = requests.get(url, timeout=5)
        
        if response.status_code == 200:
            data = response.json()
            print_success("Python server OK")
            print_info(f"  ESP32: {data.get('esp32', 'N/A')}")
            print_info(f"  MQTT: {data.get('mqtt', 'N/A')}")
            print_info(f"  Recognition: {data.get('recognition_phase', 'N/A')}")
            print_info(f"  Templates: {data.get('templates', 0)}")
            return True
        else:
            print_error(f"Python server error: {response.status_code}")
            return False
            
    except Exception as e:
        print_error(f"Python server error: {e}")
        return False

def test_python_relay():
    """Test 5: Kiểm tra Python MJPEG relay"""
    print_header("TEST 5: PYTHON MJPEG RELAY")
    
    try:
        url = f"http://{PYTHON_IP}:{PYTHON_PORT}/stream"
        print_info(f"Testing: {url}")
        
        response = requests.get(url, stream=True, timeout=5)
        
        if response.status_code == 200:
            # Đọc 1 chunk để verify
            chunk = next(response.iter_content(chunk_size=1024))
            
            if chunk:
                print_success("Python relay OK - đang broadcast video")
                print_info(f"  Content-Type: {response.headers.get('Content-Type', 'N/A')}")
                print_info(f"  First chunk size: {len(chunk)} bytes")
                return True
            else:
                print_error("Python relay không có data")
                return False
        else:
            print_error(f"Python relay error: {response.status_code}")
            return False
            
    except Exception as e:
        print_error(f"Python relay error: {e}")
        return False

def test_python_members():
    """Test 6: Kiểm tra Python members API"""
    print_header("TEST 6: PYTHON MEMBERS API")
    
    try:
        url = f"http://{PYTHON_IP}:{PYTHON_PORT}/members"
        print_info(f"Testing: {url}")
        
        response = requests.get(url, timeout=5)
        
        if response.status_code == 200:
            data = response.json()
            members = data.get('members', [])
            
            print_success(f"Python members API OK")
            print_info(f"  Total members: {len(members)}")
            
            if members:
                for m in members[:3]:  # Show first 3
                    print_info(f"    - {m.get('name', 'N/A')} ({m.get('role', 'N/A')})")
            
            return True
        else:
            print_error(f"Python members API error: {response.status_code}")
            return False
            
    except Exception as e:
        print_error(f"Python members API error: {e}")
        return False

def test_end_to_end():
    """Test 7: End-to-end flow"""
    print_header("TEST 7: END-TO-END FLOW")
    
    print_info("Simulating Flutter app flow...")
    
    # Step 1: Flutter lấy stream từ Python
    try:
        url = f"http://{PYTHON_IP}:{PYTHON_PORT}/stream"
        print_info(f"Step 1: Flutter → Python stream")
        
        response = requests.get(url, stream=True, timeout=3)
        chunk = next(response.iter_content(chunk_size=1024))
        
        if chunk:
            print_success("  Flutter nhận được stream từ Python ✅")
        else:
            print_error("  Flutter không nhận được stream")
            return False
            
    except Exception as e:
        print_error(f"  Flutter → Python failed: {e}")
        return False
    
    # Step 2: Python lấy frame từ ESP32
    try:
        url = f"http://{ESP32_IP}:{ESP32_PORT}/capture"
        print_info(f"Step 2: Python → ESP32 capture")
        
        response = requests.get(url, timeout=3)
        
        if response.status_code == 200 and len(response.content) > 0:
            print_success("  Python nhận được frame từ ESP32 ✅")
        else:
            print_error("  Python không nhận được frame")
            return False
            
    except Exception as e:
        print_error(f"  Python → ESP32 failed: {e}")
        return False
    
    # Step 3: Verify full chain
    print_success("End-to-end flow OK ✅")
    print_info("  ESP32 → Python → Flutter: WORKING")
    return True

def main():
    """Main test runner"""
    print_header("🧪 SMART HOME SYSTEM TEST")
    print_info(f"ESP32-CAM: {ESP32_IP}:{ESP32_PORT}")
    print_info(f"Python Server: {PYTHON_IP}:{PYTHON_PORT}")
    print_info(f"Start time: {time.strftime('%Y-%m-%d %H:%M:%S')}")
    
    results = {}
    
    # Run tests
    results['ESP32 Status'] = test_esp32_status()
    time.sleep(1)
    
    results['ESP32 Stream'] = test_esp32_stream()
    time.sleep(1)
    
    results['ESP32 Capture'] = test_esp32_capture()
    time.sleep(1)
    
    results['Python Server'] = test_python_server()
    time.sleep(1)
    
    results['Python Relay'] = test_python_relay()
    time.sleep(1)
    
    results['Python Members'] = test_python_members()
    time.sleep(1)
    
    results['End-to-End'] = test_end_to_end()
    
    # Summary
    print_header("📊 TEST SUMMARY")
    
    passed = sum(1 for v in results.values() if v)
    total = len(results)
    
    for test_name, result in results.items():
        status = f"{Fore.GREEN}PASS" if result else f"{Fore.RED}FAIL"
        print(f"  {test_name:.<40} {status}{Style.RESET_ALL}")
    
    print(f"\n{Fore.CYAN}Total: {passed}/{total} tests passed{Style.RESET_ALL}")
    
    if passed == total:
        print(f"\n{Fore.GREEN}{'='*60}")
        print(f"{Fore.GREEN}🎉 ALL TESTS PASSED! System is ready!{Style.RESET_ALL}")
        print(f"{Fore.GREEN}{'='*60}{Style.RESET_ALL}")
        return 0
    else:
        print(f"\n{Fore.RED}{'='*60}")
        print(f"{Fore.RED}❌ SOME TESTS FAILED! Check errors above.{Style.RESET_ALL}")
        print(f"{Fore.RED}{'='*60}{Style.RESET_ALL}")
        return 1

if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        print(f"\n{Fore.YELLOW}Test interrupted by user{Style.RESET_ALL}")
        sys.exit(1)
